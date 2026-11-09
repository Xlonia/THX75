class_name FamilyMaps
extends RefCounted
## =============================================================
## 热力图族·期望系（③期收官）：He 全局期望 / Hd 总结期望云 / Hr 快弹警告 / Hp 敌方规律
## 【管线】每图 400×400 R8，front/back ping-pong，10Hz，单入口 advance()：
##   advance(i, pts) = decay(front→back) → stamp(pts 进 back) → front=back
## 【策划对齐与简化声明】
##   He=所有非点向弹幕射程内轨迹期望（粗采样 8 点/发）
##   Hr=快弹（速度≥4）1 秒轨迹
##   Hp=敌方轨迹、0.98 慢衰减（长记忆规律）——每侧一张（Hp0 我方视角/Hp1 敌方视角）
##   Hd=He 的慢积累+半径2模糊（期望云近似；多边形等高线为表现层）
## 【AI 用途】采样点上多图加权（策划权重：He2 Hd3 Hr1 Hp3）→ _ai_drive
## =============================================================

const W := 400
const H := 400
## 每侧一张威胁图：HeK=威胁 K 侧的轨迹（来自 1-K 侧弹幕）；Hp 慢记忆=规律
const NAMES := ["He0", "He1", "Hd0", "Hd1", "Hr0", "Hr1", "Hp0", "Hp1"]

var ok := false
var _rd: RenderingDevice = null
var _tex: Array = []          ## _tex[i] = [texA, texB]
var _front: Array = []        ## 每图当前状态所在槽（0/1）
var _stamp_sets: Array = []   ## _stamp_sets[i] = [setA(写texA), setB(写texB)]
var _decay_sets: Array = []   ## _decay_sets[i] = [setA→B, setB→A]
var _sample_sets: Array = []  ## _sample_sets[i] = [setA(读texA), setB(读texB)]（绑定每图 _vals_bufs[i]）
var _sample_shared_sets: Array = [] ## 同上但绑定合并缓冲 _samp_shared（sample_batch 用）
var _stamp_pipe: RID
var _stamp_shader_rid: RID = RID()
var _decay_shader_rid: RID = RID()
var _sample_shader_rid: RID = RID()
var _decay_pipe: RID
var _sample_pipe: RID
var _stamp_buf: RID
var _stamp_bufs: Array = [] ## 每图独立点缓冲（advance_batch 一次提交多图印章用）
var _vals_bufs: Array = [] ## 每图独立回读缓冲（8×4096×4）
var _ubos: Array = []     ## 每图 decay 参数 UBO
var _samp_shared: RID     ## 【P1 修复】合并回读缓冲：2侧×4图×4096点（sample_batch 专用）
var _derive_pipe: RID = RID()
var _derive_shader_rid: RID = RID()
var _hp_pipe: RID = RID()
var _hp_shader_rid: RID = RID()
var _ha_tex: Array = []      ## 每侧 [RID,RID]：Ha 马赛克（双槽 ping-pong）
var _ha_front: Array = [0, 0]
const HA_NAMES := ["Ha0", "Ha1"] ## display 用（不进 NAMES/advance 序列）
var _ha_sample_shared_sets: Array = [] ## [side][front] → 采样绑定
var results: Dictionary = {}  ## 异步回读结果（0~1 帧后可用）
var flip_seq := [0, 0, 0, 0, 0, 0, 0, 0] ## 【0.0.9·等高线】每图翻面/重写序号（ContourField 去重：源未变不重复提取）
var _decays := [0.9, 0.9, 0.92, 0.92, 0.9, 0.9, 0.98, 0.98]
var _blur2 := [0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0]
## —— 计时（μs，指数滑动平均；tick 帧性能归因用）——
var adv_us := 0.0      ## advance_batch（含 CPU 点构建外的 GPU 提交）
var samp_batch_us := 0.0 ## sample_batch（含 1 次同步回读）
var stamp_build_us := 0.0 ## 调用方点列构建（battle_arena 写入）

