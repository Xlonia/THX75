extends Node
## battle_tick_perf —— 战斗 tick 性能复测（分频批 20261028 简洁版）
## 【20261105·探针口径修正】默认改测真实默认队（1031f：作者真实场景=默认5v5；
## 此前恒开 stress_override=全事件 repeat+2/range×2 满仓高火力，读数与作者
## 实测不可比——探针偏差教训 1031c）。要复现历史满仓口径，把 STRESS 改 true。
const STRESS := false
const RUN_FRAMES := 900
var arena: Node2D
var _step := 0
var _phys: Array[float] = []
var _proc: Array[float] = []
func _ready() -> void:
	if STRESS:
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
	if _step >= RUN_FRAMES:
		_phys.sort()
		_proc.sort()
		var pm: float = _phys[_phys.size() / 2]
		var pp: float = _proc[_proc.size() / 2]
		print("PERF[%s] 物理 median=%.2fms proc median=%.2fms 弹=%d ents=%d" % [
			"满仓" if STRESS else "真实默认队", pm, pp, arena.bullets.size(), arena.entities.size()])
		var pst: Array = Bullet._path_stat
		var pt := float(pst[0] + pst[1] + pst[2] + pst[3])
		if pt > 0.0:
			print("PATH 占比 frozen=%.0f%% 查表=%.0f%% 闭包=%.0f%% 兜底=%.0f%%（总 %d 步）" % [
				pst[0] / pt * 100.0, pst[1] / pt * 100.0, pst[2] / pt * 100.0, pst[3] / pt * 100.0, int(pt)])
		if STRESS:
			GameGlobals.apply_stress_override(false)
		get_tree().quit(0)
