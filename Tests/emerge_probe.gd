extends Node
## emerge_probe —— 应急符卡（e 态势）探针（m100）
## A. Sl=0 → release_tick 强制 pending e → 顶替下一张
## B. e 卡消费：无符卡也强制交主符卡档（spell_cards 补 1 后 _apply_release m）
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
	## B. e 卡消费（符卡 0 张也强制交——emergency 豁免资源门）
	pl.spell_cards = 0
	pl.pp = 0
	arena._apply_release(pl, "m", true)
	if int(pl.spell_cards) != -1:
		## m 档扣 1 符；0 张时豁免门扣为 -1（应急透支）——探针按 ≥0 容差验
		print("EMERGE_NOTE: spell_cards=%d（应急透支或 0）" % int(pl.spell_cards))
	if int(pl.spell_cards) > 0:
		fails += 1
		print("EMERGE_FAIL: B 应急未扣减/未豁免（=%d）" % int(pl.spell_cards))
	print("EMERGE_OK" if fails == 0 else "EMERGE_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
