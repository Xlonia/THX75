extends SceneTree
## 【m73 tab 编辑器环境探针】复刻 Godot 编辑器主屏条件（--script 模式=无 autoload，
## THXKit 不存在→_kit()=null→走镜像）实测 scenario_editor 四子标签页构建：
## m69 修复前=editor_timelines null 整页中断（作者实测"大部分空白"）；
## 修复后=四页全部有内容。跑法：godot --headless --path . --script res://Tests/edittab_probe.gd
func _init() -> void:
	_run()
func _run() -> void:
	var ok := true
	var has_thxkit := root != null and root.has_node("THXKit")
	print("[edittab] 无 autoload 环境（THXKit 在场=%s）" % str(has_thxkit))
	var sc: GDScript = load("res://addons/thx_gamekit/editor/scenario_editor.gd") if ResourceLoader.exists("res://addons/thx_gamekit/editor/scenario_editor.gd") else load("res://addons/thxgamekit/kit/addons/thx_gamekit/editor/scenario_editor.gd")
	if sc == null:
		print("EDTTAB_FAIL: scenario_editor 载入失败")
		quit(1)
		return
	var inst: Control = sc.new()
	root.add_child(inst)
	await process_frame
	await process_frame
	# _ready 应已建四页——逐页检查非空
	var subs: TabContainer = inst._subs
	if subs == null:
		print("EDTTAB_FAIL: _subs 未构建")
		quit(1)
		return
	for i in subs.get_child_count():
		var page := subs.get_child(i)
		var n: int = page.get_child_count()
		print("[edittab] 页=%s 子节点=%d" % [page.name, n])
		if n == 0:
			ok = false
	# 内核引用页进一步检查：勾选框行存在（作者报"只有文字没勾选框"的验证点）
	var cfg_page: Control = subs.get_node_or_null("内核引用")
	if cfg_page != null:
		var found_cb := _count_checkbox(cfg_page)
		print("[edittab] 内核引用页 CheckBox 数=%d" % found_cb)
		if found_cb < 3:
			ok = false
	if ok:
		print("EDTTAB_OK（四页非空+勾选框在位）")
		quit(0)
	else:
		print("EDTTAB_FAIL")
		quit(1)

func _count_checkbox(node: Node) -> int:
	var n := 0
	if node is CheckBox:
		n += 1
	for c in node.get_children():
		n += _count_checkbox(c)
	return n
