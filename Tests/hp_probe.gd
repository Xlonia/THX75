extends Node
## hp_probe —— Hp 地图"无法映射"破案探针（m111）
## 读回 fam_maps Hp 纹理统计非零像素：init 后/手动重跑 _warmup_hp 后对比
func _ready() -> void:
	var arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	for i in 90:
		arena._physics_process(1.0 / 60.0)
	print("loading_done=", not arena._loading, " fam_ok=", arena.fam_maps.ok if arena.fam_maps != null else "null")
	for side in 2:
		var t: Texture2D = arena.fam_maps.display("Hp" + str(side))
		var nz := -1
		if t != null:
			var img: Image = t.get_image()
			nz = 0
			for y in range(0, img.get_height(), 4):
				for x in range(0, img.get_width(), 4):
					if img.get_pixel(x, y).r > 0.01:
						nz += 1
		print("Hp%d 初读 非零采样=%d" % [side, nz])
	arena._warmup_hp()
	for side2 in 2:
		var t2: Texture2D = arena.fam_maps.display("Hp" + str(side2))
		var nz2 := -1
		if t2 != null:
			var img2: Image = t2.get_image()
			nz2 = 0
			for y2 in range(0, img2.get_height(), 4):
				for x2 in range(0, img2.get_width(), 4):
					if img2.get_pixel(x2, y2).r > 0.01:
						nz2 += 1
		print("Hp%d 重跑后 非零采样=%d" % [side2, nz2])
	get_tree().quit(0)
