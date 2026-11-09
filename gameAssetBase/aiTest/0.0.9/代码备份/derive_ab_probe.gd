extends Node
## =============================================================
## derive_ab_probe —— 审计 B4 派生 pass 改造 位级+耗时对账（需 GPU，非 headless）
##   本地 RD 上：随机 Ht + 随机旧 Hd 输入
##   旧=Tests/ht_derive_ref.glsl（Hd+Ha 同 shader、每像素重算 625 块和、派发两次）
##   新=shaders/ht_derive.glsl（仅 Hd）+ shaders/ha_block.glsl（区块 pass）
##   比对 Hd/Ha 输出逐字节；各跑 N 次 submit+sync 计时（含驱动开销上限）
## 用法：godot --path . res://Tests/derive_ab_probe.tscn
## =============================================================
const N := 20

func _ready() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		print("DERIVE_SKIP —— 无本地 RD（headless）")
		get_tree().quit(0)
		return
	var fmt := RDTextureFormat.new()
	fmt.width = 400
	fmt.height = 400
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	seed(1109)
	var src_img := PackedByteArray()
	var old_img := PackedByteArray()
	src_img.resize(160000)
	old_img.resize(160000)
	for i in 160000:
		## 热区+冷区混合（含 0 与满值），覆盖 floor/round 边界
		src_img[i] = (randi() % 256) if (i / 400 + i % 400) % 7 != 0 else 0
		old_img[i] = randi() % 256
	var zero := PackedByteArray()
	zero.resize(160000)
	var t_src := rd.texture_create(fmt, RDTextureView.new(), [src_img])
	var t_old := rd.texture_create(fmt, RDTextureView.new(), [old_img])
	var a_hd := rd.texture_create(fmt, RDTextureView.new(), [zero])
	var a_ha := rd.texture_create(fmt, RDTextureView.new(), [zero])
	var b_hd := rd.texture_create(fmt, RDTextureView.new(), [zero])
	var b_ha := rd.texture_create(fmt, RDTextureView.new(), [zero])
	var sh_ref: RID = rd.shader_create_from_spirv((load("res://Tests/ht_derive_ref.glsl") as RDShaderFile).get_spirv())
	var sh_hd: RID = rd.shader_create_from_spirv((load("res://shaders/ht_derive.glsl") as RDShaderFile).get_spirv())
	var sh_ha: RID = rd.shader_create_from_spirv((load("res://shaders/ha_block.glsl") as RDShaderFile).get_spirv())
	if not (sh_ref.is_valid() and sh_hd.is_valid() and sh_ha.is_valid()):
		print("DERIVE_FAIL —— SPIRV 无效 ref=%s hd=%s ha=%s" % [sh_ref.is_valid(), sh_hd.is_valid(), sh_ha.is_valid()])
		get_tree().quit(1)
		return
	var p_ref := rd.compute_pipeline_create(sh_ref)
	var p_hd := rd.compute_pipeline_create(sh_hd)
	var p_ha := rd.compute_pipeline_create(sh_ha)
	var s_ref := rd.uniform_set_create([_u(t_src, 0), _u(a_hd, 1), _u(a_ha, 2), _u(t_old, 3)], sh_ref, 0)
	var s_hd := rd.uniform_set_create([_u(t_src, 0), _u(b_hd, 1), _u(t_old, 2)], sh_hd, 0)
	var s_ha := rd.uniform_set_create([_u(t_src, 0), _u(b_ha, 1)], sh_ha, 0)
	## 预热（管线首编译不计）
	_run_old(rd, p_ref, s_ref)
	_run_new(rd, p_hd, s_hd, p_ha, s_ha)
	var t_old_us := 0.0
	var t_new_us := 0.0
	for k in N:
		var t0 := Time.get_ticks_usec()
		_run_old(rd, p_ref, s_ref)
		var t1 := Time.get_ticks_usec()
		_run_new(rd, p_hd, s_hd, p_ha, s_ha)
		var t2 := Time.get_ticks_usec()
		t_old_us += float(t1 - t0)
		t_new_us += float(t2 - t1)
	var d_hd := _diff(rd.texture_get_data(a_hd, 0), rd.texture_get_data(b_hd, 0))
	var d_ha := _diff(rd.texture_get_data(a_ha, 0), rd.texture_get_data(b_ha, 0))
	print("DERIVE Hd 不等像素=%d  Ha 不等像素=%d（各 160000）" % [d_hd, d_ha])
	print("DERIVE 每拍单侧耗时（submit+sync 墙钟，%d 次均值）：旧=%.0fµs 新=%.0fµs" % [N, t_old_us / N, t_new_us / N])
	rd.free()
	if d_hd == 0 and d_ha == 0:
		print("DERIVE_OK —— 位级等价")
		get_tree().quit(0)
	else:
		print("DERIVE_DIFF")
		get_tree().quit(1)

func _u(rid: RID, b: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = b
	u.add_id(rid)
	return u

func _run_old(rd: RenderingDevice, p: RID, s: RID) -> void:
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, p)
	rd.compute_list_bind_uniform_set(cl, s, 0)
	rd.compute_list_dispatch(cl, 50, 50, 1)
	rd.compute_list_dispatch(cl, 50, 50, 1) ## 原实现的重复第二次派发
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func _run_new(rd: RenderingDevice, p1: RID, s1: RID, p2: RID, s2: RID) -> void:
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, p1)
	rd.compute_list_bind_uniform_set(cl, s1, 0)
	rd.compute_list_dispatch(cl, 50, 50, 1)
	rd.compute_list_bind_compute_pipeline(cl, p2)
	rd.compute_list_bind_uniform_set(cl, s2, 0)
	rd.compute_list_dispatch(cl, 1, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func _diff(a: PackedByteArray, b: PackedByteArray) -> int:
	var n := 0
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			n += 1
	return n
