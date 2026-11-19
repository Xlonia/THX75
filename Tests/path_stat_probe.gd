extends Node
## path_stat_probe —— demo_aimed 弹实际走的 _step_regular 路径统计（表/闭包/兜底）
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
	var pl = arena.player_leader
	var en = arena.enemy_leader
	arena.bullet_suppress_at = 999999
	## 真实场面铺弹
	var shots := 0
	while arena.bullets.size() < 900 and shots < 200:
		arena._on_fire(null, arena._find_event("demo_aimed"), {})
		shots += 1
		if shots % 6 == 0:
			for fr in 6:
				arena._physics_process(1.0 / 60.0)
	print("在场=", arena.bullets.size())
	## 清零路径统计
	var stat_before: Array = Bullet._path_stat.duplicate()
	var N := 60
	var t := Time.get_ticks_usec()
	for i in N:
		arena._physics_process(1.0 / 60.0)
	var dt := (Time.get_ticks_usec() - t) / float(N) / 1000.0
	var stat_after: Array = Bullet._path_stat.duplicate()
	print("每帧 phys=%.2fms" % dt)
	print("路径增量：frozen=%d 查表=%d 闭包=%d 兜底=%d" % [
		stat_after[0] - stat_before[0], stat_after[1] - stat_before[1],
		stat_after[2] - stat_before[2], stat_after[3] - stat_before[3]])
	get_tree().quit(0)
