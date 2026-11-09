extends Control
## =============================================================
## versus_menu —— 自定义对战选人（第①期：队伍战配置）
## 我方/敌方各选 5~6 角色（Characters.csv 池；敌方可从 Enemy.csv 池补充）
## 每角色 5 杂兵（demo 目标 5×5）；预设队伍一键填充
## =============================================================

var player_picks: Array[OptionButton] = []
var enemy_picks: Array[OptionButton] = []
var pp_spin: SpinBox
var volley_pick: OptionButton
var _stress_check: CheckBox
var _chars: Array[Dictionary] = []

const TEAM_SLOTS := 5 ## demo：5角色/侧（上限6）

func _input(event: InputEvent) -> void:
	if capturing_action == "" or not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE:
		capturing_action = ""
		if capture_hint: capture_hint.visible = false
		return
	if event.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_ENTER, KEY_ESCAPE]:
		return ## 修饰键不开放
	GameGlobals.set_key(capturing_action, int(event.keycode))
	if capture_label:
		capture_label.text = "    当前按键: %s" % OS.get_keycode_string(int(event.keycode))
	capturing_action = ""
	if capture_hint: capture_hint.visible = false

func _ready() -> void:
	_chars = CharaDB.load_all()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	## 【布局修复（作者 2026-10-02 截图：UI 错位、按钮无法触及）】
	## 旧版对 VBox 直接 PRESET_CENTER——容器从中心点向右下生长溢出屏幕。
	## 改为全屏 CenterContainer 包裹，VBox 自动收缩居中。
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	center.add_child(root)
	var title := Label.new()
	title.text = "自定义对战（决斗测试·队伍战）"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)
	## 双栏队伍
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	root.add_child(cols)
	var pcol := _team_column(cols, "我方（第1位为自机）", player_picks)
	var ecol := _team_column(cols, "敌方", enemy_picks)
	## 配置行
	var cfg := GridContainer.new()
	cfg.columns = 4
	cfg.add_theme_constant_override("h_separation", 16)
	root.add_child(cfg)
	volley_pick = _add_opt(cfg, "发射模式", ["轮射（rotate）", "齐射（salvo）"])
	pp_spin = SpinBox.new()
	pp_spin.min_value = 0
	pp_spin.max_value = 500
	pp_spin.value = GameGlobals.versus_start_pp
	_add_labeled(cfg, "开局P点", pp_spin)
	## 高火力演习（作者批复 2026-10-02：更恶劣演练 + 运行时覆写官方参数验证）
	var stress := CheckBox.new()
	stress.text = "高火力演习(覆写官方参数:更密+更久)"
	stress.button_pressed = false
	_add_labeled(cfg, "覆写测试", stress)
	_stress_check = stress
	var hint := Label.new()
	hint.text = "WASD移动　Shift:全队快机(演示)　V轮射↔齐射　F3 DDM图　Esc暂停"
	hint.add_theme_font_size_override("font_size", 12)
	root.add_child(hint)
	var go := Button.new()
	go.text = "开始决斗"
	go.add_theme_font_size_override("font_size", 20)
	go.pressed.connect(_on_start)
	root.add_child(go)
	var keys_b := Button.new()
	keys_b.text = "键位一览"
	keys_b.pressed.connect(_show_key_bindings)
	root.add_child(keys_b)
	var back := Button.new()
	back.text = "返回标题"
	back.pressed.connect(func(): GameGlobals.goto_scene("res://scenes/title_menu.tscn"))
	root.add_child(back)
	## 默认队伍
	_set_team(player_picks, ["MarisaA", "ReimuA", "ReisenA", "Alice", "Nitori"])
	_set_team(enemy_picks, ["Rumia", "Suika", "Aya", "Patchouli", "Yuka"])
	volley_pick.select(0 if GameGlobals.versus_volley == "rotate" else 1)

