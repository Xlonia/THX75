extends Node
## heat_source_probe —— Ht 高点三层对账探针（0.0.9 作者批·不默认开启）
##   每次对账：Ht 回读找高点 → 对每高点三层分类
##   A=Ht白+DDM白+有弹（正常：弹在显示在热在）
##   B=Ht白+DDM白+无弹（幽灵 stamp——弹已被消除/移除但 DDM 仍 stamp）
##   C=Ht白+DDM黑（Ht 自身残留——摊入/衰减尾巴，与 DDM 无关）
##   输出三类计数+样本位置+（B 类）stamp 表中该位置印章的 w 编码
var arena: Node2D
var step := 0
func _ready() -> void:
	GameGlobals.arena_mode = "versus"
	GameGlobals.contour_edge_px = 8
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
func _process(_d: float) -> void:
	step += 1
	if step >= 360:
		_reconcile()
		get_tree().quit(0)
func _reconcile() -> void:
	print("========================================")
	print("HEAT_SOURCE_PROBE frame=%d 弹=%d" % [step, arena.bullets.size()])
	## Ht 回读（我方视角 front）
	var ht: HeatmapField = arena.ht_side[0]
	var ht_data: PackedByteArray = arena.shared_rd.texture_get_data(ht.front_rid(), 0)
	var ht_img := Image.create_from_data(400, 400, false, Image.FORMAT_R8, ht_data)
	## DDM 回读
	var ddm_data: PackedByteArray = arena.shared_rd.texture_get_data(arena.ddm_gpu0.image_rid(), 0)
	var ddm_img := Image.create_from_data(400, 400, false, Image.FORMAT_R8, ddm_data)
	## stamps 快照（当前导出缓冲）
	var stamps0: PackedFloat32Array = arena._stamp_buf0
	var stamps1: PackedFloat32Array = arena._stamp_buf1
	## 高点扫描（64 联通块质心——简化：64 值网格 8×8 块聚类）
	var visited := {}
	var classes := {"A": 0, "B": 0, "C": 0}
	var samples: Array = []
	for y0 in range(0, 400, 8):
		for x0 in range(0, 400, 8):
			var key := Vector2i(x0, y0)
			if visited.has(key):
				continue
			## 8×8 块峰值
			var peak := 0.0
			var peak_p := Vector2.ZERO
			for dy in 8:
				for dx in 8:
					var v: float = ht_img.get_pixel(mini(x0 + dx, 399), mini(y0 + dy, 399)).r * 255.0
					if v > peak:
						peak = v
						peak_p = Vector2(x0 + dx, y0 + dy)
			if peak < 64.0:
				continue
			## 三层判定
			var ddm_v: float = ddm_img.get_pixel(int(peak_p.x), int(peak_p.y)).r * 255.0
			var has_bullet := false
			var bullet_desc := ""
			for b in arena.bullets:
				if b.pos.distance_to(peak_p) < 16.0 and not b.hidden_now:
					has_bullet = true
					bullet_desc = "%s d%d side%d" % [b.ev.event_name, b.depth, b.source_side]
					break
			## stamp 表中该位置印章（±10px）
			var has_stamp := false
			var stamp_w := -1.0
			for buf in [stamps0, stamps1]:
				var i := 0
				while i + 3 < buf.size():
					if Vector2(buf[i], buf[i + 1]).distance_to(peak_p) < 10.0:
						has_stamp = true
						stamp_w = buf[i + 3]
						break
					i += 4
			var cls := "A"
			if ddm_v > 32.0:
				cls = "A" if has_bullet else "B"
			else:
				cls = "C"
			classes[cls] += 1
			if cls != "A" and samples.size() < 10:
				samples.append("p=%s ht=%.0f ddm=%.0f 弹=%s stamp=%s w=%.3f" % [
					str(peak_p), peak, ddm_v, bullet_desc if bullet_desc != "" else "无",
					str(has_stamp), stamp_w])
	print("分类：A(正常)=%d B(幽灵stamp)=%d C(Ht残留)=%d" % [classes["A"], classes["B"], classes["C"]])
	for s in samples:
		print("  ", s)
	print("========================================")
