extends Node
## revive_probe —— 消弹后 DDM 白区"诈尸"追踪
##   触发一次符卡消弹 → 每 15 帧读 DDM 白像素数+质心 → 白区复活时
##   定位该位置的弹（事件名/来源/depth），锁定诈尸弹源
## 【0.0.9·热-弹对齐 20261109】新增：每拍同口径统计监测区内敌弹数
##   （谱系 spawn_src）+ 外环热——"Ht 热存在而弹=0"的帧=热场侧伪影实锤
##   （扩散回填/残留）；"热有弹"帧=真弹幕（列谱系判定诈尸来源）
var arena: Node2D
var step := 0
var released := false
var release_pos := Vector2.ZERO
var last_white := 0
var pside := 0
func _ready() -> void:
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
func _process(_d: float) -> void:
	step += 1
	if step == 300: ## 5 秒后（铺场满）触发符卡消弹
		var p: BattleEntity = arena.player_leader
		if p != null:
			release_pos = p.position
			pside = p.side
			arena._apply_release(p, "s")
			released = true
			print("[revive] 符卡消弹触发 at %s" % str(release_pos))
		else:
			print("[revive] 无领队——中止")
			get_tree().quit(1)
	if released and step % 15 == 0:
		var ddm = arena.ddm_gpu0
		var raw: PackedByteArray = arena.shared_rd.texture_get_data(ddm.image_rid(), 0)
		var img: Image = Image.create_from_data(400, 400, false, Image.FORMAT_R8, raw)
		var ht: HeatmapField = arena.ht_side[0]
		var ht_raw: PackedByteArray = arena.shared_rd.texture_get_data(ht.front_rid(), 0)
		var ht_img := Image.create_from_data(400, 400, false, Image.FORMAT_R8, ht_raw)
		## 【局部口径】只统计消弹半径 100px 内的白点（排除敌方正常发射）
		var white := 0
		var ht_white := 0
		var ring_hot := 0
		var cen := Vector2.ZERO
		for y in range(0, 400, 4):
			for x in range(0, 400, 4):
				var pv := Vector2(x, y)
				var dst := pv.distance_to(release_pos)
				if dst >= 100.0:
					continue
				if dst >= 60.0:
					if ht_img.get_pixel(x, y).r * 255.0 > 24.0:
						ring_hot += 1 ## 外环热（扩散回填源强指标）
					continue
				if img.get_pixel(x, y).r > 0.3:
					white += 1
					cen += pv
				if ht_img.get_pixel(x, y).r * 255.0 > 24.0:
					ht_white += 1
		if white > 0:
			cen /= float(white)
		## 【热-弹对齐】监测区 60px 内敌弹清点（谱系）
		var es := 1 - pside
		var bl_in := 0
		var bl_desc := ""
		for b in arena.bullets:
			if b.source_side != es:
				continue
			if b.pos.distance_to(release_pos) <= 60.0:
				bl_in += 1
				if bl_desc.length() < 120:
					bl_desc += "%s(src=%s,hidden=%s) " % [b.ev.event_name, b.spawn_src, str(b.hidden_now)]
		var tag := ""
		if ht_white > 8 and bl_in == 0:
			tag = " ★热无弹（热场侧伪影：扩散回填/残留——无真弹幕）"
		elif bl_in > 0 and ht_white > 8:
			tag = " ○热有弹（真弹幕：%s）" % bl_desc.strip_edges()
		print("[revive f=%d] 核区DDM白=%d Ht热=%d 外环热=%d 弹=%d（上次DDM=%d） 质心=%s%s" % [
			step, white, ht_white, ring_hot, bl_in, last_white, str(cen), tag])
		if white > last_white + 10 and last_white <= 5:
			print("  [诈尸] 消弹区白区复活于 %s——附近弹源：" % str(cen))
			for b in arena.bullets:
				if b.pos.distance_to(cen) < 60.0:
					print("    → %s src=%s depth=%d hidden=%s side=%d t=%.0f" % [
						b.ev.event_name, b.spawn_src, b.depth, str(b.hidden_now), b.source_side, b.t])
		last_white = white
		## 【一次性源诊断】白区质心处弹=0 时，转储一切可能盖章源（全侧弹/
		## 激光几何/火炮/延时副本），锁定"无弹之章"的物理来源
		if white > 4 and bl_in == 0 and step in [330, 360, 420, 480]:
			print("  [源诊断 f=%d] 白质心=%s——全侧 40px 弹（含 is_phy/beyond）：" % [step, str(cen)])
			for b in arena.bullets:
				var near: float = b.pos.distance_to(cen)
				var geo_near := -1.0
				if b.ev.tag == DanmakuEventData.TAG_LASER and b.laser_samples.size() > 0:
					geo_near = 1e9
					for i2 in range(0, b.laser_samples.size(), 8):
						geo_near = minf(geo_near, (b.laser_samples[i2] as Vector2).distance_to(cen))
				if near <= 40.0 or (geo_near >= 0.0 and geo_near <= 40.0):
					print("    弹 %s tag=%s side=%s phy=%s beyond=%s pos=%s dist=%s geo=%s r=%s src=%s" % [
						b.ev.event_name, str(b.ev.tag), str(b.source_side), str(b.ev.is_phy),
						str(b.beyond_mask()), str(b.pos), str(snappedf(near, 0.1)),
						str(snappedf(geo_near, 0.1)), str(b.draw_radius), b.spawn_src])
			for c in arena._cannons:
				var oc: Vector2 = c.get("origin0", Vector2.INF)
				print("    炮 origin0=%s fired=%d/%s ev=%s" % [str(oc), int(c.get("fired", 0)), str(c.get("rpt", {}).get("freq", "?")), (c.get("ev") as DanmakuEventData).event_name])
			print("    pend=%d" % arena._rot_pend.size())
	if step >= 900:
		print("REVIVE_DONE")
		get_tree().quit(0)
