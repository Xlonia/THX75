extends Node
func _ready() -> void:
	print("[A] CharaTex.DATA_BASE=", CharaTex.DATA_BASE)
	print("[A] CharaTex._dir_scanned=", CharaTex._dir_scanned, " _stem_map=", CharaTex._stem_map.size())
	var ct := CharaTex.get_chara("Youshio", "晚汐")
	print("[A] Youshio ct=", "有" if not ct.is_empty() else "无", " path=", ct.get("tex").resource_path if not ct.is_empty() and ct.get("tex") != null else "?")
	print("[B] DanmakuTex.DATA_BASE=", DanmakuTex.DATA_BASE, " scanned=", DanmakuTex._official_scanned, " index=", DanmakuTex._official_index.size())
	print("[B] ammos0 resolve=", DanmakuTex.resolve("ammos0") != null and DanmakuTex.resolve("ammos0").get_size())
	## GameGlobals shim 的 OFFICIAL_EVENT_CSVS（编辑器读这组）
	print("[C] shim CSV paths=", GameGlobals.OFFICIAL_EVENT_CSVS.values()[0])
	get_tree().quit()
