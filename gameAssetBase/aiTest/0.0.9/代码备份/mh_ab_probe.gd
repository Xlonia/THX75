extends Node
## =============================================================
## mh_ab_probe —— MotionHot 完整状态接管 A/B 位级对账（审计①-1 20261109）
##   同种子、同场景（真实默认队），物理逐步直驱（不经实时节流）：
##   A 轮 motion_hot_enabled=true（C++ 接管）/ B 轮 =false（纯 GD 原路径）
##   每 30 帧记录全弹快照（事件名|侧|pos 量化 1e-4|t|存活帧），两轮逐帧比对：
##   弹数一致 + 每弹状态一致（排序后逐项）——位级等价=接管语义零偏差
##   另记 A 轮接管弹占比与物理耗时中位
## 用法：godot --headless --path . res://Tests/mh_ab_probe.tscn
## =============================================================
const FRAMES := 900
const SNAP_EVERY := 30
const FINE_FROM := 700 ## 精查窗口：逐帧快照
const FINE_TO := 760
const SEED := 20261109
const CONTROL := false ## true=B vs B 对照（验证测试台确定性）
const MODE := "motion" ## motion=MotionHot接管A/B；hash=C++哈希A/B

var run := 0
var arena: Node2D
var step := 0
var snaps := [{}, {}]
var useq := [{}, {}]
var ents := [{}, {}]
var phys := [[], []]
var owned_ratio: Array = []

func _ready() -> void:
	_start()

func _start() -> void:
	seed(SEED)
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	step = 0
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	arena.motion_hot_enabled = (run == 0) and MODE == "motion" and not CONTROL
	if MODE == "hash":
		arena.bullet_hash_cpp_enabled = (run == 0) ## 两轮都纯 GD 运动，只切哈希实现
	_seeded = false

var _seeded := false

func _process(_d: float) -> void:
	if arena == null or not arena.is_inside_tree():
		return
	## 加载屏（_loading）期间不计；首个战斗帧前定种子——两轮从同一时钟起点对齐
	if not _seeded and not arena._loading:
		seed(SEED)
		## 测试台确定性：①采样平滑固定关（设置文件可能 N>1——GD 采样插值 vs
		## C++ 逐帧精确本就不同）②态势卡系统独立 RNG 实例（未受 seed() 控制）
		arena._sample_n = 1
		var k := 0
		for e in arena.entities:
			if e is BattleEntity and e.get("sit_cards") != null and e.sit_cards.get("rng") != null:
				e.sit_cards.rng.seed = SEED + k
				k += 1
		_seeded = true
	var t0 := Time.get_ticks_usec()
	arena._physics_process(1.0 / 60.0)
	if not _seeded:
		return
	phys[run].append(float(Time.get_ticks_usec() - t0) / 1000.0)
	step = arena.time_frames
	## 实体全状态逐帧（位置/HP/AP/死亡）——定位"实体先分歧、弹后受影响"
	var er := ""
	for e in arena.entities:
		if e is BattleEntity:
			er += "%s:%.4f,%.4f,%s,%d,%s;" % [e.chara_name(), e.position.x, e.position.y, str(e.hp), e.ap, str(e.dead)]
	ents[run][step] = er
	if (step % SNAP_EVERY == 0 or (step >= FINE_FROM and step <= FINE_TO)) and not snaps[run].has(step):
		var rows: Array = []
		var own := 0
		for b in arena.bullets:
			if b._mh_owned:
				own += 1
			rows.append("%s|%d|%.4f|%.4f|%.1f|%.1f" % [b.ev.event_name, b.source_side,
				b.pos.x, b.pos.y, b.t, b._alive_frames])
		## 精查窗口：另存未排序全状态（数组顺序+隐藏态），定位"集合相同、顺序/隐态不同"
		if step >= FINE_FROM and step <= FINE_TO:
			var urows: Array = []
			for ub in arena.bullets:
				urows.append("%s|%.4f,%.4f|t%.1f|v%.3f,%.3f|d%.4f,%.4f|h%s|r%.2f" % [ub.ev.event_name, ub.pos.x, ub.pos.y,
					ub.t, ub.velocity.x, ub.velocity.y, ub.dir.x, ub.dir.y, str(ub.hidden_now), ub.hit_radius()])
			useq[run][step] = urows
		rows.sort()
		snaps[run][step] = rows
		if run == 0 and arena.bullets.size() > 0:
			owned_ratio.append(float(own) / float(arena.bullets.size()))
	if step >= FRAMES:
		if run == 0:
			run = 1
			var old := arena
			arena = null
			old.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
			_start()
		else:
			_report()

