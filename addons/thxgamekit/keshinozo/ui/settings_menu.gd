extends Control
## =============================================================
## 【m68 设置功能（作者 20261114）】标题画面"设置"按钮→本面板（**覆盖层**，
## 非场景切换——空转专案的教训）。标签页结构：键位（当前唯一页；后续
## 音量/游戏性等页随需扩展）。
##   · 键位页：GameGlobals.KEY_MODIFIABLE 单功能键改键（点「改键」→按新键）
##     + **默认设置**按钮（恢复出厂并持久化）
##   · 持久化=user://keybinds.cfg（既有机制——保存可一直沿用）
##   · 双击类与 Ctrl/Shift/Enter/Esc 组合键按 2026-10-13 批复不开放修改
##   · 战斗侧全部经 GameGlobals.get_key(action) 实时读取（无假绑定）
## =============================================================

var _hint: Label
var _capturing := "" ## 正在捕获的动作名（空=未捕获）
var _key_labels := {} ## action → 当前键名 Label（捕获/恢复后刷新）

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 24)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	pad.add_child(box)
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	tabs.add_child(_build_keys_page())
	var bar := HBoxContainer.new()
	box.add_child(bar)
	var reset_b := Button.new()
	reset_b.text = "默认设置"
	reset_b.focus_mode = Control.FOCUS_NONE
	reset_b.pressed.connect(func():
		GameGlobals.reset_key_config()
		_refresh_keys()
		_hint.text = "已恢复默认键位（已保存）")
	bar.add_child(reset_b)
	var close_b := Button.new()
	close_b.text = "关闭"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(func(): queue_free())
	bar.add_child(close_b)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	box.add_child(_hint)

func _build_keys_page() -> Control:
	var page := Control.new()
	page.name = "键位"
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	sc.add_child(box)
	var tip := Label.new()
	tip.text = "点击「改键」后按下新键即生效并保存（user://keybinds.cfg，一直沿用）。\n双击类与 Ctrl/Shift/Enter/Esc 组合键按批复不开放修改。"
	tip.add_theme_font_size_override("font_size", 12)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tip)
	for action in GameGlobals.KEY_MODIFIABLE:
		box.add_child(_key_row(action))
	return page

func _key_row(action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = action
	l.custom_minimum_size = Vector2(220, 0)
	row.add_child(l)
	var cur := Label.new()
	cur.text = OS.get_keycode_string(GameGlobals.get_key(action))
	cur.custom_minimum_size = Vector2(140, 0)
	row.add_child(cur)
	_key_labels[action] = cur
	var b := Button.new()
	b.text = "改键"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		_capturing = action
		_hint.text = "「%s」捕获中——按下新键（Esc 取消）" % action)
	row.add_child(b)
	return row

func _refresh_keys() -> void:
	for action in _key_labels:
		(_key_labels[action] as Label).text = OS.get_keycode_string(GameGlobals.get_key(action))

func _input(event: InputEvent) -> void:
	## 键位捕获（与 versus_menu 键位一览同款机制——本面板独占 _capturing）
	if _capturing == "" or not (event is InputEventKey and event.pressed and not event.echo):
		return
	get_viewport().set_input_as_handled()
	var act := _capturing
	_capturing = ""
	if event.keycode == KEY_ESCAPE:
		_hint.text = "已取消捕获"
		return
	GameGlobals.set_key(act, int(event.keycode))
	_refresh_keys()
	_hint.text = "「%s」已改为 %s（已保存）" % [act, OS.get_keycode_string(int(event.keycode))]
