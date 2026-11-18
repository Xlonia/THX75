extends Node
## mm_layout_probe v2 —— 单实例幂标值定位（transform/color 各自落在哪些 float）
func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.instance_count = 1
	var buf := PackedFloat32Array()
	buf.resize(12)
	for i in 12:
		buf[i] = float(i + 1) ## 1..12
	mm.buffer = buf
	var xf: Transform2D = mm.get_instance_transform_2d(0)
	var c: Color = mm.get_instance_color(0)
	print("xf=", xf)
	print("c=", c)
	print("M: X=(f%g,f%g) Y=(f%g,f%g) O=(f%g,f%g) | C=(f%g,f%g,f%g,f%g)" % [
		xf.x.x, xf.x.y, xf.y.x, xf.y.y, xf.origin.x, xf.origin.y,
		c.r, c.g, c.b, c.a])
	get_tree().quit(0)
