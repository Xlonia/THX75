extends Node
## 插入按钮真实 UI 无头测试：实例化编辑器→选事件→找到 x 表达式框→
## 打开工具浮窗→选中 gettarget→点「插入」→断言文本插入成功
var fails := 0
func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["PASS" if c else "FAIL", m])
	if not c:
		fails += 1
func _ready() -> void:
	var ed: Node = (load("res://addons/thxgamekit/kit/scenes/danmaku_editor.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", ed)
	await get_tree().process_frame
	await get_tree().process_frame
	## 找一个表达式输入框（弹幕页 x 权重）
	var target_le: LineEdit = null
	var stack: Array = [ed]
	while not stack.is_empty() and target_le == null:
		var n: Node = stack.pop_back()
		if n is LineEdit and n.text.contains("gettarget"):
			target_le = n
			break
		for c in n.get_children():
			stack.push_back(c)
	_check(target_le != null, "找到表达式输入框")
	if target_le == null:
		_done()
		return
	var before: String = target_le.text
	## 打开浮窗（参数类）
	ed._show_tool_popup(true, target_le)
	await get_tree().process_frame
	## 在窗口根找 PopupPanel
	var popup: PopupPanel = null
	for w in get_tree().root.get_children():
		if w is PopupPanel:
			popup = w
	_check(popup != null, "浮窗已挂根")
	if popup == null:
		_done()
		return
	## 找 ItemList 与「插入」按钮
	var il: ItemList = null
	var ins_btn: Button = null
	var st2: Array = [popup]
	while not st2.is_empty():
		var n2: Node = st2.pop_back()
		if n2 is ItemList and il == null:
			il = n2
		if n2 is Button and (n2 as Button).text == "插入":
			ins_btn = n2
		for c2 in n2.get_children():
			st2.push_back(c2)
	_check(il != null and ins_btn != null, "ItemList+插入按钮存在（列表%d项）" % (il.item_count if il else -1))
	## 选中 gettarget 条目（变量引用分类默认）
	var gi := -1
	for i in il.item_count:
		if il.get_item_text(i).contains("gettarget"):
			gi = i
			break
	_check(gi >= 0, "gettarget 条目存在")
	il.select(gi)
	il.item_selected.emit(gi)
	await get_tree().process_frame
	## 找参数选框（build_row 内 OptionButton）并选 hpweapon
	## 参数选框=build_row 内的 OptionButton（其条目含 hpweapon）
	var ob: OptionButton = null
	var all_ob: Array = popup.find_children("*", "OptionButton", true, false)
	for c3 in all_ob:
		var o3: OptionButton = c3
		for i2 in o3.item_count:
			if o3.get_item_text(i2) == "hpweapon":
				ob = o3
				break
		if ob != null:
			break
	var want_param := "x"
	if ob != null:
		for i2 in ob.item_count:
			if ob.get_item_text(i2) == "hpweapon":
				ob.select(i2)
				want_param = "hpweapon"
				break
	_check(ob != null, "参数选框找到（含 hpweapon）")
	ins_btn.pressed.emit()
	await get_tree().process_frame
	var after: String = target_le.text
	_check(after != before and after.contains("gettarget(%s)" % want_param), "插入含所选参数 gettarget(%s)（得 …%s）" % [want_param, want_param, after.substr(maxi(0, after.length() - 22), 22)])
	_done()
func _done() -> void:
	print("INSERT_%s" % ("OK" if fails == 0 else "FAIL:%d" % fails))
	get_tree().quit(1 if fails > 0 else 0)