func _init(rd: RenderingDevice, _ddm_unused: RID) -> void:
	_rd = rd
	if _rd == null:
		return
	var stamp_sh: RDShaderFile = load("res://shaders/traj_stamp.glsl")
	var decay_sh: RDShaderFile = load("res://shaders/fam_decay.glsl")
	var samp_sh: RDShaderFile = load("res://shaders/ht_sample.glsl")
	var derive_sh: RDShaderFile = load("res://shaders/ht_derive.glsl")
	var hp_sh: RDShaderFile = load("res://shaders/hp_derive.glsl")
	if stamp_sh == null or decay_sh == null or samp_sh == null or derive_sh == null or hp_sh == null:
		push_warning("[FamilyMaps] 着色器加载失败")
		return
	var stamp_rid := _rd.shader_create_from_spirv(stamp_sh.get_spirv(), "traj_stamp")
	var decay_rid := _rd.shader_create_from_spirv(decay_sh.get_spirv(), "fam_decay")
	var samp_rid := _rd.shader_create_from_spirv(samp_sh.get_spirv(), "fam_sample")
	var derive_rid := _rd.shader_create_from_spirv(derive_sh.get_spirv(), "ht_derive")
	if not stamp_rid.is_valid() or not decay_rid.is_valid() or not samp_rid.is_valid() or not derive_rid.is_valid():
		push_warning("[FamilyMaps] SPIRV 无效")
		return
	_derive_shader_rid = derive_rid
	_derive_pipe = _rd.compute_pipeline_create(derive_rid)
	if not _derive_pipe.is_valid():
		push_warning("[FamilyMaps] 派生管线创建失败")
		return
	_hp_shader_rid = _rd.shader_create_from_spirv(hp_sh.get_spirv(), "hp_derive")
	if not _hp_shader_rid.is_valid():
		push_warning("[FamilyMaps] Hp 派生 SPIRV 无效")
		return
	_hp_pipe = _rd.compute_pipeline_create(_hp_shader_rid)
	if not _hp_pipe.is_valid():
		push_warning("[FamilyMaps] Hp 派生管线创建失败")
		return
	_stamp_shader_rid = stamp_rid
	_stamp_pipe = _rd.compute_pipeline_create(stamp_rid)
	_decay_shader_rid = decay_rid
	_decay_pipe = _rd.compute_pipeline_create(decay_rid)
	_sample_shader_rid = samp_rid
	_sample_pipe = _rd.compute_pipeline_create(samp_rid)
	if not _stamp_pipe.is_valid() or not _decay_pipe.is_valid() or not _sample_pipe.is_valid():
		push_warning("[FamilyMaps] 管线创建失败")
		return
	_stamp_buf = _rd.storage_buffer_create(4096 * 16)
	_samp_shared = _rd.storage_buffer_create(10 * 4096 * 4) ## 【20261102d】2侧×5图（+Ha）×4096点（原 8 槽） ## 【P1】合并回读缓冲
	_vals_bufs.append(_rd.storage_buffer_create(4096 * 4))
	var fmt := RDTextureFormat.new()
	fmt.width = W
	fmt.height = H
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var zero := PackedByteArray()
	zero.resize(W * H)
	for i in NAMES.size():
		var a := _rd.texture_create(fmt, RDTextureView.new(), [zero])
		var b := _rd.texture_create(fmt, RDTextureView.new(), [zero])
		if not a.is_valid() or not b.is_valid():
			push_warning("[FamilyMaps] 纹理创建失败")
			return
		_tex.append([a, b])
		_front.append(0)
		_vals_bufs.append(_rd.storage_buffer_create(4096 * 4)) ## 每图独立回读缓冲
		_stamp_bufs.append(_rd.storage_buffer_create(16384 * 16)) ## 每图独立点缓冲（16384 上限）
		var u_img_a := _img_uniform(a, 0)
		var u_img_b := _img_uniform(b, 0)
		var u_img_b1 := _img_uniform(b, 1) ## decay 着色器 binding 1（back 槽）
		var u_img_a1 := _img_uniform(a, 1) ## decay 着色器 binding 1（反向 set）
		var u_st := RDUniform.new()
		u_st.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_st.binding = 1
		u_st.add_id(_stamp_bufs[i])
		var u_sp := RDUniform.new()
		u_sp.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_sp.binding = 1
		u_sp.add_id(_stamp_buf)
		var u_va := RDUniform.new()
		u_va.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_va.binding = 2
		u_va.add_id(_vals_bufs[i])
		var pb := _rd.uniform_buffer_create(16)
		_ubos.append(pb)
		var u_prm := RDUniform.new()
		u_prm.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		u_prm.binding = 2
		u_prm.add_id(pb)
		_stamp_sets.append([
			_rd.uniform_set_create([u_img_a, u_st], stamp_rid, 0),
			_rd.uniform_set_create([u_img_b, u_st], stamp_rid, 0),
		])
		var ds0 := _rd.uniform_set_create([u_img_a, u_img_b1, u_prm], decay_rid, 0)
		var ds1 := _rd.uniform_set_create([u_img_b, u_img_a1, u_prm], decay_rid, 0)
		_decay_sets.append([ds0, ds1])
		_sample_sets.append([
			_rd.uniform_set_create([u_img_a, u_sp, u_va], samp_rid, 0),
			_rd.uniform_set_create([u_img_b, u_sp, u_va], samp_rid, 0),
		])
		var u_vs := RDUniform.new()
		u_vs.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_vs.binding = 2
		u_vs.add_id(_samp_shared)
		_sample_shared_sets.append([
			_rd.uniform_set_create([u_img_a, u_sp, u_vs], samp_rid, 0),
			_rd.uniform_set_create([u_img_b, u_sp, u_vs], samp_rid, 0),
		])
	## 【20261030·①Ha 接入】每侧 Ha 马赛克双槽（derive shader binding2 直写）
	var hfmt := RDTextureFormat.new()
	hfmt.width = W
	hfmt.height = H
	hfmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	hfmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT 		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT 		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	for side2 in 2:
		var ha0 := _rd.texture_create(hfmt, RDTextureView.new(), [zero])
		var ha1 := _rd.texture_create(hfmt, RDTextureView.new(), [zero])
		if not ha0.is_valid() or not ha1.is_valid():
			push_warning("[FamilyMaps] Ha 纹理创建失败")
			return
		_ha_tex.append([ha0, ha1])
	## 【20261102d·Ha 采样接入】每侧×2 front 的采样绑定（Ha 纹理+共享点缓冲+共享值缓冲）
	_ha_sample_shared_sets.resize(2)
	for side3 in 2:
		_ha_sample_shared_sets[side3] = [null, null]
		for fr in 2:
			var u_ha0 := RDUniform.new()
			u_ha0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			u_ha0.binding = 0
			u_ha0.add_id(_ha_tex[side3][fr])
			var u_sp2 := RDUniform.new()
			u_sp2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u_sp2.binding = 1
			u_sp2.add_id(_stamp_buf)
			var u_vs2 := RDUniform.new()
			u_vs2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u_vs2.binding = 2
			u_vs2.add_id(_samp_shared)
			_ha_sample_shared_sets[side3][fr] = _rd.uniform_set_create(
				[u_ha0, u_sp2, u_vs2], _sample_shader_rid, 0)
	ok = true

	ok = true

