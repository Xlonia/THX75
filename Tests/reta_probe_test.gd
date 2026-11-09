extends Node
## R-ETA 探针（作者 0.0.8）：不同角色 × 不同弹幕的避弹表现矩阵
##   弹幕类型：追踪狙(demo_missile) / 直线自机狙(demo_aimed) / 激光(demo_laser)
##   角色：ReisenA / MarisaA / Youshio（不同 Normal 速度）
##   指标：240 帧内 AP/HP 折损 + 是否命中过（免疫次数统计）
## 结果直接打印矩阵，作者对照 F5。

var fails := 0

func _ready() -> void:
	var arena: Node2D = (load("res://scenes/battle_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	## 单挑环境：只留目标角色与一名敌方发射者（多角色外循环见 _run_for）
	var target: BattleEntity = arena.player_ents[0]
	target.position = Vector2(200, 300)
	var shooter: BattleEntity = arena.enemy_ents[0]
	shooter.position = Vector2(200, 60)
	for e in arena.entities:
		var ee: BattleEntity = e
		if ee != null and ee != target and ee != shooter:
			ee.dead = true
	print("RETA_MATRIX 目标=%s (判定%.0f/结界%.0f 慢机%.1f)" % [
		target.chara_name(), target.judge_radius(), target.barrier_radius(), target.normal_speed()])
	print("RETA_MATRIX —— 多角色矩阵开始（ReisenA/MarisaA/Youshio）")
	for cname in ["ReisenA", "MarisaA", "Youshio"]:
		var row: BattleEntity = null
		for e0 in arena.entities:
			var ee0: BattleEntity = e0
			if ee0 != null and ee0.chara_name() == cname:
				row = ee0
				break
		if row == null:
			row = BattleEntity.new()
			row.setup(CharaDB.get_by_name(cname), 0, BattleEntity.Kind.MEMBER)
			row.position = Vector2(200, 300)
			arena.add_child(row)
			arena.entities.append(row)
			arena._connect_economy(row)
		_run_matrix(arena, row, shooter)
func _run_matrix(arena: Node2D, target: BattleEntity, shooter: BattleEntity) -> void:
	print("RETA_MATRIX 目标=%s (判定%.0f/结界%.0f 慢机%.1f)" % [
		target.chara_name(), target.judge_radius(), target.barrier_radius(), target.normal_speed()])
	for ev_name in ["demo_aimed", "demo_missile", "demo_laser"]:
		var ev := GameGlobals.get_event(ev_name)
		if ev == null:
			print("RETA_MATRIX %s 缺失，跳过" % ev_name)
			continue
		ev.compile()
		var hits := 0
		var last_immune := false
		target.immune_frames = 0
		target.ap = 50
		target.hp = [10, 20, 10]
		## 朝目标发射 6 波（每 40 帧一波，从 shooter 位置）
		var shots := 0
		for f in 240:
			if f % 40 == 0 and shots < 6:
				shots += 1
				var b := Bullet.new()
				b.setup(ev, shooter.position + Vector2(randf_range(-60, 60), 0), 1, shooter, arena, 0, {})
				arena.bullets.append(b)
				arena.bullet_hash.insert(b)
			arena._physics_process(1.0 / 60.0)
			arena._process(1.0 / 60.0)
			if target.immune_frames > 0 and not last_immune:
				hits += 1
			last_immune = target.immune_frames > 0
		var ap_loss: int = 50 - target.ap
		var hp_loss: int = maxf(0.0, float(30 - (target.hp[0] + target.hp[1] + target.hp[2])))
		print("RETA_MATRIX %-12s 命中次数=%d AP折损=%d HP折损=%d 弹幕存活=%d" % [
			ev_name, hits, ap_loss, hp_loss, arena.bullets.size()])
		## 清场
		arena.bullets.clear()
		arena.bullet_hash.clear()
		target.dead = false
		target.immune_frames = 0
	print("RETA_MATRIX END")
	get_tree().quit(0)
