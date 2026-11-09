extends Node
## x_copy/y_copy 收敛测试（作者批复 20261025：斜向目标、非正右侧）
## 断言：旋转扇内全部副本的世界速度=目标方向（集中功能；偏差<0.5°）
func _ready() -> void:
	var arena: Node2D = (load("res://scenes/battle_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	var me: BattleEntity = arena.player_ents[0]
	me.position = Vector2(200, 300) ## 弹幕起点（下方）
	var enemy: BattleEntity = arena.enemy_ents[0]
	enemy.position = Vector2(300, 100) ## 斜向右上目标（测试作者要求：非正右侧）
	var ev := DanmakuEventData.new()
	ev.event_name = "t_conv"
	ev.tag = DanmakuEventData.TAG_PHYSICAL
	ev.speed = "1"
	ev.x = "x_copy/d"
	ev.y = "y_copy/d"
	ev.rotate_range = "2"
	ev.rotate_div = "8"
	ev.compile()
	for i in 9:
		var ang := -1.0 + 0.25 * i ## -1..1 rad 扇
		var b := Bullet.new()
		b.rot_angle = ang
		b.setup(ev, me.position, 0, me, arena, 0, {})
		var v := b.velocity ## 出生即冻结速度（无t依赖）
		var want := (enemy.position - me.position).normalized()
		var want2 := Vector2(b._ctx.get("target_x", 0.0), b._ctx.get("target_y", 0.0)).normalized()
		var dev := absf(rad_to_deg(v.angle_to(want2)))
		if dev > 0.5:
			print("XCOPY_FAIL ang=%+.2f dev=%.3f°" % [ang, dev])
			get_tree().quit(1)
			return
	print("XCOPY_OK 9角度全部偏差<0.5°（集中功能成立）")
	get_tree().quit(0)
