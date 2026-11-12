extends Node
## portrait_probe —— 选人界面贴图链实测（作者：Reimu/Marisa/Reisen 选人界面不显示）
func _ready() -> void:
	await get_tree().process_frame
	var vm: Control = (load("res://scenes/versus_menu.tscn") as PackedScene).instantiate()
	add_child(vm)
	await get_tree().process_frame
	await get_tree().process_frame
	## 模拟选 ReimuA/MarisaB/ReisenA → _set_team → 检查 TR.texture
	var trs: Array = vm._pick_tex_rects[0] ## 我方侧
	print("TR 数=%d" % trs.size())
	var picks_empty: Array[OptionButton] = []
	vm._set_team(picks_empty, ["ReimuA", "MarisaB", "ReisenA"], 0)
	await get_tree().process_frame
	for i in 3:
		var tr: TextureRect = trs[i] if i < trs.size() else null
		var t := tr.texture if tr != null else null
		print("  [%d] texture=%s" % [i, "无" if t == null else t.resource_path.get_file() if t.resource_path != "" else "(Atlas)" + str(t.atlas.resource_path.get_file() if t is AtlasTexture else "?")])
	## 直接 API 层
	for nm in ["ReimuA", "MarisaB", "ReisenA", "Youshio"]:
		var ct := CharaTex.get_chara(nm, "")
		print("  API %s → %s" % [nm, "空" if ct.is_empty() else String(ct["tex"].resource_path.get_file())])
	## 手选刷新验证：我方槽1 选第4项（metadata=ReimuA 附近角色）→emit→TR 刷新
	var pk: OptionButton = vm.player_picks[1]
	pk.select(3)
	pk.item_selected.emit(3)
	await get_tree().process_frame
	var nm3: String = str(pk.get_item_metadata(3))
	var ct3 := CharaTex.get_chara(nm3, "")
	var tr1: TextureRect = vm._pick_tex_rects[0][1]
	var expect_tex = ct3["tex"] if not ct3.is_empty() else null
	print("  %s 手选刷新（槽1→%s TR=%s）" % ["PASS" if tr1.texture == expect_tex else "FAIL", nm3, "有" if tr1.texture != null else "无"])
	print("PORTRAIT_DONE")
	get_tree().quit()
