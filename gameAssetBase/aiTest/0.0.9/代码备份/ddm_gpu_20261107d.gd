class_name DdmGpu
extends RefCounted
## =============================================================
## DDM 伤害弹幕图 GPU 后端（第①期性能改造核心）
## 【策划对齐】“弹幕是一个能够将材质渲染至弹幕图与屏幕显示的粒子效果”
##   ——取消 0 期 CPU 逐弹像素印章/包围盒擦除/master 全量重建，
##   改为每帧 GPU 两趟 compute：①清零 ②弹幕印章（线程=弹幕，内循环圆盘填充）。
## 【被弹解析不回读】命中判定改由 CPU 空间哈希（BulletHash）完成——
##   语义等价于对 DDM 的上升沿探测（键=伤害|模式，最高伤害优先），且是
##   矢量精确（文档：矢量运算，1像素还是100像素都能精准命中部位）。
##   GPU DDM 图用于：AI 热力图源（③期）、调试显示（F3）、预览。
## 【降级】无 RenderingDevice（headless/兼容模式）时 ok=false，
##   调用方跳过 GPU 路径，游戏逻辑完全不受影响（被弹走哈希）。
## 【capacity】印章 SSBO 预分配 MAX_STAMPS，每帧 buffer_update 增量上传。
## 【②期准备】构造时可注入共享 RenderingDevice（RD 资源不能跨设备，
##   HeatmapField 要读 DDM 图 → 战场用同一个 RD 实例统一提交，FIFO 保序）。
## =============================================================

const W := 400
const H := 400
const MAX_STAMPS := 16384 ## 单侧最大印章数（弹幕+激光细分；超出截断并计数告警）

var ok := false
var main_device := false ## true=挂在主渲染设备上（Texture2DRD 零拷贝显示可用）
var _rd: RenderingDevice = null
var _clear_shader: RDShaderFile
var _stamp_shader: RDShaderFile
var _clear_shader_rid: RID   ## 4.7 API：先 shader_create_from_spirv 转 RID
var _stamp_shader_rid: RID
var _clear_region_pipe: RID = RID()
var _clear_region_set: RID = RID()
var _clear_pipe: RID
var _texarr: RID = RID()
var _texarr_sampler: RID = RID()
var _texarr_set: RID = RID()
var _stamp_pipe: RID
var _clear_set: RID
var _stamp_set: RID
var _tex: RID = RID()          ## R8 存储纹理（双方各一份实例）
var _tex_prev: RID = RID()     ## 上一帧 DDM（Hv 升降沿差分；③期）
var _stamp_buffer: RID
var _stamp_uniform: RDUniform
var _dropped := 0              ## 本帧被截断的印章数（性能诊断）

func _init(shared_rd: RenderingDevice = null) -> void:
	_rd = shared_rd if shared_rd != null else RenderingServer.create_local_rendering_device()
	if _rd == null:
		push_warning("[DdmGpu] 无本地渲染设备（headless/兼容），DDM 图走降级模式")
		return
	if not _setup():
		_rd = null
		return
	ok = true

