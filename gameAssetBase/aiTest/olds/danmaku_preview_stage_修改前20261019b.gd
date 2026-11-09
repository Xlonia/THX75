extends Node2D
## =============================================================
## 弹幕显示浮窗舞台（作者批复 2026-10-03）：
##   "弹幕显示"= 一个独立浮窗，玩家在该浮窗内按 Z 让角色发射弹幕
##   （仅限单个弹幕事件）。直接作为 OS Window 的子节点（Window 即 Viewport，
##   输入/渲染原生可用，无需 SubViewport）。
## 舞台：400×400 逻辑画布按窗口缩放；角色在 (200,250)，敌人假想点在正上方
## （target_x/y 等变量在弹幕出现瞬间取定值——与战场同语义，弹幕直线飞出）。
## 渲染：与战场同一 HS 上色材质（MultiMesh）+ 我方法弹白色前向轨道。
## =============================================================

const LOGICAL := 400.0
## 【批复#7】浮窗内缩放：0.5~3.0 倍（鼠标滚轮调节），窗口本身可自由拖拽缩放
var zoom := 1.0

var ev: DanmakuEventData = null
var bullets: Array = []
var _pend: Array = [] ## 旋转重复延时副本 {at, ang, rid, frames}
var char_pos := Vector2(200, 250)
var frame := 0
var _mm_cache: Dictionary = {}
var _mm_last_cnt: Dictionary = {}
var _mm_layer: Node2D

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09)
	bg.size = Vector2(LOGICAL, LOGICAL)
	add_child(bg)
	_mm_layer = Node2D.new()
	## 复用战场绘制桥（draw_kind="bulletmm" → 本舞台 draw_bullet_mm）
	_mm_layer.set_script(load("res://scripts/versus/arena_painters.gd"))
	_mm_layer.host = self
	_mm_layer.draw_kind = "bulletmm"
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bullet_tint.gdshader")
	_mm_layer.material = mat
	add_child(_mm_layer)
	if get_viewport() != null:
		get_viewport().size_changed.connect(_adapt)
	call_deferred("_adapt")

func _adapt() -> void:
	## 【崩溃修复 20261003】再点浮窗按钮时旧窗体 queue_free 竞态会令
	## get_viewport() 为空——判空直接返回（新窗体的 _adapt 会接管适配）
	var vp := get_viewport()
	if vp == null:
		return
	var sz := vp.get_visible_rect().size
	var sc: float = minf(sz.x, sz.y) / LOGICAL * zoom ## 窗口自适应 × 用户缩放
	scale = Vector2(sc, sc)
	position = (sz - Vector2(LOGICAL, LOGICAL) * sc) * 0.5

## 滚轮=浮窗内缩放（0.5~3.0；批复#7）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom + 0.1, 0.5, 3.0)
			_adapt()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom - 0.1, 0.5, 3.0)
			_adapt()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Z:
				fire_once()
			KEY_ESCAPE:
				get_window().queue_free()

func set_event(e: DanmakuEventData) -> void:
	ev = e
	for b in bullets.duplicate():
		bullets.erase(b)
	queue_redraw()

func _physics_process(_delta: float) -> void:
	frame += 1
	var dt := 1.0
	for i in range(_pend.size() - 1, -1, -1):
		var pr: Dictionary = _pend[i]
		pr["frames"] = int(pr["frames"]) - 1
		if int(pr["frames"]) <= 0:
			_spawn_copy(pr["at"], pr["ang"], pr["rid"], pr.get("pinned", Vector2.ZERO))
			_pend.remove_at(i)
	for i in range(bullets.size() - 1, -1, -1):
		var b: Bullet = bullets[i]
		if not b.update(dt):
			bullets.remove_at(i)
		elif pos_out(b.pos):
			bullets.remove_at(i)
	_mm_layer.queue_redraw()
	queue_redraw()

func pos_out(p: Vector2) -> bool:
	return p.x < -80 or p.x > 480 or p.y < -80 or p.y > 480

