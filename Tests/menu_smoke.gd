extends Node
## menu_smoke —— 自定义对战菜单实例化冒烟（含预设探针按钮/F8 注册）
func _ready() -> void:
	var s = load("res://scenes/versus_menu.tscn").instantiate()
	add_child(s)
	await get_tree().process_frame
	assert(s.player_picks.size() == 5, "我方5槽")
	assert(s.enemy_picks.size() == 5, "敌方5槽")
	s._apply_preset_probe()
	var names := []
	for p in s.enemy_picks:
		names.append(str(p.get_item_metadata(p.selected)))
	assert(names == ["Sanae", "Xlonia", "", "", ""], "敌方位次（1号早苗2号希洛妮娅3空）：%s" % str(names))
	var pnames := []
	for p in s.player_picks:
		pnames.append(str(p.get_item_metadata(p.selected)))
	assert(pnames == ["Suika", "Suika", "Suika", "Suika", "Suika"], "我方萃香×5：%s" % str(pnames))
	print("MENU_SMOKE_OK —— 预设探针按钮+F8 队伍位次正确")
	get_tree().quit(0)
