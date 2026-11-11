extends Node
## =============================================================
## win_probe —— 编辑器独立窗口机制实测（需窗口模式，非 headless）
##   ①root.gui_embed_subwindows 现值（false=Window 节点=真 OS 窗口）
##   ②呼出编辑器窗口前后 OS 窗口列表数量（2=真独立窗口；1=内嵌失效）
##   ③编辑器窗口尺寸/位置（内嵌模式下会被主窗口裁剪=底栏按钮消失的根源）
## 用法：godot --path . res://Tests/win_probe.tscn
## =============================================================
func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("[win] gui_embed_subwindows=%s" % str(get_tree().root.gui_embed_subwindows))
	var n0: int = DisplayServer.get_window_list().size()
	print("[win] 初始 OS 窗口数=%d" % n0)
	## 呼出编辑器（复刻 title_menu._open_editor_window）
	var w := Window.new()
	w.title = "THX075 弹幕编辑器"
	w.size = Vector2i(1280, 800)
	var ed := (load("res://addons/thxgamekit/kit/scenes/danmaku_editor.tscn") as PackedScene).instantiate()
	w.add_child(ed)
	get_tree().root.add_child(w)
	w.show()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var n1: int = DisplayServer.get_window_list().size()
	print("[win] 呼出编辑器后 OS 窗口数=%d（%s）" % [n1, "真独立窗口" if n1 > n0 else "内嵌——embed 失效！"])
	var ed_rect := Rect2i(w.position, w.size)
	print("[win] 编辑器窗口 pos=%s size=%s（可见域外=内嵌裁剪风险）" % [str(ed_rect.position), str(ed_rect.size)])
	w.queue_free()
	print("WIN_OK" if n1 > n0 else "WIN_EMBED_FAIL")
	get_tree().quit(0)
