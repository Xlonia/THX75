extends Node
## m128_probe —— 剧情桥 A/C 存档 + thx manifest 实包探针
## A. StoryBridge：flag 写读回环/信号/组清除
## B. .thxstory：save→load 回环（flag 组+ battle_cfg 保真）
## C. battle_request：写穿 versus_*（不切场景——探针环境无 GameGlobals 场景路由）
## D. load_thx manifest：实包（Tests/manifest_demo.thx）装载+事件入池+注册警告路径
func _ready() -> void:
	var fails := 0
	var sb := get_node_or_null("/root/StoryBridge")
	if sb == null:
		print("M128_FAIL: StoryBridge autoload 缺席")
		print("M128_FAIL")
		get_tree().quit()
		return
	## A. flag 写读回环+信号
	var sig_seen := []
	sb.flag_changed.connect(func(g, i, v): sig_seen.append([g, i, v]))
	sb.set_flag("demo", 1, "序章完成")
	sb.set_flag("demo", 2, true)
	sb.set_flag("demo", 3, 42)
	if sb.get_flag("demo", 1) != "序章完成" or sb.get_flag("demo", 2) != true or sb.get_flag("demo", 3) != 42:
		fails += 1
		print("M128_FAIL: A flag 写读回环不符")
	if sig_seen.size() != 3:
		fails += 1
		print("M128_FAIL: A2 信号未收到 %d" % sig_seen.size())
	sb.clear_group("demo")
	if sb.has_flag("demo", 1):
		fails += 1
		print("M128_FAIL: A3 组清除未生效")
	sb.set_flag("demo", 1, "回填") ## 重铺（B 节存档保真用）
	## B. .thxstory 存档回环
	sb._last_cfg = {"player_team": ["MarisaA", "ReimuA"], "enemy_team": ["Rumia"], "start_pp": 77, "start_spell": 2}
	if not sb.save_story("user://storysaves/probe.thxstory"):
		fails += 1
		print("M128_FAIL: B 存档写失败")
	sb._flag_groups = {} ## 清内存态
	sb.set_flag("x", 0, "毒") ## 噪声
	var cfg: Dictionary = sb.load_story("user://storysaves/probe.thxstory")
	if cfg.is_empty() or int(cfg.get("start_pp", 0)) != 77 or int(cfg.get("start_spell", 0)) != 2:
		fails += 1
		print("M128_FAIL: B2 battle_cfg 保真不符")
	if sb.get_flag("demo", 1) != "回填" or sb.has_flag("x", 0):
		fails += 1
		print("M128_FAIL: B3 flag 回填/噪声清除不符")
	## C. battle_request 写穿（探针环境 GameGlobals autoload 在=真写穿）
	var gg := get_node_or_null("/root/GameGlobals")
	var pp0: int = gg.versus_start_pp if gg != null else -999
	sb._last_cfg = {"start_pp": 123, "start_spell": 2}
	sb.battle_request({"start_pp": 123, "start_spell": 2})
	if gg == null:
		print("M128_SKIP: C 无 GameGlobals（headless 纯内核环境）")
	elif gg.versus_start_pp != 123:
		fails += 1
		print("M128_FAIL: C 写穿不符（pp=%s 原=%d）" % [str(gg.versus_start_pp), pp0])
	else:
		print("M128_NOTE: C 写穿过（pp=%d——change_scene 在探针环境安全不执行切场）" % gg.versus_start_pp)
	## D. load_thx manifest 实包
	THXKit.mod_events.clear() ## 清池（防串档）
	var names: Array[String] = THXKit.load_thx("res://Tests/manifest_demo.thx")
	if names.size() < 1 or not THXKit.mod_events.has("demo_manifest_event"):
		fails += 1
		print("M128_FAIL: D 实包装载不符（%s）" % str(names))
	else:
		print("M128_NOTE: D 实包事件=%s（manifest plugins=[keshinozo] 已注册→无警告路径）" % str(names))
	var ids: Array = THXKit.content_plugin_ids()
	if not ids.has("keshinozo"):
		fails += 1
		print("M128_FAIL: D2 keshinozo 内容域未注册（%s）" % str(ids))
	if fails == 0:
		print("M128_OK")
	else:
		print("M128_FAIL: 共 %d" % fails)
	get_tree().quit()
