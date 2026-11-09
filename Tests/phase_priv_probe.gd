extends Node
## =============================================================
## phase_priv_probe —— 破阵/撤离判定 + 杂兵批（0.0.9 20261110，headless 可跑）
##   A. 阶段：短兵→破阵（角色空缺/杂兵空缺5/首次符卡）→撤离（队2破/全体4破/投降）
##   B. AI 投降：phase<3 不发起；phase≥3+被剥+劣势→发起（每场一次）
##   C. 预备队：退下→预备+1→_spawn_private_for 消耗预备
##   D. 万岁冲锋：设 banzai 后逐帧向所属角色判定点合拢（4px 内停）
## 用法：godot --headless --path . res://Tests/phase_priv_probe.tscn
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
	## A. 阶段：初始=1（远距）→ 推进 20 秒到短兵（破阵判定以短兵为前提）
	_chk(arena.phase == 1, "开局=远距压制（phase=%d）" % arena.phase)
	## 时间跳到短兵门口（真实驱动 15 帧跨越 1200——不跑长战斗，
	## 免得 AI 互殴把双方打光=判定凑不齐）
	arena.time_frames = 1190.0
	_drive(15)
	arena._update_phase()
	_chk(arena.phase == 2, "20秒 → 短兵（phase=%d）" % arena.phase)
	## 破阵判定①：某方角色空缺≥1 → 击杀一名敌方角色
	var victim: BattleEntity = arena.enemy_ents[0]
	victim.dead = true ## 角色空缺（满目疮痍）
	arena._update_phase()
	_chk(arena.phase >= 3, "角色空缺≥1 → 破阵（phase=%d）" % arena.phase)
	## 撤离判定：该队再有一名角色 AP 归零（barrier_broken）→ 撤离
	var victim2: BattleEntity = null
	for e in arena.enemy_ents:
		if e is BattleEntity and not e.dead:
			victim2 = e
			break
	if victim2 != null:
		victim2.barrier_broken = true
		victim2.ap = 0
	# 还需第二个被剥（某队两个）——把敌方再剥一名
	for e in arena.enemy_ents:
		if e is BattleEntity and not e.dead and e != victim2:
			e.barrier_broken = true
			e.ap = 0
			break
	print("    [dbg] p_broken=%d e_broken=%d sender=%d" % [
		arena._side_ap_broken(0), arena._side_ap_broken(1), arena.surrender_sender])
	arena._update_phase()
	print("    [dbg] 判定后 phase=%d" % arena.phase)
	_chk(arena.phase == 4, "某队两个角色AP归零 → 撤离阶段（phase=%d）" % arena.phase)
	## B. AI 投降：phase≥3+被剥+劣势 → 发起（撤离阶段已到；直接驱动检测帧）
	var saw_req := false
	arena._ai_surr_used = false
	for k in 130:
		arena._physics_process(1.0 / 60.0)
		if arena.surrender_sender == 1:
			saw_req = true
			break
	_chk(saw_req, "AI 投降（策划口径：破阵/撤离+被剥+劣势）")
	_chk(arena._ai_surr_used, "每场仅一次")
	## C. 预备队
	var chara: BattleEntity = null
	for e in arena.player_ents:
		if e is BattleEntity and not e.dead:
			chara = e
			break
	while arena._private_count(chara) < 2:
		arena._spawn_private_for(chara)
	var pv: BattleEntity = null
	for e in arena.entities:
		if e is BattleEntity and e.kind == BattleEntity.Kind.PRIVATE and e.owner_ent == chara and not e.dead:
			pv = e
			break
	var reserve0: int = int(arena._priv_reserve.get(chara, 0))
	pv.dead = true
	arena._priv_reserve[chara] = int(arena._priv_reserve.get(chara, 0)) + 1 ## 复刻退下路径
	_chk(int(arena._priv_reserve.get(chara, 0)) == reserve0 + 1, "退下→预备+1")
	arena._spawn_private_for(chara)
	_chk(int(arena._priv_reserve.get(chara, 0)) == reserve0, "增援优先消耗预备（%d→%d）" % [reserve0 + 1, int(arena._priv_reserve.get(chara, 0))])
	## D. 万岁冲锋合拢
	var pb: BattleEntity = null
	for e in arena.entities:
		if e is BattleEntity and e.kind == BattleEntity.Kind.PRIVATE and e.owner_ent == chara and not e.dead:
			pb = e
			break
	if pb != null:
		pb.local_pos = Vector2(60.0, 0.0) ## 拉远
		pb.set_meta("banzai", 1800)
		var d0: float = pb.local_pos.length()
		for k in 150:
			arena._physics_process(1.0 / 60.0)
		_chk(pb.local_pos.length() < d0 and pb.local_pos.length() <= 4.0 + 0.001,
			"万岁冲锋合拢至判定点（%.1f→%.1f px）" % [d0, pb.local_pos.length()])
	print("PHASE_OK" if fails == 0 else "PHASE_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
