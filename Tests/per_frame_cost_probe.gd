extends Node
## per_frame_cost_probe —— phys 8.8ms 解剖：200P 场景逐弹每帧成本分段
## （update/repeat/命中/哈希插入——找逐弹大头）
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
	## 真实场面复刻：敌方全火力点持续开火（每拍 _on_fire 全链——含 repeat/命中活动）
	var shots := 0
	while arena.bullets.size() < 900 and shots < 200:
		arena._on_fire(null, arena._find_event("demo_aimed"), {})
		shots += 1
		if shots % 6 == 0:
			for fr in 6:
				arena._physics_process(1.0 / 60.0)
	print("铺弹后在场=", arena.bullets.size(), " shots=", shots)
	var N := 120
	## 逐帧全 _physics_process（真实口径）
	var t := Time.get_ticks_usec()
	for i in N:
		arena._physics_process(1.0 / 60.0)
	var per_frame := (Time.get_ticks_usec() - t) / float(N)
	print("每帧 phys=%.2fms" % [per_frame / 1000.0])
	## 分项：单独跑 bullet update 段（复刻 _bullet_updates 核心循环——去掉命中/AI/热力）
	t = Time.get_ticks_usec()
	var gctx := {"field_t": float(arena.time_frames), "field_phase": 1.0}
	for i in N:
		for b in arena.bullets:
			var bl: Bullet = b
			bl.sync_shared(gctx)
			if not bl.update(1.0):
				pass
	print("纯逐弹 update=%.2fms/帧" % [(Time.get_ticks_usec() - t) / float(N) / 1000.0])
	get_tree().quit(0)
