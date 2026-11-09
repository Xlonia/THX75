extends Node
## =============================================================
## flow_e2e —— 角色分配弹幕 全链路复现测试（20261020 专项）
## 按作者实际操作流：编辑器新建事件 → 挂载到 MarisaA 主火力点 → 进自定义对战
## 分 A（同会话）/ B（重启模拟：工作集清空）两段，逐步打印断点。
## =============================================================

var ev_name := "autorot_check"

func _ready() -> void:
	print("=== FLOW E2E ===")
	# —— 模拟编辑器打开：从五分表载入工作集（编辑器 _load_official_csv 的行为）——
	GameGlobals.editor_events = DanmakuEventData.parse_csv_text("")
	for path in GameGlobals.OFFICIAL_EVENT_CSVS.values():
		if FileAccess.file_exists(path):
			GameGlobals.editor_events.append_array(
				DanmakuEventData.parse_csv_text(FileAccess.get_file_as_string(path)))
	print("A0 工作集事件数=", GameGlobals.editor_events.size())

	# —— 作者操作①：新建弹幕（旋转重复参数同作者测验）——
	var ev := DanmakuEventData.new()
	ev.event_name = ev_name
	ev.slot = "main"
	ev.tag = DanmakuEventData.TAG_REGULAR
	ev.texture = "tama0"
	ev.speed = "3"
	ev.x = "1"
	ev.y = "0"
	ev.rotate_range = "1.5707963"
	ev.rotate_div = "4"
	ev.compile()
	GameGlobals.editor_events.append(ev)
	GameGlobals.sync_official_events(GameGlobals.editor_events) ## 编辑器在变更点的自动落盘（根治项）
	print("A1 新建事件入工作集+自动落盘 ok")

	# —— 作者操作②：角色页挂载到 MarisaA 主火力点（走与编辑器相同的代码）——
	var row: Dictionary = CharaDB.get_by_name("MarisaA")
	if row.is_empty():
		print("A2 FAIL: MarisaA 行未找到")
		get_tree().quit(1)
		return
	row["main_evs"] = ev_name
	var saved := CharaDB.save_row("MarisaA", row)
	print("A2 挂载+save_row=", saved, " main_evs=", CharaDB.get_by_name("MarisaA").get("main_evs"))

	# —— 作者操作③：进自定义对战（battle_arena 全新实例）——
	var arena: Node2D = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)

	# 检查 FireControl 绑定
	var fc = null
	for f in arena.fire_controls:
		if f.entity != null and f.entity.chara_name() == "MarisaA":
			fc = f
			break
	if fc == null:
		print("A3 FAIL: 未找到 MarisaA 的 FireControl（fire_controls=%d）" % arena.fire_controls.size())
		get_tree().quit(1)
		return
	var bound_names := []
	for e in fc._bound_main:
		bound_names.append(e.event_name)
	print("A3 MarisaA 主槽绑定=", bound_names)

	# 步进物理，数弹
	var got := false
	for i in 240:
		arena._physics_process(1.0 / 60.0)
		if i == 30:
			for b in arena.bullets:
				if b.ev.event_name == ev_name:
					got = true
	print("A4 240帧后：新弹幕出场=", got, " 场上弹幕=", arena.bullets.size())
	print("=== A 段结束（同会话）===")

	# ===== B 段：重启模拟（工作集清空=新进程）=====
	GameGlobals.editor_events = []
	GameGlobals.official_events.clear()
	GameGlobals._load_official()
	var got2: Array = GameGlobals.get_slot_events("MarisaA", "main")
	var names2 := []
	for e2 in got2:
		names2.append(e2.event_name)
	print("B1 重启后（未重开编辑器）主槽绑定=", names2)
	# B2：作者重开编辑器 → 工作集自动从分表载入（含此前自动落盘的新事件）
	GameGlobals.editor_events = DanmakuEventData.parse_csv_text("")
	for path in GameGlobals.OFFICIAL_EVENT_CSVS.values():
		if FileAccess.file_exists(path):
			GameGlobals.editor_events.append_array(
				DanmakuEventData.parse_csv_text(FileAccess.get_file_as_string(path)))
	var got3: Array = GameGlobals.get_slot_events("MarisaA", "main")
	var names3 := []
	for e3 in got3:
		names3.append(e3.event_name)
	print("B2 重开编辑器后主槽绑定=", names3)
	# 清理：把测试事件从角色行移除并还原 CSV 绑定
	var row2: Dictionary = CharaDB.get_by_name("MarisaA")
	row2["main_evs"] = ""
	CharaDB.save_row("MarisaA", row2)
	print("=== 清理完成 ===")
	get_tree().quit(0)
