extends Node
## revive_probe —— 消弹后 DDM 白区"诈尸"追踪
##   触发一次符卡消弹 → 每 15 帧读 DDM 白像素数+质心 → 白区复活时
##   定位该位置的弹（事件名/来源/depth），锁定诈尸弹源
var arena: Node2D
var step := 0
var released := false
var release_pos := Vector2.ZERO
var last_white := 0
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
		var white := 0
		var cen := Vector2.ZERO
		for y in range(0, 400, 4):
			for x in range(0, 400, 4):
				if img.get_pixel(x, y).r > 0.3:
					white += 1
					cen += Vector2(x, y)
		if white > 0:
			cen /= float(white)
		print("[revive f=%d] 白采样点=%d（上次=%d） 质心=%s" % [step, white, last_white, str(cen)])
		if white > last_white + 20 and last_white <= 5:
			## 白区复活——定位该位置的弹
			print("  [诈尸] 白区复活于 %s——附近弹源：" % str(cen))
			for b in arena.bullets:
				if b.pos.distance_to(cen) < 60.0:
					print("    → %s depth=%d hidden=%s side=%d org=%s" % [
						b.ev.event_name, b.depth, str(b.hidden_now), b.source_side, str(b.origin)])
		last_white = white
	if step >= 900:
		print("REVIVE_DONE")
		get_tree().quit(0)
