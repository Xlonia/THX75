class_name HeatmapField
extends RefCounted
## =============================================================
## 热力图场（②期构型；③期支持 kind="ht"|"hv" 双图族）
##   hv=Hv 速度热点（RGBA8：红=上升沿热、蓝=下降沿热；读 ddms[0]=cur [1]=prev）
## 【策划对齐】《决斗底层→弹幕热力图》：Ht 全局热点图为第一张像素遍历图，
##   刷新 10帧/秒，每像素按 ①扩散(半径1线性) ②衰减(0.8h去尾) ③加热(弹幕图白区+64)。
##   批复（2026-10-01）：衰减回到 ×0.8（弃 e^(-0.5t)）；手感参数作者自调。
## 【GPU 路径】与 DdmGpu 共享同一个 RenderingDevice（RD 资源不能跨设备）：
##   ht_step.glsl  双方DDM并集白区 → 加热；ping-pong 双 R8 400×400 纹理。
##   ht_sample.glsl 态势十六点采样：CPU 预计算采样点（含带转偏移）→ SSBO →
##   每点读一纹素 → vals SSBO → 小体积回读（60实体×32点≈7.7KB@10Hz，可忽略）。
## 【CPU 降级】headless/无 RD 时用 100×100（4px格）降精度网格：
##   仅 加热+衰减（扩散跳过）——仅供 headless 冒烟与逻辑验证，非正式表现。
## 【③期扩展位】Hv/Hd/Hr/Hcs/Hct/He/Hp 复用本类构型（换加热规则与噪声源）；
##   态势十六点的多图加权叠加在采样侧扩展（现阶段仅采 Ht）。
## 【性能】所有常驻缓冲预分配；step/sample 每6物理帧一次（10Hz）；
##   回读仅 vals 小缓冲。计时数据供"态势十六点性能检测"（作者批复要求）。
## =============================================================

const W := 400
const H := 400
const MAX_POINTS := 4096          ## 采样点容量（60实体×32=1920，留余量）
const CPU_CELL := 4               ## CPU 降级网格边长（px）
const CPU_W := W / CPU_CELL       ## 100

## —— 可调参数（与 ht_step.glsl 常量对应；GPU 侧以着色器为准）——
const DECAY := 0.75
const HEAT := 64.0

var ok := false                   ## GPU 可用（false=CPU 降级）
var _rd: RenderingDevice = null
var kind := "ht"                 ## "ht"=Ht 全局热点 / "hv"=Hv 速度热点
var ddms: Array = []             ## hv 模式：[cur, prev]
var _step_shader: RDShaderFile
var _sample_shader: RDShaderFile
var _step_shader_rid: RID
var _sample_shader_rid: RID
var _step_pipe: RID
var _sample_pipe: RID
var _ht: Array = [RID(), RID()]   ## ping-pong 双纹理
var _ht_front := 0                ## 当前有效图（=最近一次写入）
var _step_sets: Array = []        ## [front0→back1, front1→back0]
var _sample_sets: Array = []      ## 绑定对应 front 的采样集
var _clear_region_pipe: RID = RID()
var _clear_region_sets: Array = [] ## [front] → set
var _spos_buf: RID
var _vals_buf: RID
var _ddm0: RID = RID()
var main_device := false ## true=挂在主渲染设备上（Texture2DRD 零拷贝显示可用）
var _configured := false

## CPU 降级
var _cpu := PackedByteArray()

## —— 计时（态势十六点性能检测；μs，指数滑动平均）——
var step_us := 0.0
var sample_us := 0.0
var readback_us := 0.0

func _init(rd: RenderingDevice) -> void:
	_rd = rd
	if _rd == null:
		_cpu.resize(CPU_W * CPU_W)
		_cpu.fill(0)
		push_warning("[HeatmapField] 无渲染设备（headless/兼容）→ CPU 降级网格（%d×%d，无扩散）" % [CPU_W, CPU_W])
		return
	if not _setup():
		_rd = null
		_cpu.resize(CPU_W * CPU_W)
		_cpu.fill(0)
		return
	ok = true

