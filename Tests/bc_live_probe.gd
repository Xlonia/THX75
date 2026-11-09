extends Node
## =============================================================
## bc_live_probe —— 基础规避 BC 行为级 A/B（headless 可跑）
##   同种子同场景，A 轮 bc_enabled=true / B 轮 false，各 900 帧：
##   ①被弹总量（每 30 帧 Σ 全角色 HP+AP 缺口——BC 应显著降低）
##   ②平均存活（死亡角色数）
##   ③物理中位耗时（BC 的性能代价）
## 用法：godot --headless --path . res://Tests/bc_live_probe.tscn
## =============================================================
const FRAMES := 900
const SEEDV := 1109

var run := 0
var arena: Node2D
var dmg: Array = [0.0, 0.0]
var dead_max: Array = [0, 0]
var phys: Array = [[], []]
var last_def: Array = [0, 0]

func _ready() -> void:
	_start()

func _start() -> void:
	seed(SEEDV)
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	arena.bc_enabled = (run == 0)
	var g := 0
	while arena._loading and g < 2000:
		arena._physics_process(1.0 / 60.0)
		g += 1
	last_def[run] = _deficit()

func _deficit() -> int:
	## 战损口径：Σ部位 stun（瘫痪秒）+ Σ(3-存活部位数)×50 + 结界破×40 + 死亡×120
	var d := 0
	for e in arena.entities:
		if e is BattleEntity and e.kind != BattleEntity.Kind.PRIVATE:
			for k2 in 3:
				d += int(e.stun_frames[k2]) / 60.0
				if e.hp[k2] <= 0:
					d += 50
			if e.barrier_broken:
				d += 40
			if e.dead:
				d += 120
	return int(d)

func _process(_d: float) -> void:
	if arena == null or not arena.is_inside_tree():
		return
	var t0 := Time.get_ticks_usec()
	arena._physics_process(1.0 / 60.0)
	phys[run].append(float(Time.get_ticks_usec() - t0) / 1000.0)
	if arena.time_frames % 30 == 0:
		var df: int = _deficit()
		dmg[run] += maxf(df - int(last_def[run]), 0)
		last_def[run] = df
		var nd := 0
		for e in arena.entities:
			if e is BattleEntity and e.kind != BattleEntity.Kind.PRIVATE and e.dead:
				nd += 1
		dead_max[run] = maxi(dead_max[run], nd)
	if arena.time_frames >= FRAMES:
		if run == 0:
			run = 1
			var old := arena
			arena = null
			old.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
			_start()
		else:
			var pa: Array = phys[0].duplicate()
			var pb: Array = phys[1].duplicate()
			pa.sort()
			pb.sort()
			print("[BC-LIVE] 被弹缺口累计：开BC=%.0f  关BC=%.0f | 最多死亡角色：开=%d 关=%d | 物理中位：开=%.2fms 关=%.2fms" % [
				dmg[0], dmg[1], dead_max[0], dead_max[1], pa[pa.size() / 2], pb[pb.size() / 2]])
			print("BC_LIVE_OK")
			get_tree().quit(0)
