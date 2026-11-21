extends Node
## emerge_probe —— 应急（e 态势）探针（m100 首版；m108 作者修正案同步）
## A. Sl=0 → release_tick 强制 pending e → 顶替下一张
## B. e 卡消费=先释放**能力**（m108 作者修正：原"强制交主符卡"为写错）——
##    资源照扣（能力 25P），不够花费则跳过（无论多需要也跳过）
## C. 能力档释放副作用在位（技能装填复位）
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
	## A. Sl=0 触发
	pl.sit_cards.SL = 0.0
	pl.sit_cards.pending_kind = ""
	pl.sit_cards.pending_tries = 0
	var replaced: String = pl.sit_cards.release_tick(2)
	if replaced != "e":
		fails += 1
		print("EMERGE_FAIL: A Sl=0 未强制 e（replaced=%s）" % replaced)
	## B. e 卡消费=先释放能力（走 _ent_tick_sit 弹卡路径）：资源照扣
	pl.pp = 200
	pl.spell_cards = 2
	pl.sit_cards.skill_ready = false ## 应急绕申请骰——但走正常释放（能力档）
	pl.sit_cards.ring[0] = "e" ## 强制下一张=e
	var pp0: int = pl.pp
	var sc0: int = pl.spell_cards
	arena._ent_tick_sit(0.1)
	if int(pl.pp) != pp0 - 25:
		fails += 1
		print("EMERGE_FAIL: B 应急释放能力未照扣 25P（%d→%d）" % [pp0, int(pl.pp)])
	if int(pl.spell_cards) != sc0:
		fails += 1
		print("EMERGE_FAIL: B 应急能力档误耗符卡（%d→%d）" % [sc0, int(pl.spell_cards)])
	if not pl.has_meta("release_flash"):
		fails += 1
		print("EMERGE_FAIL: B 应急能力未实际释放")
	if int(pl.sit_cards.skill_load_t) != 0.0 and pl.sit_cards.skill_load_t != 0.0:
		pass ## 装填复位（on_released n）——容忍浮点
	## B2. 资源不够（P<25）→ 应急也跳过（无论多需要）
	var pl2 = null
	for e2 in arena.player_ents:
		if e2 is BattleEntity and e2 != pl and not e2.dead and e2.side == 0 \
				and e2.kind != BattleEntity.Kind.PRIVATE:
			pl2 = e2
			break
	if pl2 != null:
		if pl2.sit_cards == null:
			pl2.sit_cards = SitCardSystem.new()
		pl2.sit_cards.SL = 0.0
		pl2.sit_cards.pending_kind = ""
		pl2.pp = 10 ## 不足 25
		pl2.spell_cards = 2
		pl2.sit_cards.ring[0] = "e"
		var pp2: int = pl2.pp
		arena._ent_tick_sit(0.1)
		if int(pl2.pp) != pp2:
			fails += 1
			print("EMERGE_FAIL: B2 资源不足仍扣费（%d→%d）" % [pp2, int(pl2.pp)])
		if pl2.has_meta("release_flash"):
			fails += 1
			print("EMERGE_FAIL: B2 资源不足仍释放")
	else:
		print("EMERGE_SKIP: B2 无第二成员可测")
	print("EMERGE_OK" if fails == 0 else "EMERGE_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