func _setup() -> bool:
	_clear_shader = load("res://shaders/ddm_clear.glsl")
	var clear_region_shader = load("res://shaders/ddm_clear_region.glsl")
	_stamp_shader = load("res://shaders/ddm_stamps.glsl")
	if _clear_shader == null or _stamp_shader == null:
		push_warning("[DdmGpu] 计算着色器加载失败")
		return false
	## 纹理：R8 400×400，采样+存储（枚举为 RenderingDevice 全局枚举）
	var fmt := RDTextureFormat.new()
	fmt.width = W
	fmt.height = H
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_tex = _rd.texture_create(fmt, RDTextureView.new(), [])
	fmt.usage_bits |= RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT ## prev 拷贝目标
	_tex_prev = _rd.texture_create(fmt, RDTextureView.new(), [])
	if not _tex.is_valid() or not _tex_prev.is_valid():
		return false
	## 印章 SSBO（容量固定，帧内 buffer_update）
	_stamp_buffer = _rd.storage_buffer_create(MAX_STAMPS * 16)
	## 管线与描述集
	## 【Godot 4.7 API 变更】compute_pipeline_create 接收 shader RID——
	##   需先 shader_create_from_spirv()（旧版直接传 RDShaderSPIRV，必得 null）。
	var clear_s := _clear_shader.get_spirv()
	_clear_shader_rid = _rd.shader_create_from_spirv(clear_s, "ddm_clear")
	var stamp_s := _stamp_shader.get_spirv()
	_stamp_shader_rid = _rd.shader_create_from_spirv(stamp_s, "ddm_stamps")
	if not _clear_shader_rid.is_valid() or not _stamp_shader_rid.is_valid():
		push_warning("[DdmGpu] SPIRV → shader RID 失败")
		return false
	_clear_pipe = _rd.compute_pipeline_create(_clear_shader_rid)
	_stamp_pipe = _rd.compute_pipeline_create(_stamp_shader_rid)
	## 【22b 20261103·消弹残影】区域清除管线
	var crs: RDShaderSPIRV = clear_region_shader.get_spirv()
	var cr_rid: RID = _rd.shader_create_from_spirv(crs, "ddm_clear_region")
	if cr_rid.is_valid():
		_clear_region_pipe = _rd.compute_pipeline_create(cr_rid)
		var cr_img := RDUniform.new()
		cr_img.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		cr_img.binding = 0
		cr_img.add_id(_tex)
		_clear_region_set = _rd.uniform_set_create([cr_img], cr_rid, 0)
	if not _clear_pipe.is_valid() or not _stamp_pipe.is_valid():
		push_warning("[DdmGpu] compute 管线创建失败")
		return false
	var tex_uniform := RDUniform.new()
	tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	tex_uniform.binding = 0
	tex_uniform.add_id(_tex)
	## 【4.7 API】uniform_set_create 第2参数是 shader RID（非 pipeline RID）
	_clear_set = _rd.uniform_set_create([tex_uniform], _clear_shader_rid, 0)
	_stamp_uniform = RDUniform.new()
	_stamp_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	_stamp_uniform.binding = 1
	_stamp_uniform.add_id(_stamp_buffer)
	## 【22b 20261102·修4】纹理数组（材质形状加热）：16 层 r8 256×256
	var ta_fmt := RDTextureFormat.new()
	ta_fmt.width = 256
	ta_fmt.height = 256
	ta_fmt.array_layers = 256 ## 【20261103】1-255 纹理槽（0=圆盘兜底）
	ta_fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	## 【0.0.9·修复 20261107·根因】1102 修4 漏设 texture_type——默认=2D(1)，
	## 引擎把数组纹理当单层处理（array_layers 被忽略→data 校验"should be (1)"）
	## →256 层全部上传失败（p_layer 越界）→形状加热/材质形状自始失效
	ta_fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	ta_fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT 		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT 		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	## 【0.0.9·修复 20261107】空数据创建导致 array_layers=0（texture_get 层数读数
	## 与 p_layer>=layer_count 全层上传失败——8 材质槽全灭=形状加热/显示退化）——
	## 创建时必须带满 256 层数据
	## data=每层一项（256 层×256×256 R8=65536B/层）
	var ta_zero := PackedByteArray()
	ta_zero.resize(256 * 256)
	var ta_data: Array = []
	for ta_i in 256:
		ta_data.append(ta_zero)
	_texarr = _rd.texture_create(ta_fmt, RDTextureView.new(), ta_data)
	if not _texarr.is_valid():
		push_warning("[DdmGpu] 纹理数组创建失败——形状加热降级")
	_texarr_sampler = _rd.sampler_create(RDSamplerState.new())
	var ta_uniform := RDUniform.new()
	ta_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	ta_uniform.binding = 2
	ta_uniform.add_id(_texarr)
	var samp_uniform := RDUniform.new()
	samp_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	samp_uniform.binding = 3
	samp_uniform.add_id(_texarr_sampler)
	## 合并进 _stamp_set（同一 set 的 binding 0/1/2/3）
	_stamp_set = _rd.uniform_set_create([tex_uniform, _stamp_uniform, ta_uniform, samp_uniform], _stamp_shader_rid, 0)
	return true

## 【修4】纹理槽内容上传：slots={槽id: Image(r8 256×256)}
func update_tex_array(slots: Dictionary) -> void:
	if not ok or slots.is_empty():
		return
	for slot in slots:
		var img: Image = slots[slot]
		if slot < 0 or slot >= 256 or img == null:
			continue
		var _up_err: int = _rd.texture_update(_texarr, slot - 1, img.get_data()) ## 层=槽-1（槽 0=圆盘兜底）
		if _up_err != OK:
			push_warning("[DdmGpu] 纹理层上传失败 err=" + str(_up_err) + " slot=" + str(slot))