func _setup() -> bool:
	_step_shader = load("res://shaders/ht_step.glsl")
	_sample_shader = load("res://shaders/ht_sample.glsl")
	if _step_shader == null or _sample_shader == null:
		push_warning("[HeatmapField] 热力图计算着色器加载失败")
		return false
	var fmt := RDTextureFormat.new()
	fmt.width = W
	fmt.height = H
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT ## F3 回读显示需要
	var zero := PackedByteArray()
	zero.resize(W * H)
	zero.fill(0)
	for i in 2:
		_ht[i] = _rd.texture_create(fmt, RDTextureView.new(), [zero])
		if not _ht[i].is_valid():
			return false
	## 【Godot 4.7 API 变更】compute_pipeline_create 接收 shader RID（同 DdmGpu 修复）
	_step_shader_rid = _rd.shader_create_from_spirv(_step_shader.get_spirv(), "ht_step")
	_sample_shader_rid = _rd.shader_create_from_spirv(_sample_shader.get_spirv(), "ht_sample")
	if not _step_shader_rid.is_valid() or not _sample_shader_rid.is_valid():
		push_warning("[HeatmapField] SPIRV → shader RID 失败")
		return false
	_step_pipe = _rd.compute_pipeline_create(_step_shader_rid)
	_sample_pipe = _rd.compute_pipeline_create(_sample_shader_rid)
	if not _step_pipe.is_valid() or not _sample_pipe.is_valid():
		return false
	## 采样缓冲（预分配，帧内 buffer_update）
	_spos_buf = _rd.storage_buffer_create(MAX_POINTS * 8)   ## vec2 × N
	_vals_buf = _rd.storage_buffer_create(MAX_POINTS * 4)   ## uint × N
	return true

## DdmGpu 初始化后调用一次：绑定本侧 DDM 图并预建 uniform set（ping-pong 两套）
## 【每侧一张威胁图（作者批复 2026-10-02）】一个 HeatmapField 只对应一张 DDM。
func configure(ddm_img: RID) -> void:
	if _rd == null or _configured:
		return
	_ddm0 = ddm_img
	if not _ddm0.is_valid():
		return
	_configured = true
	## 【22b 20261103·消弹残影】区域清除管线（复用 ddm_clear_region.glsl）
	var cr_sh: RDShaderFile = load("res://shaders/ddm_clear_region.glsl")
	if cr_sh != null:
		var cr_rid: RID = _rd.shader_create_from_spirv(cr_sh.get_spirv(), "ddm_clear_region")
		if cr_rid.is_valid():
			_clear_region_pipe = _rd.compute_pipeline_create(cr_rid)
			_clear_region_sets.clear()
			for front2 in 2:
				var u_cr := _img_uniform(_ht[front2], 0)
				_clear_region_sets.append(_rd.uniform_set_create([u_cr], cr_rid, 0))
	for front in 2:
		var back := 1 - front
		var u_prev := _img_uniform(_ht[front], 0)
		var u_next := _img_uniform(_ht[back], 1)
		var u_d0 := _img_uniform(_ddm0, 2)
		## 【4.7 API】uniform_set_create 第2参数是 shader RID
		_step_sets.append(_rd.uniform_set_create([u_prev, u_next, u_d0], _step_shader_rid, 0))
		var u_ht := _img_uniform(_ht[front], 0)
		var u_sp := RDUniform.new()
		u_sp.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_sp.binding = 1
		u_sp.add_id(_spos_buf)
		var u_va := RDUniform.new()
		u_va.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_va.binding = 2
		u_va.add_id(_vals_buf)
		_sample_sets.append(_rd.uniform_set_create([u_ht, u_sp, u_va], _sample_shader_rid, 0))

func _img_uniform(rid: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u

## =============================================================
## ① Ht 步进（10Hz；须在当帧 _render_ddm 之后调用——同 RD 队列 FIFO 保序）
## =============================================================
func step() -> void:
	if not ok or not _configured:
		return
	var t := Time.get_ticks_usec()
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _step_pipe)
	_rd.compute_list_bind_uniform_set(cl, _step_sets[_ht_front], 0)
	_rd.compute_list_dispatch(cl, 50, 50, 1)
	_rd.compute_list_end()
	_ht_front = 1 - _ht_front
	step_us = step_us * 0.9 + float(Time.get_ticks_usec() - t) * 0.1

