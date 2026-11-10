extends Node
## =============================================================
## batch3_probe —— 铃仙轰炸引用/召唤修复/投降门/撤离活动（0.0.9 20261111）
##   A. 铃仙：Y → _reisen_queue 25 项 → 80 帧内全部释放（引用 boom_rabbit0 存在）
##   B. 召唤：_do_summon 后 fire_control 指向新角色（不开火根因）+ 原角色入 _summoned_out
##   C. 投降门：短兵（未重返）请求被拒；破阵后允许
##   D. 撤离活动：retreating 实体向边界点移动；被弹→直接撤离（不掉血）
## 用法：godot --headless --path . res://Tests/batch3_probe.tscn
## =============================================================
var arena: Node2D
var fails := 0

func _chk(ok: bool, msg: String) -> void:
	if ok:
		print("  PASS " + msg)
	else:
		fails += 1
		print("  FAIL " + msg)

func _drive(frames: int) -> void:
	for k in frames:
		arena._physics_process(1.0 / 60.0)

func _ready() -> void:
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	var g := 0
	while arena._loading and g < 2000:
		arena._physics_process(1.0 / 60.0)
		g += 1
	_drive(30)
	## A. 铃仙轰炸
	var caster: BattleEntity = null
	for e in arena.player_ents:
		if e is BattleEntity and not e.dead:
			caster = e
			break
	arena._reisen_bombard(caster)
	_chk(arena._reisen_queue.size() == 25, "轰炸队列 25 项（实际 %d）" % arena._reisen_queue.size())
	var b0: int = arena.bullets.size()
	_drive(85)
	_chk(arena._reisen_queue.is_empty(), "3 帧轮番全部释放")
	_chk(arena.bullets.size() > b0, "boom_rabbit0 已入场（%d→%d）" % [b0, arena.bullets.size()])
	## B. 召唤：火控接替 + 原角色入候补
	var sel: BattleEntity = caster
	var old_name: String = sel.chara_name()
	var fc_old := 0
	for fc in arena.fire_controls:
		if fc.entity == sel:
			fc_old += 1
	_chk(fc_old > 0, "被接替角色有火控（%d）" % fc_old)
	var row := CharaDB.get_by_name("Remilna")
	_chk(not row.is_empty(), "Hnaszami=Remilna 在角色表")
	arena._do_summon(sel, row)
	var ne: BattleEntity = arena.player_ents[arena.player_ents.find(sel)] if arena.player_ents.has(sel) else null
	## player_ents 已替换——找新角色
	ne = null
	for e in arena.player_ents:
		if e is BattleEntity and e.chara_name() == "Remilna":
			ne = e
			break
	_chk(ne != null, "Remilna 已接替上场")
	var fc_new := 0
	for fc in arena.fire_controls:
		if fc.entity == ne:
			fc_new += 1
	_chk(fc_new > 0, "火控已接替→新角色可开火（%d）" % fc_new)
	_chk(arena._summoned_out.has(old_name), "原角色 %s 入候补区" % old_name)
	## E. 召唤后开火实证：驱动 300 帧，按 source 分桶统计新弹
	var ne2: BattleEntity = null
	for e in arena.player_ents:
		if e is BattleEntity and e.chara_name() == "Remilna":
			ne2 = e
			break
	if ne2 != null:
		## 诊断：新角色火控内部状态
		for fc in arena.fire_controls:
			if fc.entity == ne2:
				var evn: int = 0
				for p2 in fc.weapon_points:
					evn += p2.events.size()
				print("    [诊断] fc.entity=%s bound_main=%d 点数=%d 点事件合计=%d mode=%s engaged=%s" % [
					fc.entity.chara_name(), fc._bound_main.size(), fc.weapon_points.size(), evn, fc.mode, str(fc._engaged)])
		var fired_n := [0]
		for fc in arena.fire_controls:
			if fc.entity == ne2:
				fc.fired.connect(func(_p, ev, _r):
					fired_n[0] += 1
					if fired_n[0] <= 3:
						print("    [fired] emit #%d ev=%s" % [fired_n[0], ev.event_name]))
		var cnt_old := 0
		var cnt_new := 0
		var bbase: int = arena.bullets.size()
		arena._expired_count = 0
		ne.immune_frames = 99999 ## 观测期免弹（真实战斗会击杀=污染观测）
		for k in 300:
			ne.immune_frames = 99999
			arena._physics_process(1.0 / 60.0)
			if k % 100 == 99:
				for fc in arena.fire_controls:
					if fc.entity == ne2 and fc.weapon_points.size() > 0:
						var p9 = fc.weapon_points[0]
						print("    [tick诊断] k=%d locked=%s timer=%.1f hp=%s dead=%s" % [
							k + 1, str(p9.locked), p9.timer, str(fc.entity.hp), str(fc.entity.dead)])
		for b in arena.bullets:
			if b.source == ne2:
				cnt_new += 1
		print("    [开火实证] 新角色(Remilna)名下弹=%d" % cnt_new)
		_chk(cnt_new > 0, "召唤角色用自己的火控出弹")

	## C. 投降门：短兵（未重返）拒绝
	arena.time_frames = 1190.0
	_drive(15)
	arena._update_phase()
	arena.surrender_sender = -1
	var n0: int = arena._toasts.size()
	arena._physics_process(1.0 / 60.0) ## 触发不了——直接模拟按键分支太重，改查门条件
	var gate_open: bool = arena.phase >= 3 or (arena.phase == 2 and arena._phase2_reentered)
	_chk(not gate_open, "短兵（未重返）投降门=关（phase=%d）" % arena.phase)
	## 破阵后门开
	var victim: BattleEntity = arena.enemy_ents[0]
	victim.dead = true
	arena._update_phase()
	gate_open = arena.phase >= 3 or (arena.phase == 2 and arena._phase2_reentered)
	_chk(gate_open, "破阵后投降门=开（phase=%d）" % arena.phase)
	## D. 撤离活动：强制 phase=4 + retreating 实体
	arena.phase = 4
	var ret: BattleEntity = null
	for e in arena.player_ents:
		if e is BattleEntity and not e.dead:
			ret = e
			break
	ret.position = Vector2(200.0, 200.0)
	ret.set_meta("retreating", true)
	ret.set_meta("retreat_target", arena._nearest_edge_point(ret.position))
	var tgt: Vector2 = ret.get_meta("retreat_target")
	_chk(tgt.x <= 8.001 or tgt.x >= 391.999 or tgt.y <= 8.001 or tgt.y >= 391.999,
		"撤离目标=最近边界点（%s）" % str(tgt))
	_drive(400) ## 足够抵达
	_chk(ret.dead and bool(ret.get_meta("retreated", false)), "抵达边界→撤离成功")
	## 撤离途中被弹=直接撤离
	var ret2: BattleEntity = null
	for e in arena.player_ents:
		if e is BattleEntity and not e.dead:
			ret2 = e
			break
	if ret2 != null:
		ret2.position = Vector2(200.0, 200.0)
		ret2.set_meta("retreating", true)
		ret2.set_meta("retreat_target", arena._nearest_edge_point(ret2.position))
		var hp0: int = ret2.hp[1]
		var bl := Bullet.new()
		bl.setup(GameGlobals.get_event("demo_aimed"), ret2.position, 1, arena.enemy_ents[1] if arena.enemy_ents.size() > 1 else arena.enemy_leader, arena)
		arena.bullets.append(bl)
		## 哈希重建（_resolve_hits 查询依赖当帧哈希——直调必须自建）
		arena.bullet_hash.clear()
		if arena.bullet_hash_cpp != null:
			arena.bullet_hash_cpp.begin_frame()
			arena._hash_objs.clear()
		for bi in arena.bullets.size():
			var bb: Bullet = arena.bullets[bi]
			if bb.hidden_now:
				continue
			arena.bullet_hash.insert(bb)
			if arena.bullet_hash_cpp != null:
				arena.bullet_hash_cpp.insert(bb.pos.x, bb.pos.y, bb.hit_radius(), bi, bb.source_side, bb.ev.is_phy)
				arena._hash_objs.append(bb)
		arena.time_frames += 1 ## 奇数帧结算
		arena._resolve_hits()
		_chk(ret2.dead and bool(ret2.get_meta("retreated", false)) and ret2.hp[1] == hp0,
			"撤离途中被弹→直接撤离（不掉血）")
	print("B3_OK" if fails == 0 else "B3_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
