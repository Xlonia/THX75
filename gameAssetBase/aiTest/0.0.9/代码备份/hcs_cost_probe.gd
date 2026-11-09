extends Node
## =============================================================
## hcs_cost_probe —— Hcs/Hct（审计 B2）现役成本实测（headless 可跑）
##   真实默认队铺场到 f=600/900 → 对全体非攻击态势实体逐个计时
##   _compute_hcs_hct（各 20 次取中位）；按现役调度（每拍 10Hz、实体交错 %2）
##   折算每拍与每帧摊平成本。另拆分"弹幕预筛扫描"与"49 点内循环"占比。
## 用法：godot --headless --path . res://Tests/hcs_cost_probe.tscn
## =============================================================
var arena: Node2D
var step := 0

func _ready() -> void:
	GameGlobals.arena_mode = "versus"
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
	step += 1
	arena._physics_process(1.0 / 60.0)
	if arena._loading:
		return
	if arena.time_frames == 600 or arena.time_frames == 900:
		_measure()
	if arena.time_frames >= 900:
		print("HCS_EQ %d/%d 不等" % [eq_bad, eq_tot])
		print("HCS_OK" if eq_bad == 0 else "HCS_DIFF")
		get_tree().quit(0 if eq_bad == 0 else 1)

var eq_bad := 0
var eq_tot := 0

func _measure() -> void:
	## 【等价验证】同实体同帧：C++ 快路径 vs GD 原路径 98 点逐项比对
	for e in arena.entities:
		if not (e is BattleEntity) or e.dead or e.kind == BattleEntity.Kind.PRIVATE:
			continue
		arena.hcs_cpp_enabled = true
		arena._compute_hcs_hct(e)
		var a_hcs: PackedFloat32Array = e.hcs_pts.duplicate()
		var a_hct: PackedFloat32Array = e.hct_pts.duplicate()
		arena.hcs_cpp_enabled = false
		arena._compute_hcs_hct(e)
		for k in 49:
			eq_tot += 2
			if absf(a_hcs[k] - e.hcs_pts[k]) > 0.001:
				eq_bad += 1
				if eq_bad <= 6:
					print("  [不等] %s hcs[%d] C++=%.1f GD=%.1f" % [e.chara_name(), k, a_hcs[k], e.hcs_pts[k]])
			if absf(a_hct[k] - e.hct_pts[k]) > 0.001:
				eq_bad += 1
				if eq_bad <= 6:
					print("  [不等] %s hct[%d] C++=%.1f GD=%.1f" % [e.chara_name(), k, a_hct[k], e.hct_pts[k]])
		arena.hcs_cpp_enabled = true
	var per_ent: Array = []
	var tot := 0.0
	var n := 0
	for e in arena.entities:
		if not (e is BattleEntity) or e.dead or e.kind == BattleEntity.Kind.PRIVATE:
			continue
		var ts: Array = []
		for k in 20:
			var t0 := Time.get_ticks_usec()
			arena._compute_hcs_hct(e)
			ts.append(Time.get_ticks_usec() - t0)
		ts.sort()
		var med: float = float(ts[10])
		per_ent.append(med)
		tot += med
		n += 1
	## 现役调度：每拍（10Hz）每侧实体 %2 交错→每拍约算一半实体
	var per_tick := tot * 0.5
	print("[hcs f=%d] 弹=%d 角色=%d 单实体中位=%.0fµs 全体=%.0fµs | 每拍(交错半数)≈%.2fms 每帧摊平≈%.3fms" % [
		arena.time_frames, arena.bullets.size(), n, tot / maxf(1.0, float(n)), tot,
		per_tick / 1000.0, per_tick / 1000.0 / 6.0])
