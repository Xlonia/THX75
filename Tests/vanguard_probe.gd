extends Node
## vanguard_probe —— 角色前锋探针（m100，scheme 24-30；m103 追加 D/E 两节）
## A. 互斥：晚汐不能当前锋
## B. 上场：位置重合+ap25+5 杂兵+player_ents 加入
## C. 结界破损自动离场
## D. 前锋轮盘（Shift+C）：模式标定+候选排除现役/互斥+取消锁
## E. 结界半径 +1 接线（scheme 30：barrier_radius=判定+Defend+1）
func _ready() -> void:
	var arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	for i in 8:
		arena._physics_process(1.0 / 60.0)
	var fails := 0
	var pl = arena.player_leader
	pl.pp = 200
	## A. 互斥
	var you_row = {"Name": "Youshio", "NameZH": "晚汐"}
	var n_v0: int = arena._vanguards.size()
	arena._do_vanguard(pl, you_row)
	if arena._vanguards.size() != n_v0:
		fails += 1
		print("VANGUARD_FAIL: A 互斥未拦截晚汐")
	## B. 正常上场（非互斥角色——用 Rumia 测试行）
	var rumia_row = {"Name": "Rumia", "NameZH": "露米娅"}
	arena._do_vanguard(pl, rumia_row)
	if arena._vanguards.size() != n_v0 + 1:
		fails += 1
		print("VANGUARD_FAIL: B 上场失败")
	else:
		var v = arena._vanguards[arena._vanguards.size() - 1]
		if v.position != pl.position:
			fails += 1
			print("VANGUARD_FAIL: B 位置未重合")
		if int(v.ap) != 25:
			fails += 1
			print("VANGUARD_FAIL: B 结界非 25")
		var privs := 0
		for e in arena.entities:
			if e is BattleEntity and e.kind == BattleEntity.Kind.PRIVATE and e.owner_ent == v:
				privs += 1
		if privs != 5:
			fails += 1
			print("VANGUARD_FAIL: B 自带杂兵非 5（=%d）" % privs)
	## C. 结界破损自动离场
	if arena._vanguards.size() > 0:
		var v2 = arena._vanguards[arena._vanguards.size() - 1]
		v2.ap = 0
		arena._vanguard_tick()
		if arena._vanguards.size() != n_v0 + 1 - 1 + 1 - 1:
			pass
		if arena._vanguards.has(v2) and is_instance_valid(v2) and not v2.dead:
			fails += 1
			print("VANGUARD_FAIL: C 结界破损未离场")
	## D. 前锋轮盘（m103 接线）：模式标定+候选排除现役+互斥三角色+取消锁
	arena._open_vanguard_wheel(pl)
	if not arena._wheel_open or arena._wheel_mode != "vanguard":
		fails += 1
		print("VANGUARD_FAIL: D 轮盘未开或模式错（%s）" % str(arena._wheel_mode))
	else:
		var vg_names: Array = []
		for row in arena._wheel_cands:
			vg_names.append(str(row.get("Name", "")))
		if vg_names.is_empty():
			fails += 1
			print("VANGUARD_FAIL: D 候选为空")
		for ex in arena.VANGUARD_EXCLUDE:
			if vg_names.has(ex):
				fails += 1
				print("VANGUARD_FAIL: D 互斥角色入候选 %s" % ex)
		for e2 in arena.player_ents:
			if e2 is BattleEntity and e2.kind != BattleEntity.Kind.PRIVATE and vg_names.has(e2.chara_name()):
				fails += 1
				print("VANGUARD_FAIL: D 现役角色入候选 %s" % e2.chara_name())
		arena._wheel_cancel()
		if arena._wheel_open or not arena._wheel_lock:
			fails += 1
			print("VANGUARD_FAIL: D 取消未关盘或未锁")
		arena._wheel_lock = false ## 模拟松开组合键解锁（真实=逐帧检查）
	## E. 结界半径 +1 接线（scheme 30：barrier_radius=判定+Defend+1）
	arena._open_vanguard_wheel(pl)
	if arena._wheel_open and not arena._wheel_cands.is_empty():
		var row2: Dictionary = arena._wheel_cands[0]
		arena._do_vanguard(pl, row2)
		if arena._vanguards.is_empty():
			fails += 1
			print("VANGUARD_FAIL: E 轮盘选取上场失败")
		else:
			var v3 = arena._vanguards[arena._vanguards.size() - 1]
			var expect: float = v3.judge_radius() + float(row2.get("Defend", 1)) + 1.0
			if absf(v3.barrier_radius() - expect) > 0.01:
				fails += 1
				print("VANGUARD_FAIL: E 前锋结界半径未+1（%.2f vs %.2f）" % [v3.barrier_radius(), expect])
			var pl_expect: float = pl.judge_radius() + float(pl.db.get("Defend", 1))
			if absf(pl.barrier_radius() - pl_expect) > 0.01:
				fails += 1
				print("VANGUARD_FAIL: E 普通角色结界半径被误加")
	else:
		fails += 1
		print("VANGUARD_FAIL: E 轮盘未开（候选空）")
	print("VANGUARD_OK" if fails == 0 else "VANGUARD_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