func _report() -> void:
	for ef in range(1, FRAMES + 1):
		if ents[0].has(ef) and ents[1].has(ef) and ents[0][ef] != ents[1][ef]:
			var ea: PackedStringArray = String(ents[0][ef]).split(";")
			var eb: PackedStringArray = String(ents[1][ef]).split(";")
			print("  [实体首差] f=%d" % ef)
			for q in mini(ea.size(), eb.size()):
				if ea[q] != eb[q]:
					print("    A=%s
    B=%s" % [ea[q], eb[q]])
					break
			break
	for uf in range(FINE_FROM, FINE_TO + 1):
		var ua: Array = useq[0].get(uf, [])
		var ub2: Array = useq[1].get(uf, [])
		if ua != ub2:
			print("  [未排序首差] f=%d A长=%d B长=%d" % [uf, ua.size(), ub2.size()])
			var ca := {}
			var cb := {}
			for x in ua:
				ca[x] = int(ca.get(x, 0)) + 1
			for y in ub2:
				cb[y] = int(cb.get(y, 0)) + 1
			for x2 in ca:
				if int(cb.get(x2, 0)) < int(ca[x2]):
					print("    仅A: %s" % x2)
			for y2 in cb:
				if int(ca.get(y2, 0)) < int(cb[y2]):
					print("    仅B: %s" % y2)
			## 前一帧（双方一致）中，与差异弹相关的同名弹全量
			print("    —— f=%d（一致帧）全部 demo_missile/与差异同位弹：" % (uf - 1))
			var prev: Array = useq[0].get(uf - 1, [])
			for qi in prev.size():
				if String(prev[qi]).begins_with("demo_missile"):
					print("      idx=%d %s" % [qi, prev[qi]])
			break
	var mism := 0
	var first_bad := -1
	var detail := ""
	for f in snaps[0]:
		var a: Array = snaps[0][f]
		var b: Array = snaps[1].get(f, [])
		if a != b:
			mism += 1
			if first_bad < 0 or f < first_bad:
				first_bad = f
				detail = "f=%d A弹=%d B弹=%d" % [f, a.size(), b.size()]
				for k in mini(a.size(), b.size()):
					if a[k] != b[k]:
						detail += "\n    首差 A=%s\n         B=%s" % [a[k], b[k]]
						break
	var pa: Array = phys[0].duplicate()
	var pb: Array = phys[1].duplicate()
	pa.sort()
	pb.sort()
	var ow := 0.0
	for r in owned_ratio:
		ow += r
	ow = ow / maxf(1.0, float(owned_ratio.size()))
	var last_f: int = FRAMES - FRAMES % SNAP_EVERY
	print("=== MotionHot A/B 对账（种子 %d，%d 帧，每 %d 帧快照）===" % [SEED, FRAMES, SNAP_EVERY])
	print("  快照 %d 组，不一致 %d 组；末帧弹数 A=%d B=%d" % [snaps[0].size(), mism,
		(snaps[0].get(last_f, []) as Array).size(), (snaps[1].get(last_f, []) as Array).size()])
	print("  A 轮接管弹平均占比=%.0f%%（hash 模式恒 0）" % (ow * 100.0))
	print("  物理中位：A=%.2fms  B=%.2fms（motion:A=C++接管/B=纯GD；hash:A=C++哈希/B=GD哈希）" % [pa[pa.size() / 2], pb[pb.size() / 2]])
	if mism == 0:
		print("MH_AB_OK —— 位级等价")
		get_tree().quit(0)
	else:
		print("MH_AB_DIFF —— " + detail)
		get_tree().quit(1)
