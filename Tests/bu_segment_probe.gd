extends Node
## bu_segment_probe —— _bullet_updates 5.07ms 内部再分：844 C++ 弹的回填+哈希插入成本
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
	## A: cpp 哈希插入单独（每弹 pos 取整×2+append）
	var t := Time.get_ticks_usec()
	for i in N:
		arena.bullet_hash_cpp.begin_frame()
		for bi in arena.bullets.size():
			var bl: Bullet = arena.bullets[bi]
			if not bl.hidden_now:
				arena.bullet_hash_cpp.insert(bl.pos.x, bl.pos.y, bl.hit_radius(), bi, bl.source_side, bl.ev.is_phy)
	print("cpp 哈希插入=%.2fms/帧（%d 弹）" % [(Time.get_ticks_usec() - t) / float(N) / 1000.0, arena.bullets.size()])
	## B: sync_shared+update 逐弹（GD 分支——仅 GD 逐帧弹）
	var gd_bullets: Array = []
	for b in arena.bullets:
		if not (b as Bullet)._mh_owned:
			gd_bullets.append(b)
	t = Time.get_ticks_usec()
	var gctx := {"field_t": 0.0, "field_phase": 1.0}
	for i in N:
		for b2 in gd_bullets:
			var bl2: Bullet = b2
			bl2.sync_shared(gctx)
			bl2.update(1.0)
	print("GD 逐弹 update=%.2fms/帧（%d 弹）" % [(Time.get_ticks_usec() - t) / float(N) / 1000.0, gd_bullets.size()])
	## C: MotionHot 回填（advance+get_frozen_pos+get_dead）
	if arena.motion_hot != null:
		t = Time.get_ticks_usec()
		for i in N:
			arena.motion_hot.begin_frame(1.0)
			var mo: PackedFloat64Array = arena.motion_hot.get_frozen_pos()
			var md: Array = arena.motion_hot.get_dead()
		print("MotionHot 回填=%.2fms/帧" % [(Time.get_ticks_usec() - t) / float(N) / 1000.0])
	get_tree().quit(0)