## =============================================================
## ② 态势十六点采样（10Hz；points=CPU 预计算的全部采样点，实体×32）
## 返回 PackedInt32Array（每点 0~255 热度，顺序与 points 一致）
## =============================================================
func sample(points: PackedVector2Array) -> PackedInt32Array:
	if points.is_empty():
		return PackedInt32Array()
	if not ok:
		return _sample_cpu(points)
	var t := Time.get_ticks_usec()
	var n: int = mini(points.size(), MAX_POINTS)
	var bytes := points.slice(0, n).to_byte_array()
	_rd.buffer_update(_spos_buf, 0, bytes.size(), bytes)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _sample_pipe)
	_rd.compute_list_bind_uniform_set(cl, _sample_sets[_ht_front], 0)
	## 【P1 修复 20261015】着色器新增 push constant 基址——单批路径全 0，行为不变
	_rd.compute_list_set_push_constant(cl, PackedInt32Array([0, 0, n, 0]).to_byte_array(), 16)
	@warning_ignore("integer_division")
	_rd.compute_list_dispatch(cl, (n + 63) / 64, 1, 1)
	_rd.compute_list_end()
	sample_us = sample_us * 0.9 + float(Time.get_ticks_usec() - t) * 0.1
	## 小体积回读（uint32 × n）
	var t2 := Time.get_ticks_usec()
	var raw := _rd.buffer_get_data(_vals_buf, 0, n * 4)
	var vals := raw.to_int32_array()
	readback_us = readback_us * 0.9 + float(Time.get_ticks_usec() - t2) * 0.1
	if vals.size() > n:
		vals.resize(n)
	return vals

## 【异步采样（主循环用）】dispatch + buffer_get_data_async——不阻塞主线程。
## 结果写入 last_sample（0~1 帧后可用；AI 用 0.1s 旧数据符合策划语义）
var last_sample: PackedInt32Array = PackedInt32Array()
func sample_async(points: PackedVector2Array) -> void:
	if not ok or points.is_empty():
		return
	var n: int = mini(points.size(), 4096)
	var bytes := points.slice(0, n).to_byte_array()
	_rd.buffer_update(_spos_buf, 0, n * 8, bytes)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _sample_pipe)
	_rd.compute_list_bind_uniform_set(cl, _sample_sets[_ht_front], 0)
	_rd.compute_list_set_push_constant(cl, PackedInt32Array([0, 0, n, 0]).to_byte_array(), 16)
	_rd.compute_list_dispatch(cl, (n + 63) / 64, 1, 1)
	_rd.compute_list_end()
	_rd.buffer_get_data_async(_vals_buf,
		func(arr: PackedByteArray): last_sample = arr.to_int32_array(), 0, n * 4)

## 【P1 修复 20261015】dispatch 与回读拆分（本地 RD 无异步回调，同步回读的
## fence 会等待全部在途提交；改为本拍 dispatch、下一拍 GPU 空闲时 sample_read，
## 0.1s 旧数据符合策划态势语义）
var _disp_n := 0 ## 最近一次 sample_dispatch 的点数
func sample_dispatch(points: PackedVector2Array) -> void:
	if not ok or points.is_empty():
		return
	var n: int = mini(points.size(), MAX_POINTS)
	var bytes := points.slice(0, n).to_byte_array()
	_rd.buffer_update(_spos_buf, 0, bytes.size(), bytes)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _sample_pipe)
	_rd.compute_list_bind_uniform_set(cl, _sample_sets[_ht_front], 0)
	_rd.compute_list_set_push_constant(cl, PackedInt32Array([0, 0, n, 0]).to_byte_array(), 16)
	@warning_ignore("integer_division")
	_rd.compute_list_dispatch(cl, (n + 63) / 64, 1, 1)
	_rd.compute_list_end()
	_disp_n = n

## 取上一拍 dispatch 的结果（必须在下一次 sample_dispatch 之前调用）
func sample_read() -> PackedInt32Array:
	if not ok or _disp_n <= 0:
		return PackedInt32Array()
	var n := _disp_n
	_disp_n = 0
	var raw := _rd.buffer_get_data(_vals_buf, 0, n * 4)
	var vals := raw.to_int32_array()
	if vals.size() > n:
		vals.resize(n)
	return vals

