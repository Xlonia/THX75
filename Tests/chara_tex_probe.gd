extends Node
## chara_tex_probe —— 选人贴图侦查（作者：部分角色不显示）
func _ready() -> void:
	## 等 GameGlobals（autoload）推送 DATA_BASE 完成
	await get_tree().process_frame
	var chars: Array = CharaDB.load_all()
	print("角色表 %d 行" % chars.size())
	for row in chars:
		var nm := str(row.get("Name", ""))
		var zh := str(row.get("NameZH", ""))
		var ct := CharaTex.get_chara(nm, zh)
		if ct.is_empty():
			print("  [缺] %s(%s)" % [nm, zh])
		else:
			var t: Texture2D = ct["tex"]
			print("  [有] %s(%s) → %s %d帧" % [nm, zh, t.resource_path.get_file(), int(ct["frames"])])
	print("PROBE_DONE")
	get_tree().quit()
