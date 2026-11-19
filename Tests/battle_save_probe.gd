extends Node
## battle_save_probe —— 对战存档探针（m101 首版；m102 追加 E/F 两节）
## A. 保存→清空→读取→阵容+对战逻辑逐项一致（round-trip）
## B. 对战逻辑随档（logics 三步向导列表/formation/pp/spell）
## C. 坏档拒绝（非 JSON/kind 不符/结构缺项——且不半改现状）
## D. 列表接口（.thxb 枚举+按时间排序）
## E. 分侧读取（作者 20261120 二裁：仅我方/仅敌方——同一敌人不同我方做比较）
## F. 导入/导出（系统资源浏览器选中路径走同一入口；坏档导入拒绝）

func _ready() -> void:
	var fails := 0
	var gg = GameGlobals
	var probe_name := "probe_roundtrip.thxb"
	## 预清理：上次失败运行的探针残留（自愈——只动 probe_* 前缀，不碰作者存档）
	for s0 in gg.list_battle_saves():
		if str(s0["name"]).begins_with("probe_"):
			DirAccess.remove_absolute(str(s0["path"]))
	## 造一份配置
	gg.versus_player_team = ["MarisaA", "ReimuA", "", "Alice", ""]
	gg.versus_enemy_team = ["Rumia", "Suika"]
	gg.versus_chara_cfg = {
		"MarisaA": {
			"logics": [
				{"desc": "战场方位 · 对峙", "stance": "standoff", "stance_dist": 180.0,
					"metric": "hp_max", "aim": true, "volley": false, "cruise": false,
					"appeal_boost": 0.0, "avoid_phys_pair": false},
				{"desc": "攻击 · 齐射", "aim": true, "volley": true, "metric": "dist_min"},
			],
			"formation": "线列防护",
			"pp": 250,
			"spell": 3,
		},
		"Rumia": {"formation": "万岁突击", "pp": 80, "spell": 1},
	}
	## A/B. 保存→打乱→读取→比对
	var err: String = gg.save_battle_save(probe_name, gg.versus_player_team, gg.versus_enemy_team)
	if err != "":
		print("BSAVE_FAIL: A 保存报错 %s" % err)
		fails += 1
	## 清空现状（证明读取是整体替换）
	gg.versus_player_team = []
	gg.versus_enemy_team = []
	gg.versus_chara_cfg = {}
	err = gg.load_battle_save(probe_name)
	if err != "":
		print("BSAVE_FAIL: A 读取报错 %s" % err)
		fails += 1
	if gg.versus_player_team != ["MarisaA", "ReimuA", "", "Alice", ""]:
		fails += 1
		print("BSAVE_FAIL: A 我方阵容不一致 %s" % str(gg.versus_player_team))
	if gg.versus_enemy_team != ["Rumia", "Suika"]:
		fails += 1
		print("BSAVE_FAIL: A 敌方阵容不一致 %s" % str(gg.versus_enemy_team))
	var mcfg: Dictionary = gg.versus_chara_cfg.get("MarisaA", {})
	if int(mcfg.get("pp", -1)) != 250 or int(mcfg.get("spell", -1)) != 3 \
			or str(mcfg.get("formation", "")) != "线列防护" \
			or (mcfg.get("logics", []) as Array).size() != 2:
		fails += 1
		print("BSAVE_FAIL: B MarisaA 对战逻辑不一致 %s" % str(mcfg))
	var mlgics: Array = mcfg.get("logics", [])
	if mlgics.size() == 2 and (str(mlgics[1].get("desc", "")) != "攻击 · 齐射" \
			or not bool(mlgics[1].get("volley", false))):
		fails += 1
		print("BSAVE_FAIL: B 向导条目字段不一致 %s" % str(mlgics[1]))
	var rcfg: Dictionary = gg.versus_chara_cfg.get("Rumia", {})
	if int(rcfg.get("pp", -1)) != 80 or str(rcfg.get("formation", "")) != "万岁突击":
		fails += 1
		print("BSAVE_FAIL: B Rumia 对战逻辑不一致 %s" % str(rcfg))
	## A2. 文件名不带后缀也能读
	err = gg.load_battle_save("probe_roundtrip")
	if err != "":
		fails += 1
		print("BSAVE_FAIL: A2 无后缀名读取失败 %s" % err)
	## C. 坏档拒绝（三个口径）
	var bad := GameGlobals.BATTLE_SAVE_DIR.path_join("probe_bad.thxb")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("这不是 JSON{{{")
	f.close()
	var keep_p: Array = gg.versus_player_team
	var keep_c: Dictionary = gg.versus_chara_cfg
	err = gg.load_battle_save("probe_bad.thxb")
	if err == "" or gg.versus_player_team != keep_p or gg.versus_chara_cfg != keep_c:
		fails += 1
		print("BSAVE_FAIL: C1 非 JSON 未拒绝或半改现状 err=%s" % err)
	var f2 := FileAccess.open(bad, FileAccess.WRITE)
	f2.store_string(JSON.stringify({"kind": "别的什么", "player_team": [], "enemy_team": [], "chara_cfg": {}}))
	f2.close()
	err = gg.load_battle_save("probe_bad.thxb")
	if err == "":
		fails += 1
		print("BSAVE_FAIL: C2 kind 不符未拒绝")
	var f3 := FileAccess.open(bad, FileAccess.WRITE)
	f3.store_string(JSON.stringify({"kind": gg.BATTLE_SAVE_KIND, "player_team": [], "chara_cfg": {}}))
	f3.close()
	err = gg.load_battle_save("probe_bad.thxb")
	if err == "":
		fails += 1
		print("BSAVE_FAIL: C3 结构缺项未拒绝")
	err = gg.load_battle_save("probe_不存在.thxb")
	if err == "":
		fails += 1
		print("BSAVE_FAIL: C4 不存在的档未拒绝")
	## D. 列表
	var saves: Array = gg.list_battle_saves()
	var names: Array = []
	for s in saves:
		names.append(str(s["name"]))
	if not names.has("probe_roundtrip.thxb"):
		fails += 1
		print("BSAVE_FAIL: D 列表缺 probe_roundtrip.thxb %s" % str(names))
	## E. 分侧读取（作者 20261120 二裁：对同一敌人但我方情况不同做比较）
	## 注意：save_battle_save 取 GameGlobals.versus_chara_cfg 现值——先设态再存。
	## side1=全量档（我方 MarisaA/ReimuA+敌方 Rumia/Suika 各自 cfg）；
	## side2=我方换 Alice 且档内只有 Alice 的 cfg（敌方条目空——测清残留路径）。
	gg.versus_chara_cfg = {
		"MarisaA": {"pp": 100}, "ReimuA": {"pp": 110},
		"Rumia": {"pp": 80}, "Suika": {"formation": "万岁突击"},
	}
	var e1: String = gg.save_battle_save("probe_side1.thxb", ["MarisaA", "ReimuA"], ["Rumia", "Suika"])
	gg.versus_chara_cfg = {"Alice": {"pp": 300}}
	var e2: String = gg.save_battle_save("probe_side2.thxb", ["Alice"], ["Rumia", "Suika"])
	## 基线=side1 整体读（我方 MarisaA/ReimuA，敌方 Rumia/Suika，cfg 四条）
	err = gg.load_battle_save("probe_side1.thxb", "all")
	if err != "":
		fails += 1
		print("BSAVE_FAIL: E 基线读取报错 %s" % err)
	## E1 仅我方：side2 → 我方换 Alice，敌方阵容与 cfg 均不动；
	## 旧我方 MarisaA/ReimuA 换人=cfg 清掉，Alice 随档 300
	err = gg.load_battle_save("probe_side2.thxb", "player")
	if err != "":
		fails += 1
		print("BSAVE_FAIL: E 仅我方读取报错 %s" % err)
	if gg.versus_player_team != ["Alice"]:
		fails += 1
		print("BSAVE_FAIL: E 仅我方阵容未换 %s" % str(gg.versus_player_team))
	if gg.versus_enemy_team != ["Rumia", "Suika"]:
		fails += 1
		print("BSAVE_FAIL: E 敌方阵容被误动 %s" % str(gg.versus_enemy_team))
	if int(gg.versus_chara_cfg.get("Alice", {}).get("pp", -1)) != 300:
		fails += 1
		print("BSAVE_FAIL: E 新我方 cfg 未随档 %s" % str(gg.versus_chara_cfg))
	if gg.versus_chara_cfg.has("MarisaA") or gg.versus_chara_cfg.has("ReimuA"):
		fails += 1
		print("BSAVE_FAIL: E 旧我方残留未清 %s" % str(gg.versus_chara_cfg))
	if int(gg.versus_chara_cfg.get("Rumia", {}).get("pp", -1)) != 80 \
			or str(gg.versus_chara_cfg.get("Suika", {}).get("formation", "")) != "万岁突击":
		fails += 1
		print("BSAVE_FAIL: E 敌方 cfg 被误动 %s" % str(gg.versus_chara_cfg))
	## E2 仅敌方：side2 → 敌方阵容不变，但档内无 Rumia/Suika 条目=残留清掉；
	## 我方 Alice 与其 cfg 不动
	err = gg.load_battle_save("probe_side2.thxb", "enemy")
	if err != "":
		fails += 1
		print("BSAVE_FAIL: E2 仅敌方读取报错 %s" % err)
	if gg.versus_player_team != ["Alice"]:
		fails += 1
		print("BSAVE_FAIL: E2 我方被误动 %s" % str(gg.versus_player_team))
	if gg.versus_enemy_team != ["Rumia", "Suika"]:
		fails += 1
		print("BSAVE_FAIL: E2 敌方阵容不符 %s" % str(gg.versus_enemy_team))
	if gg.versus_chara_cfg.has("Rumia") or gg.versus_chara_cfg.has("Suika"):
		fails += 1
		print("BSAVE_FAIL: E2 敌方残留未清 %s" % str(gg.versus_chara_cfg))
	if int(gg.versus_chara_cfg.get("Alice", {}).get("pp", -1)) != 300:
		fails += 1
		print("BSAVE_FAIL: E2 我方 cfg 被误动 %s" % str(gg.versus_chara_cfg))
	## E3. 非法范围参数
	err = gg.load_battle_save("probe_side1.thxb", "middle")
	if err == "":
		fails += 1
		print("BSAVE_FAIL: E3 非法范围未拒绝")
	if e1 != "" or e2 != "":
		fails += 1
		print("BSAVE_FAIL: E 分侧保存报错 %s/%s" % [e1, e2])
	## F. 导入/导出（系统资源浏览器选中路径走同一入口——导出到固定文件夹之外）
	var ext_path: String = "user://probe_export_out.thxb"
	err = gg.export_battle_save("probe_side1", ext_path)
	if err != "":
		fails += 1
		print("BSAVE_FAIL: F 导出报错 %s" % err)
	if not FileAccess.file_exists(ext_path):
		fails += 1
		print("BSAVE_FAIL: F 导出文件缺失")
	err = gg.import_battle_save(ext_path)
	if err != "":
		fails += 1
		print("BSAVE_FAIL: F 导入报错 %s" % err)
	if not FileAccess.file_exists(String(gg.BATTLE_SAVE_DIR).path_join("probe_export_out.thxb")):
		fails += 1
		print("BSAVE_FAIL: F 导入未落盘 %s" % err)
	## 坏档导入拒绝（C3 把 bad 写成了 kind 合法——这里重写 kind 不符内容）
	var fbad := FileAccess.open(bad, FileAccess.WRITE)
	fbad.store_string(JSON.stringify({"kind": "别的什么", "player_team": [], "enemy_team": [], "chara_cfg": {}}))
	fbad.close()
	err = gg.import_battle_save(bad)
	if err == "":
		fails += 1
		print("BSAVE_FAIL: F 坏档导入未拒绝")
	## 清理探针档（不污染作者 user://）
	DirAccess.remove_absolute(GameGlobals.BATTLE_SAVE_DIR.path_join(probe_name))
	DirAccess.remove_absolute(bad)
	DirAccess.remove_absolute(GameGlobals.BATTLE_SAVE_DIR.path_join("probe_side1.thxb"))
	DirAccess.remove_absolute(GameGlobals.BATTLE_SAVE_DIR.path_join("probe_side2.thxb"))
	DirAccess.remove_absolute(GameGlobals.BATTLE_SAVE_DIR.path_join("probe_export_out.thxb"))
	DirAccess.remove_absolute(ext_path)
	var saves5: Array = gg.list_battle_saves()
	for s2 in saves5:
		if str(s2["name"]).begins_with("probe_"):
			fails += 1
			print("BSAVE_FAIL: 清理残留 %s" % str(s2["name"]))
	## 复原作者现状（探针只动了内存态）
	gg.versus_player_team = []
	gg.versus_enemy_team = []
	gg.versus_chara_cfg = {}
	if fails == 0:
		print("BSAVE_OK: 保存/读取/分侧读取/导入导出/坏档拒绝/列表 全过（阵容+对战逻辑 round-trip 一致）")
	get_tree().quit(1 if fails > 0 else 0)
