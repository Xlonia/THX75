extends Node
## 编辑器窗口打开验证（submodule 脚本直实例化——与 title_menu 同路径）
func _ready() -> void:
	var win := Window.new()
	win.title = "THX075 弹幕编辑器"
	var ed: Control = (load("res://addons/thxgamekit/kit/addons/thx_gamekit/editor/danmaku_editor.gd") as GDScript).new()
	ed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(ed)
	add_child(win)
	await get_tree().process_frame
	await get_tree().process_frame
	var ok1: bool = is_instance_valid(ed) and ed.get_child_count() > 0
	print("  %s 编辑器实例化（子节点 %d）" % ["PASS" if ok1 else "FAIL", ed.get_child_count() if ed.get_child_count() > 0 else 0])
	## 编辑器工作集=本地 events（装载自 GameGlobals.OFFICIAL_EVENT_CSVS→内核 data 晚汐示例）
	var ok2: bool = ed.events.size() > 0
	print("  %s 事件装载（工作集 %d 件）" % ["PASS" if ok2 else "FAIL", ed.events.size()])
	print("EDT_OK" if ok1 and ok2 else "EDT_FAIL")
	get_tree().quit(0 if ok1 and ok2 else 1)
