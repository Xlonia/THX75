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
	var rows := CharaDB.load_all()
	var no_tex := 0
	var no_ev := 0
	for d in rows:
		var has_tex: bool = not CharaTex.get_chara(str(d.get("Name", "")), str(d.get("NameZH", ""))).is_empty()
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
	for t2 in ["团队：双击 Ctrl 取消全部指令✓；T 自动增援✓（空缺阈值口径）；敌方投降 AI✓；道具 M/J/U✓（m109 疗伤/修理/复活）；R 增援✓（支援框条件 m110）",
		"角色：接管 Z/X/C/X+C✓（m66/m92/m104）；X/C 请求 2 秒窗✓；Shift+R/Z/A✓；铃仙 Y✓；长按S 撤退✓；长按A 轮换=搭档组规则遗留（结界<5 限制未建模）",
		"杂兵：悬停/血量排序✓；万岁冲锋✓；退下/预备队✓",
		"通用：改键入口✓（键位一览→修改按键）",
		"
【遗留（0.2.0/后续）】长按A 搭档组规则｜道具 AI 逻辑（目标选择器对接 m114）｜擦弹效果测试（判定链已就位）｜Hp 图重设计（实时印章+慢记忆——已停用备忘）"]:
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
