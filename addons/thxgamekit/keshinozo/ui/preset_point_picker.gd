class_name PresetPointPicker
extends Control
## =============================================================
## 机控预设点鼠标点选（新二 81 行：设置中玩家可以用鼠标指定三个点，对应
## 4/5/6 快捷键，可以在任意决斗中使用）——0.0.9·20261109
##   场地 400×400 按 SCALE 缩放绘制；点击场地=把"当前槽"的点设到点击处，
##   槽按 4→5→6 循环；右键=只切换当前槽。落点即写回 GameGlobals 并存档。
## =============================================================
const SCALE := 0.75
var active := 0 ## 当前槽 0..2 → 快捷键 4/5/6

func _ready() -> void:
	custom_minimum_size = Vector2(400, 400) * SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var p: Vector2 = (event.position / SCALE).clamp(Vector2.ZERO, Vector2(400, 400))
			GameGlobals.preset_points[active] = p.round()
			GameGlobals.save_default_archive()
			active = (active + 1) % 3
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			active = (active + 1) % 3
			queue_redraw()

func _draw() -> void:
	var sz := Vector2(400, 400) * SCALE
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.07, 0.08, 0.12))
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.5, 0.55, 0.7), false, 1.0)
	## 中线（上=敌方 下=我方）
	draw_line(Vector2(0, sz.y / 2.0), Vector2(sz.x, sz.y / 2.0), Color(0.3, 0.32, 0.4), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(6, 16), "敌方", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.5, 0.5))
	draw_string(ThemeDB.fallback_font, Vector2(6, sz.y - 6), "我方", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.7, 1.0))
	for i in 3:
		var p: Vector2 = GameGlobals.preset_points[i]
		var c := Color(1.0, 0.85, 0.3) if i == active else Color(0.85, 0.85, 0.9)
		draw_circle(p * SCALE, 5.0, c)
		draw_arc(p * SCALE, 9.0, 0, TAU, 20, c, 1.2)
		draw_string(ThemeDB.fallback_font, p * SCALE + Vector2(10, -6), str(4 + i), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
