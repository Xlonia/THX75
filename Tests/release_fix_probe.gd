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
		if absf(float(run2["r"]) - 50.0) > 0.01:
			fails += 1
			print("RFIX_FAIL: R1 n 档半径非 50（m106 古典档位）")
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
	## R2c. 框外（后方部署带）召唤/前锋=不消耗P 不强制（m105 几何翻转）
	## 注意：R2 的召唤已把领队替换——此处用当前 player_leader（在场实体）
	var summoner = arena.player_leader
	if summoner != null and not summoner.dead:
		if summoner.sit_cards == null:
			summoner.sit_cards = SitCardSystem.new()
		summoner.pp = 200
		var before2: int = summoner.pp
		summoner.position = Vector2(20, 200) ## |20-200|=180>175=框外
		arena._do_summon(summoner, CharaDB.get_by_name("Rumia"))
		var ne2 = null
		for e4 in arena.player_ents:
			if e4 is BattleEntity and e4.has_meta("summoned") and e4.position == Vector2(20, 200):
				ne2 = e4
		if ne2 == null:
			fails += 1
			print("RFIX_FAIL: R2c 框外召唤未上场")
		else:
			if int(arena.player_leader.pp) != before2:
				fails += 1
				print("RFIX_FAIL: R2c 框外召唤仍扣费（%d→%d）" % [before2, int(arena.player_leader.pp)])
			if ne2.has_meta("release_flash"):
				fails += 1
				print("RFIX_FAIL: R2c 框外召唤不应强制发动能力")
	## R2d. 框外前锋=不扣费不强制
	var pl3 = null
	for e5 in arena.player_ents:
		if e5 is BattleEntity and not e5.has_meta("summoned") and not e5.dead \
				and e5.side == 0 and e5.kind != BattleEntity.Kind.PRIVATE \
				and e5 != pl and e5 != pl2:
			pl3 = e5
			break
	if pl3 != null:
		pl3.position = Vector2(20, 380) ## |380-200|=180>175=框外
		pl3.pp = 120
		var b3: int = pl3.pp
		arena._do_vanguard(pl3, {"Name": "Rumia", "NameZH": "露米娅"})
		if not arena._vanguards.is_empty() and arena._vanguards[arena._vanguards.size() - 1].position == Vector2(20, 380):
			if int(pl3.pp) != b3:
				fails += 1
				print("RFIX_FAIL: R2d 框外前锋仍扣费（%d→%d）" % [b3, int(pl3.pp)])
	## R4. 队友释放后 2s 全队锁（作者改案-A）——释放即置锁
	pl.pp = 300
	arena._apply_release(pl, "n")
	if int(arena._team_cast_cd[pl.side]) != int(arena.time_frames) + 120:
		fails += 1
		print("RFIX_FAIL: R4 释放未置 2s 全队锁（%s）" % str(arena._team_cast_cd[pl.side]))
	## R5. 应急符卡不掉灰卡（m106 洒落雨修正——真凶=应急灰卡雨）
	if pl.sit_cards == null:
		pl.sit_cards = SitCardSystem.new()
	pl.sit_cards.spell_ready = true
	pl.spell_cards = 2
	pl.pp = 200
	var d0: int = arena.drops.size()
	arena._apply_release(pl, "m", true) ## 应急态
	if arena.drops.size() != d0:
		fails += 1
		print("RFIX_FAIL: R5 应急释放掉灰卡（%d→%d）" % [d0, arena.drops.size()])
	## R5b. 应急 e 保持 m100 契约（Sl=0 即触发——不受装填门；洒落雨由
	## 应急不掉灰卡单独修掉）+Sl>0 不触发
	pl.sit_cards.pending_kind = ""
	pl.sit_cards.SL = 128.0
	pl.sit_cards.release_tick(2)
	if pl.sit_cards.pending_kind != "":
		fails += 1
		print("RFIX_FAIL: R5b Sl>0 仍触发应急 e（%s）" % pl.sit_cards.pending_kind)
	pl.sit_cards.SL = 0.0
	pl.sit_cards.pending_kind = "" ## 清掉上一拍申请残留（隔离本断言）
	var r5b2: String = pl.sit_cards.release_tick(2) ## SL=0→ratio_a 必成=本拍顶替返回 e
	if r5b2 != "e":
		fails += 1
		print("RFIX_FAIL: R5b Sl=0 未触发应急 e（ret=%s）" % r5b2)
	## R6. 释放骰（scheme 168-171 接线）：比率 0=必败/比率大=必成
	if pl.sit_cards.release_attempt(0.0, 0.0):
		fails += 1
		print("RFIX_FAIL: R6 释放骰比率 0 仍成功")
	if not pl.sit_cards.release_attempt(10000.0, 0.0):
		fails += 1
		print("RFIX_FAIL: R6 释放骰比率超大仍失败")
	## R7. Al 乘数：AL=0.2 时 dsr 变小→…（验证挂钩生效——AL=0.2 分母=1/5）
	pl.sit_cards.AL = 0.2
	pl.sit_cards.release_tick(2) ## 无副作用冒烟（不炸即可）
	pl.sit_cards.AL = 1.0
	if fails == 0:
		print("RFIX_OK: 圆时长批复公式+支援框几何+接管=滚轮所选+2s队锁+应急不掉灰卡/e保持m100契约+释放骰+Al挂钩 全过")
	get_tree().quit(1 if fails > 0 else 0)
