extends Node
## special_probe —— m88 特殊弹设四钩探针（反弹/就近消弹/亡计/被弹）
## A 就近消弹：nearclear=80 事件发射→近旁敌对弹清除
## B 亡计：death_evs 事件弹死亡（航程超限）→原位释放亡计事件
## C 反弹弹设：spawn_conv 事件发射→近旁敌对弹原地转化为己方事件弹
## D 被弹弹设：ctx 暴露 self_hitcool（发射上下文/门上下文）
## 【跑法】godot --headless --path . res://Tests/special_probe.tscn → SPECIAL_OK / SPECIAL_FAIL n
var arena: Node2D
var _fails := 0

func _ready() -> void:
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	for i in 8:
		arena._physics_process(1.0 / 60.0)
	_run_all()
	print("SPECIAL_OK" if _fails == 0 else "SPECIAL_FAIL %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _fail(msg: String) -> void:
	_fails += 1
	print("SPECIAL_FAIL: ", msg)

func _mk_ev(nm: String) -> DanmakuEventData:
	var ev := DanmakuEventData.new()
	ev.event_name = nm
	ev.texture = "tama0"
	ev.speed = "2"
	ev.x = "1"
	ev.y = "0"
	ev.range_frames = 300
	return ev

func _count_hostile(side: int, at: Vector2, r: float) -> int:
	var n := 0
	var r2 := r * r
	for b in arena.bullets:
		var bl: Bullet = b
		if bl.source_side != side:
			continue
		var dx: float = bl.pos.x - at.x
		var dy: float = bl.pos.y - at.y
		if dx * dx + dy * dy <= r2:
			n += 1
	return n

func _run_all() -> void:
	var pl = arena.player_leader
	var en = arena.enemy_leader
	if pl == null or en == null:
		_fail("无领队")
		return
	## A. 就近消弹
	var ev_nc := _mk_ev("probe_nc")
	ev_nc.nearclear = 80
	var errsa: Array[String] = ev_nc.compile()
	if not errsa.is_empty():
		_fail("A 编译失败：%s" % errsa[0])
	var n0: int = arena.bullets.size()
	arena._spawn_event_copies(arena._find_event("demo_aimed"), Vector2(230.0, 200.0), en, null, {}, 0)
	var hostile0 := _count_hostile(1, Vector2(200.0, 200.0), 100.0)
	if hostile0 <= 0:
		_fail("A 预置敌对弹失败")
	else:
		arena._spawn_event_copies(ev_nc, Vector2(200.0, 200.0), pl, null, {}, 0)
		var hostile1 := _count_hostile(1, Vector2(200.0, 200.0), 100.0)
		if hostile1 >= hostile0:
			_fail("A 就近消弹未清（%d→%d）" % [hostile0, hostile1])
	if arena.bullets.size() <= n0:
		_fail("A 发射体本身未出现")
	## B. 亡计
	var ev_d := _mk_ev("probe_death")
	ev_d.death_evs = "demo_burst"
	var errsb: Array[String] = ev_d.compile()
	if not errsb.is_empty():
		_fail("B 编译失败：%s" % errsb[0])
	var n0b: int = arena.bullets.size()
	arena._spawn_event_copies(ev_d, Vector2(120.0, 120.0), en, null, {}, 0)
	var carrier: Bullet = null
	for b in arena.bullets:
		if b.ev == ev_d:
			carrier = b
	if carrier == null:
		_fail("B 亡计载体未出现")
	else:
		carrier._alive_frames = carrier.range_now + 10.0 ## 航程超限→死亡
		var n1b: int = arena.bullets.size()
		arena._physics_process(1.0 / 60.0) ## 一帧主循环→死亡回收+亡计释放
		var burst_n := 0
		for b2 in arena.bullets:
			if b2.ev != null and b2.ev.event_name == "demo_burst":
				burst_n += 1
		if arena.bullets.size() <= n1b and burst_n == 0:
			_fail("B 亡计未释放（burst=%d）" % burst_n)
	## C. 反弹弹设
	var ev_cv := _mk_ev("probe_conv")
	ev_cv.spawn_conv = "demo_burst,60"
	var errsc: Array[String] = ev_cv.compile()
	if not errsc.is_empty():
		_fail("C 编译失败：%s" % errsc[0])
	arena._spawn_event_copies(arena._find_event("demo_aimed"), Vector2(300.0, 300.0), en, null, {}, 0)
	var hostile_c0 := _count_hostile(1, Vector2(300.0, 300.0), 60.0)
	var own_c0 := _count_hostile(0, Vector2(300.0, 300.0), 60.0)
	arena._spawn_event_copies(ev_cv, Vector2(300.0, 300.0), pl, null, {}, 0)
	var hostile_c1 := _count_hostile(1, Vector2(300.0, 300.0), 60.0)
	var own_c1 := _count_hostile(0, Vector2(300.0, 300.0), 60.0)
	if hostile_c1 != 0 and hostile_c1 >= hostile_c0:
		_fail("C 反弹未转化（敌%d→%d）" % [hostile_c0, hostile_c1])
	if own_c1 <= own_c0:
		_fail("C 转化弹未归属己方（%d→%d）" % [own_c0, own_c1])
	## D. 被弹弹设 ctx
	var c0: Dictionary = arena._rot_eval_ctx(pl, null)
	if not c0.has("self_hitcool") or float(c0["self_hitcool"]) != 0.0:
		_fail("D ctx 缺 self_hitcool 或初值错")
	pl.immune_frames = 30
	var c1: Dictionary = arena._rot_eval_ctx(pl, null)
	if float(c1["self_hitcool"]) != 1.0:
		_fail("D 被弹冷却未置 1")
	pl.immune_frames = 0
