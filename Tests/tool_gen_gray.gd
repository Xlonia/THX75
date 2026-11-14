extends SceneTree
## 【m70 一次性工具】生成对比度 0 的符卡副本（灰卡独立资源——作者 20261115）：
## spell.PNG → 全像素=均值色（对比度 0）→ spell_gray.PNG
## 重跑：godot --headless --path . --script res://Tests/tool_gen_gray.gd
func _init() -> void:
	var img := Image.load_from_file("res://gameAssetBase/shooting/resource/spell.PNG")
	if img == null:
		push_error("[gray] spell.PNG 载入失败")
		quit(1)
		return
	var mean := Color(0, 0, 0, 0)
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			mean += img.get_pixel(x, y)
			n += 1
	mean = mean / float(maxi(n, 1))
	for y in img.get_height():
		for x in img.get_width():
			img.set_pixel(x, y, mean)
	img.save_png("res://gameAssetBase/shooting/resource/spell_gray.PNG")
	print("[gray] GRAY_OK ", img.get_size(), " mean=", mean)
	quit(0)
