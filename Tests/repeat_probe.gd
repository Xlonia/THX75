extends Node
## =============================================================
## repeat_probe —— 重复（非旋转）故障探针【0.0.9 作者令 20261105】
##   试炼场预览口径：preview 模式 + 自动发射器每 0.5s 发射指定事件，
##   逐帧追踪目标事件每一颗弹（出生/depth/载体/死亡/死因），按
##   "每次发射 → 期望 repeat 节拍 → 实际重放扇"对账，输出丢失报告。
##   用法（headless）：
##     godot --headless --path . res://Tests/repeat_probe.tscn -- event=sonic_wave_like0
##     godot --headless --path . res://Tests/repeat_probe.tscn -- event=spell_sanae frames=900
##   可变探针参数：event= frames= seed= emit=（秒，发射间隔）
##   【方法论】池复用 id 假阳性防御（1104b 教训）：t 回退=新生，重登记。
## =============================================================
const DEFAULT_EVENT := "sonic_wave_like0"
const DEFAULT_FRAMES := 900

var arena: Node2D
var event_name := DEFAULT_EVENT
var run_frames := DEFAULT_FRAMES
var _step := 0

var _born: Dictionary = {}       # id -> {frame, depth, carrier, t, t_event}
var _died: Dictionary = {}       # id -> {frame, born, cause}
var _last_snap: Dictionary = {}  # id -> {pos, alive_f, range, t}
var _carriers_log: Array = []    ## 【id 复用防御】登记时增量记录（终局读 _born 会被复用覆盖）
var _replays_log: Array = []

func _ready() -> void:
	seed(20261105)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("event="):
			event_name = a.substr(6)
		elif a.begins_with("frames="):
			run_frames = int(a.substr(7))
	GameGlobals.arena_mode = "preview"
	GameGlobals.preview_event_name = event_name
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false

var _pool_ids: Dictionary = {}
func _process(_d: float) -> void:
	if arena == null:
		return
	_pool_ids.clear()
	for pb0 in arena._bullet_pool:
		_pool_ids[pb0.get_instance_id()] = true
	arena._physics_process(1.0 / 60.0)
	for pb in arena._bullet_pool: ## 【池尸检】id 差集——同帧取出-死亡-回填也可见
		if _pool_ids.has(pb.get_instance_id()):
			continue
		if pb.ev != null and pb.ev.event_name == event_name and pb._alive_frames < 10.0:
			print("  [瞬死] f=%d pos=(%.1f,%.1f) 存活=%.1f t=%.1f te=%.0f depth=%d tx=%s ty=%s org=(%.1f,%.1f) rng=%.0f car=%s" % [
				_step, pb.pos.x, pb.pos.y, pb._alive_frames, pb.t, pb.t_event, pb.depth,
				str(pb._ctx.get("target_x", "—")), str(pb._ctx.get("target_y", "—")),
				pb.origin.x, pb.origin.y, pb.range_now, pb.repeat_enabled])
	_keep_preview_alive() ## 预览玩家会被弹幕打死→finished→发射停摆（假丢失）
	if _step % 30 == 0: ## 【可见性普查】逻辑层弹量 vs 会被渲染的弹量（渲染门=hidden/场内）
		var tot := 0
		var vis := 0
		var hidd := 0
		var ofield := 0
		var carries := 0
		for cb in arena.bullets:
			if cb.ev == null or cb.ev.event_name != event_name:
				continue
			tot += 1
			if cb.repeat_enabled:
				carries += 1
			if cb.hidden_now:
				hidd += 1
			elif not (cb.pos.x > -24.0 and cb.pos.x < 424.0 and cb.pos.y > -24.0 and cb.pos.y < 424.0):
				ofield += 1
			else:
				vis += 1
		var emp: Vector2 = arena.emitter_ent.position if arena.emitter_ent != null else Vector2(-1, -1)
		print("[普查 f=%d] 目标弹=%d 可渲染=%d 场外=%d 载体=%d 池=%d 发射器=(%.0f,%.0f) 玩家=(%.0f,%.0f)" % [
			_step, tot, vis, ofield, carries, arena._bullet_pool.size(), emp.x, emp.y,
			arena.player_leader.position.x, arena.player_leader.position.y])
	_step += 1
	_scan()
	if _step >= run_frames:
		_report()
		get_tree().quit(0)

## 【假丢失防御】预览玩家持续满血满结界
func _keep_preview_alive() -> void:
	var p = arena.player_leader
	if p != null and is_instance_valid(p):
		p.dead = false
		p.immune_frames = 2
		if p.hp is Array and (p.hp.size() < 3 or int(p.hp[0]) < 9000):
			p.hp = [9999, 9999, 9999]
		if int(p.ap) < 9000:
			p.ap = 9999
	arena.finished = false

