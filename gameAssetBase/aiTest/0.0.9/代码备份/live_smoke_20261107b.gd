extends Node
## live_smoke —— 真渲染长跑分档+分时量化（physics vs process 手动驱动计时）
const RUN := 7200 ## 120 秒（含后期低弹段）
var arena: Node2D
var _step := 0
var _phys_ms := 0.0
var _proc_ms := 0.0
var _phys_mx := 0.0
var _proc_mx := 0.0
var _n := 0
var _last := 0
var _win: Array = []
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "contour=off":
			pass
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.contour.enabled = true
	arena._heat_view = 4
	arena.set_physics_process(false) ## 手动驱动（分段计时）
	arena._dbg_split = true
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
func _process(_d: float) -> void:
	var t0: int = Time.get_ticks_usec()
	arena._physics_process(1.0 / 60.0)
	var t1: int = Time.get_ticks_usec()
	arena._process(1.0 / 60.0)
	var t2: int = Time.get_ticks_usec()
	_phys_ms += float(t1 - t0) / 1000.0
	_proc_ms += float(t2 - t1) / 1000.0
	_phys_mx = maxf(_phys_mx, float(t1 - t0) / 1000.0)
	_proc_mx = maxf(_proc_mx, float(t2 - t1) / 1000.0)
	_n += 1
	_step += 1
	var now: int = Time.get_ticks_usec()
	if _last > 0:
		_win.append(float(now - _last) / 1000.0)
	_last = now
	if _step == 40 * 60: ## 模拟后期：双方各杀 2 队员（火力衰减→弹量降段）
		var k0 := 0
		var k1 := 0
		for e in arena.entities:
			if e is BattleEntity and not (e as BattleEntity).dead:
				if (e as BattleEntity).side == 0 and k0 < 2 and (e as BattleEntity).kind != BattleEntity.Kind.PRIVATE:
					(e as BattleEntity).hp = [0, 0, 0]
					(e as BattleEntity).dead = true
					k0 += 1
				elif (e as BattleEntity).side == 1 and k1 < 2 and (e as BattleEntity).kind != BattleEntity.Kind.PRIVATE:
					(e as BattleEntity).hp = [0, 0, 0]
					(e as BattleEntity).dead = true
					k1 += 1
		print("[sim] 后期模拟：杀 2+2 角色")
	if _step % 60 == 0:
		var avg := 0.0
		var mx := 0.0
		for v in _win:
			avg += v
			mx = maxf(mx, v)
		avg /= maxf(1.0, float(_win.size()))
		print("[sec %3d] 弹=%4d 帧avg=%5.1f max=%5.1f | phys=%5.1f(峰值%5.1f) proc=%5.1f(峰值%5.1f) ms" % [
			_step / 60, arena.bullets.size(), avg, mx,
			_phys_ms / float(_n), _phys_mx, _proc_ms / float(_n), _proc_mx])
		var da: Array = arena._dbg_acc
		print("    └ AI=%.2f 实体=%.2f 态势=%.2f 火控=%.2f 弹更=%.2f 被弹=%.2f ms" % [
			da[0]/float(_n)/1000.0, da[1]/float(_n)/1000.0, da[5]/float(_n)/1000.0,
			da[2]/float(_n)/1000.0, da[3]/float(_n)/1000.0, da[4]/float(_n)/1000.0])
		arena._dbg_acc = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		_phys_ms = 0.0; _proc_ms = 0.0; _phys_mx = 0.0; _proc_mx = 0.0; _n = 0
		_win.clear()
	if _step >= RUN:
		print("LIVE_DONE")
		get_tree().quit(0)
