extends Node
## battle_tick_perf —— 战斗 tick 性能复测（分频批 20261028 简洁版）
const RUN_FRAMES := 900
var arena: Node2D
var _step := 0
var _phys: Array[float] = []
var _proc: Array[float] = []
func _ready() -> void:
	GameGlobals.apply_stress_override(true)
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
func _process(_d: float) -> void:
	if arena == null:
		return
	_step += 1
	var t0 := Time.get_ticks_usec()
	arena._physics_process(1.0 / 60.0)
	var t1 := Time.get_ticks_usec()
	arena._process(1.0 / 60.0)
	var t2 := Time.get_ticks_usec()
	_phys.append(float(t1 - t0) / 1000.0)
	_proc.append(float(t2 - t1) / 1000.0)
	if _step >= 900:
		_phys.sort()
		_proc.sort()
		var pm: float = _phys[_phys.size() / 2]
		var pp: float = _proc[_proc.size() / 2]
		print("PERF 物理 median=%.2fms proc median=%.2fms 弹=%d ents=%d" % [
			pm, pp, arena.bullets.size(), arena.entities.size()])
		GameGlobals.apply_stress_override(false)
		get_tree().quit(0)
