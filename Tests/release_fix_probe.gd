extends Node
## release_fix_probe —— m104 三修探针（作者前锋验证反馈）
## R1. 释放圆时长=批复公式（剩余P每100P=1s 最低1s；原写死 5s=作者"圆太大"根因）
## R2. 支援框外P豁免：召唤费显式扣 25P+强制能力不扣被召唤者 P；前锋同（scheme 33）
## R3. 接管对象=滚轮所选（takeover_ent/_ctrl_ent；失效回落领队）

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
	if pl.sit_cards == null:
		pl.sit_cards = SitCardSystem.new()
	## R1. 符卡释放圆时长（s：pp=100→1s；n：pp=200 扣 25→1.75s）
	pl.pp = 100
	pl.spell_cards = 2
	var n0: int = arena._spell_runs.size()
	arena._apply_release(pl, "s")
	if arena._spell_runs.size() != n0 + 1:
		fails += 1
		print("RFIX_FAIL: R1 s 档未挂载")
	else:
		var run: Dictionary = arena._spell_runs[arena._spell_runs.size() - 1]
		var span: int = int(run["until_frame"]) - int(run["start_frame"])
		if span != 60: ## pp=100 → 1 秒（原写死 300 帧）
			fails += 1
			print("RFIX_FAIL: R1 s 档圆时长非 1s（%d 帧）" % span)
	pl.pp = 200
	arena._apply_release(pl, "n")
	if arena._spell_runs.size() != n0 + 2:
		fails += 1
		print("RFIX_FAIL: R1 n 档未挂载")
	else:
		var run2: Dictionary = arena._spell_runs[arena._spell_runs.size() - 1]
		var span2: int = int(run2["until_frame"]) - int(run2["start_frame"])
		if span2 != 105: ## 200-25=175 → 1.75s=105 帧
			fails += 1
			print("RFIX_FAIL: R1 n 档圆时长非 1.75s（%d 帧）" % span2)
		if absf(float(run2["r"]) - 80.0) > 0.01:
			fails += 1
			print("RFIX_FAIL: R1 n 档半径非 80")
	## R2. 支援框外召唤 P 豁免（位置=场心 200,200=中心 350² 内）
	pl.pp = 300
	var sum_row: Dictionary = CharaDB.get_by_name("Rumia")
	var before: int = pl.pp
	arena._do_summon(pl, sum_row)
	var ne = null
	for e in arena.player_ents:
		if e is BattleEntity and e.has_meta("summoned"):
			ne = e
	if ne == null:
		fails += 1
		print("RFIX_FAIL: R2 召唤未上场")
	else:
		if int(pl.pp) != before - 25:
			fails += 1
			print("RFIX_FAIL: R2 召唤费未扣（%d→%d）" % [before, int(pl.pp)])
		if int(ne.pp) != before - 25: ## 强制能力 P 豁免=被召唤者 P 不再 -25
			fails += 1
			print("RFIX_FAIL: R2 强制能力仍扣被召唤者 P（%d）" % int(ne.pp))
	## R2b. 前锋支援框外强制能力（scheme 33）——前锋费 25 扣，前锋本体 P 不扣
	var pl2 = null
	for e2 in arena.player_ents:
		if e2 is BattleEntity and not e2.has_meta("summoned") and e2 != ne and not e2.dead \
				and e2.side == 0 and e2.kind != BattleEntity.Kind.PRIVATE and e2 != pl:
			pl2 = e2
			break
	if pl2 != null:
		if pl2.sit_cards == null:
			pl2.sit_cards = SitCardSystem.new()
		pl2.position = Vector2(200, 200) ## 中心 350² 内
		pl2.pp = 150
		var b2: int = pl2.pp
		arena._do_vanguard(pl2, {"Name": "Rumia", "NameZH": "露米娅"})
		if arena._vanguards.is_empty():
			fails += 1
			print("RFIX_FAIL: R2b 前锋未上场")
		else:
			var v = arena._vanguards[arena._vanguards.size() - 1]
			if int(pl2.pp) != b2 - 25:
				fails += 1
				print("RFIX_FAIL: R2b 前锋费未扣（%d→%d）" % [b2, int(pl2.pp)])
			if int(v.pp) != 0: ## 前锋本体默认 0——强制能力豁免不改（免得双重扣费）
				fails += 1
				print("RFIX_FAIL: R2b 前锋强制能力仍扣本体 P（%d）" % int(v.pp))
	## R3. 接管对象=滚轮所选
	var member = null
	for e3 in arena.player_ents:
		if e3 is BattleEntity and e3 != arena.player_leader and not e3.dead and e3.side == 0 \
				and e3.kind != BattleEntity.Kind.PRIVATE:
			member = e3
			break
	if member != null:
		arena.takeover_ent = member
		arena.take_over = true
		if arena._ctrl_ent() != member:
			fails += 1
			print("RFIX_FAIL: R3 接管对象未指向滚轮所选")
		arena.takeover_ent = null
		if arena._ctrl_ent() != arena.player_leader:
			fails += 1
			print("RFIX_FAIL: R3 失效未回落领队")
	else:
		print("RFIX_SKIP: R3 无第二成员可测")
	if fails == 0:
		print("RFIX_OK: 圆时长批复公式+支援框外P豁免+接管=滚轮所选 全过")
	get_tree().quit(1 if fails > 0 else 0)
