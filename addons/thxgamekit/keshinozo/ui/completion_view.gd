@tool
const _CDB := preload("res://addons/thxgamekit/kit/addons/thx_gamekit/core/data/chara_db.gd")
const _CTX := preload("res://addons/thxgamekit/kit/addons/thx_gamekit/core/render/chara_tex.gd")
class_name CompletionView
extends RefCounted
## =============================================================
## 完成度一览弹窗（0.0.9·作者 20261109 要求④）：缺贴图/弹幕槽未配全的角色
## +未实装机控清单。入口=自定义对战按钮+标题画面左下按钮。
## 【留档】作者三项要求（后续版本跟进时作参考）：
##   ①弹幕编辑器角色设置中设置贴图并支持预览（本版=目录约定装载）
##   ②精灵图集完整动画帧表（本版=条带启发式+8fps 循环，单帧图静止）
##   ③本一览按钮本身
## =============================================================

static func show(tree: SceneTree) -> void:
	var win := Window.new()
	win.title = "完成度一览"
	win.size = Vector2i(560, 620)
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
	var h1 := Label.new()
	h1.text = "【角色】贴图=Players/Battle/Chars/<名>.PNG；弹幕槽=main/sub/skill/spell"
	h1.add_theme_font_size_override("font_size", 13)
	box.add_child(h1)
	var rows := _CDB.load_all()
	var no_tex := 0
	var no_ev := 0
	for d in rows:
		var has_tex: bool = not _CTX.get_chara(str(d.get("Name", "")), str(d.get("NameZH", ""))).is_empty()
		var miss := _missing_slots(d)
		var full := miss == ""
		if not has_tex:
			no_tex += 1
		if not full:
			no_ev += 1
		var l := Label.new()
		l.text = "%s%s：%s%s" % ["✓" if has_tex else "✗", "✓" if full else "✗",
			str(d.get("Name", "?")), "" if full else "（缺 %s）" % miss]
		l.add_theme_font_size_override("font_size", 12)
		box.add_child(l)
	var h2 := Label.new()
	h2.text = "\n缺贴图 %d/%d；弹幕槽未配全 %d/%d" % [no_tex, rows.size(), no_ev, rows.size()]
	h2.add_theme_font_size_override("font_size", 13)
	box.add_child(h2)
	var h3 := Label.new()
	h3.text = "\n【机控未实装/部分（20261109 盘点）】"
	h3.add_theme_font_size_override("font_size", 13)
	box.add_child(h3)
	for t2 in ["团队：双击 Shift 取消未做；T 自动增援开关未接线；冒进≡龟缩（姿态权重待接）；敌方投降 AI 未做；道具 M/J/U 未做",
		"角色：接管中 Z/X/C 未区分接管态、X+C 主要符卡未做；X/C 请求窗口约0.1秒（规格2秒）；Shift+R、Shift+Z、Shift+A 未做；铃仙 Y 占位；撤退长按 S 未做；长按A 队伍特殊规则/结界破碎条件未做",
		"杂兵：悬停选取/血量排序未做；退下未回预备队；万岁冲锋未移动至判定点",
		"通用：改键界面无入口（capturing_action 未接线）",
		"\n【后续版本参考（作者要求留档 0.0.9）】①弹幕编辑器角色设置中设置贴图+预览 ②完整动画帧表（当前=条带图集启发式+8fps 循环）"]:
		var l3 := Label.new()
		l3.text = t2
		l3.add_theme_font_size_override("font_size", 12)
		l3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l3)
	win.close_requested.connect(func(): win.queue_free())
	var ds := DisplayServer.window_get_position()
	var wsz := DisplayServer.window_get_size()
	win.position = ds + (wsz - Vector2i(560, 620)) / 2
	tree.root.add_child(win)

static func _missing_slots(d: Dictionary) -> String:
	var miss: Array = []
	for col in ["main_evs", "sub_evs", "skill_evs", "spell_evs"]:
		if str(d.get(col, "")).strip_edges() == "":
			miss.append(col.trim_suffix("_evs"))
	return "/".join(miss)
