extends Node
## =============================================================
## trace_clear_probe —— 消弹区"诈尸"谱系追踪（作者令 20261109：追踪来源）
##   ①真实默认队铺场 6 秒 → 玩家 _apply_release("s"，200px)
##   ②快照：监测半径(216px)内敌弹 instance_id / 半径内火炮 origin0 /
##     hidden 弹数（豁免幸存者）/ 火炮与 pend 总数
##   ③此后 8 秒逐帧扫描区内敌弹：
##     - id∈快照 → 幸存者（处死遗漏实证：hidden 豁免/杀漏）
##     - id∉快照 → 新生弹 → spawn_src 谱系分类（fire/fan/pend/cannon/rp_child）
##   ④对照组：同场景不消弹，同窗口同口径扫描——区分"正常敌方火力进入区"
##   纯 CPU 侧（headless 可跑）：谱系标签 fire/fan/pend/cannon/rp_child
##   由 _spawn_bullet src_tag 参数落账（20261109 插桩）
## =============================================================
const R := 216.0          ## 监测半径 = 消弹 200 + 8
const SETTLE := 360       ## 铺场 6 秒
const WATCH := 480        ## 消弹后观察 8 秒

var arena: Node2D
var run := 0              ## 0=消弹轮 1=对照轮
var step := 0
var released := false
var release_pos := Vector2.ZERO
var snap_ids := {}
var snap_cannons_in := 0
var snap_hidden := 0
var snap_total := 0
var new_by_src := {}
var new_samples := []
var survivor_n := 0
var survivor_logs := 0
var reports: Array = []

func _ready() -> void:
	_start_run()

func _start_run() -> void:
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	step = 0
	released = false
	snap_ids = {}
	snap_cannons_in = 0
	snap_hidden = 0
	snap_total = 0
	new_by_src = {}
	new_samples = []
	survivor_n = 0
	survivor_logs = 0

func _process(_d: float) -> void:
	if arena == null:
		return
	step += 1
	if step == SETTLE:
		## 与 battle_tick_perf 同款（pause 门挡加热链路）
		if arena.pause_panel != null:
			arena.pause_panel.visible = false
		if run == 0:
			var p: BattleEntity = arena.player_leader
			if p == null:
				print("[trace] 无领队——中止")
				get_tree().quit(1)
				return
			release_pos = p.position
			_snap_zone(p)
			arena._apply_release(p, "s")
			released = true
			print("[trace] ===消弹轮=== 释放 at %s 区内敌弹=%d hidden(豁免幸存)=%d 区内火炮=%d 全场火炮=%d pend=%d" % [
				str(release_pos), snap_total, snap_hidden, snap_cannons_in,
				arena._cannons.size(), arena._rot_pend.size()])
		else:
			release_pos = arena.player_leader.position if arena.player_leader != null else Vector2.ZERO
			released = true
			print("[trace] ===对照轮=== 监测点 %s（不消弹）" % str(release_pos))
		return
	if not released:
		return
	if step <= SETTLE + WATCH:
		_scan_zone()
		return
	_report()
	if run == 0:
		run = 1
		arena.queue_free()
		await get_tree().process_frame
		_start_run()
	else:
		get_tree().quit(0)

func _enemy_side() -> int:
	var p: BattleEntity = arena.player_leader
	return 1 - p.side if p != null else 1

func _snap_zone(p: BattleEntity) -> void:
	var es := _enemy_side()
	for b in arena.bullets:
		if b.source_side != es:
			continue
		if b.pos.distance_to(p.position) > R:
			continue
		snap_total += 1
		if b.hidden_now:
			snap_hidden += 1 ## 【处死豁免】hidden 弹消弹跳过=必然幸存
		snap_ids[b.get_instance_id()] = true
	for c in arena._cannons:
		var org: Vector2 = c.get("origin0", Vector2.INF)
		var src_c = c.get("src")
		if org != Vector2.INF and src_c != null and (src_c as BattleEntity).side == es \
				and org.distance_to(p.position) <= R:
			snap_cannons_in += 1

func _scan_zone() -> void:
	var es := _enemy_side()
	for b in arena.bullets:
		if b.source_side != es:
			continue
		var dist: float = b.pos.distance_to(release_pos)
		if dist > R:
			continue
		var id: int = b.get_instance_id()
		if snap_ids.has(id):
			survivor_n += 1
			if survivor_logs < 8:
				survivor_logs += 1
				print("  [幸存者] f=%d %s hidden=%s spawn_src=%s depth=%d dist=%.0f t=%.1f" % [
					step, b.ev.event_name, str(b.hidden_now), b.spawn_src, b.depth, dist, b.t])
		else:
			new_by_src[b.spawn_src] = int(new_by_src.get(b.spawn_src, 0)) + 1
			if new_samples.size() < 12:
				new_samples.append("f%d %s src=%s depth=%d rep=%s dist=%.0f" % [
					step, b.ev.event_name, b.spawn_src, b.depth, str(b.repeat_enabled), dist])

func _report() -> void:
	var head := "=== 第%d轮(%s) 谱系报告 ===" % [run + 1, "消弹" if run == 0 else "对照"]
	var l2 := "  区内新生弹按出生路径：%s" % str(new_by_src)
	var l3 := "  幸存者出现次数=%d（快照 id 复现）" % survivor_n
	print(head)
	print(l2)
	print(l3)
	for s in new_samples:
		print("    新弹样本: " + s)
	reports.append(head + "\n" + l2 + "\n" + l3)
