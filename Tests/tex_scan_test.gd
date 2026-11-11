extends Node
func _ready() -> void:
	print("[tex] DATA_BASE=", DanmakuTex.DATA_BASE)
	DanmakuTex._scan_official_once()
	print("[tex] direct scan _index=", DanmakuTex._official_index.size())
	print("[tex] ammos0 in index=", DanmakuTex._official_index.has("ammos0"))
	var tex := DanmakuTex.resolve("ammos0")
	print("[tex] resolve size=", tex.get_size())
	get_tree().quit()
