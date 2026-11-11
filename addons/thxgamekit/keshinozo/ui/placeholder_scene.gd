extends Control
## 剧情模式 / EX关卡 占位场景（点进去但剧情无效的选项）
## —— 对应策划要求：“目前做一个点进去但剧情无效的选项即可”
## 副本场景：scenes/story_placeholder.tscn 与 scenes/ex_placeholder.tscn
## 共用本脚本，按场景文件名区分标题文案。

func _ready() -> void:
	var is_ex := get_scene_file_path().contains("ex_placeholder")
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	var title := Label.new()
	title.text = "EX关卡" if is_ex else "剧情模式"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tip := Label.new()
	tip.text = "施工中 —— 剧情系统将对接 dialogic 插件（策划文档：未来剧情编辑器）\n当前为占位入口，剧情尚未实装。"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tip)
	var back := Button.new()
	back.text = "返回标题"
	back.pressed.connect(func(): GameGlobals.goto_scene("res://scenes/title_menu.tscn"))
	box.add_child(back)
	## 随手吸一口 dialogic 的 autotest：无剧情内容时静默不启动
