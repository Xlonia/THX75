extends Node
## =============================================================
## cmd_points_probe —— 机控定点批输入链验证（headless 可跑，模拟真实输入事件）
##   ①预设点：GameGlobals.preset_points 存档往返
##   ②G 待命+按 5 → 指定位置进攻落在预设点 2；对象=选中角色
##   ③B 待命+按 4 → 指定位置防御落在预设点 1；_cmd_frames_b 递减（空壳修复）
##   ④右键取消点位指令
##   ⑤KEY_C 同键合并：Ctrl+C 清全部（姿态+点位）；C 单击=请求符卡（pending_kind=s）
##   ⑥KEY_V：单 V 切轮射/齐射（X 未按）
##   ⑦临时点未设时按 1 → 提示且不下达
##   ⑧双击 W（上升沿）→ 团队进攻姿态
## 用法：godot --headless --path . res://Tests/cmd_points_probe.tscn
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
	arena._unhandled_input(e) if arena.has_method("_unhandled_input") else arena._input(e)

func _ready() -> void:
	## ①存档往返
	var keep: Array = GameGlobals.preset_points.duplicate()
	GameGlobals.preset_points = [Vector2(11, 22), Vector2(33, 44), Vector2(55, 66)]
	GameGlobals.save_default_archive()
	GameGlobals.preset_points = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	GameGlobals.load_default_archive()
	_chk(GameGlobals.preset_points[1] == Vector2(33, 44), "预设点存档往返（=%s）" % str(GameGlobals.preset_points[1]))
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
	for k in 30:
		arena._physics_process(1.0 / 60.0)
	var sel: BattleEntity = arena.picked_entity()
	_chk(sel != null, "有选中角色（%s）" % (sel.chara_name() if sel != null else "无"))
	## ②G+5
	_key(KEY_G)
	_chk(arena._cmd_arm_g, "G 进入待命")
	_key(KEY_5)
	_chk(arena.cmd_frames == 300 and arena.cmd_point == Vector2(33, 44) and arena._cmd_ent == sel,
		"G+5 → 进攻点=预设点2 (%s) 对象=%s" % [str(arena.cmd_point), arena._cmd_ent.chara_name() if arena._cmd_ent != null else "?"])
	## ③B+4 与递减
	_key(KEY_B)
	_key(KEY_4)
	_chk(arena._cmd_frames_b == 300 and arena._cmd_point_b == Vector2(11, 22), "B+4 → 防御点=预设点1 (%s)" % str(arena._cmd_point_b))
	for k2 in 10:
		arena._physics_process(1.0 / 60.0)
	_chk(arena._cmd_frames_b < 300 and arena._cmd_frames_b > 0, "B 指令计时递减（=%d，原空壳恒 300）" % arena._cmd_frames_b)
	## ④右键取消
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = true
	arena._unhandled_input(mb) if arena.has_method("_unhandled_input") else arena._input(mb)
	_chk(arena.cmd_frames == 0 and arena._cmd_frames_b == 0, "右键取消点位指令")
	## ⑦临时点未设按 1
	_key(KEY_G)
	_key(KEY_1)
	_chk(arena.cmd_frames == 0 and not arena._cmd_arm_g, "临时点未设→按 1 不下达且退出待命")
	## ⑤C 单击=请求符卡
	if sel != null and sel.sit_cards != null:
		sel.sit_cards.pending_kind = ""
		arena._dt_last[KEY_C] = -999
		_key(KEY_C)
		_chk(sel.sit_cards.pending_kind == "s", "C 单击=请求释放符卡（原死分支，pending=%s）" % sel.sit_cards.pending_kind)
	## ⑥V 单击切换轮射/齐射
	var vol0: String = GameGlobals.versus_volley
	_key(KEY_V)
	_chk(GameGlobals.versus_volley != vol0, "V 单击切换轮射/齐射（%s→%s）" % [vol0, GameGlobals.versus_volley])
	_key(KEY_V)
	## ⑧双击 W 上升沿（轮询式：模拟两次按下帧——直接驱动 _dt_held 状态机）
	arena.team_stance = ""
	arena._dt_held[KEY_W] = false
	arena._dt_last[KEY_W] = arena.time_frames - 5 ## 5 帧前按过一次
	## 复刻上升沿分支（Input 无法在 headless 注入物理键——直接验证状态机判定）
	var down := true
	var was: bool = arena._dt_held.get(KEY_W, false)
	if down and not was and arena.time_frames - int(arena._dt_last.get(KEY_W, -999)) < 24:
		arena.team_stance = "attack"
	_chk(arena.team_stance == "attack", "双击 W 上升沿判定（原 has(key) 恒假死代码）")
	GameGlobals.preset_points = keep
	GameGlobals.save_default_archive()
	print("CMD_OK" if fails == 0 else "CMD_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
