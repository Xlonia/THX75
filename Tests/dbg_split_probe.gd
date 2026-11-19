extends Node
## dbg_split_probe —— 用既有 _dbg_split 分段仪表解剖 920 弹 phys
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
	arena._dbg_split = true
	for k in 6:
		arena._dbg_acc[k] = 0.0
	var N := 120
	var t := Time.get_ticks_usec()
	for i in N:
		arena._physics_process(1.0 / 60.0)
	var total := (Time.get_ticks_usec() - t) / float(N) / 1000.0
	## 段序：[0]=phys 前(t0 前) [1]=态势/实体(t0→t1b? 读现场) [2]=实体 [3]=_bullet_updates
	## [4]=命中+拾取 [5]=态势拆分 —— 以现场打印实测为准
	var labels := ["seg0(实体前)", "seg1(态势拆分)", "seg2(实体)", "seg3(bullet_updates)", "seg4(命中拾取)", "seg5(实态势)"]
	for k in 6:
		var ms: float = arena._dbg_acc[k] / float(N) / 1000.0
		print("%s=%.2fms" % [labels[k], ms])
	print("全链=%.2fms" % total)
	get_tree().quit(0)
