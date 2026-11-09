extends TextureRect
## 灵梦标题动画（作者批复 2026-10-13：立绘全身、随窗口缩放）
## 原版硬编码 720/-200（仅适配 1280 宽）——现全部改为窗口宽度比例：
##   入场：从画面右侧（0.5625×宽）缓动飘至左侧（-0.15625×宽）
##   点击任意键：从左侧缓动飘回原位（0）
## 材质 1920×1080（含全身），TextureRect 全窗拉伸 KEEP_ASPECT_COVERED。

var bg_reimu_spd
var bg_reimu_startmove = false
var bg_reimu_clickmove = false
var geclickmovet = false
var bg_reimu_spd_var

func _win_w() -> float:
	## 立绘层已缩放 0.5：动画行程按半幅窗口计算（保持原视觉节奏）
	return get_viewport_rect().size.x * 0.5

func _start_x() -> float:
	return _win_w() * 0.5625 ## 720/1280：画面右外侧

func _end_x() -> float:
	return -_win_w() * 0.15625 ## -200/1280：左侧仅露边缘

func _ready() -> void:
	position.x = _start_x()
	bg_reimu_startmove = true
	bg_reimu_spd_var = 0.01
	resized.connect(_on_resize)

func _on_resize() -> void:
	## 窗口缩放：按比例重置到当前动画阶段对应的位置
	if bg_reimu_startmove:
		position.x = _start_x()
	elif bg_reimu_clickmove:
		position.x = _end_x()
	else:
		position.x = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and geclickmovet == false:
		bg_reimu_clickmove = true
		bg_reimu_startmove = false
		position.x = _end_x()
		bg_reimu_spd_var = 0.01
		geclickmovet = true

func _process(_delta: float) -> void:
	if bg_reimu_startmove == true: #开头灵梦从右飘来的这个动画
		bg_reimu_spd = bg_reimu_spd_var * abs(position.x - _end_x())
		position.x -= bg_reimu_spd
		bg_reimu_spd_var += 0.001
		if position.x <= _end_x(): #动画结束
			bg_reimu_startmove = false
			position.x = _end_x()
			bg_reimu_spd_var = 0.01
	if bg_reimu_clickmove == true: #灵梦往右飘回原位的这个动画
		bg_reimu_spd = bg_reimu_spd_var * 3 * abs(position.x)
		position.x += bg_reimu_spd
		bg_reimu_spd_var += 0.001
		if position.x >= 0: #动画结束
			bg_reimu_clickmove = false
			position.x = 0
			bg_reimu_spd_var = 0.01
