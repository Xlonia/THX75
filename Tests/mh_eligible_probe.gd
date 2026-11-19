extends Node
## mh_eligible_probe —— 920 弹场面：C++ 接管 vs GD 逐帧的弹数分布（命题 B 面）
func _ready() -> void:
	var arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	for i in 8:
		arena._physics_process(1.0 / 60.0)
	var en = arena.enemy_leader
	arena.bullet_suppress_at = 999999
	var shots := 0
	while arena.bullets.size() < 900 and shots < 200:
		arena._on_fire(null, arena._find_event("demo_aimed"), {})
		shots += 1
		if shots % 6 == 0:
			for fr in 6:
				arena._physics_process(1.0 / 60.0)
	print("在场=", arena.bullets.size())
	var owned := 0
	var gd_frame := 0
	var gd_sample := 0
	var why := {}
	for b in arena.bullets:
		var bl: Bullet = b
		if bl._mh_owned:
			owned += 1
		elif bl.mh_eligible():
			gd_sample += 1
		else:
			gd_frame += 1
			var k: String = "repeat载体" if (bl.repeat_enabled and bl.repeat_freq_now > 0) else ("表达式弹" if (bl.ev.ex_alpha != null or bl.ev.ex_hue != null or bl.ev.ex_pass != null) else "other")
			why[k] = int(why.get(k, 0)) + 1
	print("C++接管=%d GD待接管( eligible 未处理 )=%d GD逐帧=%d" % [owned, gd_sample, gd_frame])
	print("GD 逐帧原因分布=", why)
	get_tree().quit(0)
