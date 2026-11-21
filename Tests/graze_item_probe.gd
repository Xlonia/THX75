extends Node
## graze_item_probe —— m109 探针：擦弹判定+道具本体+场地规则 CSV 装载
## A. 擦弹：自机接近未标记敌对弹=计数+1+贴 grazed 标签；命中环内不计；不重复计
## B. 道具：M=疗伤（部位回一半上限）J=修理（结界回满）U=复活（满目疮痍站起）
##    库存耗尽=指令失败不扣负
## C. 场地规则 CSV：装载两规则+is_active 查询（框外/框内）
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
	arena._item_ai_cd = [999999, 999999] ## 【冻结道具 AI】全程冻结，B4 段解冻专项测
	print("DBG0 items=", arena.team_items[0], " gg=", GameGlobals.versus_team_items)
	for i0 in 8:
		arena._physics_process(1.0 / 60.0)
	print("DBG8 items=", arena.team_items[0])
	arena._item_ai_cd = [999999, 999999]
	## A. 擦弹：铺敌对弹（判定环外、擦弹环内 12px；及远弹）
	var en = arena.enemy_leader
	arena._spawn_event_copies(arena._find_event("demo_aimed"), pl.position + Vector2(13, 0), en, null, {}, 0)
	arena._spawn_event_copies(arena._find_event("demo_aimed"), pl.position + Vector2(200, 0), en, null, {}, 0)
	var n0: int = arena.graze_count
	for fr in 4:
		arena._physics_process(1.0 / 60.0)
	if arena.graze_count < n0 + 1:
		fails += 1
		print("GITEM_FAIL: A 擦弹未计数（%d→%d）" % [n0, arena.graze_count])
	var tagged := false
	for b in arena.bullets:
		if b is Bullet and b.source_side == 1 and not b.hidden_now and b.grazed:
			tagged = true
	if not tagged:
		fails += 1
		print("GITEM_FAIL: A 无弹被贴 grazed 标签")
	var c1: int = arena.graze_count
	for fr2 in 8:
		arena._physics_process(1.0 / 60.0)
	if arena.graze_count > c1 + 1:
		fails += 1
		print("GITEM_FAIL: A 同弹重复计数（%d→%d）" % [c1, arena.graze_count])
	arena.bullets.clear() ## 【m111 续】A 段弹幕清场——B 段道具用例不被流弹干扰
	pl.dead = false
	pl.immune_frames = 99999 ## 免疫流弹（B 段不受被弹结算干扰）
	arena._item_ai_cd = [999999, 999999] ## 【冻结道具 AI】B 段手工用例不被 AI 抢耗
	arena.team_items[0] = [2, 1, 1] ## 【m114】AI/手工用例口径重置（成员出厂 hp3/ap25 会触发 AI——见 AI 命题口径）
	## B. 道具（目标=滚轮所选；默认 idx0=领队）
	if pl.sit_cards == null:
		pl.sit_cards = SitCardSystem.new()
	pl.hp = [3, 20, 10] ## 部位 0 受损
	print("DBG B: pick=", arena.picked_entity(), " pl=", pl, " pickidx=", arena._pick_idx,
		" items=", arena.team_items[0], " dead=", pl.dead, " side=", pl.side)
	arena._use_item(KEY_M) ## 疗伤
	print("DBG B2: hp=", pl.hp, " items=", arena.team_items[0])
	if int(pl.hp[0]) != 8:
		fails += 1
		print("GITEM_FAIL: B 疗伤未回一半上限（hp[0]=%d 应 8）" % int(pl.hp[0]))
	pl.ap = 10
	arena._use_item(KEY_J) ## 修理
	if int(pl.ap) != int(pl._initial_ap()):
		fails += 1
		print("GITEM_FAIL: B 修理未回满结界（ap=%d 应 %d）" % [int(pl.ap), int(pl._initial_ap())])
	## B2. 复活：第二成员
	arena._pick_idx = mini(1, arena.player_ents.size() - 1)
	var pl2 = arena.picked_entity()
	if pl2 != null and pl2 != pl:
		pl2.dead = true
		arena._use_item(KEY_U) ## 复活
		if pl2.dead:
			fails += 1
			print("GITEM_FAIL: B2 复活后仍 dead")
	## B3. 库存耗尽=指令失败
	arena._pick_idx = 0
	arena.team_items[0][0] = 0
	pl.hp = [3, 20, 10]
	arena._use_item(KEY_M)
	if int(pl.hp[0]) != 3 or int(arena.team_items[0][0]) != 0:
		fails += 1
		print("GITEM_FAIL: B3 库存 0 仍生效/扣负")
	## B4. 道具 AI 逻辑（m114：EntityOps geniterate 选择器+本侧过滤+节流）
	arena._item_ai_cd[0] = 0 ## 解冻（AI 一拍内响应）
	arena._pick_idx = 0
	arena.team_items[0] = [2, 0, 0]
	var pl3 = null
	for e5 in arena.player_ents:
		if e5 is BattleEntity and e5 != pl and not e5.dead and e5.kind != BattleEntity.Kind.PRIVATE:
			pl3 = e5
			break
	if pl3 != null:
		pl3.hp = [1, 5, 3] ## member 部位0=1 ≤2 → AI 疗伤目标
		var cnt0: int = int(arena.team_items[0][0])
		arena._item_ai_tick()
		if int(pl3.hp[0]) != 2 or int(arena.team_items[0][0]) != cnt0 - 1:
			fails += 1
			print("GITEM_FAIL: B4 道具 AI 疗伤未生效（hp=%d 库存=%d）" % [int(pl3.hp[0]), int(arena.team_items[0][0])])
	## C. 场地规则 CSV（arena setup 已装载）
	if not FieldRules.is_active("support_out", Vector2(20, 200)):
		fails += 1
		print("GITEM_FAIL: C CSV 装载后 support_out 框外未活跃")
	if not FieldRules.is_active("total_support", Vector2(200, 200)):
		fails += 1
		print("GITEM_FAIL: C CSV 装载后 total_support 框内未活跃")
	if fails == 0:
		print("GITEM_OK: 擦弹判定+道具本体+场地规则CSV装载 全过")
	get_tree().quit(1 if fails > 0 else 0)