## 【20261028f】Hd 直接派生写入 fam Hd 纹理（替代 decay+印章）：
## names 序：He0 He1 Hd0 Hd1 Hr0 Hr1 Hp0 Hp1 → Hd0=2 Hd1=3。
## 派生后 front 切换，采样路径（_tex 原样）零改动。
## 【0.0.9·Hp 重做（策划新三 66 行）】初始化模拟假 DDM 上传：
## side=视角侧（Hp0=我方视角），img=256/400 模拟图（L8）
func upload_hp_image(side: int, img: Image) -> void:
	if not ok:
		return
	var i: int = 6 + side
	_rd.texture_update(_tex[i][_front[i]], 0, img.get_data())
	flip_seq[i] += 1 ## 【等高线去重】Hp 数据已重写

func derive_hd_from_ht(side: int, ht_tex: RID) -> void:
	if not ok or not ht_tex.is_valid():
		return
	var i: int = 2 + side
	var front: int = _front[i]
	var back: int = 1 - front
	var u_src := RDUniform.new()
	u_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_src.binding = 0
	u_src.add_id(ht_tex)
	var u_dst := RDUniform.new()
	u_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_dst.binding = 1
	u_dst.add_id(_tex[i][back])
	## 【20261030·①Ha】同 dispatch 双输出：binding2=Ha 马赛克
	var ha_front: int = _ha_front[side]
	var ha_back: int = 1 - ha_front
	var u_ha := RDUniform.new()
	u_ha.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_ha.binding = 2
	u_ha.add_id(_ha_tex[side][ha_back])
	var us := _rd.uniform_set_create([u_src, u_dst, u_ha], _derive_shader_rid, 0)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _derive_pipe)
	_rd.compute_list_bind_uniform_set(cl, us, 0)
	_rd.compute_list_dispatch(cl, 50, 50, 1)
	_rd.compute_list_dispatch(cl, 50, 50, 1)
	_rd.compute_list_end()
	_front[i] = back
	flip_seq[i] += 1 ## 【等高线去重】源已刷新
	_ha_front[side] = ha_back

