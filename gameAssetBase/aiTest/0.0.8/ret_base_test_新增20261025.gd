extends Node
## v0.0.8 RET 基底测试：RET-C 倾向/引力点几何 + Sl 简化可行性
var fails := 0
func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["PASS" if c else "FAIL", m])
	if not c:
		fails += 1
func _ready() -> void:
	var ent := BattleEntity.new()
	ent.setup(CharaDB.get_by_name("ReimuA"), 0, BattleEntity.Kind.MEMBER)
	ent.position = Vector2(200, 200)
	var ret := RetSystem.new(ent)
	## ① 全冷场（sit16 全 0 < cur 100）：三环 16 向全可行 → 倾向≈0（对称抵消）
	ent.sit16_1d = PackedInt32Array(); ent.sit16_1d.resize(16)
	ent.sit16_2d = PackedInt32Array(); ent.sit16_2d.resize(16)
	ent.sit16_5d = PackedInt32Array(); ent.sit16_5d.resize(16)
	ent.set_meta("ht_at", 100)
	ret.spin = 0.0
	ret.compute_retc()
	_check(ret.path_tendency.length() < 0.001, "全冷对称场倾向≈0（得 %.3f）" % ret.path_tendency.length())
	_check(ret.gravity_points.size() == 3, "引力点=最大三方向（得 %d）" % ret.gravity_points.size())
	## ② 单向热（1d 北向 200 其余 0，cur=100）：倾向应指向南（避热）
	for k in 16:
		var a := -PI / 2.0 + TAU * float(k) / 16.0
		var dv := Vector2(cos(a), sin(a))
		if dv.y < -0.9:
			ent.sit16_1d[k] = 200 ## 北=−y 热点
	ret.compute_retc()
	_check(ret.path_tendency.y > 0.3, "北热→倾向南（得 %s）" % ret.path_tendency.round())
	var best: Vector2 = ret.best_dirs[0]
	_check(best.y > 0.5, "首选方向朝南（得 %s）" % best.round())
	## ③ Sl：Hcs 全 0（冷）+1d/2d 全冷 → 16 方向全可行 → Sl=256
	ent.hcs_pts = PackedFloat32Array(); ent.hcs_pts.resize(49)
	for k in 16:
		ent.sit16_1d[k] = 0
	ret.compute_simplified_sl()
	_check(ret.sl == 256, "全冷场 Sl=256（得 %d）" % ret.sl)
	## ④ Sl=0 路径：1d 全热（>96）且 Hcs 高 → e 态势触发源
	for k in 16:
		ent.sit16_1d[k] = 200
		ent.hcs_pts[k] = 200.0
		ent.hcs_pts[16 + k] = 200.0
	ret.compute_simplified_sl()
	_check(ret.sl == 0, "全热场 Sl=0（e 态势源，得 %d）" % ret.sl)
	## ⑤ 战场链路：实体挂载+10Hz 计算不炸
	var arena: Node2D = (load("res://scenes/battle_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	var p0: BattleEntity = arena.player_ents[0]
	_check(p0.ret != null, "战场实体挂载 RetSystem")
	for i in 12:
		arena._physics_process(1.0 / 60.0)
		arena._process(1.0 / 60.0)
	_check(p0.ret != null and p0.sit_cards != null and p0.sit_cards.SL >= 0.0, "10Hz 计算+SL 回写（SL=%.0f）" % p0.sit_cards.SL)
	print("RET_%s" % ("OK" if fails == 0 else "FAIL:%d" % fails))
	get_tree().quit(1 if fails > 0 else 0)
