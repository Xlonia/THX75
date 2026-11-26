extends PanelContainer
class_name StoryTestPanel
## =============================================================
## 【m128 剧情桥测试面板（作者令：A/C 测试存档+相应测试面板）】
## versus_menu「剧情桥测试」按钮打开。三区：
##   ①存档区：下拉（user://storysaves/*.thxstory）+ 刷新/读档/应用进场
##   ②flag 区：组/序号/值 三列表格（只读显示——写走 Dialogic/剧情侧）
##   ③造档区：组/序号/值 三输入 + 「写入 flag」+「导出测试存档」
## 应用进场=apply_story（读档→写穿 versus_* → change_scene battle_arena）。
## =============================================================
var _sb: Node = null ## StoryBridge autoload
var _list: OptionButton = null
var _flag_text: RichTextLabel = null
var _g_in: LineEdit = null
var _i_in: LineEdit = null
var _v_in: LineEdit = null


func _ready() -> void:
	custom_minimum_size = Vector2(430, 360)
	_sb = get_node_or_null("/root/StoryBridge")
	_build()


func _build() -> void:
	var v := VBoxContainer.new()
	add_child(v)
	v.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "剧情桥测试（A flag / C 对战请求——.thxstory）"
	title.add_theme_font_size_override("font_size", 13)
	v.add_child(title)
	## ① 存档区
	var h1 := HBoxContainer.new()
	v.add_child(h1)
	_list = OptionButton.new()
	_list.custom_minimum_size = Vector2(220, 24)
	h1.add_child(_list)
	var b_ref := Button.new()
	b_ref.text = "刷新"
	b_ref.pressed.connect(_refresh_list)
	h1.add_child(b_ref)
	var b_load := Button.new()
	b_load.text = "读档"
	b_load.pressed.connect(_do_load)
	h1.add_child(b_load)
	var b_apply := Button.new()
	b_apply.text = "应用进场"
	b_apply.pressed.connect(_do_apply)
	h1.add_child(b_apply)
	## ② flag 显示区
	var t_title := Label.new()
	t_title.text = "flag 变量表（组 / 序号 / 值）——写走剧情侧，本面板只读显示"
	t_title.add_theme_font_size_override("font_size", 11)
	t_title.add_theme_color_override("font_color", Color("9a9aa5"))
	v.add_child(t_title)
	_flag_text = RichTextLabel.new()
	_flag_text.custom_minimum_size = Vector2(410, 110)
	_flag_text.bbcode_enabled = true
	v.add_child(_flag_text)
	## ③ 造档区
	var h2 := HBoxContainer.new()
	v.add_child(h2)
	_g_in = _mk_in(h2, "组")
	_i_in = _mk_in(h2, "序号")
	_v_in = _mk_in(h2, "值")
	var b_set := Button.new()
	b_set.text = "写入 flag"
	b_set.pressed.connect(_do_set)
	h2.add_child(b_set)
	var h3 := HBoxContainer.new()
	v.add_child(h3)
	var b_mk := Button.new()
	b_mk.text = "造测试存档（demo 组+对战配置）"
	b_mk.pressed.connect(_do_make)
	h3.add_child(b_mk)
	var hint := Label.new()
	hint.text = "应用进场=读档→写穿 versus_*→直接进 battle_arena（批复③）"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color("eeb30b"))
	v.add_child(hint)
	_refresh_list()
	_refresh_flags()


func _mk_in(parent: Control, ph: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = ph
	e.custom_minimum_size = Vector2(90, 24)
	parent.add_child(e)
	return e


func _refresh_list() -> void:
	_list.clear()
	if _sb == null:
		return
	for f in _sb.story_save_list():
		_list.add_item(f)


func _sel_path() -> String:
	if _sb == null or _list.item_count == 0:
		return ""
	var f := _list.get_item_text(_list.selected if _list.selected >= 0 else 0)
	return "user://storysaves/" + f


func _do_load() -> void:
	if _sb == null:
		return
	_sb.load_story(_sel_path())
	_refresh_flags()


func _do_apply() -> void:
	if _sb == null:
		return
	_sb.apply_story(_sel_path())


func _do_set() -> void:
	if _sb == null:
		return
	var g := _g_in.text.strip_edges()
	var i := _i_in.text.strip_edges().to_int()
	var raw := _v_in.text.strip_edges()
	var v: Variant = raw.to_float() if raw.is_valid_float() else (raw if raw != "" else true)
	_sb.set_flag(g, i, v)
	_refresh_flags()


func _do_make() -> void:
	## 造一份标准测试档：demo 组三 flag + 对战配置（默认队样例）
	if _sb == null:
		return
	_sb.set_flag("demo", 1, "序章完成")
	_sb.set_flag("demo", 2, true)
	_sb.set_flag("demo", 3, 42)
	_sb._last_cfg = {
		"player_team": ["MarisaA", "ReimuA", "ReisenA", "Alice", "Nitori"],
		"enemy_team": ["Rumia", "Suika", "Aya", "Patchouli", "Yuka"],
		"start_pp": 100,
		"start_spell": 1,
	}
	_sb.save_story("user://storysaves/story_test_demo.thxstory")
	_refresh_list()
	_refresh_flags()


func _refresh_flags() -> void:
	if _sb == null or _flag_text == null:
		return
	var lines := ""
	var groups: Dictionary = _sb._flag_groups
	if groups.is_empty():
		lines = "[color=#9a9aa5]（空——写入 flag 或读档）[/color]"
	for g in groups:
		var idxs: Dictionary = groups[g]
		lines += "[color=#3bc5ff]%s[/color]：" % str(g)
		for i in idxs:
			lines += "[%s]=%s  " % [str(i), str(idxs[i])]
		lines += "\n"
	_flag_text.text = lines
