class_name RetreatPointPicker
extends Control
## =============================================================
## 【m70 撤退预设点鼠标点选（scheme 新二 84 行：设置中用鼠标指定，
## 对应 9/0 键两点）】场地 400×400 按 SCALE 缩放绘制（支援框 350² 虚线提示）；
## 点击场地=把"当前槽"的点设到点击处，槽按 9→0 循环；右键=只切换当前槽。
## 落点即写回 GameGlobals.retreat_points 并存档。
## =============================================================
const SCALE := 0.75
var active := 0 ## 当前槽 0/1 → 快捷键 9/0

func _ready() -> void:
	custom_minimum_size = Vector2(400, 400) * SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var p: Vector2 = (event.position / SCALE).clamp(Vector2.ZERO, Vector2(400, 400))
			GameGlobals.retreat_points[active] = p.round()
			GameGlobals.save_default_archive()
			active = (active + 1) % 2
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			active = (active + 1) % 2
			queue_redraw()

func _draw() -> void:
	var sz := Vector2(400, 400) * SCALE
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.07, 0.08, 0.12))
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.5, 0.55, 0.7), false, 1.0)
	## 支援框（中心 350²，新二 8 行）虚线提示——撤退点语义上应在框外
	var f0: float = 25.0 * SCALE
	var f1: float = 375.0 * SCALE
	draw_rect(Rect2(Vector2(f0, f0), Vector2(f1 - f0, f1 - f0)), Color(0.4, 0.6, 0.9, 0.6), false, 1.0)
	for i in 2:
		var p: Vector2 = GameGlobals.retreat_points[i]
		var c := Color(1.0, 0.85, 0.3) if i == active else Color(0.85, 0.85, 0.9)
		draw_circle(p * SCALE, 5.0, c)
		draw_arc(p * SCALE, 9.0, 0, TAU, 20, c, 1.2)
		draw_string(ThemeDB.fallback_font, p * SCALE + Vector2(12, -6), "9" if i == 0 else "0",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