func fire_once() -> void:
	if ev == null:
		return
	## 【旋转重复（弹幕编辑器-新）】释放时刻求值 rotate 参数（20261019 表达式化）
	## → 按步序展开；rotate_delay 步进延时（走 _pend）；首发反解基向锚定延时副本
	var ctx := _rot_eval_ctx()
	var rp: Dictionary = ev.eval_rotate_params(ctx)
	var plan: Array = DanmakuEventData.rotate_release_plan(rp)
	if plan.is_empty():
		return
	var positions: PackedFloat32Array = DanmakuEventData.rotate_positions(rp)
	var delay_step: int = maxi(0, ev.rotate_delay)
	var first := true
	var anchor_base := Vector2.ZERO
	for si in plan.size():
		for pair in plan[si]:
			var k: int = int(pair[0])
			var rid: int = int(pair[1])
			var ang: float = (positions[k] if k < positions.size() else 0.0) + float(rp.get("offset", 0.0))
			var at: Vector2 = char_pos + Vector2(0, -8)
			if delay_step <= 0 or si == 0:
				var b := _spawn_copy(at, ang, rid, anchor_base)
				if si == 0 and b != null and anchor_base == Vector2.ZERO:
					anchor_base = b.dir.rotated(-ang) ## 反解扇形基向（防延时重瞄漂移）
				first = false
			else:
				_pend.append({"at": at, "ang": ang, "rid": rid, "frames": si * delay_step,
					"pinned": anchor_base})
				first = false

## 释放时刻求值上下文（光标=假想敌；与战场快照同语义）
func _rot_eval_ctx() -> Dictionary:
	var at := char_pos + Vector2(0, -8)
	var tp := bullet_nearest_enemy_pos(0, at)
	var c := {"field_t": float(frame), "field_phase": 1.0,
		"t": 0.0, "t_r": 0.0, "rate_roll": 0.0, "pattern_roll": 0.0, "rotate_id": 0.0,
		"r0": 0.0, "r1": 0.0, "n": 0.0, "self_x": at.x, "self_y": at.y}
	if tp != at:
		c["target_x"] = tp.x - at.x
		c["target_y"] = tp.y - at.y
		c["d"] = tp.distance_to(at)
	return c

func _spawn_copy(at: Vector2, ang: float, rid: int, pinned: Vector2 = Vector2.ZERO) -> Bullet:
	var b := Bullet.new()
	b.rot_angle = ang ## 必须先于 setup：冻结表达式在 setup 内引用 rotate_id
	b.rotate_id = rid
	b.pinned_dir = pinned
	b.setup(ev, at, 0, null, self, 0, {"wpcs": 1, "to_c": 0, "main_lr": 0, "sub_lr": 0})
	b.repeat_enabled = false ## 预览不繁殖
	bullets.append(b)
	return b

## —— Bullet 世界接口（极简桩：假想敌在角色正上方）——
func bullet_time_frames() -> float:
	return float(frame)

func bullet_phase() -> int:
	return 1

func bullet_nearest_enemy(_side: int, _from: Vector2) -> Object:
	return null

func bullet_nearest_enemy_pos(_side: int, _from: Vector2) -> Vector2:
	## 【批复 20261019】光标位置=被瞄准的假想敌（自机狙在预览中可用）
	var lp := get_local_mouse_position()
	return Vector2(clampf(lp.x, -80.0, 480.0), clampf(lp.y, -80.0, 480.0))

func bullet_hit_query(_cx: float, _cy: float, _r: float, _s: int, _e) -> Dictionary:
	return {}

func spawn_event_by_name(event_name: String, at: Vector2, side: int, depth: int) -> void:
	if depth > Bullet.MAX_DEPTH:
		return
	var chain: DanmakuEventData = GameGlobals.get_event(event_name)
	if chain == null:
		return
	var b := Bullet.new()
	b.setup(chain, at, side, null, self, depth, {})
	b.repeat_enabled = false
	bullets.append(b)