func _team_column(parent: Control, label_text: String, picks: Array[OptionButton]) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	parent.add_child(col)
	var l := Label.new()
	l.text = label_text
	col.add_child(l)
	for i in TEAM_SLOTS:
		var pick := OptionButton.new()
		pick.custom_minimum_size = Vector2(330, 0)
		for d in _chars:
			pick.add_item("%s　%s　快%d/慢%d" % [d["Name"], d["NameZH"], d["Cruise"], d["Normal"]])
			pick.set_item_metadata(pick.item_count - 1, d["Name"])
		pick.select(i)
		picks.append(pick)
		col.add_child(pick)
	return col

func _add_opt(grid: GridContainer, label_text: String, items: Array) -> OptionButton:
	var pick := OptionButton.new()
	for it in items:
		pick.add_item(str(it))
	_add_labeled(grid, label_text, pick)
	return pick

func _add_labeled(grid: GridContainer, label_text: String, ctrl: Control) -> void:
	var l := Label.new()
	l.text = label_text
	grid.add_child(l)
	grid.add_child(ctrl)

func _set_team(picks: Array[OptionButton], names: Array) -> void:
	for i in mini(picks.size(), names.size()):
		_select_by_name(picks[i], names[i])

func _select_by_name(pick: OptionButton, chara_name: String) -> void:
	for i in pick.item_count:
		if String(pick.get_item_metadata(i)) == chara_name:
			pick.select(i)
			return
	pick.select(0)

func _on_start() -> void:
	var pteam: Array = []
	for p in player_picks:
		pteam.append(p.get_item_metadata(p.selected))
	var eteam: Array = []
	for p in enemy_picks:
		eteam.append(p.get_item_metadata(p.selected))
	GameGlobals.versus_player_team = pteam
	GameGlobals.versus_enemy_team = eteam
	GameGlobals.versus_player_name = pteam[0]
	GameGlobals.versus_enemy_name = eteam[0]
	GameGlobals.versus_start_pp = int(pp_spin.value)
	GameGlobals.versus_volley = "rotate" if volley_pick.selected == 0 else "salvo"
	GameGlobals.apply_stress_override(_stress_check.button_pressed)
	GameGlobals.arena_mode = "versus"
	GameGlobals.goto_scene("res://scenes/battle_arena.tscn")


## 键位一览浮窗（作者批复：罗列所有可行按键 + 实现状态）
## 【批复 2026-10-13】单功能键可点"修改按键"→按任意键完成改键（双击/修饰键不开放）
var capturing_action := ""      ## 正在捕获的键位动作名（空=未捕获）
var capture_label: Label = null ## 当前按键显示标签
var capture_hint: Label = null
func _show_key_bindings() -> void:
	var win := Window.new()
	win.title = "键位一览（scheme·机控）"
	win.size = Vector2i(640, 700)
	## 【修复：窗口空白】Window 的直接子 Control 不会自动铺满——
	## 必须显式设 anchors（全窗），ScrollContainer 才有可滚动区域
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(root)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var last_cat := ""
	for b in KeyBindings.BINDINGS:
		if b["cat"] != last_cat:
			last_cat = b["cat"]
			var h := Label.new()
			h.text = "【%s指令】" % b["cat"]
			h.add_theme_font_size_override("font_size", 17)
			box.add_child(h)
		var l := Label.new()
		var mark: String = "✓" if String(b["state"]).begins_with("已") else "…"
		l.text = "%s  %s → %s（%s）｜%s" % [mark, b["keys"], b["name"], b["dur"], b["state"]]
		l.add_theme_font_size_override("font_size", 12)
		box.add_child(l)
	win.close_requested.connect(func(): win.queue_free())
	capture_hint = Label.new()
	capture_hint.text = "请按下新的按键…（Esc 取消）"
	capture_hint.visible = false
	capture_hint.modulate = Color(1, 0.9, 0.4)
	win.add_child(capture_hint) ## X 可关
	win.position = (DisplayServer.window_get_position()
		+ (DisplayServer.window_get_size() - Vector2i(640, 700)) / 2) ## 居中主窗
	get_tree().root.add_child(win)
	win.show()
