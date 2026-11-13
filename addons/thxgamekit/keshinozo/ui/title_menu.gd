@tool
extends Control
## =============================================================
## title_menu —— 标题画面主菜单（游戏的完整入口）
## 菜单项（按策划要求暂定四项）：
##   剧情模式（占位）、EX关卡（占位）、自定义对战、弹幕编辑器
## 新角色立绘背景（themes/images/tmainUvReimu.png）+ 灵梦横飞动画
## 复用 themes.tscn 的 reimu_bgswf.gd 逻辑（原工程既有资产）
## =============================================================

const MENU_ITEMS := [
	{"id": "story", "label": "剧情模式"},
	{"id": "ex", "label": "EX关卡"},
	{"id": "versus", "label": "自定义对战"},
	{"id": "editor", "label": "弹幕编辑器"},
]

func _ready() -> void:
	if Engine.is_editor_hint():
		return ## 编辑器态不构建（运行时 UI）
	## 背景（原工程资产）
	var bg := TextureRect.new()
	bg.texture = load("res://themes/images/tmainUvReimu.png")
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	## 灵梦横飞动画层（复用既有脚本）
	var reimu := TextureRect.new()
	reimu.texture = load("res://themes/images/Reimu.png")
	reimu.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	reimu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## 【批复 2026-10-13】立绘缩放为原先一半，露出整个立绘（1920×1080 全身图）
	reimu.scale = Vector2(0.5, 0.5)
	reimu.set_script(load("res://reimu_bgswf.gd"))
	add_child(reimu)
	## 标题
	var title := Label.new()
	title.text = "东方无欲拾食纪 ~Starve Universia~"
	title.add_theme_font_size_override("font_size", 40)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position.y += 40
	add_child(title)
	## 菜单按钮列
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	for item in MENU_ITEMS:
		var btn := Button.new()
		btn.text = " %s " % item["label"]
		btn.add_theme_font_size_override("font_size", 22)
		btn.pressed.connect(_on_menu.bind(item["id"]))
		box.add_child(btn)
	## 【键盘导航（作者批复 2026-10-02：RPGVX式上下选取）】
	## 初始焦点在第一项；VBox 内按钮的方向键移动由 Godot 焦点系统自动处理，
	## Enter/Space（ui_accept）确认。
	if box.get_child_count() > 0:
		(box.get_child(0) as Button).grab_focus()
	_menu_buttons = []
	for c in box.get_children():
		_menu_buttons.append(c as Button)
	## 【0.0.9·旧弹幕模式（作者批 20261108）】默认=渲染帧驱动（工作期调试同款，
	## 永不积压）；勾选=引擎 60Hz 物理调度+多 tick 追赶（高级玩家对比测试·重启生效）
	if not Engine.is_editor_hint():
		GameGlobals.load_default_archive()
	var legacy := CheckBox.new()
	legacy.text = "旧弹幕模式（高级测试用·重启生效）"
	legacy.button_pressed = GameGlobals.bullet_legacy_physics
	legacy.toggled.connect(func(on: bool):
		GameGlobals.bullet_legacy_physics = on
		GameGlobals.save_default_archive()
		print("[标题] 旧弹幕模式=%s（重启生效）" % str(on)))
	add_child(legacy)
	legacy.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	legacy.position.y -= 90
	## 版本注记
	var foot := Label.new()
	foot.text = "TH75 东方无欲拾食纪 v0.0.9 | Story/EX为占位（剧情待实装）"
	foot.add_theme_font_size_override("font_size", 12)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position.y -= 30
	add_child(foot)
	## 【0.0.9·完成度一览（作者 20261109 要求④）】标题左下入口（复用 versus_menu 弹窗）
	var done_b := Button.new()
	done_b.text = "完成度一览"
	done_b.focus_mode = Control.FOCUS_NONE
	done_b.add_theme_font_size_override("font_size", 12)
	done_b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	done_b.position.y -= 60
	done_b.pressed.connect(_show_completion)
	add_child(done_b)

## 复用自定义对战的完成度弹窗（同款数据源）
func _show_completion() -> void:
	if Engine.is_editor_hint():
		return
	load("res://addons/thxgamekit/keshinozo/ui/completion_view.gd").show(get_tree())

## 【批复】RPG/东方式：Z=选中、X=退出/返回
var _menu_buttons: Array = []
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Z, KEY_ENTER, KEY_SPACE:
				var f := get_viewport().gui_get_focus_owner()
				if f is Button:
					(f as Button).emit_signal("pressed")
			KEY_X, KEY_ESCAPE:
				## 标题无上级可退——最小化提示（防误关）；未来主菜单→设定等层级用于返回
				pass

func _on_menu(id: String) -> void:
	match id:
		"story":
			GameGlobals.goto_scene("res://scenes/story_placeholder.tscn")
		"ex":
			GameGlobals.goto_scene("res://scenes/ex_placeholder.tscn")
		"versus":
			GameGlobals.goto_scene("res://scenes/versus_menu.tscn")
		"editor":
			_open_editor_window()

## 【0.0.9·编辑器窗口（作者 20261110 终裁）】回归古典的额外窗口（同进程独立
## OS 窗口——主体可呼出编辑器、编辑器可弹预览窗）；保留 启动弹幕编辑器.bat
## 供命令行/直接双击启动
var _editor_window: Window = null
func _open_editor_window() -> void:
	if _editor_window != null and is_instance_valid(_editor_window):
		_editor_window.grab_focus()
		return
	_editor_window = Window.new()
	_editor_window.title = "THX075 弹幕编辑器"
	_editor_window.size = Vector2i(1280, 800)
	_editor_window.min_size = Vector2i(860, 560)
	_editor_window.position = (DisplayServer.window_get_position()
		+ (DisplayServer.window_get_size() - Vector2i(1280, 800)) / 2)
	## 【挂载点适配】submodule 内 tscn 的脚本路径是内核绝对 res（th75 挂载点
	## 不存在=窗口空白根因）——直接实例化 editor 脚本（Control），同等内容
	var ed: Control = (load("res://addons/thxgamekit/kit/addons/thx_gamekit/editor/danmaku_editor.gd") as GDScript).new()
	ed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_editor_window.add_child(ed)
	_editor_window.close_requested.connect(func(): _editor_window.queue_free())
	get_tree().root.add_child(_editor_window)
	_editor_window.show()
