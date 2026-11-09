extends Node
## 墙检测测试（作者修订版：2d/5d 双环、连续3对或相对3对、热段≥4 保留）
var fails := 0
func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["PASS" if c else "FAIL", m])
	if not c:
		fails += 1

## 直接驱动战场实体 meta 后调墙检测——需经 _ai_drive；改为构造 arena 模拟
func _ready() -> void:
	var arena: Node2D = (load("res://scenes/battle_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	var ent: BattleEntity = arena.player_ents[0]
	## 工具：调用墙检测逻辑（提出为可测函数前的临时方案：直接复制核心到本地验证）
	## ——用 arena 内实体走 _ai_drive 会连带其它力；这里手动调用同参数
	## 简化：直接设置 sit16_2d/5d 并模拟检测（检测代码在 _ai_drive 内联——
	## 本测试改为黑盒：设置环数据后跑一帧 _ai_drive 检查 meta）
	## a) 连续 6 点热（3 对连续）
	ent.sit16_2d = PackedInt32Array(); ent.sit16_2d.resize(16)
	ent.sit16_1d = PackedInt32Array(); ent.sit16_1d.resize(16)
	for k in 16:
		ent.sit16_2d[k] = 200 if k >= 2 and k <= 7 else 0
	ent.sit16_5d = PackedInt32Array(); ent.sit16_5d.resize(16)
	arena._ai_drive(ent, arena.enemy_leader, 1.0)
	var wd: Dictionary = ent.get_meta("apf_wall_dirs", {})
	_check(wd.size() >= 6, "连续6点(3对)→wall（得 %d 方向）" % wd.size())
	## b) 相对 3 对（不连续）：0/8, 3/11, 6/14
	for k in 16:
		ent.sit16_2d[k] = 200 if k in [0, 8, 3, 11, 6, 14] else 0
	arena._ai_drive(ent, arena.enemy_leader, 1.0)
	wd = ent.get_meta("apf_wall_dirs", {})
	_check(wd.size() >= 6, "相对3对(不连续)→wall（得 %d）" % wd.size())
	## c) 仅 2 对相对 → 不成墙
	for k in 16:
		ent.sit16_2d[k] = 200 if k in [0, 8, 3, 11] else 0
	arena._ai_drive(ent, arena.enemy_leader, 1.0)
	wd = ent.get_meta("apf_wall_dirs", {})
	_check(wd.size() < 6, "仅2对→不成墙（得 %d）" % wd.size())
	## d) 5d 环单独命中（2d 全冷）
	for k in 16:
		ent.sit16_2d[k] = 0
		ent.sit16_5d[k] = 200 if k >= 4 and k <= 9 else 0
	arena._ai_drive(ent, arena.enemy_leader, 1.0)
	wd = ent.get_meta("apf_wall_dirs", {})
	_check(wd.size() >= 6, "5d 环独立命中→wall（得 %d）" % wd.size())
	## e) 热段 ≥4 保留（2d 连续 4 点）
	for k in 16:
		ent.sit16_5d[k] = 0
		ent.sit16_2d[k] = 200 if k >= 5 and k <= 8 else 0
	arena._ai_drive(ent, arena.enemy_leader, 1.0)
	wd = ent.get_meta("apf_wall_dirs", {})
	_check(wd.size() >= 4, "连续4点热段保留→wall（得 %d）" % wd.size())
	## f) RET-C 引力点不落墙方向（wall=全环，树开空）
	for k in 16:
		ent.sit16_2d[k] = 0 ## 清检测——用 1d 制造低热方向
		ent.sit16_5d[k] = 0
	ent.set_meta("apf_wall_dirs", {0: true, 8: true, 1: true, 9: true, 2: true, 10: true})
	ent.set_meta("ht_at", 200)
	for k in 16:
		ent.sit16_1d[k] = 0 ## 全冷=全部方向可行
	ent.ret = RetSystem.new(ent)
	ent.ret.spin = 0.0
	ent.ret.compute_retc()
	var ok_no_wall := true
	for gp in ent.ret.best_dirs:
		var dk := wrapi(roundi((Vector2(gp).angle() - (-PI / 2.0)) / (TAU / 16.0)), 0, 16)
		if dk in [0, 1, 2, 8, 9, 10]:
			ok_no_wall = false
	_check(ok_no_wall and ent.ret.best_dirs.size() == 3, "RET-C 引力点避开墙方向（%d 个）" % ent.ret.best_dirs.size())
	print("WALL_%s" % ("OK" if fails == 0 else "FAIL:%d" % fails))
	get_tree().quit(1 if fails > 0 else 0)
