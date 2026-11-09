extends Node
## =============================================================
## ddm_tail_probe —— DDM 印章缓冲"陈旧尾部"幽灵印章 确定性复现（20261109）
##   帧1：200 枚印章铺满区域 A（左上）→ 帧2：只 5 枚在区域 B（右下）
##   shader 守卫若用 stamps.data.length()（=缓冲容量 16384）而非本帧数量 n，
##   dispatch 按 64 向上取整 → 线程 5..63 读到帧1 残留印章 → 区域 A 出现
##   "无弹之章"（屏幕无弹、DDM 有章→Ht 加热=作者所见"诈尸"）
## 用法（需 GPU，非 headless）：godot --path . res://Tests/ddm_tail_probe.tscn
## =============================================================
func _ready() -> void:
	var rd: RenderingDevice = GameGlobals.arena_rendering_device()
	if rd == null:
		print("TAIL_SKIP —— 无 RD（headless）")
		get_tree().quit(0)
		return
	var ddm := DdmGpu.new(rd)
	if not ddm.ok:
		print("TAIL_SKIP —— DdmGpu 不可用")
		get_tree().quit(0)
		return
	var a := PackedFloat32Array()
	for k in 200:
		a.append(20.0 + float(k % 20) * 8.0)            ## x 20..172
		a.append(20.0 + floorf(float(k) / 20.0) * 8.0)  ## y 20..92
		a.append(3.0)
		a.append(0.0)
	ddm.render(a)
	var white_a1 := _count(rd, ddm, Rect2i(0, 0, 200, 120))
	var b := PackedFloat32Array()
	for k in 5:
		b.append(300.0 + float(k) * 10.0)
		b.append(300.0)
		b.append(3.0)
		b.append(0.0)
	ddm.render(b)
	var ghost := _count(rd, ddm, Rect2i(0, 0, 200, 120))
	var real_b := _count(rd, ddm, Rect2i(280, 280, 100, 40))
	## 帧3：0 枚（全场无弹）——stamp dispatch 跳过，A 必须干净
	ddm.render(PackedFloat32Array())
	var ghost0 := _count(rd, ddm, Rect2i(0, 0, 200, 120))
	print("帧1 区域A白=%d | 帧2(5枚在B) B白=%d A幽灵白=%d | 帧3(0枚) A幽灵白=%d" % [
		white_a1, real_b, ghost, ghost0])
	## 【轨迹印章 traj_stamp（He/Hr/Hp）同构验证】fam 衰减上限 0.985→无新章像素
	## ≤251；幽灵章恒写 255——区域 A 出现 255=陈旧尾部幽灵
	var fam := FamilyMaps.new(rd, ddm.image_rid())
	var fam_ghost := -1
	var fam_a1 := -1
	if fam.ok:
		var pa := PackedFloat32Array()
		for k in 200:
			pa.append(20.0 + float(k % 20) * 8.0)
			pa.append(20.0 + floorf(float(k) / 20.0) * 8.0)
		fam.advance(0, pa)
		fam_a1 = _count255(rd, fam._tex[0][fam._front[0]], Rect2i(0, 0, 200, 120))
		var pb := PackedFloat32Array()
		for k in 5:
			pb.append(300.0 + float(k) * 10.0)
			pb.append(300.0)
		fam.advance(0, pb)
		fam_ghost = _count255(rd, fam._tex[0][fam._front[0]], Rect2i(0, 0, 200, 120))
		print("fam He0 帧1 区域A满白=%d | 帧2(5点在B) 区域A满白(幽灵)=%d" % [fam_a1, fam_ghost])
		fam.shutdown()
	else:
		print("fam SKIP（FamilyMaps 不可用）")
	ddm.shutdown()
	if white_a1 <= 0 or real_b <= 0:
		print("TAIL_FAIL —— 基准印章未落图（管线异常）")
		get_tree().quit(1)
	elif ghost > 0 or ghost0 > 0 or fam_ghost > 0:
		print("TAIL_GHOST —— 复现：DDM 幽灵 %d 像素 / fam 幽灵 %d 像素" % [ghost, fam_ghost])
		get_tree().quit(1)
	elif fam.ok and fam_a1 <= 0:
		print("TAIL_FAIL —— fam 基准印章未落图")
		get_tree().quit(1)
	else:
		print("TAIL_OK")
		get_tree().quit(0)

func _count255(rd: RenderingDevice, tex: RID, r: Rect2i) -> int:
	var raw: PackedByteArray = rd.texture_get_data(tex, 0)
	var n := 0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if raw[y * 400 + x] == 255:
				n += 1
	return n

func _count(rd: RenderingDevice, ddm: DdmGpu, r: Rect2i) -> int:
	var raw: PackedByteArray = rd.texture_get_data(ddm.image_rid(), 0)
	var n := 0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if raw[y * 400 + x] > 128:
				n += 1
	return n
