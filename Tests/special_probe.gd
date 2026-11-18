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
	if pl.sit_cards == null:
		pl.sit_cards = SitCardSystem.new() ## 防御兜底（n/s 释放链 on_released 需要）
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
	## E. 留空选择器=全场敌对弹（m90 scheme 修正：不再回退圆形）
	var ev_iv = _mk_ev("probe_iv_base")
	ev_iv.range_frames = 600
	ev_iv.rotate_div = "2"
	ev_iv.rotate_range = "0.5*pi"
	arena._spawn_event_copies(ev_iv, Vector2(40.0, 40.0), en, null, {}, 0)
	arena._spawn_event_copies(ev_iv, Vector2(360.0, 360.0), en, null, {}, 0)
	var base_n := 0
	for b0 in arena.bullets:
		if b0.source_side == 1 and b0.ev != null and b0.ev.event_name == "probe_iv_base":
			base_n += 1
	if base_n < 2:
		_fail("E 预置弹未展开（n=%d）" % base_n)
	arena._run_sel_op(pl, {"op": "inverse", "params": "ev:demo_burst", "ev": ""}, {"svg": {}, "r": 80.0})
	var conv := 0
	for b in arena.bullets:
		if b.source_side == 1 and b.ev != null and b.ev.event_name == "probe_iv_base" + "_conv":
			conv += 1
	if conv != 0:
		_fail("E 不应发生（校验逻辑错）")
	var conv2 := 0
	for b1 in arena.bullets:
		if b1.source_side == 1 and b1.ev != null and b1.ev.event_name == "demo_burst" \
				and (b1.pos.distance_to(Vector2(40.0, 40.0)) < 30.0 or b1.pos.distance_to(Vector2(360.0, 360.0)) < 30.0):
			conv2 += 1
	if conv2 < 2:
		_fail("E 留空选择器未达全场（近远角转化=%d，应≥2）" % conv2)
	## F. 三档符卡挂载（m90：n=skill_evs / s=spell_s_evs / m=spell_evs）
	pl.db["skill_evs"] = "spell_classical"
	pl.db["spell_s_evs"] = "spell_classical"
	var runs_n: int = arena._spell_runs.size()
	arena._apply_release(pl, "n")
	var ok_n := false
	for r in arena._spell_runs:
		if r["ent"] == pl and r.get("spell") != null and r["spell"].spell_name == "spell_classical":
			ok_n = true
	if not ok_n or arena._spell_runs.size() <= runs_n:
		_fail("F 能力档纯定义挂载未发生")
	pl.sit_cards.spell_ready = true
	pl.spell_cards = 1
	var runs_s: int = arena._spell_runs.size()
	arena._apply_release(pl, "s")
	var ok_s := false
	for r2 in arena._spell_runs:
		if r2["ent"] == pl and r2.get("spell") != null and r2["spell"].spell_name == "spell_classical":
			ok_s = true
	if not ok_s or arena._spell_runs.size() <= runs_s:
		_fail("F 符卡档纯定义挂载未发生")
	## I. 【m95】弹幕选择器函数链（radius(120) 解析+链式约束）
	var dsel: Dictionary = BulletOps.parse_dsel("radius(120).older(30)")
	if str(dsel.get("shape", "")) != "circle" or float(dsel.get("r", 0)) != 120.0 			or float(dsel.get("t_min", 0)) != 30.0:
		_fail("I 弹幕函数链解析错（%s）" % str(dsel))
	## I2. iterate=敌侧遍历（固定返回类型环境——作者 20261118 语义）
	var it0: Array = EntityOps.resolve("iterate(hp>>0)", pl, arena)
	var en_ok := true
	for e9 in it0:
		if int(e9.get("side")) != 1:
			en_ok = false
	if it0.is_empty() or not en_ok:
		_fail("I2 iterate 未限定敌侧（n=%d）" % it0.size())
	## I3. geniterate(命题,类型)=跨类型显式（private 类型可取）
	var gi: Array = EntityOps.resolve("geniterate(hp>>0,private)", pl, arena)
	if gi.is_empty():
		_fail("I3 geniterate private 类型未取到杂兵")
