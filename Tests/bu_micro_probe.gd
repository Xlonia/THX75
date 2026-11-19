extends Node
## bu_micro_probe —— 921 弹 _bullet_updates 主循环逐弹 GD 分支成本直接量化
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
	var N := 60
	## 主循环空转复刻：只做 for+分支判定+continue（不做任何 update 工作）
	var t := Time.get_ticks_usec()
	for i in N:
		for i2 in range(arena.bullets.size() - 1, -1, -1):
			var b: Bullet = arena.bullets[i2]
			if b._mh_owned:
				continue
			elif not b._mh_checked:
				continue
			else:
				continue
	print("主循环空转=%.2fms/帧（921 弹纯分支）" % ((Time.get_ticks_usec() - t) / float(N) / 1000.0))
	## 对照：真 _bullet_updates
	t = Time.get_ticks_usec()
	for i in N:
		arena._bullet_updates(1.0)
	print("真 _bullet_updates=%.2fms/帧" % ((Time.get_ticks_usec() - t) / float(N) / 1000.0))
	print("→ 差值=真实逐弹工作（repeat_tick/哈希 cpp 插入/非接管 update）")
	get_tree().quit(0)
