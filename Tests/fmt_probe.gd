extends Node
func _ready() -> void:
	var f := RDTextureFormat.new()
	var props := []
	for p in f.get_property_list():
		var n: String = str(p.get("name", ""))
		if n.begins_with("script") or n.begins_with("resource") or n == "":
			continue
		props.append(n)
	print("RDTextureFormat props: ", props)
	print("default texture_type=", f.texture_type, " (2D_ARRAY=", RenderingDevice.TEXTURE_TYPE_2D_ARRAY, ")")
	f.array_layers = 256
	f.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	var rd = GameGlobals.arena_rendering_device()
	var zero := PackedByteArray()
	zero.resize(65536)
	var data := []
	for i in 256:
		data.append(zero)
	var tex := rd.texture_create(f, RDTextureView.new(), data)
	print("with type 2D_ARRAY: valid=", tex.is_valid())
	if tex.is_valid():
		var e := rd.texture_update(tex, 5, zero)
		print("layer5 update err=", e)
		rd.free_rid(tex)
	get_tree().quit(0)