## 【22b 20261103·消弹残影】区域清除：消弹范围内 DDM 像素写 0
func clear_region(cx: float, cy: float, radius: float) -> void:
	if not ok or not _clear_region_pipe.is_valid():
		return
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _clear_region_pipe)
	_rd.compute_list_bind_uniform_set(cl, _clear_region_set, 0)
	_rd.compute_list_set_push_constant(cl,
		PackedInt32Array([int(cx), int(cy), int(radius), 0]).to_byte_array(), 16)
	_rd.compute_list_dispatch(cl, 50, 50, 1)
	_rd.compute_list_end()

## 每帧调用：stamps = PackedFloat32Array（每 4 float 一枚：x,y,r,0）
## 返回是否成功提交（false=降级）
func render(stamps: PackedFloat32Array) -> bool:
	if not ok:
		return false
	var n: int = stamps.size() >> 2 ## 每枚4 float（作者红线：无整数除法警告）
	_dropped = maxi(0, n - MAX_STAMPS)
	n = mini(n, MAX_STAMPS)
	## 印章上传必须在 compute list 之外（4.7：list 创建期间禁止 buffer_update）
	if n > 0:
		var bytes := stamps.slice(0, n * 4).to_byte_array()
		_rd.buffer_update(_stamp_buffer, 0, bytes.size(), bytes)
	## ① 清零（400/8 × 400/8 组）
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _clear_pipe)
	_rd.compute_list_bind_uniform_set(cl, _clear_set, 0)
	_rd.compute_list_dispatch(cl, 50, 50, 1)
	## ② 印章（每线程一枚）
	if n > 0:
		_rd.compute_list_bind_compute_pipeline(cl, _stamp_pipe)
		_rd.compute_list_bind_uniform_set(cl, _stamp_set, 0)
		@warning_ignore("integer_division")
		_rd.compute_list_dispatch(cl, (n + 63) / 64, 1, 1)
	_rd.compute_list_end() ## 提交（RD 自动插入存储→后续使用屏障）
	return true

## 【0.0.9·Hv 修复】cur→prev 拷贝（Hv 升降沿差分用）。
## 【时序 bug 20261106】原在 render() 尾部=同帧 hv.step() 读取**之前**执行
## →prev 恒等于 cur→差分恒 0→Hv 永无升降沿=恒空（Hr 派生随之恒空）。
## 现改为 hv.step() 之后由 battle_arena 显式调用。
func copy_to_prev() -> void:
	if not ok:
		return
	_rd.texture_copy(_tex, _tex_prev, Vector3(), Vector3(),
		Vector3(W, H, 1), 0, 0, 0, 0)

## 供 Sprite/TextureRect 显示的纹理（F3 调试用）
## 【作者批复 2026-10-02：DDM 是 60帧 刷新的，取消0.1秒渲染DDM】
## 主设备路径（Texture2DRD 零拷贝）每帧可刷新；本地 RD（兼容环境）才回读节流。
## 注：计算本身一直是每帧提交；10Hz 的只是此前 F3 显示的重建节流，现已取消。
func get_display_texture() -> Texture2D:
	if not ok:
		return null
	if main_device:
		var t := Texture2DRD.new()
		t.texture_rd_rid = _tex
		return t
	var data := _rd.texture_get_data(_tex, 0)
	if data.is_empty():
		return null
	var img := Image.create_from_data(W, H, false, Image.FORMAT_R8, data)
	return ImageTexture.create_from_image(img)

## DDM 存储图 RID（HeatmapField 在同一 RD 上读取加热）
func image_rid() -> RID:
	return _tex

## 上一帧 DDM 图 RID（Hv 升降沿差分）
func prev_image_rid() -> RID:
	return _tex_prev

## 【内存泄漏修复 20261004】会话级资源释放（战场 PREDELETE 调用；
## 共享设备本身由 GameGlobals 常驻管理，这里只释放本实例 RID）
func shutdown() -> void:
	if _rd == null:
		return
	for rid in [_clear_set, _stamp_set, _clear_pipe, _stamp_pipe,
			_clear_shader_rid, _stamp_shader_rid, _tex, _stamp_buffer,
			_texarr, _texarr_sampler, _texarr_set]: ## 【审计#46】补纹理数组释放
		if rid.is_valid():
			_rd.free_rid(rid)
	_clear_set = RID()
	_stamp_set = RID()
	_clear_pipe = RID()
	_stamp_pipe = RID()
	_clear_shader_rid = RID()
	_stamp_shader_rid = RID()
	_tex = RID()
	_tex_prev = RID()
	_stamp_buffer = RID()
	ok = false

func get_dropped() -> int:
	return _dropped
