extends Node
## =============================================================
## priv_fix_probe —— 杂兵卡死修复验证（0.0.9 20261110，headless 可跑）
##   A. 钳制：local_pos 强推场外 → sync_private_pos 后必回场内（8..392）
##   B. 解散：角色死亡 → 其下杂兵全部 dead + 空缺计入增援累计
## 用法：godot --headless --path . res://Tests/priv_fix_probe.tscn
## =============================================================
var arena: Node2D
var fails := 0

func _chk(ok: bool, msg: String) -> void:
	if ok:
		print("  PASS " + msg)
	else:
		fails += 1
		print("  FAIL " + msg)

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
	for k in 30:
		arena._physics_process(1.0 / 60.0)
	var chara: BattleEntity = null
	for e in arena.entities:
		if e is BattleEntity and e.kind != BattleEntity.Kind.PRIVATE and e.side == 0 and not e.dead:
			chara = e
			break
	if chara == null:
		print("PRIV_FAIL —— 无可测角色")
		get_tree().quit(1)
		return
	# 给该角色配一名杂兵
	while arena._private_count(chara) < 1:
		arena._spawn_private_for(chara)
	var priv: BattleEntity = null
	for e2 in arena.entities:
		if e2 is BattleEntity and e2.kind == BattleEntity.Kind.PRIVATE and e2.owner_ent == chara and not e2.dead:
			priv = e2
			break
	_chk(priv != null, "杂兵已生成")
	if priv == null:
		print("PRIV_FAIL")
		get_tree().quit(1)
		return
	# A. 钳制：把 local_pos 强推到角色左侧 500px（必出左边界）
	priv.local_pos = Vector2(-500.0, 0.0)
	priv.sync_private_pos()
	_chk(priv.position.x >= 2.0 and priv.position.x <= 398.0 and priv.position.y >= 2.0 and priv.position.y <= 398.0,
		"场外杂兵强制拉回（pos=%s）" % str(priv.position))
	_chk(priv.local_pos == priv.position - chara.position, "local_pos 回写（防边界对抗）")
	# B. 解散：击杀所属角色
	var gap0: int = arena._priv_gap_acc[chara.side]
	chara.dead = true ## 与投降/召唤接替同款置死路径（take_hit 流另行覆盖）
	arena._physics_process(1.0 / 60.0) ## _entity_ticks 检测死亡→解散
	_chk(priv.dead, "角色被击败→杂兵就地解散")
	_chk(int(arena._priv_gap_acc[chara.side]) > gap0, "空缺计入增援累计（%d→%d）" % [gap0, arena._priv_gap_acc[chara.side]])
	var left := 0
	for e3 in arena.entities:
		if e3 is BattleEntity and e3.kind == BattleEntity.Kind.PRIVATE and e3.owner_ent == chara and not e3.dead:
			left += 1
	_chk(left == 0, "该角色名下无存活杂兵")
	print("PRIV_OK" if fails == 0 else "PRIV_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
