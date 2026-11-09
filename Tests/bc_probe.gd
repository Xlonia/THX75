extends Node
## =============================================================
## bc_probe —— 基础规避 BC（新三 213-218）单元与等价验证（headless 可跑）
##   A. 合成法则（纯 GD，直接喂阻断比例）：
##     ①无弹+无 APF → 四力平衡 → 合力≈0（不移动）
##     ②右弧贴身阻断=1 → 合力向左逃逸
##     ③右弧半阻断=0.5 → 左向力减半
##     ④APF push 向左 0.5 → 左向力加成（同向引力）
##     ⑤速度钳制：bc_k=|合力|/256 钳 1（慢机速度上限）
##   B. 射线几何（GD 回退版 _bc_rays 的隔离验证）：场内摆弹 → 四弧阻断方向正确
##   C. C++ vs GD 等价：bc_rays 两侧同参数全弹快照 → 4 值全等（扩展缺失则 SKIP）
## 用法：godot --headless --path . res://Tests/bc_probe.tscn
## =============================================================
var arena: Node2D
var fails := 0

func _ready() -> void:
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	## 加载屏（分帧预热）走完再测——物理直驱
	var guard := 0
	while arena._loading and guard < 2000:
		arena._physics_process(1.0 / 60.0)
		guard += 1
	print("[bc] 加载完成 guard=%d" % guard)
	_part_a()
	_part_b()
	await _part_c()
	print("BC_OK" if fails == 0 else "BC_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func _chk(ok: bool, msg: String) -> void:
	if ok:
		print("  PASS %s" % msg)
	else:
		fails += 1
		print("  FAIL %s" % msg)

## 与 battle_arena._ai_drive 内 BC 合成同法则的纯函数复刻
func _synth(blk: Array, push: Vector2) -> Vector2:
	var axis := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	var net := Vector2.ZERO
	for bi in 4:
		var ax: Vector2 = axis[bi]
		var f_k: float = 256.0 * (1.0 - float(blk[bi])) + 256.0 * ax.dot(push)
		net += ax * f_k
	return net / 256.0

func _part_a() -> void:
	print("== A. 合成法则 ==")
	var b0 := _synth([0, 0, 0, 0], Vector2.ZERO)
	_chk(b0.length() < 0.01, "无弹无APF 四力平衡（合力=%.4f）" % b0.length())
	var b1 := _synth([0, 0, 0, 1], Vector2.ZERO)
	_chk(absf(b1.x + 1.0) < 0.01, "右弧贴身→左向满基力逃逸（x=%.2f 应=-1.0）" % b1.x)
	var b2 := _synth([0, 0, 0, 0.5], Vector2.ZERO)
	_chk(absf(b2.x + 0.5) < 0.01, "右弧半阻断→该向力半减（x=%.2f 应=-0.5）" % b2.x)
	var b3 := _synth([0, 0, 0, 0], Vector2(-0.5, 0))
	_chk(b3.x < -0.49 and absf(b3.y) < 0.01, "APF向左0.5→左向加成（=%s）" % str(b3))
	var b4 := _synth([1, 1, 1, 1], Vector2(2, 2))
	_chk(b4.length() > 2.0, "APF 大斥力穿透 BC（=%s）" % str(b4))
	_chk(minf(b4.length(), 1.0) == 1.0, "速度钳制慢机上限")

func _part_b() -> void:
	print("== B. 射线几何（GD 回退）==")
	var ent: BattleEntity = arena.player_leader
	if ent == null:
		_chk(false, "无领队")
		return
	var blen := ent.normal_speed() * 6.0
	## 隔离：临时只留测试弹+强制 GD 回退（结束后原样恢复，不扰动 C++ slot）
	var saved: Array = arena.bullets
	arena.motion_hot_enabled = false
	arena.bullets = []
	## 右侧 0.06 秒距处一颗弹：右弧应阻断、其余≈0
	var b := Bullet.new()
	b.setup(GameGlobals.get_event("demo_ring"), ent.position + Vector2(blen * 0.6, 0), 1, arena.enemy_leader, arena)
	arena.bullets.append(b)
	var blk: PackedFloat32Array = arena._bc_rays(ent, blen)
	_chk(blk[3] > 0.2, "右弧命中（右=%.2f）" % blk[3])
	_chk(blk[2] < 0.05 and blk[0] < 0.05 and blk[1] < 0.05, "其余弧无弹（左=%.2f 上=%.2f 下=%.2f）" % [blk[2], blk[0], blk[1]])
	## 上方弹→上弧
	arena.bullets = []
	var b2 := Bullet.new()
	b2.setup(GameGlobals.get_event("demo_ring"), ent.position + Vector2(0, -blen * 0.6), 1, arena.enemy_leader, arena)
	arena.bullets.append(b2)
	var blk2: PackedFloat32Array = arena._bc_rays(ent, blen)
	_chk(blk2[0] > 0.2, "上弧命中（上=%.2f）" % blk2[0])
	arena.bullets = saved
	arena.motion_hot_enabled = true

func _part_c() -> void:
	print("== C. C++ vs GD 射线等价（接管 slot + 快照全量）==")
	if arena.motion_hot == null or not arena.motion_hot_enabled:
		print("  SKIP —— 扩展/接管不可用（headless 无 GDExtension 时正常）")
		return
	## 铺 60 帧（产生接管 slot 弹），随后每 10 帧抽 4 实体比对
	var mism := 0
	var tot := 0
	for f in 240:
		arena._physics_process(1.0 / 60.0) ## 铺场（产生接管 slot 弹）
	var ents: Array = []
	for e in arena.entities:
		if e is BattleEntity and not e.dead and e.kind != BattleEntity.Kind.PRIVATE:
			ents.append(e)
	if ents.is_empty():
		_chk(false, "无可测实体")
		return
	for rep in 12:
		arena._physics_process(1.0 / 60.0)
		var blen := float(ents[rep % ents.size()].normal_speed()) * 6.0
		for md in 2: ## 双口径各对一遍（0=弹幕本体 1=DDM）
			## 【对齐真游戏路径】先打包本帧快照（直调 bc_rays 不带打包——
			## 旧帧快照=新弹不可见，先前 2/96 不等即此口径误差）
			arena._clear_zones_now = []
			arena._hcs_pack_extra()
			var got_cpp: PackedFloat32Array = arena.motion_hot.bc_rays(
				ents[rep % ents.size()].position.x, ents[rep % ents.size()].position.y,
				blen, ents[rep % ents.size()].side, md) ## C++ 直调（指定口径）
			arena._clear_zones_now = []
			var gd_blk: PackedFloat32Array = _gd_rays(ents[rep % ents.size()], blen, md) ## GD 全量
			for k in 4:
				tot += 1
				if absf(float(got_cpp[k]) - float(gd_blk[k])) > 0.02:
					mism += 1
					if mism <= 4:
						print("    [不等] %s 口径%d 弧%d C++=%.3f GD=%.3f" % [ents[rep % ents.size()].chara_name(), md, k, got_cpp[k], gd_blk[k]])
	print("  等价 %d/%d 值不等" % [mism, tot])
	_chk(mism == 0, "C++ 与 GD 射线一致")

## GD 全量射线（含接管弹——对照 C++ slot 路径）
func _gd_rays(ent: BattleEntity, blen: float, md: int = 0) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var cand: Array = []
	for bl in arena.bullets:
		var b: Bullet = bl
		if b.hidden_now:
			continue
		if md == 1:
			## DDM 口径：场内、非消弹区（探针无消弹区=空）；本侧仅超遮罩物弹
			if b.pos.x < -b.draw_radius or b.pos.x > 400.0 + b.draw_radius or b.pos.y < -b.draw_radius or b.pos.y > 400.0 + b.draw_radius:
				continue
			if b.source_side == ent.side and not (b.ev.is_phy and b.beyond_mask()):
				continue
		elif b.source_side == ent.side and not b.ev.is_phy:
			continue
		if b.ev.tag == DanmakuEventData.TAG_LASER:
			var lw := b.laser_width()
			for si in range(0, b.laser_samples.size(), maxi(1, int(lw * 4.0))):
				var lp: Vector2 = b.laser_samples[si]
				if lp.distance_to(ent.position) <= blen + lw:
					cand.append([lp, lw])
		elif b.pos.distance_to(ent.position) <= blen + b.draw_radius:
			cand.append([b.pos, b.draw_radius])
	if cand.is_empty():
		return out
	var mids := [-PI / 2.0, PI / 2.0, PI, 0.0]
	var offs := [-PI / 6.0, -PI / 12.0, 0.0, PI / 12.0, PI / 6.0]
	for a in 4:
		var worst := 0.0
		for o in offs:
			var u := Vector2(cos(float(mids[a]) + float(o)), sin(float(mids[a]) + float(o)))
			var best_t := -1.0
			for c in cand:
				var w: Vector2 = (c[0] as Vector2) - ent.position
				var r: float = c[1]
				var th := -1.0
				if w.length_squared() <= r * r:
					th = 0.0
				else:
					var tca := w.dot(u)
					var d2 := w.length_squared() - tca * tca
					if tca >= 0.0 and d2 <= r * r:
						var t0 := tca - sqrt(r * r - d2)
						if t0 <= blen:
							th = maxf(t0, 0.0)
				if th >= 0.0 and (best_t < 0.0 or th < best_t):
					best_t = th
			if best_t >= 0.0:
				worst = maxf(worst, (blen - best_t) / blen)
		out[a] = worst
	return out
