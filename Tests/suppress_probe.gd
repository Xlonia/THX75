extends Node
## suppress_probe —— 方案C 超阈值打压护栏探针（m84 20261117）
## A. 事件预备档案：demo_aimed（rpt_f=4/range=300）→ sup_class=真/折半缓存=2/150
## B. 阈下出生=原参数（300/4）
## C. 超阈出生=减半（range 300→150、freq 4→2）
## D. 豁免勾选=不减半（300/4 原样）
## E. 非重复类（autorot_check rpt_f=0）超阈也不减半（方案C 只打压高重复类）
## 【跑法】godot --headless --path . res://Tests/suppress_probe.tscn → SUPPRESS_OK / SUPPRESS_FAIL n
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
		arena._physics_process(1.0 / 60.0) ## 热身（态势卡懒初始化同款）
	_run_all()
	print("SUPPRESS_OK" if _fails == 0 else "SUPPRESS_FAIL %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _fail(msg: String) -> void:
	_fails += 1
	print("SUPPRESS_FAIL: ", msg)

func _spawn_one(ev) -> Bullet:
	var n0: int = arena.bullets.size()
	arena._spawn_event_copies(ev, Vector2(200.0, 200.0), arena.player_leader, null, {}, 0)
	if arena.bullets.size() <= n0:
		return null
	return arena.bullets[arena.bullets.size() - 1]

func _run_all() -> void:
	var ev = arena._find_event("demo_aimed")
	if ev == null:
		_fail("demo_aimed 未解析")
		return
	## A. 编译期预备档案（官方装载即 compile——零运行时求值的承诺面）
	if not ev.sup_class:
		_fail("sup_class 应为真（repeat_freq=4）")
	if ev.sup_half_freq != 2 or absf(ev.sup_half_range - 150.0) > 0.01:
		_fail("折半缓存错（freq=%d range=%.1f）" % [int(ev.sup_half_freq), float(ev.sup_half_range)])
	## B. 阈下出生=原参数
	arena.bullet_suppress_at = 999999
	var b0: Bullet = _spawn_one(ev)
	if b0 == null or absf(b0.range_now - 300.0) > 0.01 or int(b0.repeat_freq_now) != 4:
		_fail("阈下参数被改动（range=%.1f freq=%d）" % [
			-1.0 if b0 == null else b0.range_now, -1 if b0 == null else int(b0.repeat_freq_now)])
	## C. 超阈出生=减半
	arena.bullet_suppress_at = arena.bullets.size() - 1
	var b1: Bullet = _spawn_one(ev)
	if b1 == null or absf(b1.range_now - 150.0) > 0.01 or int(b1.repeat_freq_now) != 2:
		_fail("超阈未减半（range=%.1f freq=%d）" % [
			-1.0 if b1 == null else b1.range_now, -1 if b1 == null else int(b1.repeat_freq_now)])
	## D. 豁免勾选=原样
	ev.suppress_exempt = true
	var b2: Bullet = _spawn_one(ev)
	if b2 == null or absf(b2.range_now - 300.0) > 0.01 or int(b2.repeat_freq_now) != 4:
		_fail("豁免失效（range=%.1f freq=%d）" % [
			-1.0 if b2 == null else b2.range_now, -1 if b2 == null else int(b2.repeat_freq_now)])
	ev.suppress_exempt = false
	## E. 非重复类不打压
	var evn = arena._find_event("autorot_check")
	if evn == null:
		_fail("autorot_check 未解析")
		return
	arena.bullet_suppress_at = arena.bullets.size() - 1
	var b3: Bullet = _spawn_one(evn)
	if b3 == null or absf(b3.range_now - 300.0) > 0.01:
		_fail("非重复类被误减半（range=%.1f）" % (-1.0 if b3 == null else b3.range_now))