## 【0.0.9·等高线】图 front 槽翻面序号（ContourField 源未变跳过提取）
func flip_of(name: String) -> int:
	var i: int = NAMES.find(name)
	return flip_seq[i] if i >= 0 else -1

## 【0.0.9·等高线】图 front 槽纹理 RID（下采样 dispatch 源绑定）
func tex_rid(name: String) -> RID:
	var i: int = NAMES.find(name)
	if i < 0:
		return RID()
	return _tex[i][_front[i]]

func _img_uniform(rid: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u

func _push_params(i: int) -> void:
	var f := PackedFloat32Array([_decays[i], _blur2[i]])
	_rd.buffer_update(_ubos[i], 0, 16, f.to_byte_array())

## 【单入口】第 i 图：衰减(front→back) → 印章(back) → front=back
func advance(i: int, pts: PackedFloat32Array) -> void:
	if not ok:
		return
	_push_params(i)
	var front: int = _front[i]
	var back: int = 1 - front
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _decay_pipe)
	_rd.compute_list_bind_uniform_set(cl, _decay_sets[i][front], 0)
	_rd.compute_list_dispatch(cl, 50, 50, 1)
	_rd.compute_list_end()
	if pts.size() >= 2:
		var n: int = mini(pts.size() / 2, 16384) ## 【0.0.9·远区域缺弹】4096→16384（千弹×8 预测点超限被静默截断=远处点丢失）
		var full := PackedFloat32Array()
		full.resize(n * 4)
		for k in n:
			full[k * 4] = pts[k * 2]
			full[k * 4 + 1] = pts[k * 2 + 1]
		_rd.buffer_update(_stamp_bufs[i], 0, n * 16, full.to_byte_array())
		var cl2 := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(cl2, _stamp_pipe)
		_rd.compute_list_bind_uniform_set(cl2, _stamp_sets[i][back], 0) ## 写 back
		_rd.compute_list_dispatch(cl2, (n + 63) / 64, 1, 1)
		_rd.compute_list_end()
	_front[i] = back

## 【P1 修复 20261015】批量 advance：jobs = [[图序, 点列(x,y 交错)], ...]
## 全部收进同一 compute list 一次提交（原逐图 advance 两次提交×8 图=16 次/拍，
## 驱动提交开销是 tick 帧大头）。点缓冲按图独立，buffer_update 全部先于提交。
func advance_batch(jobs: Array) -> void:
	if not ok or jobs.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var flips: Array = []
	for job in jobs:
		var i: int = job[0]
		if i < 0 or i >= NAMES.size():
			continue
		var pts: PackedFloat32Array = job[1]
		_push_params(i)
		var front: int = _front[i]
		var back: int = 1 - front
		if pts.size() >= 2:
			var n: int = mini(pts.size() / 2, 16384) ## 【0.0.9·远区域缺弹】4096→16384（千弹×8 预测点超限被静默截断=远处点丢失）
			var full := PackedFloat32Array()
			full.resize(n * 4)
			for k in n:
				full[k * 4] = pts[k * 2]
				full[k * 4 + 1] = pts[k * 2 + 1]
			_rd.buffer_update(_stamp_bufs[i], 0, n * 16, full.to_byte_array())
		flips.append([i, front, back, pts.size() >= 2])
	var cl := _rd.compute_list_begin()
	for f in flips:
		var i: int = f[0]
		var front: int = f[1]
		var back: int = f[2]
		_rd.compute_list_bind_compute_pipeline(cl, _decay_pipe)
		_rd.compute_list_bind_uniform_set(cl, _decay_sets[i][front], 0)
		_rd.compute_list_dispatch(cl, 50, 50, 1)
		if f[3]:
			var n: int = mini(job_pts_len(jobs, i), 4096)
			_rd.compute_list_bind_compute_pipeline(cl, _stamp_pipe)
			_rd.compute_list_bind_uniform_set(cl, _stamp_sets[i][back], 0)
			_rd.compute_list_dispatch(cl, (n + 63) / 64, 1, 1)
	_rd.compute_list_end()
	for f in flips:
		_front[f[0]] = f[2]
		flip_seq[f[0]] += 1 ## 【等高线去重】
	adv_us = adv_us * 0.9 + float(Time.get_ticks_usec() - t0) * 0.1

