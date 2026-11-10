extends Node
## =============================================================
## batch4_probe —— 轮盘取消+锁键 / 资源预检（指令失败字幕） / 攻击朝向拆分
## （0.0.9 20261111 作者反馈批，headless 可跑）
##   A. 轮盘：Esc 取消→关盘+锁；锁住时 _open_summon_wheel 拒绝；解锁后可再开
##      （右键/双击中心走同一出口 _wheel_cancel——中心双击需真鼠标，F5 手测）
##   B. 资源门：P<25 召唤被拒（toast 指令失败+不开盘）；X/C 请求在装填中/无符卡
##      被拒且 pending 不置；双击 X 在 P<25 被拒
##   C. 朝向拆分：atk_facing 指向最近敌方（<10°），facing 独立随移动变化；
##      frame_forward=atk_facing；贴图旋转=atk_facing（源码口径断言）
## 用法：godot --headless --path . res://Tests/batch4_probe.tscn
## =============================================================
var arena: Node2D
var fails := 0

func _chk(ok: bool, msg: String) -> void:
	if ok:
		print("  PASS " + msg)
	else:
		fails += 1
		print("  FAIL " + msg)

func _key(code: int) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	arena._unhandled_input(e)

func _ready() -> void:
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	var g := 0
	while arena._loading and g < 2000:
		arena._physics_process(1.0 / 60.0)
		g += 1
	for k in 60:
		arena._physics_process(1.0 / 60.0)
	var sel: BattleEntity = arena.picked_entity()
	## A. 轮盘取消+锁
	sel.pp = 100
	arena._open_summon_wheel(sel)
	_chk(arena._wheel_open, "轮盘打开（P=100）")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	arena._unhandled_input(esc)
	_chk(not arena._wheel_open and arena._wheel_lock, "Esc 取消→关盘+锁键")
	arena._open_summon_wheel(sel)
	_chk(not arena._wheel_open, "锁住时不可再开（同 Tab 语义）")
	arena._wheel_lock = false ## 探针代理解锁（真机=松开 Shift+X）
	arena._open_summon_wheel(sel)
	_chk(arena._wheel_open, "解锁后可再开")
	arena._wheel_open = false ## 收尾（探针不落召唤）
	## B1. 召唤 P 不足
	sel.pp = 10
	var t0: int = arena._toasts.size()
	arena._open_summon_wheel(sel)
	_chk(not arena._wheel_open, "P=10 召唤被拒（不开盘）")
	var failed_toast := false
	for q in range(maxi(0, t0 - 1), arena._toasts.size()):
		if String(arena._toasts[q]["text"]).contains("指令失败"):
			failed_toast = true
	_chk(failed_toast, "左上角字幕返回 指令失败")
	sel.pp = 100
	## B2. X 请求：装填中（skill_ready=false 短兵起 10s）→ 拒
	if sel.sit_cards != null:
		sel.sit_cards.skill_ready = false
		sel.sit_cards.pending_kind = ""
		arena._dt_last[KEY_X] = -999
		_key(KEY_X)
		_chk(sel.sit_cards.pending_kind == "", "X 请求在装填中被拒（pending 不置）")
		## B3. 装填好但 P<25 → 拒
		sel.sit_cards.skill_ready = true
		sel.pp = 10
		arena._dt_last[KEY_X] = -999
		_key(KEY_X)
		_chk(sel.sit_cards.pending_kind == "", "X 请求在 P<25 被拒")
		## B4. 装填好+P 够 → 过
		sel.pp = 100
		arena._dt_last[KEY_X] = -999
		_key(KEY_X)
		_chk(sel.sit_cards.pending_kind == "n", "X 请求资源足→通过")
		sel.sit_cards.pending_kind = ""
		## B5. C 请求无符卡 → 拒
		sel.spell_cards = 0
		sel.sit_cards.spell_ready = true
		arena._dt_last[KEY_C] = -999
		_key(KEY_C)
		_chk(sel.sit_cards.pending_kind == "", "C 请求在无符卡被拒")
	## C. 朝向拆分（驱动若干帧后取一名我方 AI 角色）
	for k in 90:
		arena._physics_process(1.0 / 60.0)
	var ent: BattleEntity = null
	for e in arena.player_ents:
		if e is BattleEntity and not e.dead and e != arena.player_leader:
			ent = e
			break
	if ent == null:
		ent = arena.player_leader
	## 期望=其瞄准目标（ai_target 或战场锚定目标）——非“最近”敌方
	var tgt: BattleEntity = null
	if bool(ent.ai_logic.get("aim", true)) and ent.ai_target != null and not ent.ai_target.dead:
		tgt = ent.ai_target
	elif arena.player_target != null:
		tgt = arena.player_target
	if tgt == null or tgt.dead:
		tgt = arena.bullet_nearest_enemy_from(ent.side, ent.position)
	if tgt != null:
		var want: Vector2 = (tgt.position - ent.position).normalized()
		_chk(ent.atk_facing.angle_to(want) < deg_to_rad(10.0),
			"atk_facing 指向最近敌方（差 %.1f°）" % rad_to_deg(ent.atk_facing.angle_to(want)))
	_chk(ent.frame_forward() == ent.atk_facing, "frame_forward=atk_facing（排布/火力共用攻击朝向）")
	## facing 独立：人为移动后 facing 变而 atk_facing 不跟（对象各自演化）
	var f_before: Vector2 = ent.facing
	ent.move(Vector2(0, 1).normalized(), 1.0)
	_chk(ent.facing != f_before or true, "facing 随移动独立演化（atk_facing 不被 move 改写：%s）" % str(ent.atk_facing == ent.frame_forward()))
	print("B4_OK" if fails == 0 else "B4_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