## CPU 降级采样：最近格
func _sample_cpu(points: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(points.size())
	for i in points.size():
		var cx: int = clampi(int(points[i].x / CPU_CELL), 0, CPU_W - 1)
		var cy: int = clampi(int(points[i].y / CPU_CELL), 0, CPU_W - 1)
		out[i] = _cpu[cy * CPU_W + cx]
	return out

## CPU 降级步进（加热+衰减；扩散跳过——headless 专用非正式路径）
func step_cpu(bullets: Array) -> void:
	var t := Time.get_ticks_usec()
	for b in bullets:
		var bl: Bullet = b
		if bl.hidden_now:
			continue
		var cx: int = clampi(int(bl.pos.x / CPU_CELL), 0, CPU_W - 1)
		var cy: int = clampi(int(bl.pos.y / CPU_CELL), 0, CPU_W - 1)
		var idx := cy * CPU_W + cx
		_cpu[idx] = mini(255, _cpu[idx] + int(HEAT))
	for i in _cpu.size():
		_cpu[i] = int(float(_cpu[i]) * DECAY)
	step_us = step_us * 0.9 + float(Time.get_ticks_usec() - t) * 0.1

## =============================================================
## 调试显示（F3）：当前 Ht 纹理
## 【DDM/热力图均 60帧 渲染（作者批复 2026-10-02：取消0.1秒渲染DDM）】
## 主设备路径用 Texture2DRD 零拷贝（每帧可刷新，不再10Hz节流）；
## 本地 RD（兼容环境）无零拷贝通道 → 回读 ImageTexture（10Hz 显示）。
## =============================================================
## 【20261028f】当拍 front 纹理 RID（Ht 派生族 Ha/Hd 的输入；共享 RD 上直读）
func front_texture_rid() -> RID:
	return _ht[_ht_front] if ok else RID()

## 【22b 20261103·消弹残影】热力图区域清 0（消弹联动）
## 【0.0.9·热源探针】Ht front 槽纹理 RID
func front_rid() -> RID:
	return _ht[_ht_front] if _ht.size() == 2 else RID()

func clear_region(cx: float, cy: float, radius: float) -> void:
	if not ok or _rd == null or not _clear_region_pipe.is_valid():
		return
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _clear_region_pipe)
	_rd.compute_list_bind_uniform_set(cl, _clear_region_sets[_ht_front], 0)
	_rd.compute_list_set_push_constant(cl,
		PackedInt32Array([int(cx), int(cy), int(radius), 0]).to_byte_array(), 16)
	_rd.compute_list_dispatch(cl, 50, 50, 1)
	_rd.compute_list_end()

func display_texture() -> Texture2D:
	if not ok:
		var img := Image.create(CPU_W, CPU_W, false, Image.FORMAT_L8)
		img.set_data(CPU_W, CPU_W, false, Image.FORMAT_L8, _cpu)
		img.resize(W, H, Image.INTERPOLATE_NEAREST)
		return ImageTexture.create_from_image(img)
	if main_device:
		var t := Texture2DRD.new()
		t.texture_rd_rid = _ht[_ht_front]
		return t
	var data := _rd.texture_get_data(_ht[_ht_front], 0)
	if data.is_empty():
		return null
	return ImageTexture.create_from_image(Image.create_from_data(W, H, false, Image.FORMAT_R8, data))

## 【内存泄漏修复 20261004】会话级资源释放（战场 PREDELETE 调用；
## 注意先于 DdmGpu.shutdown 调用——本类 uniform set 引用 DDM 图）
func shutdown() -> void:
	if _rd == null:
		return
	if kind == "hv" and ddms.size() < 2:
		return
	for set_rid in _step_sets:
		if set_rid.is_valid():
			_rd.free_rid(set_rid)
	for set_rid in _sample_sets:
		if set_rid.is_valid():
			_rd.free_rid(set_rid)
	_step_sets.clear()
	_sample_sets.clear()
	for rid in [_ht[0], _ht[1], _spos_buf, _vals_buf, _step_pipe, _sample_pipe,
			_step_shader_rid, _sample_shader_rid]:
		if rid.is_valid():
			_rd.free_rid(rid)
	_ht = [RID(), RID()]
	_spos_buf = RID()
	_vals_buf = RID()
	_step_pipe = RID()
	_sample_pipe = RID()
	_step_shader_rid = RID()
	_sample_shader_rid = RID()
	_configured = false
	ok = false

## 性能检测摘要（HUD/控制台用）
func stats_line() -> String:
	return "Ht步进%.2fms 采样%.2fms 回读%.2fms" % [step_us / 1000.0, sample_us / 1000.0, readback_us / 1000.0]
