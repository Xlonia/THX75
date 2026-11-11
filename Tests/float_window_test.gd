extends Node
## float_window_test —— 弹幕显示浮窗验证（kpath 修复后）
func _ready() -> void:
	## 模拟编辑器环境：预览台脚本从内核 submodule 加载
	var stage_script: GDScript = load(THXKit.kpath("res://addons/thx_gamekit/editor/danmaku_preview_stage.gd"))
	var ok1: bool = stage_script != null
	print("  %s 预览台脚本加载（kpath）" % ["PASS" if ok1 else "FAIL"])
	var stage: Node2D = stage_script.new()
	add_child(stage)
	await get_tree().process_frame
	await get_tree().process_frame
	var ev := THXKit.get_event("demo_youshio1")
	if ev != null:
		stage.ev = ev
	## 浮窗出弹=fire_once()（Z 按键处理内部调用——探针直接调）
	if stage.has_method("fire_once"):
		stage.fire_once()
	for k in 30:
		stage._physics_process(1.0 / 60.0)
	var ok2: bool = stage.bullets.size() > 0
	print("  %s 浮窗出弹（%d 弹在场）" % ["PASS" if ok2 else "FAIL", stage.bullets.size()])
	print("  INFO MM 渲染=headless 不触发 draw（F5 可视验证）")
	print("FLT_OK" if ok1 and ok2 else "FLT_FAIL")
	get_tree().quit(0 if ok1 and ok2 else 1)
