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
		var slot_row := HBoxContainer.new()
		col.add_child(slot_row)
		var pick := OptionButton.new()
		pick.custom_minimum_size = Vector2(230, 0)
		## 【批复 20261019】除第一位（自机/领队）外允许留空——1v1/1v5 等
		## AI 调试阵型；留空槽位开战时跳过（不生成实体）
		if i > 0:
			pick.add_item("（留空）")
			pick.set_item_metadata(pick.item_count - 1, "")
		for d in _chars:
			pick.add_item("%s　%s　快%d/慢%d" % [d["Name"], d["NameZH"], d["Cruise"], d["Normal"]])
			pick.set_item_metadata(pick.item_count - 1, d["Name"])
		pick.select(i if i < _chars.size() else 0)
		picks.append(pick)
		slot_row.add_child(pick)
		## 【批复 20261024】角色选框旁三按钮：对战逻辑/杂兵排布/资源
		var cfg_b := Button.new()
		cfg_b.text = "逻辑"
		cfg_b.pressed.connect(_open_chara_cfg.bind(pick, "logic"))
		slot_row.add_child(cfg_b)
		var fm_b := Button.new()
		fm_b.text = "排布"
		fm_b.pressed.connect(_open_chara_cfg.bind(pick, "formation"))
		slot_row.add_child(fm_b)
		var res_b := Button.new()
		res_b.text = "资源"
		res_b.pressed.connect(_open_chara_cfg.bind(pick, "res"))
		slot_row.add_child(res_b)
	return col

## 【批复 20261024】每角色配置弹窗：逻辑（方位+指标）/排布预设/资源（P/符卡）
func _open_chara_cfg(pick: OptionButton, page: String) -> void:
	if pick.selected < 0:
		return
	var cname := str(pick.get_item_metadata(pick.selected))
	if cname == "":
		print("[对战配置] 该槽位为留空，无配置")
		return
	var cfg: Dictionary = GameGlobals.versus_chara_cfg.get(cname, {})
	var dlg := AcceptDialog.new()
	var titles := {"logic": "对战逻辑", "formation": "杂兵排布", "res": "资源"}
	dlg.title = "%s · %s" % [cname, titles[page]]
	var box := VBoxContainer.new()
	dlg.add_child(box)
	if page == "logic":
		var l1 := Label.new()
		l1.text = "方位逻辑"
		box.add_child(l1)
		var stance := OptionButton.new()
		for it in [["standoff", "对峙(远程协助)"], ["approach", "近身"], ["none", "无目标"]]:
			stance.add_item(it[1])
			stance.set_item_metadata(stance.item_count - 1, it[0])
		var cur_s := str(cfg.get("stance", "standoff"))
		for i2 in stance.item_count:
			if str(stance.get_item_metadata(i2)) == cur_s:
				stance.select(i2)
		box.add_child(stance)
		var l2 := Label.new()
		l2.text = "目标选择器"
		box.add_child(l2)
		var metric := OptionButton.new()
		for it in [["hp_max", "剩余血量高的(主力)"], ["ap_max", "结界厚的"], ["hp_any_low", "围剿(血量低)"], ["dist_min", "最近的"], ["dist_max", "最远的"]]:
			metric.add_item(it[1])
			metric.set_item_metadata(metric.item_count - 1, it[0])
		var cur_m := str(cfg.get("metric", "hp_max"))
		for i3 in metric.item_count:
			if str(metric.get_item_metadata(i3)) == cur_m:
				metric.select(i3)
		box.add_child(metric)
		dlg.confirmed.connect(func():
			cfg["stance"] = str(stance.get_item_metadata(stance.selected))
			cfg["metric"] = str(metric.get_item_metadata(metric.selected))
			GameGlobals.versus_chara_cfg[cname] = cfg)
	elif page == "formation":
		var fl := Label.new()
		fl.text = "杂兵排布预设"
		box.add_child(fl)
		var fpick := OptionButton.new()
		for key in PrivateFormation.PRESETS.keys():
			fpick.add_item(key)
		var cur_f := str(cfg.get("formation", "线列防护"))
		for i4 in fpick.item_count:
			if fpick.get_item_text(i4) == cur_f:
				fpick.select(i4)
		box.add_child(fpick)
		dlg.confirmed.connect(func():
			cfg["formation"] = fpick.get_item_text(fpick.selected)
			GameGlobals.versus_chara_cfg[cname] = cfg)
	else:
		var pl := Label.new()
		pl.text = "初始 P 点(0~500)"
		box.add_child(pl)
		var pp_s := SpinBox.new()
		pp_s.min_value = 0
		pp_s.max_value = 500
		pp_s.value = float(cfg.get("pp", 100))
		box.add_child(pp_s)
		var sl := Label.new()
		sl.text = "初始符卡数(0~16)"
		box.add_child(sl)
		var sp_s := SpinBox.new()
		sp_s.min_value = 0
		sp_s.max_value = 16
		sp_s.value = float(cfg.get("spell", 2))
		box.add_child(sp_s)
		dlg.confirmed.connect(func():
			cfg["pp"] = int(pp_s.value)
			cfg["spell"] = int(sp_s.value)
			GameGlobals.versus_chara_cfg[cname] = cfg)
	get_parent().add_child(dlg)
	dlg.popup_centered()

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
		var nm0: String = str(p.get_item_metadata(p.selected))
		if nm0 != "":
			pteam.append(nm0) ## 留空槽位跳过（批复 20261019：1v1/1v5 测试）
	var eteam: Array = []
	for p in enemy_picks:
		var nm1: String = str(p.get_item_metadata(p.selected))
		if nm1 != "":
			eteam.append(nm1) ## 留空槽位跳过
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
