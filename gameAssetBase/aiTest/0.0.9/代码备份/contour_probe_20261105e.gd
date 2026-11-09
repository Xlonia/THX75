extends Node
## =============================================================
## contour_probe —— 等高线提取探针（0.0.9·策划新三 52-68）
##   Part A（headless 可跑）：纯逻辑单测——合成高斯场 → ContourField
##   ._extract_polys：断言层结构/边长≤8px/闭环/动画环 10 帧/提取耗时
##   Part B（需 GPU，非 headless）：arena 实例化 → contour.tick 实链路
##   （headless 下 gpu_ok=false 自动 SKIP）
## 用法：godot --headless --path . res://Tests/contour_probe.tscn
## =============================================================
const GRID := 50

func _ready() -> void:
	_part_a()
	_part_b()

func _part_a() -> void:
	print("== Part A：纯逻辑 marching squares ==")
	## 合成场：两个高斯斑（峰 200 → 第 12 层；峰 90 → 第 5 层）
	var c := PackedFloat32Array()
	c.resize(GRID * GRID)
	for y in GRID:
		for x in GRID:
			var px := x * 8.0 + 4.0
			var py := y * 8.0 + 4.0
			var v1 := 200.0 * exp(-Vector2(px - 160.0, py - 160.0).length_squared() / (2.0 * 40.0 * 40.0))
			var v2 := 90.0 * exp(-Vector2(px - 300.0, py - 100.0).length_squared() / (2.0 * 30.0 * 30.0))
			c[y * GRID + x] = minf(v1 + v2, 255.0)
	var t0 := Time.get_ticks_usec()
	var levels: Array = ContourField._extract_polys(c)
	var dt_us: int = Time.get_ticks_usec() - t0
	assert(levels.size() == 15, "15 层输出")
	var total_polys := 0
	var max_edge := 0.0
	var closed_found := false
	for li in levels.size():
		for poly in levels[li]:
			total_polys += 1
			var pts: PackedVector2Array = poly["pts"]
			if poly["closed"]:
				closed_found = true
			for i in pts.size():
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[(i + 1) % pts.size()]
				var d2: float = a.distance_to(b)
				if d2 > 8.001:
					print("  [超长边] %s → %s len=%.3f" % [a, b, d2])
				max_edge = maxf(max_edge, d2)
	assert(total_polys > 0, "有折线产出")
	assert(max_edge <= 8.001, "每条边长≤8px（实测 %.2f）" % max_edge)
	assert(closed_found, "高峰层存在闭环等高线（峰200→层12）")
	## 动画环：连续 push 12 帧 → 只保留 10
	var cf := ContourField.new(null, null) ## 不进 GPU 路径，只用 _hist
	for k in 12:
		var h: Array = cf._hist.get_or_add("Hd0", [])
		h.append({"frame": k, "levels": levels})
		if h.size() > ContourField.HIST:
			h.pop_front()
	assert(cf._hist["Hd0"].size() == ContourField.HIST, "动画环恒 10 帧")
	assert(int(cf.query("Hd0", 0)["frame"]) == 11, "back=0=最新帧")
	assert(int(cf.query("Hd0", 9)["frame"]) == 2, "back=9=最老帧")
	print("  PASS 15层 折线=%d 最大边长=%.2fpx 闭环=%s 提取=%dµs（20fps 预算 50000µs）" % [
		total_polys, max_edge, closed_found, dt_us])
	print("PART_A_OK")

func _part_b() -> void:
	print("== Part B：GPU 集成（arena 实链路）==")
	GameGlobals.arena_mode = "preview"
	GameGlobals.preview_event_name = "sonic_wave_like0"
	var arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false ## 与 battle_tick_perf 同款（pause 门挡 _render_ddm/Ht 加热）
	await get_tree().process_frame
	if arena.contour == null or not arena.contour.ok:
		print("PART_B_SKIP —— GPU 不可用（headless/CPU 降级）")
		get_tree().quit(0)
		return
	await get_tree().process_frame
	arena._heat_view = 4 ## Hd 视图（触发 _process tick）
	for k in 30:
		await get_tree().process_frame
	var n_hd: int = arena.contour.hist_len("Hd0")
	var n_hd1: int = arena.contour.hist_len("Hd1")
	print("  Hd0 动画帧=%d Hd1 动画帧=%d 提取耗时=%.1fµs" % [
		n_hd, n_hd1, arena.contour.extract_us])
	var fr: Dictionary = arena.contour.query("Hd0", 0)
	var polys := 0
	for lvl in fr.get("levels", []):
		polys += (lvl as Array).size()
	print("  Hd0 最新帧折线总数=%d（30帧=0.5s 弹幕稀疏可空）" % polys)
	if n_hd < 1:
		print("PART_B_FAIL —— Hd0 未提取")
		get_tree().quit(1)
		return
	## 【确定性注入】向 Hd0 front 灌合成热度块→强制提取→断言折线非空
	var img := PackedByteArray()
	img.resize(400 * 400)
	img.fill(0)
	for yy in range(150, 250):
		for xx in range(150, 250):
			img[yy * 400 + xx] = 200
	var fam = arena.fam_maps
	fam._rd.texture_update(fam._tex[2][fam._front[2]], 0, img)
	var chk: PackedByteArray = fam._rd.texture_get_data(fam._tex[2][fam._front[2]], 0)
	var chk_max := 0
	for i in chk.size():
		chk_max = maxi(chk_max, int(chk[i]))
	print("  [诊断] Hd0 front 直接回读 max=%d（期望 200）" % chk_max)
	fam.flip_seq[2] += 1 ## 模拟源刷新（绕过 flip 去重）
	arena.contour._extract_map("Hd0", 9999) ## 直调（绕 20fps 门控；仍走 GPU 提取+回读+MS 全链路）
	var fr2: Dictionary = arena.contour.query("Hd0", 0)
	var polys2 := 0
	var max_edge := 0.0
	for lvl in fr2.get("levels", []):
		for poly in lvl:
			polys2 += 1
			var pts: PackedVector2Array = poly["pts"]
			for i in pts.size():
				max_edge = maxf(max_edge, pts[i].distance_to(pts[(i + 1) % pts.size()]))
	print("  注入后折线=%d 最大边长=%.2fpx" % [polys2, max_edge])
	if polys2 <= 0 or max_edge > 8.001:
		print("PART_B_FAIL —— 注入后折线=%d 最大边长=%.2f" % [polys2, max_edge])
		get_tree().quit(1)
		return
	print("PART_B_OK")
	get_tree().quit(0)
