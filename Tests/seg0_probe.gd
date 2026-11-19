extends Node
## seg0_probe —— seg0(1.89ms) 二分：_ret/命中/杂兵/逐实体 tick 分账
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
	## 逐项手动计时（seg0 内主要函数）
	var cands := [
		["_entity_ticks", [1.0 / 60.0]], ["_sit_tick", [1.0 / 60.0]], ["_fire_ticks", [1.0 / 60.0]],
		["_spell_runs_tick", []], ["_flow_runs_tick", []], ["_priv_shooters_tick", []],
		["_cannon_tick", []], ["_rot_pending_tick", []], ["_resolve_hits", []],
	]
	for c in cands:
		if not arena.has_method(c[0]):
			continue
		var t := Time.get_ticks_usec()
		for i in N:
			arena.callv(c[0], c[1])
		print("%s=%.2fms" % [c[0], (Time.get_ticks_usec() - t) / float(N) / 1000.0])
	get_tree().quit(0)