## advance_batch 内部用：取图 i 的点数/2（jobs 里同图只出现一次）
func job_pts_len(jobs: Array, i: int) -> int:
	for job in jobs:
		if job[0] == i:
			return job[1].size() / 2
	return 0

var _disp_cache: Dictionary = {} ## name -> {tex, front}（N6：front 未翻面复用）
## F1 显示（front 槽回读；front 未翻面时复用缓存）
func display(name: String) -> Texture2D:
	if not ok:
		return null
	## 【20261030·①Ha】Ha 走独立纹理族（不进 NAMES/advance 序列）
	var hi: int = HA_NAMES.find(name)
	if hi >= 0:
		var hc: Dictionary = _disp_cache.get(name, {})
		if hc.has("tex") and hc["front"] == _ha_front[hi]:
			return hc["tex"]
		var hdata := _rd.texture_get_data(_ha_tex[hi][_ha_front[hi]], 0)
		if hdata.is_empty():
			return null
		var ht2 := ImageTexture.create_from_image(Image.create_from_data(W, H, false, Image.FORMAT_R8, hdata))
		_disp_cache[name] = {"tex": ht2, "front": _ha_front[hi]}
		return ht2
	var i: int = NAMES.find(name)
	if i < 0:
		return null
	var c: Dictionary = _disp_cache.get(name, {})
	if c.has("tex") and c["front"] == _front[i]:
		return c["tex"]
	var data := _rd.texture_get_data(_tex[i][_front[i]], 0)
	if data.is_empty():
		return null
	var t := ImageTexture.create_from_image(Image.create_from_data(W, H, false, Image.FORMAT_R8, data))
	_disp_cache[name] = {"tex": t, "front": _front[i]}
	return t

## 【P1 修复 20261015】多侧多图合并采样，dispatch/read 拆分两段：
## batch_dispatch：点分批写入共享 spos 缓冲区段 + 全部 dispatch 收进同一
##   compute list（push constant 基址寻址）——一次提交；
## batch_read：一次同步回读覆盖所有已用区段（在下一拍 batch_dispatch 前调用，
##   此时 GPU 已空闲，fence≈0）。
## sides = [{ "pts": PackedVector2Array, "maps": Array[String] }, ...]（≤2 侧×4 图）
var _batch_slots: Dictionary = {}
var _batch_tops := 0
func batch_dispatch(sides: Array) -> void:
	if not ok or sides.is_empty():
		return
	var slots := {} ## 图名 -> [区段槽(侧*5+图序), 点数]（20261102d：+Ha 5图/侧）
	var pts_base := 0
	var tops := 0
	for s in sides.size():
		var sd: Dictionary = sides[s]
		var pts: PackedVector2Array = sd["pts"]
		var maps: Array = sd["maps"]
		var n: int = mini(pts.size(), 4096)
		if n <= 0:
			continue
		_rd.buffer_update(_stamp_buf, pts_base * 8, n * 8, pts.slice(0, n).to_byte_array())
		for j in maps.size():
			var mi: int = NAMES.find(maps[j])
			if mi < 0:
				continue
			var slot := s * 5 + j
			slots[maps[j]] = [slot, n]
			tops = maxi(tops, slot * 4096 + n)
		pts_base += n
	## 【20261102d】Ha 采样 dispatch（独立绑定；槽位=侧*5+4）
	for s2 in sides.size():
		var sd2: Dictionary = sides[s2]
		var ha_name: String = "Ha" + str(sd2["side"])
		var pts2: PackedVector2Array = sd2["pts"]
		var n2: int = mini(pts2.size(), 4096)
		if n2 <= 0:
			continue
		var slot2: int = s2 * 5 + 4
		slots[ha_name] = [slot2, n2]
		tops = maxi(tops, slot2 * 4096 + n2)
	if slots.is_empty():
		return
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _sample_pipe)
	pts_base = 0
	for s in sides.size():
		var sd: Dictionary = sides[s]
		var pts: PackedVector2Array = sd["pts"]
		var maps: Array = sd["maps"]
		var n: int = mini(pts.size(), 4096)
		if n <= 0:
			continue
		for j in maps.size():
			## 【20261102d】Ha 走独立纹理族（_ha_sample_shared_sets 预建绑定）
			var ha_i: int = HA_NAMES.find(maps[j])
			if ha_i >= 0:
				continue ## Ha 的 dispatch 在下方单独循环（绑定预建集）
			var mi: int = NAMES.find(maps[j])
			if mi < 0:
				continue
			var slot := s * 5 + j
			_rd.compute_list_set_push_constant(cl,
				PackedInt32Array([pts_base, slot * 4096, n, 0]).to_byte_array(), 16)
			_rd.compute_list_bind_uniform_set(cl, _sample_shared_sets[mi][_front[mi]], 0)
			_rd.compute_list_dispatch(cl, (n + 63) / 64, 1, 1)
		## 【20261102d】Ha 采样 dispatch（预建绑定；槽=侧*5+4）
		var ha_name2: String = "Ha" + str(sd["side"])
		if _ha_sample_shared_sets.size() > s and _ha_sample_shared_sets[s][ _ha_front[s] ] != null:
			_rd.compute_list_set_push_constant(cl,
				PackedInt32Array([pts_base, (s * 5 + 4) * 4096, n, 0]).to_byte_array(), 16)
			_rd.compute_list_bind_uniform_set(cl, _ha_sample_shared_sets[s][_ha_front[s]], 0)
			_rd.compute_list_dispatch(cl, (n + 63) / 64, 1, 1)
		pts_base += n
	_rd.compute_list_end()
	_batch_slots = slots
	_batch_tops = tops

