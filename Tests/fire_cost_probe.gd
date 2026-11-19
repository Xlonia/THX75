extends Node
## fire_cost_probe —— P 驱动投放链路逐环节成本表（m98）
## 每发开火成本分解：_rot_eval_ctx / eval_spawn / eval_rotate / plan / _spawn_rotated_copy
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
	var ev = arena._find_event("demo_aimed")
	var N := 400
	## 1. _rot_eval_ctx（全量构造：20+ 键字典+get 系）
	var t0 := Time.get_ticks_usec()
	for i in N:
		arena._rot_eval_ctx(pl, null)
	var ctx_us := (Time.get_ticks_usec() - t0) / float(N)
	## 2. eval_spawn+rotate+plan（每发参数解算）
	var ctx = arena._rot_eval_ctx(pl, null)
	t0 = Time.get_ticks_usec()
	for i in N:
		var sp = ev.eval_spawn_params(ctx)
		var rp = ev.eval_rotate_params(ctx)
		var plan = DanmakuEventData.rotate_release_plan(rp)
	var eval_us := (Time.get_ticks_usec() - t0) / float(N)
	## 3. _spawn_rotated_copy（单副本：setup+钩子+入列）
	arena.bullet_suppress_at = 999999
	t0 = Time.get_ticks_usec()
	var n0: int = arena.bullets.size()
	for i in 40:
		arena._spawn_rotated_copy(ev, Vector2(200, 200), pl, null, 0.0, 0, {}, 1, false,
			Vector2.ZERO, 0.0, null, Vector2.INF, {}, {}, "probe")
	var spawn_us := (Time.get_ticks_usec() - t0) / 40.0
	print("[每发成本] ctx=%.1fµs eval+plan=%.1fµs 单副本spawn=%.1fµs" % [ctx_us, eval_us, spawn_us])
	## 4. 全链（_on_fire 一次=12 副本展开）
	arena.bullets.clear()
	t0 = Time.get_ticks_usec()
	for i in 40:
		arena._on_fire(null, ev, {})
	var full_us := (Time.get_ticks_usec() - t0) / 40.0
	print("[全链开火] %.1fµs/发（含 %d 副本展开）" % [full_us, arena.bullets.size()])
	print("FIRE_%s" % "OK")
	get_tree().quit(0)
