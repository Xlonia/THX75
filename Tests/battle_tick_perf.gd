extends Node
## battle_tick_perf —— 战斗 tick 性能复测（分频批 20261028 简洁版）
## 【20261105·探针口径修正】默认改测真实默认队（1031f：作者真实场景=默认5v5；
## 此前恒开 stress_override=全事件 repeat+2/range×2 满仓高火力，读数与作者
## 实测不可比——探针偏差教训 1031c）。要复现历史满仓口径，把 STRESS 改 true。
const STRESS := false
const DISABLE_GPU := false
const RUN_FRAMES := 2400
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
	## 【m79 GPU A/B】DISABLE_GPU=true=强制 DDM/热力图 CPU 降级（真窗口对比
	## fps——恢复=GPU 管线是 1400 弹崩溃的凶手）
	if DISABLE_GPU:
		arena.gpu_ok = false
		for h in arena.ht_side:
			if h != null:
				h.ok = false
		for h2 in arena.hv_side:
			if h2 != null:
				h2.ok = false
		## 【m83 审计修复③】hd_side 字段已不存在（原行报错=A/B 半途中断）
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
func _process(_d: float) -> void:
	if arena == null:
		return
	_step += 1
	## 【m83 审计修复③】物理双跑撤除——arena._process 内部经 _phys_acc 已驱动
	## _physics_process（渲染帧驱动模式），手动再调=每帧双倍物理（口径悲观）
	var t0 := Time.get_ticks_usec()
	arena._process(1.0 / 60.0)
	var t2 := Time.get_ticks_usec()
	_proc.append(float(t2 - t0) / 1000.0)
	_phys.append(0.0) ## 物理已并入 proc 口径（分段另见 TELEM）
	if _step % 300 == 0:
		## 【m79 渲染侧拆解（真窗口跑）】各绘制层最近耗时 + 屏幕中心弹密度
		var el := arena.find_child("EntityLayer", true, false)
		var bl := arena.find_child("BulletLayer", true, false)
		var mm := arena.find_child("BulletMM", true, false)
		var cen: Dictionary = arena.bullet_census()
		print("TELEM[%d] 弹=%d (可见=%d 场外=%d oob=%d) 载体=%d 符卡=%d fps=%d | 绘制µs 实体=%d MM=%d (均值MM=%.0f)" % [
			_step, arena.bullets.size(), int(cen.get("visible", -1)), int(cen.get("offfield", -1)), int(cen.get("oob", -1)),
			arena._flow_runs.size(), arena._spell_runs.size(), Engine.get_frames_per_second(),
			el.last_draw_us if el else -1,
			mm.last_draw_us if mm else -1, mm.draw_avg_us if mm else -1.0])
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