## —— 绘制（与战场同款：MultiMesh+HS材质 / 白色前向轨道 / 激光线）——
func _draw() -> void:
	_draw_rotate_fan()
	draw_circle(char_pos, 4.0, Color(0.4, 0.7, 1.0))
	draw_arc(char_pos, 6.0, 0, TAU, 16, Color.WHITE, 0.5)
	for b in bullets:
		var bl: Bullet = b
		if bl.hidden_now:
			continue
		if bl.ev.tag == DanmakuEventData.TAG_LASER:
			var c := bl.modulate_color()
			c.a = bl.current_alpha_01()
			var w := bl.laser_width() * 2.0
			if bl.t <= float(bl.ev.alarm):
				w *= 0.3
			for i in bl.laser_samples.size() - 1:
				draw_line(bl.laser_samples[i], bl.laser_samples[i + 1], c, w)
		else:
			var tlen := maxf(8.0, bl.track_speed * 12.0)
			draw_line(bl.pos, bl.pos + bl.track_dir * tlen, Color(1, 1, 1, 0.3), 2.0)

## 【旋转重复预览（弹幕编辑器-新 20261015）】旋转散布存在时显示半透明扇形
## 与分割点（副本角度偏差）。扇形默认朝右——它是"角度偏差"的投射，
## 不与弹幕实际方向重合（作者原文：想总是重合只会更麻烦）。
func _draw_rotate_fan() -> void:
	if ev == null:
		return
	var rp: Dictionary = ev.eval_rotate_params(_rot_eval_ctx())
	if int(rp.get("div", 0)) <= 0:
		return
	var rng := float(rp.get("range", 0.0))
	var off := float(rp.get("offset", 0.0))
	var base := char_pos + Vector2(0, -8)
	var r := 110.0
	var edge := Color(0.55, 0.85, 1.0, 0.4)
	if rng >= PI:
		draw_circle(base, r, Color(0.55, 0.85, 1.0, 0.08)) ## 全圆
		draw_arc(base, r, 0.0, TAU, 64, edge, 1.0)
	else:
		var a0 := -rng * 0.5 + off
		var pts := PackedVector2Array([base])
		for i in 25:
			var a := a0 + rng * float(i) / 24.0
			pts.append(base + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(0.55, 0.85, 1.0, 0.12))
		draw_arc(base, r, a0, a0 + rng, 48, edge, 1.0)
	for p in DanmakuEventData.rotate_positions(rp): ## 分割点=副本角度偏差
		var a2 := p + off
		draw_line(base, base + Vector2(cos(a2), sin(a2)) * r, Color(1, 1, 1, 0.25), 1.0)

## MultiMesh 粒子弹幕绘制（arena_painters "bulletmm" 回调；与战场同款：
## 每材质1个draw call，增量停靠；HS 上色由本层材质完成）
func draw_bullet_mm(onto: CanvasItem) -> void:
	var by_tex: Dictionary = {}
	for b in bullets:
		var bl: Bullet = b
		if bl.hidden_now:
			continue
		if not by_tex.has(bl.tex):
			by_tex[bl.tex] = []
		by_tex[bl.tex].append(bl)
	for tex in by_tex:
		var list: Array = by_tex[tex]
		var mm := _get_mm(tex)
		var cnt := list.size()
		if cnt > mm.instance_count:
			mm.instance_count = cnt
		for i in cnt:
			var bl: Bullet = list[i]
			var xf := Transform2D(bl.draw_rotation(), bl.pos)
			xf = xf.scaled_local(Vector2(bl.ev.danmaku_size_muti, bl.ev.danmaku_size_muti))
			mm.set_instance_transform_2d(i, xf)
			mm.set_instance_color(i, Color(bl.modulate_color().r, bl.modulate_color().g, bl.modulate_color().b, bl.current_alpha_01()))
		if cnt < int(_mm_last_cnt.get(tex, 0)):
			for i in range(cnt, _mm_last_cnt[tex]):
				mm.set_instance_transform_2d(i, Transform2D(0, Vector2(-9999, -9999)))
		_mm_last_cnt[tex] = cnt
		onto.draw_multimesh(mm, tex)

var _mm_cache2: Dictionary = {}
func _get_mm(tex: Texture2D) -> MultiMesh:
	if _mm_cache2.has(tex):
		return _mm_cache2[tex]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.instance_count = 0
	mm.mesh = _quad_mesh(tex)
	_mm_cache2[tex] = mm
	return mm

func _quad_mesh(tex: Texture2D) -> Mesh:
	var sz: Vector2 = tex.get_size() if tex != null else Vector2(16, 16)
	var h := sz * 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
