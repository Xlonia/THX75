extends Node
## ring_probe —— 判定圆失踪复现（m96-D 弧烘焙回归？）
## 烘焙→读回像素检查（白环是否真的画进纹理）
func _ready() -> void:
	var arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	for i in 8:
		arena._physics_process(1.0 / 60.0)
	print("arc_texes keys=", arena._arc_texes.keys())
	if arena._arc_texes.is_empty():
		print("RING_FAIL 烘焙字典空")
		get_tree().quit(1)
		return
	var t: Texture2D = arena._arc_texes[16]
	var img: Image = t.get_image()
	print("tex size=", img.get_size(), " format=", img.get_format())
	# 数非透明像素
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.1:
				n += 1
	print("非透明像素=%d（预期>200=环在）" % n)
	if n > 200:
		print("RING_OK")
	else:
		print("RING_FAIL 环为空")
	get_tree().quit(0)
