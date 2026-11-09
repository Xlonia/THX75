extends Node
## live_smoke —— 真渲染长跑分档+分时量化（physics vs process 手动驱动计时）
const RUN := 4800 ## 80 秒
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
		if a.begins_with("sample="):
			GameGlobals.bullet_sample_n = int(a.substr(7)) ## 采样平滑 A/B
		elif a == "legacy=1":
			GameGlobals.bullet_legacy_physics = true ## 物理驱动 A/B
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
	if _step == 30 * 60: ## 模拟后期：只杀敌方 2 员（战局继续、火力衰减→低弹长期段）
		var k1 := 0
		for e in arena.entities:
			if e is BattleEntity and not (e as BattleEntity).dead:
				if (e as BattleEntity).side == 1 and k1 < 2 and (e as BattleEntity).kind != BattleEntity.Kind.PRIVATE:
					(e as BattleEntity).hp = [0, 0, 0]
					(e as BattleEntity).dead = true
					k1 += 1
		print("[sim] 后期模拟：杀敌方 2 员（战局继续）")
	if _step % 60 == 0:
		var avg := 0.0
		var mx := 0.0
		for v in _win:
			avg += v
			mx = maxf(mx, v)
		avg /= maxf(1.0, float(_win.size()))
		var cs: Dictionary = arena.bullet_census()
		print("[sec %3d] 弹=%4d(显%d 隐%d 场外%d) 池=%d pend=%d 帧avg=%5.1f | phys=%5.1f proc=%5.1f" % [
			_step / 60, cs["total"], cs["visible"], cs["hidden"], cs["offfield"],
			cs["pool"], cs["rot_pend"], avg, _phys_ms / float(_n), _proc_ms / float(_n)])
		if int(cs["offfield"]) > 50:
			print("    场外oob分组=%s" % str(cs["offfield_by_oob"]))
			var evd: Dictionary = cs["offfield_by_ev"]
			var top := []
			for k in evd:
				top.append([int(evd[k]), k])
			top.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
			for t in top.slice(0, 3):
				print("    场外TOP %s" % str(t))
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
