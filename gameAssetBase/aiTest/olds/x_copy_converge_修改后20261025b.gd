extends Node
## x_copy/y_copy 语义测试（作者 20261025 语义订正版）
## ①帧数学 x_copy=R(-a)·(x,y)；②模长不变式；③扇形保留（9 副本初始方向=目标角−a）；
## ④轨迹弯曲朝目标（240帧后中心副本距目标 < 出发距离）
func _ready() -> void:
	var arena: Node2D = (load("res://scenes/battle_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	var me: BattleEntity = arena.player_ents[0]
	me.position = Vector2(200, 300) ## 起点（下方）
	var enemy: BattleEntity = arena.enemy_ents[0]
	enemy.position = Vector2(300, 100) ## 斜向右上目标（非正右侧——作者要求）
	var ev := DanmakuEventData.new()
	ev.event_name = "t_conv"
	ev.tag = DanmakuEventData.TAG_PHYSICAL
	ev.speed = "1"
	ev.x = "x_copy/d"
	ev.y = "y_copy/d"
	ev.rotate_range = "2"
	ev.rotate_div = "8"
	ev.compile()
	var copies: Array = []
	for i in 9:
		var ang := -1.0 + 0.25 * i
		var b := Bullet.new()
		b.rot_angle = ang
		b.setup(ev, me.position, 0, me, arena, 0, {})
		copies.append(b)
	var b0: Bullet = copies[0]
	var tx := float(b0._ctx["target_x"])
	var ty := float(b0._ctx["target_y"])
	var a0: float = b0.rot_angle
	var c := cos(-a0)
	var sn := sin(-a0)
	## ①帧数学
	var want_x := tx * c - ty * sn
	var want_y := tx * sn + ty * c
	if absf(float(b0._ctx["x_copy"]) - want_x) > 0.001 or absf(float(b0._ctx["y_copy"]) - want_y) > 0.001:
		print("XCOPY_FAIL frame-math got=(%f,%f) want=(%f,%f)" % [float(b0._ctx["x_copy"]), float(b0._ctx["y_copy"]), want_x, want_y])
		get_tree().quit(1)
		return
	## ②模长不变式
	var nrm := sqrt(float(b0._ctx["x_copy"]) ** 2 + float(b0._ctx["y_copy"]) ** 2)
	if absf(nrm - sqrt(tx * tx + ty * ty)) > 0.001:
		print("XCOPY_FAIL norm %f vs %f" % [nrm, sqrt(tx * tx + ty * ty)])
		get_tree().quit(1)
		return
	## ③扇形保留
	var tgt_ang := Vector2(tx, ty).angle()
	var dirs := {}
	for i in 9:
		var bi: Bullet = copies[i]
		bi.update(1.0) ## 非冻结路径：首个 update 才求值 velocity
		var want_ang := wrapf(tgt_ang - bi.rot_angle, -PI, PI)
		if absf(angle_difference(bi.velocity.angle(), want_ang)) > 0.001:
			print("XCOPY_FAIL fan i=%d got=%f want=%f tgt=%f" % [i, bi.velocity.angle(), want_ang, tgt_ang])
			get_tree().quit(1)
			return
		dirs[bi.velocity.angle()] = true
	if dirs.size() != 9:
		print("XCOPY_FAIL dir-count %d" % dirs.size())
		get_tree().quit(1)
		return
	## ④弯曲朝目标 + 轨迹证据（再步进 239 帧，共 240）
	var t0 := me.position + Vector2(tx, ty)
	var dist_start := me.position.distance_to(t0)
	var sep_log := PackedFloat32Array()
	for f in 239:
		for b in copies:
			var bb: Bullet = b
			bb.update(1.0)
		if f % 60 == 0:
			var cm: Bullet = copies[4]
			sep_log.append(cm.pos.distance_to(t0))
	var dist_end: float = (copies[4] as Bullet).pos.distance_to(t0)
	if dist_end >= dist_start:
		print("XCOPY_FAIL curve dist %d->%d" % [int(dist_start), int(dist_end)])
		get_tree().quit(1)
		return
	print("XCOPY_OK 帧数学/模长/扇形9向/弯曲趋近 通过（中心副本距目标 %d→%d，采样=%s）" % [int(dist_start), int(dist_end), str(sep_log)])
	get_tree().quit(0)
