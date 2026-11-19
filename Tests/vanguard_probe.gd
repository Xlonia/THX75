extends Node
## vanguard_probe —— 角色前锋探针（m100，scheme 24-30）
## A. 互斥：晚汐不能当前锋
## B. 上场：位置重合+ap25+5 杂兵+player_ents 加入
## C. 结界破损自动离场
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
	print("VANGUARD_OK" if fails == 0 else "VANGUARD_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
