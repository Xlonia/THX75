extends Node
var arena: Node2D
var _n := 0
var _shots := 0
func _ready() -> void:
	GameGlobals.apply_stress_override(true)
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
func _physics_process(_d: float) -> void:
	_n += 1
	arena.time_frames += 1
	arena._player_input()
	arena._ai_sides()
	arena._entity_ticks(1.0)
	arena._sit_tick(1.0 / 60.0)
	arena._fire_ticks(1.0)
	arena._cannon_tick()
	arena._priv_shooters_tick()
	arena._rot_pending_tick()
	arena._bullet_updates(1.0)
	arena._consume_pending_samples()
	arena._render_ddm()
	arena._heatmap_tick()
	if _n > 100 and (_n % 100) == 1 and _shots < 12:
		_shots += 1
		var ev := GameGlobals.get_event("sonic_wave_like0")
		if ev != null:
			var b := Bullet.new()
			b.setup(ev, Vector2(200, 200), 0, arena.player_leader, arena, 0, {})
			b._lf_phase = randi() % 6
			arena.bullets.append(b)
	if _n % 200 == 0:
		var alive := 0
		for b2 in arena.bullets:
			var bb: Bullet = b2
			if bb.ev.event_name == "sonic_wave_like0":
				alive += 1
		print("LG f=" + str(_n) + " sonic=" + str(alive) + " 总弹=" + str(arena.bullets.size()))
	if _n >= 1800:
		print("LG 完 12 发全部射出=" + str(_shots))
		get_tree().quit()