func _scan() -> void:
	var seen: Dictionary = {}
	for b in arena.bullets:
		if b.ev == null or b.ev.event_name != event_name:
			continue
		var bid: int = b.get_instance_id()
		seen[bid] = true
		## 【池复用防御】同 id 复用（t 回退）=全新弹——重登记并撤销旧死亡记录
		if not _born.has(bid) or (_died.has(bid) and b.t < 1.5):
			var reg := {"frame": _step, "depth": b.depth,
				"carrier": b.repeat_enabled, "t_event": b.t_event, "t": b.t}
			_born[bid] = reg
			_died.erase(bid)
			if reg["carrier"]:
				_carriers_log.append(reg)
			elif int(reg["depth"]) >= 1:
				_replays_log.append(reg)
		else:
			_born[bid]["t"] = b.t
		_last_snap[bid] = {"pos": Vector2(b.pos), "alive_f": b._alive_frames,
			"range": b.range_now, "t": b.t}
	for bid in _born.keys():
		if seen.has(bid) or _died.has(bid):
			continue
		var info: Dictionary = _born[bid]
		var snap: Dictionary = _last_snap.get(bid, {})
		var cause := "?"
		if snap.has("alive_f"):
			var af: float = float(snap["alive_f"])
			var rg: float = float(snap["range"])
			var ps: Vector2 = snap["pos"]
			if af >= rg:
				cause = "航程"
			elif not is_finite(ps.x) or not is_finite(ps.y):
				cause = "NaN"
			elif ps.x < 0.0 or ps.x > 400.0 or ps.y < 0.0 or ps.y > 400.0:
				cause = "出界(%.0f,%.0f)@存活%.0f" % [ps.x, ps.y, af]
			else:
				cause = "场内(%.0f,%.0f)@存活%.0f/航程%.0f" % [ps.x, ps.y, af, rg]
		_died[bid] = {"frame": _step, "born": info, "cause": cause}
		if af_young(cause):
			print("  [早亡] f=%d 生f=%d depth=%d 载体=%s 因=%s" % [
				_step, int(info["frame"]), int(info["depth"]), bool(info["carrier"]), cause])

func af_young(cause: String) -> bool:
	return cause != "航程" and cause != "?"

func _report() -> void:
	var ev = arena._find_event(event_name)
	if ev == null:
		push_error("事件未找到：%s" % event_name)
		return
	var carriers: Array = _carriers_log
	var replays: Array = _replays_log
	carriers.sort_custom(func(a, b): return a["frame"] < b["frame"])
	replays.sort_custom(func(a, b): return a["frame"] < b["frame"])
	var interval: int = maxi(1, int(ev.repeat_time))
	var freq: int = int(ev.repeat_freq)
	print("========================================")
	print("REPEAT_PROBE 事件=%s repeat_time=%s repeat_freq=%s range=%s rotate_div=%s delay=%s" % [
		event_name, ev.repeat_time, ev.repeat_freq, ev.range_frames,
		ev.rotate_div, ev.rotate_delay])
	print("发射次数(载体)=%d  重放扇成员(depth≥1)=%d  总追踪弹=%d" % [
		carriers.size(), replays.size(), _born.size()])
	var lost_total := 0
	var tail_artifact := 0 ## 末尾发射的节拍落在 run_frames 之外=测量伪丢失
	for ci in carriers.size():
		var cinfo: Dictionary = carriers[ci]
		var f0: int = int(cinfo["frame"])
		var got := 0
		for n in range(1, freq + 1):
			var due: int = f0 + n * interval
			if due > run_frames - 4:
				tail_artifact += 1
				continue
			var hit := false
			for r in replays:
				var rf: int = int(r["frame"])
				if rf >= due - 2 and rf <= due + 8:
					hit = true
					break
			if hit:
				got += 1
			else:
				print("  [丢拍] 发射#%d f=%d 节拍n=%d due=%d 无重放扇" % [ci, f0, n, due])
		if got < freq and f0 + freq * interval <= run_frames - 4:
			lost_total += freq - got
	print("--------")
	if lost_total == 0 and carriers.size() > 0:
		print("PROBE_OK —— %d 次发射的重放节拍全部命中（尾拍溢出 %d 个不计）" % [carriers.size(), tail_artifact])
	else:
		print("PROBE_LOST —— 共丢失重放节拍 %d 个（%d 次发射；尾拍溢出 %d 个不计）" % [
			lost_total, carriers.size(), tail_artifact])
	print("========================================")
