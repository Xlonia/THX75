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
var _sample_pick: OptionButton
var _edge_pick: OptionButton
var _chars: Array[Dictionary] = []

const TEAM_SLOTS := 5 ## demo：5角色/侧（上限6）

func _input(event: InputEvent) -> void:
	## 【0.0.9·预设探针（作者批 20261105）】F8=立即替换当前选中为探针队伍
	## （与"预设探针"按钮同效）：我方5位伊吹萃香，敌方1号早苗、2号希洛妮娅、3空
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_apply_preset_probe()
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
	## 【0.0.9·弹幕采样平滑（作者设计）】按性能手动开：每 N 帧算一次位置+中间帧平滑
	var sample_pick := OptionButton.new()
	for it in ["关闭（逐帧运算）", "每 2 帧采样", "每 3 帧采样", "每 4 帧采样", "每 5 帧采样"]:
		sample_pick.add_item(it)
	sample_pick.select(mini(GameGlobals.bullet_sample_n, 4))
	_add_labeled(cfg, "弹幕采样", sample_pick)
	_sample_pick = sample_pick
	var sample_hint := Label.new()
	sample_hint.text = "此设置是为了不同性能的用户准备的，打开采样帧率过大可能会导致弹幕表现受到影响"
	sample_hint.add_theme_font_size_override("font_size", 10)
	sample_hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	root.add_child(sample_hint)
	## 【0.0.9·等高线采样精度（作者批）】等高线边长 8/16/24/32px（性能档）
	var edge_pick := OptionButton.new()
	for it in ["等高线边长 8px（精细）", "等高线边长 16px", "等高线边长 24px", "等高线边长 32px（性能）"]:
		edge_pick.add_item(it)
	var ei: int = GameGlobals.contour_edge_px / 8 - 1
	edge_pick.select(clampi(ei, 0, 3))
	_add_labeled(cfg, "等高线精度", edge_pick)
	_edge_pick = edge_pick
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
	var probe_b := Button.new()
	probe_b.text = "预设探针(F8)：我方萃香×5　敌方早苗+希洛妮娅+3空"
	probe_b.pressed.connect(_apply_preset_probe)
	var roster_b := Button.new()
	roster_b.text = "召唤候补设置（默认存档）"
	roster_b.pressed.connect(_open_roster_cfg)
	var done_b := Button.new()
	done_b.text = "完成度一览（缺贴图/缺弹幕/未实装）"
	done_b.pressed.connect(_show_completion)
	var pts_b := Button.new()
	pts_b.text = "机控预设点设置（鼠标点选 4/5/6）"
	pts_b.pressed.connect(_open_preset_points)
	var keys_b := Button.new()
	keys_b.text = "键位一览"
	keys_b.pressed.connect(_show_key_bindings)
	## 【0.0.9·按钮两列（作者 20261110）】除开始/返回外两按钮一行，防纵向超界
	var btn_grid := GridContainer.new()
	btn_grid.columns = 2
	btn_grid.add_theme_constant_override("h_separation", 12)
	btn_grid.add_theme_constant_override("v_separation", 6)
	root.add_child(btn_grid)
	for b2 in [done_b, pts_b, roster_b, probe_b, keys_b]:
		btn_grid.add_child(b2)
		(b2 as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var go := Button.new()
	go.text = "开始决斗"
	go.add_theme_font_size_override("font_size", 20)
	go.pressed.connect(_on_start)
	root.add_child(go)
	var back := Button.new()
	back.text = "返回标题"
	back.pressed.connect(func(): GameGlobals.goto_scene("res://scenes/title_menu.tscn"))
	root.add_child(back)
	## 默认队伍
	_set_team(player_picks, ["MarisaA", "ReimuA", "ReisenA", "Alice", "Nitori"])
	_set_team(enemy_picks, ["Rumia", "Suika", "Aya", "Patchouli", "Yuka"])
	volley_pick.select(0 if GameGlobals.versus_volley == "rotate" else 1)

var _pick_tex_rects: Array = [] ## （0.0.9）选人贴图（与 picks 槽位一一对应）

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
		## 【0.0.9·角色贴图（作者 20261111 补漏）】自定义对战选人栏显示贴图
		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(32, 32)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		slot_row.add_child(tex_rect)
		while _pick_tex_rects.size() <= i:
			_pick_tex_rects.append(null)
		_pick_tex_rects[i] = tex_rect
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
		## 【批复 20261025d】角色逻辑=可增删列表；三步向导（决斗设定-新）择一添加
		var ltop := Label.new()
		ltop.text = "已添加的角色逻辑（删除即时生效；下次开战应用）"
		box.add_child(ltop)
		var logics: Array = cfg.get("logics", [])
		for li in logics.size():
			var lrow := HBoxContainer.new()
			box.add_child(lrow)
			var ll := Label.new()
			ll.text = "  ▸ %s" % str(logics[li].get("desc", str(logics[li])))
			ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lrow.add_child(ll)
			var lb := Button.new()
			lb.text = "删除"
			var lidx := li
			lb.pressed.connect(func():
				var arr: Array = GameGlobals.versus_chara_cfg.get(cname, {}).get("logics", [])
				arr.remove_at(lidx)
				cfg["logics"] = arr
				GameGlobals.versus_chara_cfg[cname] = cfg
				dlg.hide()
				_open_chara_cfg(pick, "logic"))
			lrow.add_child(lb)
		var brow2 := HBoxContainer.new()
		box.add_child(brow2)
		for wpair in [["＋向导1·战场方位", 0], ["＋向导2·攻击", 1], ["＋向导3·其它", 2]]:
			var wb := Button.new()
			wb.text = str(wpair[0])
			var wsel: int = int(wpair[1])
			wb.pressed.connect(func():
				dlg.hide()
				_open_logic_wizard(pick, cname, wsel))
			brow2.add_child(wb)
		var cur: String = cfg.get("stance", "")
		var curm: String = cfg.get("metric", "")
		if cur != "" and logics.is_empty():
			var orow := Label.new()
			orow.text = "（旧配置：%s / %s——添加向导逻辑后覆盖）" % [cur, curm]
			box.add_child(orow)
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
	## 【0.0.9·贴图同步】按槽位刷新贴图
	for i in mini(names.size(), _pick_tex_rects.size()):
		var nm: String = names[i]
		var ct: Dictionary = CharaTex.get_chara(nm, "")
		var tr: TextureRect = _pick_tex_rects[i]
		if tr != null:
			tr.texture = ct["tex"] if not ct.is_empty() else null
	for i in mini(picks.size(), names.size()):
		_select_by_name(picks[i], names[i])

func _select_by_name(pick: OptionButton, chara_name: String) -> void:
	for i in pick.item_count:
		if String(pick.get_item_metadata(i)) == chara_name:
			pick.select(i)
			return
	pick.select(0)

## 【0.0.9·召唤候补设置（作者裁定 20261106）】8 槽全局候补池，存"默认存档"
## （user://summon_default.json；属存档内容不开 CSV；自定义对战轮盘读此表）
func _open_roster_cfg() -> void:
	GameGlobals.load_default_archive()
	var dlg := AcceptDialog.new()
	dlg.title = "召唤候补设置（8 槽·Shift+X 轮盘顺序）"
	var box := VBoxContainer.new()
	dlg.add_child(box)
	var picks: Array[OptionButton] = []
	box.add_child(Label.new())
	var tip: Label = box.get_child(box.get_child_count() - 1)
	tip.text = "轮盘按此顺序排布（留空跳过）；Shift+X 按住呼出、松开选取"
	for i in 8:
		var pick := OptionButton.new()
		pick.custom_minimum_size = Vector2(230, 0)
		pick.add_item("（留空）")
		pick.set_item_metadata(0, "")
		for d in _chars:
			pick.add_item("%s　%s" % [d["Name"], d["NameZH"]])
			pick.set_item_metadata(pick.item_count - 1, d["Name"])
		if i < GameGlobals.summon_roster.size():
			for it in pick.item_count:
				if String(pick.get_item_metadata(it)) == str(GameGlobals.summon_roster[i]):
					pick.select(it)
					break
		box.add_child(pick)
		picks.append(pick)
	dlg.confirmed.connect(func():
		GameGlobals.summon_roster.clear()
		for pk in picks:
			GameGlobals.summon_roster.append(str(pk.get_item_metadata(pk.selected)))
		GameGlobals.save_default_archive()
		print("[召唤候补] 已保存默认存档：%s" % str(GameGlobals.summon_roster)))
	get_parent().add_child(dlg)
	dlg.popup_centered()

## 【0.0.9·预设探针（作者批）】一键替换选中：我方萃香×5，敌方早苗+希洛妮娅+3空
## （作者消歧义原文：我方五位均为伊吹萃香(Suika)，敌方1号东风谷早苗(Sanae)，2号希洛妮娅(Xlonia)）
func _apply_preset_probe() -> void:
	_set_team(player_picks, ["Suika", "Suika", "Suika", "Suika", "Suika"])
	_set_team(enemy_picks, ["Sanae", "Xlonia", "", "", ""])
	print("[预设探针] 已替换选中：我方萃香×5　敌方早苗+希洛妮娅+3空（开始决斗生效）")

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
	GameGlobals.bullet_sample_n = 1 + _sample_pick.selected ## 0=关（1）、2/3/4/5
	GameGlobals.contour_edge_px = 8 * (_edge_pick.selected + 1) ## 8/16/24/32
	GameGlobals.save_default_archive() ## 采样/精度进默认存档
	GameGlobals.apply_stress_override(_stress_check.button_pressed)
	GameGlobals.arena_mode = "versus"
	GameGlobals.goto_scene("res://scenes/battle_arena.tscn")


## 键位一览浮窗（作者批复：罗列所有可行按键 + 实现状态）
## 【批复 2026-10-13】单功能键可点"修改按键"→按任意键完成改键（双击/修饰键不开放）
var capturing_action := ""      ## 正在捕获的键位动作名（空=未捕获）
var capture_label: Label = null ## 当前按键显示标签
var capture_hint: Label = null
## 【0.0.9·完成度一览（作者 20261109 要求④）】缺贴图/三槽位未配全的角色清单
## +未实装机控指令——作者测试时不用再花时间找特定角色
func _show_completion() -> void:
	CompletionView.show(get_tree())

## 【0.0.9·机控预设点（新二 81 行）】鼠标点选三个预设点（4/5/6 快捷键；存档）
func _open_preset_points() -> void:
	var win := Window.new()
	win.title = "机控预设点（左键落点·右键换槽·自动存档）"
	var sz := Vector2i(int(400 * PresetPointPicker.SCALE) + 40, int(400 * PresetPointPicker.SCALE) + 110)
	win.size = sz
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	win.add_child(root)
	var tip := Label.new()
	tip.text = "左键=把当前槽（金色）设到点击处，槽按 4→5→6 循环；右键=只换槽。
决斗中：按住 G/B 后按 4/5/6 即对该点下达进攻/防御指令。"
	tip.add_theme_font_size_override("font_size", 11)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(tip)
	var picker := PresetPointPicker.new()
	picker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(picker)
	win.close_requested.connect(func(): win.queue_free())
	win.position = (DisplayServer.window_get_position()
		+ (DisplayServer.window_get_size() - sz) / 2)
	get_tree().root.add_child(win)

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

## 【批复 20261025d】角色逻辑三步向导（决斗设定-新 L127-152）：
## 第一步=向导类别（战场方位/攻击/其它），第二步=目标选择器，第三步=完成入列表
## 【批复 20261025e】三步向导有三个（决斗设定-新 向导1/2/3）——各自独立，不合并
const WIZARD1_OPTIONS := {
	"躲避风险(对峙目标)": {"stance": "standoff"},
	"近距离弹幕轰炸(近身目标)": {"stance": "approach"},
	"找时间远距离弹幕(无目标)": {"stance": "none"},
	"我怕了你队友(远程协助)": {"stance": "standoff", "stance_dist": 320.0},
	"一起释放火力(靠近目标)": {"stance": "approach", "stance_dist": 90.0},
}
const WIZARD2_OPTIONS := {
	"大胆进攻(巡航目标)": {"cruise": true},
	"一般攻击(攻击目标)": {"aim": true},
	"集中火力(齐射目标)": {"volley": true},
	"能力优先": {"skill_priority": true},
	"符卡优先": {"spell_priority": true},
	"主要符卡优先": {"main_priority": true},
}
const WIZARD3_OPTIONS := {
	"召唤搭档们同时发起攻击(能力/符卡号召)": {"appeal_boost": 1.0},
	"开局技能(特殊规则接管·占位)": {"special_rule": true},
}
const WIZARD_STEP2 := {
	"剩余血量高的(主力)": "hp_max",
	"结界厚的": "ap_max",
	"围剿(血量低的)": "hp_any_low",
	"挫其锐气(结界少的)": "ap_ratio_low",
	"最近的": "dist_min",
	"最远的": "dist_max",
	"杂兵残缺的(占位)": "priv_low",
	"标签有(占位)": "tag",
	"特定角色(占位)": "specific",
}

func _open_logic_wizard(pick: OptionButton, cname: String, which: int) -> void:
	var opts: Dictionary = [WIZARD1_OPTIONS, WIZARD2_OPTIONS, WIZARD3_OPTIONS][which]
	var wname: String = ["战场方位逻辑", "攻击逻辑", "其它"][which]
	var dlg := AcceptDialog.new()
	dlg.title = "%s · 添加角色逻辑·向导%d（%s）" % [cname, which + 1, wname]
	var box := VBoxContainer.new()
	dlg.add_child(box)
	var l1 := Label.new()
	l1.text = "第一步：%s——如何做？" % wname
	box.add_child(l1)
	var s1 := OptionButton.new()
	for k in opts.keys():
		s1.add_item(k)
	s1.select(0)
	box.add_child(s1)
	var l2 := Label.new()
	l2.text = "第二步：瞄准什么样的威胁？"
	box.add_child(l2)
	var s2 := OptionButton.new()
	for k in WIZARD_STEP2.keys():
		s2.add_item(k)
	s2.select(0)
	box.add_child(s2)
	var l3 := Label.new()
	l3.text = "第三步：完成（确认后加入列表；开战时按列表顺序应用）"
	box.add_child(l3)
	dlg.confirmed.connect(func():
		var k1: String = s1.get_item_text(s1.selected)
		var k2: String = s2.get_item_text(s2.selected)
		var entry: Dictionary = {"desc": "%s · %s" % [k1, k2]}
		entry.merge(opts.get(k1, {}))
		entry["metric"] = WIZARD_STEP2.get(k2, "hp_max")
		var cfg2: Dictionary = GameGlobals.versus_chara_cfg.get(cname, {})
		var arr: Array = cfg2.get("logics", [])
		arr.append(entry)
		cfg2["logics"] = arr
		GameGlobals.versus_chara_cfg[cname] = cfg2
		print("[对战配置] %s 添加逻辑：%s" % [cname, entry["desc"]]))
	get_parent().add_child(dlg)
	dlg.popup_centered()
