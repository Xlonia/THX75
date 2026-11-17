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
	{"id": "settings", "label": "设置"},
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
	legacy.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	## 【m70 作者 20261115】与"设置"项重叠→移到版本号右斜上方
	legacy.position = Vector2(350, -56)
	## 版本注记
	var foot := Label.new()
	foot.text = "TH75 东方无欲拾食纪 v0.0.9 | Story/EX为占位（剧情待实装）"
	foot.add_theme_font_size_override("font_size", 12)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position.y -= 30
	add_child(foot)
	## 【m79 内窗口调试（作者 20261117）】版本号上方的调试子窗口入口——
	## 编辑器进程 --log-file 落盘，内嵌窗口轮询继承报错与消息
	var dbg_b := Button.new()
	dbg_b.text = "测试：内窗口调试"
	dbg_b.focus_mode = Control.FOCUS_NONE
	dbg_b.add_theme_font_size_override("font_size", 12)
	dbg_b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	dbg_b.position = Vector2(340, -58)
	dbg_b.pressed.connect(_open_console_tail)
	add_child(dbg_b)
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

var _console_tail: Window = null ## 【m79】内窗口调试（编辑器日志继承）

func _open_console_tail() -> void:
	if _console_tail != null and is_instance_valid(_console_tail):
		_console_tail.grab_focus()
		return
	get_tree().root.gui_embed_subwindows = true ## 内嵌=可拖动子窗口形态
	var w: Window = load("res://addons/thxgamekit/kit/addons/thx_gamekit/editor/console_tail.gd").new()
	w.log_path = ProjectSettings.globalize_path("user://thx_gamekit/editor_console.log")
	w.position = Vector2i(120, 120)
	add_child(w)
	_console_tail = w

func _on_menu(id: String) -> void:
	match id:
		"story":
			GameGlobals.goto_scene("res://scenes/story_placeholder.tscn")
		"ex":
			GameGlobals.goto_scene("res://scenes/ex_placeholder.tscn")
		"versus":
			GameGlobals.goto_scene("res://scenes/versus_menu.tscn")
		"settings":
			_open_settings()
		"editor":
			_open_editor_process()

## 【m68 设置（作者 20261114）】覆盖层面板（非场景切换——空转专案教训）；
## 键位改键+默认设置，持久化 user://keybinds.cfg（settings_menu.gd 实现）
var _settings: Control = null
func _open_settings() -> void:
	if _settings != null and is_instance_valid(_settings):
		return ## 已开着
	_settings = Control.new()
	_settings.set_script(load("res://addons/thxgamekit/keshinozo/ui/settings_menu.gd"))
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_settings)

## 【编辑器=独立进程 20261114（作者批准：THXGameKit 同款模式，推翻 20261110
## 同进程子窗口方案）】OS.create_process 启动 scenes/danmaku_editor.tscn
## （th75 挂载点包装场景——kit tscn 是内核逻辑路径不能直跑）。
## 为什么必须独立进程：同进程子窗口里的编辑器退出链会把宿主进程一起带走
## （get_tree().quit 语义），且子窗口 X 按钮=无保存提问直接销毁。
## 标题进程常驻不受影响=零空转；编辑器进程退出=关窗。保留 .bat 同路径。
func _open_editor_process() -> void:
	var godot_exe := OS.get_executable_path()
	var project_dir := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray(["--path", project_dir, "res://scenes/danmaku_editor.tscn"])
	## 【m79 内窗口调试（作者 20261117）】编辑器进程控制台/报错落盘——
	## 标题画面的「内窗口调试」轮询该文件继承全部消息与报错
	var log_abs := ProjectSettings.globalize_path("user://thx_gamekit/editor_console.log")
	DirAccess.make_dir_recursive_absolute(log_abs.get_base_dir())
	args.append("--log-file")
	args.append(log_abs)
	var pid := OS.create_process(godot_exe, args)
	if pid > 0:
		print("[标题] 编辑器独立进程已启动 pid=%d（日志=%s）" % [pid, ProjectSettings.globalize_path("user://thx_gamekit/editor_console.log")])
	else:
		push_error("[标题] 编辑器独立进程启动失败")
