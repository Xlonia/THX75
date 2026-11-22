extends Node
## field_rules_probe —— 场地规则 FieldRules 探针（m107，scheme 弹幕编辑器新二"场地规则"节）
## A. 条带/框判定（缺省对=条带）
## B. sattle 特许范围（支援框形态：全场框+中心特许=仅外圈活跃）
## C. mutual 互斥覆盖（support_out 覆盖 total_support——框内外两套规则）
## D. require 需要（另一规则活跃才允许）
## E. smooth 圆滑强度（子框内 1.0→主框边衰减 0.0）
## F. itemget 磁吸（内核挂状态+THX75 drops 全屏快吸）
## G. THX75 支援框集成（框外召唤全免/框内扣费——经 FieldRules 查询）

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
	## G. THX75 支援框集成（arena setup 已注册 total_support/support_out）
	if not FieldRules.is_active("support_out", Vector2(20, 200)):
		fails += 1
		print("FRULE_FAIL: G 框外(20,200) support_out 未活跃")
	if FieldRules.is_active("total_support", Vector2(20, 200)):
		fails += 1
		print("FRULE_FAIL: G 框外 total_support 未被互斥覆盖")
	if FieldRules.is_active("support_out", Vector2(200, 200)):
		fails += 1
		print("FRULE_FAIL: G 框内 support_out 不应活跃（sattle 特许）")
	if not FieldRules.is_active("total_support", Vector2(200, 200)):
		fails += 1
		print("FRULE_FAIL: G 框内 total_support 未活跃")
	## G2. 框外召唤全免（经 FieldRules 查询）
	var pl = arena.player_leader
	if pl.sit_cards == null:
		pl.sit_cards = SitCardSystem.new()
	pl.pp = 200
	pl.position = Vector2(20, 200)
	var b0: int = pl.pp
	arena._do_summon(pl, CharaDB.get_by_name("Rumia"))
	var summoned: bool = false
	for e in arena.player_ents:
		if e is BattleEntity and e.has_meta("summoned") and e.position == Vector2(20, 200):
			summoned = true
	if not summoned:
		fails += 1
		print("FRULE_FAIL: G2 框外召唤未上场")
	elif int(arena.player_leader.pp) != b0:
		fails += 1
		print("FRULE_FAIL: G2 框外召唤仍扣费（%d→%d）" % [b0, int(arena.player_leader.pp)])
	## A. 条带判定：y 条带（x 不设限）
	FieldRules.register({"id": "t_strip", "tag": "t_strip", "chara": true,
		"box": [null, 0.0, null, 100.0]})
	if not FieldRules.is_active("t_strip", Vector2(-999, 50)):
		fails += 1
		print("FRULE_FAIL: A 条带 x 不设限失效")
	if FieldRules.is_active("t_strip", Vector2(0, 150)):
		fails += 1
		print("FRULE_FAIL: A 条带 y 越界未排除")
	## B. sattle（独立于支援框的再验）
	FieldRules.register({"id": "t_sat", "tag": "t_sat", "chara": true,
		"box": [0.0, 0.0, 100.0, 100.0], "sattle": [40.0, 40.0, 60.0, 60.0]})
	if not FieldRules.is_active("t_sat", Vector2(10, 10)):
		fails += 1
		print("FRULE_FAIL: B sattle 外应活跃")
	if FieldRules.is_active("t_sat", Vector2(50, 50)):
		fails += 1
		print("FRULE_FAIL: B sattle 框内未排除")
	## C. mutual（覆盖者活跃时被覆盖者不活跃）
	FieldRules.register({"id": "t_base", "tag": "t_base", "chara": true,
		"box": [0.0, 0.0, 200.0, 200.0]})
	FieldRules.register({"id": "t_over", "tag": "t_over", "chara": true,
		"box": [0.0, 0.0, 100.0, 100.0], "mutual": ["t_base"]})
	if FieldRules.is_active("t_base", Vector2(50, 50)):
		fails += 1
		print("FRULE_FAIL: C mutual 覆盖失效（t_base 应被 t_over 压制）")
	if not FieldRules.is_active("t_base", Vector2(150, 150)):
		fails += 1
		print("FRULE_FAIL: C mutual 作用域外 t_base 应活跃")
	## D. require（需要 t_base 活跃才允许）
	FieldRules.register({"id": "t_req", "tag": "t_req", "chara": true,
		"box": [0.0, 0.0, 200.0, 200.0], "require": ["t_base"]})
	if FieldRules.is_active("t_req", Vector2(50, 50)):
		fails += 1
		print("FRULE_FAIL: D require 的依赖被覆盖时不应活跃")
	if not FieldRules.is_active("t_req", Vector2(150, 150)):
		fails += 1
		print("FRULE_FAIL: D require 依赖活跃时应活跃")
	## E. smooth 强度（子框内 1.0；向主框边衰减）
	FieldRules.register({"id": "t_smooth", "tag": "t_smooth", "chara": true,
		"box": [0.0, 0.0, 200.0, 200.0], "smooth": [60.0, 60.0, 140.0, 140.0]})
	var s_in: float = FieldRules.smooth_strength(FieldRules.get_rule("t_smooth"), Vector2(100, 100))
	var s_edge: float = FieldRules.smooth_strength(FieldRules.get_rule("t_smooth"), Vector2(196, 100))
	if s_in < 0.999:
		fails += 1
		print("FRULE_FAIL: E smooth 子框内强度非 1（%f）" % s_in)
	if s_edge > 0.3:
		fails += 1
		print("FRULE_FAIL: E smooth 主框边强度未衰减（%f）" % s_edge)
	## F. itemget（内核挂状态）
	var pl2 = null
	for e2 in arena.player_ents:
		if e2 is BattleEntity and not e2.dead and e2.kind != BattleEntity.Kind.PRIVATE \
				and e2 != arena.player_leader:
			pl2 = e2
			break
	if pl2 != null:
		FieldRules.itemget(pl2, 9999.0, arena.time_frames + 300)
		if FieldRules.itemget_radius(pl2, arena.time_frames) < 9998.0:
			fails += 1
			print("FRULE_FAIL: F itemget 状态未挂")
		if FieldRules.itemget_radius(pl2, arena.time_frames + 400) != 0.0:
			fails += 1
			print("FRULE_FAIL: F itemget 解除条件（until）未生效")
		## F2. THX75 drops 全屏快吸：远处掉落 → 跑 _update_drops → 快吸拾取移除
		pl2.position = Vector2(370, 370)
		var dd0: int = arena.drops.size()
		arena.drops.append({"pos": Vector2(30, 30), "vel": Vector2.ZERO, "kind": "pp",
			"amount": 5, "frames": 1800, "tex": null, "owner": -1})
		for fr2 in 120: ## 8px/帧快吸：481px 距离约 60 帧吸到拾取
			arena._update_drops()
		if arena.drops.size() != dd0:
			fails += 1
			print("FRULE_FAIL: F2 itemget 磁吸未拾取远处道具（残留 %d）" % (arena.drops.size() - dd0))
		FieldRules.itemget_clear(pl2)
	else:
		print("FRULE_SKIP: F 无第二成员可测")
	FieldRules.unregister("t_strip")
	FieldRules.unregister("t_sat")
	FieldRules.unregister("t_base")
	FieldRules.unregister("t_over")
	FieldRules.unregister("t_req")
	FieldRules.unregister("t_smooth")
	## M. multi/overwrite 倍乘关系（作者 20261123 定案：覆盖=数值先者/不覆盖=叠加/
	## smooth=渐变交接/取整注册）
	FieldRules.clear()
	FieldRules.register({"id": "m_jia", "tag": "multi", "chara": false, "danmaku": true,
		"box": [0, 0, 100, 400], "multi": 2.0}) ## 甲=×2 叠加（先注册）
	FieldRules.register({"id": "m_yi", "tag": "multi", "chara": false, "danmaku": true,
		"box": [50, 0, 150, 400], "multi": 3.0, "overwrite": true}) ## 乙=×3 覆盖（后注册）
	FieldRules.register({"id": "m_bing", "tag": "multi", "chara": false, "danmaku": true,
		"box": [60, 0, 140, 400], "multi": 5.0, "overwrite": true}) ## 丙=×5 覆盖（更后=让位先者）
	if absf(FieldRules.multi_at(Vector2(25, 200), 1.0) - 2.0) > 0.001:
		fails += 1
		print("FRULE_FAIL: M 仅甲=叠加 ×2 不符（%s）" % str(FieldRules.multi_at(Vector2(25, 200), 1.0)))
	if absf(FieldRules.multi_at(Vector2(75, 200), 1.0) - 3.0) > 0.001:
		fails += 1
		print("FRULE_FAIL: M 甲乙重叠=覆盖直接覆写（×3）不符（%s）" % str(FieldRules.multi_at(Vector2(75, 200), 1.0)))
	if absf(FieldRules.multi_at(Vector2(75, 200), 4.0) - 3.0) > 0.001:
		fails += 1
		print("FRULE_FAIL: M 覆盖含实体标签覆写不符（%s）" % str(FieldRules.multi_at(Vector2(75, 200), 4.0)))
	if FieldRules.multi_at(Vector2(200, 200), 1.0) != 1.0:
		fails += 1
		print("FRULE_FAIL: M 域外=基准不变不符")
	var b = Bullet.new()
	b.ev = DanmakuEventData.new()
	b.ev.tag = DanmakuEventData.TAG_REGULAR
	b.dmg_now = 10
	b.pos = Vector2(75, 200)
	b.update_mul()
	if b.hit_damage() != 30:
		fails += 1
		print("FRULE_FAIL: M Bullet hit_damage 取整修饰不符（%d）" % b.hit_damage())
	b.pos = Vector2(200, 200)
	b.update_mul()
	if b.hit_damage() != 10:
		fails += 1
		print("FRULE_FAIL: M Bullet 域外修饰不符（%d）" % b.hit_damage())
	FieldRules.clear()
	if FieldRules.multi_count() != 0:
		fails += 1
		print("FRULE_FAIL: M multi 计数未清（%d）" % FieldRules.multi_count())
	if fails == 0:
		print("FRULE_OK: 条带/sattle/mutual/require/smooth/itemget/multi-overwrite/支援框集成 全过")
	get_tree().quit(1 if fails > 0 else 0)
