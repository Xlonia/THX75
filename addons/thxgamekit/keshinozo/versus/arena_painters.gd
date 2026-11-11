extends Node2D
## 绘制层桥接脚本（battle_arena 动态创建并挂载）
## draw_kind: "entities"=实体圈 / "bullets"=激光与轨道线 / "bulletmm"=MultiMesh粒子弹幕
##            / "ddm"=DDM调试
## 每物理帧 queue_redraw，_draw 时回调宿主的对应绘制函数

var host: Node2D = null
var draw_kind := "bullets"

func _draw() -> void:
	if host == null:
		return
	match draw_kind:
		"entities":
			host.draw_entities(self)
		"bullets":
			host.draw_bullets(self)
		"bulletmm":
			host.draw_bullet_mm(self)
		"ddm":
			host.draw_ddm_debug(self)
		"contour":
			host.draw_contour_lines(self) ## 【0.0.9·等高面】

var _redraw_acc := 0
func _physics_process(_delta: float) -> void:
	## 【0.0.9·等高面绘制降频（作者性能裁定）】contour 数据 10fps 更新——
	## 绘制同步 10Hz（原每帧全量重画数千多边形=铺场期 100-200ms 帧耗元凶）
	_redraw_acc += 1
	if draw_kind == "contour":
		if _redraw_acc % 6 == 0:
			queue_redraw()
	else:
		queue_redraw()
