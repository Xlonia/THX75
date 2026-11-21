extends Node
## fire_cost_probe14 —— 全链成本正确口径（预热后再测；同环境对照 1031c 时代 120µs）
func _ready() -> void:
	var arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	for i in 8:
		arena._physics_process(1.0 / 60.0)
	var pl = arena.player_leader
	var ev = arena._find_event("demo_aimed")
	arena.bullet_suppress_at = 999999
	var ctx = arena._rot_eval_ctx(pl, null)
	var N := 300
	## 预热 50 次（编译/管线/分配器热身）
	for i in 50:
		arena._on_fire(null, ev, {})
	arena.bullets.clear()
	arena._cannons.clear()
	arena._nodesb_alive = 0
	## 正式测量
	var t := Time.get_ticks_usec()
	var n0: int = arena.bullets.size()
	for i in N:
		arena._on_fire(null, ev, {})
	var full := (Time.get_ticks_usec() - t) / float(N)
	print("全链开火（预热后）=%.1fµs/发（展开副本数=%d）" % [full, arena.bullets.size() - n0])
	## ctx/eval 复测（预热后）
	t = Time.get_ticks_usec()
	for i in N:
		arena._rot_eval_ctx(pl, null)
	print("ctx=%.1fµs" % ((Time.get_ticks_usec() - t) / float(N)))
	t = Time.get_ticks_usec()
	for i in N:
		var sp = ev.eval_spawn_params(ctx)
		var rp = ev.eval_rotate_params(ctx)
		var plan = DanmakuEventData.rotate_release_plan(rp)
	print("eval+plan=%.1fµs" % ((Time.get_ticks_usec() - t) / float(N)))
	get_tree().quit(0)