func batch_read() -> Dictionary:
	var out := {}
	if not ok or _batch_slots.is_empty():
		return out
	var t0 := Time.get_ticks_usec()
	var all := _rd.buffer_get_data(_samp_shared, 0, _batch_tops * 4).to_int32_array()
	for mapname in _batch_slots:
		var info: Array = _batch_slots[mapname]
		var b: int = info[0] * 4096
		var n: int = info[1]
		out[mapname] = all.slice(b, b + n)
	_batch_slots.clear()
	_batch_tops = 0
	samp_batch_us = samp_batch_us * 0.9 + float(Time.get_ticks_usec() - t0) * 0.1
	return out

## 会话资源释放（战场 PREDELETE）
## 【P6 修复 20261015】补 free _vals_bufs/_ubos/_samp_shared/_sample_shared_sets——
## 原先每场对战泄漏 8 个回读缓冲 + 8 个 UBO + 合并缓冲
func shutdown() -> void:
	if _rd == null:
		return
	for i in NAMES.size():
		if i < _stamp_sets.size():
			for set_rid in _stamp_sets[i]:
				if set_rid.is_valid():
					_rd.free_rid(set_rid)
		if i < _decay_sets.size():
			for set_rid in _decay_sets[i]:
				if set_rid.is_valid():
					_rd.free_rid(set_rid)
		if i < _sample_sets.size():
			for set_rid in _sample_sets[i]:
				if set_rid.is_valid():
					_rd.free_rid(set_rid)
		## 【22b 20261103·审计#46】Ha 纹理+采样集释放（外部审计泄漏项）
		if i < _ha_sample_shared_sets.size():
			for set_rid in _ha_sample_shared_sets[i]:
				if set_rid != null and set_rid.is_valid():
					_rd.free_rid(set_rid)
		if i < _ha_tex.size():
			for t in _ha_tex[i]:
				if t.is_valid():
					_rd.free_rid(t)
		if i < _sample_shared_sets.size():
			for set_rid in _sample_shared_sets[i]:
				if set_rid.is_valid():
					_rd.free_rid(set_rid)
		if i < _tex.size():
			for rid in _tex[i]:
				if rid.is_valid():
					_rd.free_rid(rid)
	for v in _vals_bufs:
		if v.is_valid():
			_rd.free_rid(v)
	for u in _ubos:
		if u.is_valid():
			_rd.free_rid(u)
	for sb in _stamp_bufs:
		if sb.is_valid():
			_rd.free_rid(sb)
	for rid in [_stamp_pipe, _decay_pipe, _sample_pipe, _stamp_shader_rid, _decay_shader_rid, _sample_shader_rid, _stamp_buf, _samp_shared]:
		if rid.is_valid():
			_rd.free_rid(rid)
	_vals_bufs.clear()
	_ubos.clear()
	_stamp_bufs.clear()
	_sample_shared_sets.clear()
	_disp_cache.clear()
	results.clear()
	ok = false
