extends Node
## =============================================================
## 【m126 剧情桥（作者批复 20261126 四定案落地——autoload 形态）】
## Dialogic flag ↔ 游戏数据 三通道桥：
##   A flag ↔ GameGlobals：**独立变量表**（批复①——非 Dialogic 变量空间；
##     能被 Dialogic 调用即可=autoload 名 StoryBridge 直调
##     StoryBridge.set_flag(...) / get_flag(...)）
##   变化感知：**真信号**（批复②）——flag_changed(group, idx, value)
##   C 剧情→对战：**直接打开对战**（批复③——battle_request 写穿 versus_*
##     后 change_scene 到 battle_arena）；测试走 .thxt 存档（剧情按钮为时尚早）
##   难度（批复④）：**不同难度=弹幕表现不同的不同 thxe**——非古典档位；
##     本桥不设难度字段，难度=选用哪个 thxe/角色配置由剧情侧决定
## B 通道（场地规则快照）等 A 稳定后顺势接（清单 B 行）。
## =============================================================

signal flag_changed(group: String, idx: int, value: Variant) ## 批复②：变化感知信号

## —— A 通道：独立变量表（组名 → {序号 → 值}；组内后写覆盖先写——批复口径）——
var _flag_groups: Dictionary = {}

func set_flag(group: String, idx: int, value: Variant) -> void:
	if not _flag_groups.has(group):
		_flag_groups[group] = {}
	(_flag_groups[group] as Dictionary)[idx] = value
	flag_changed.emit(group, idx, value) ## 批复②：信号

func get_flag(group: String, idx: int, default: Variant = null) -> Variant:
	## 【m128】JSON int 键读回=字符串——双查适配（写=1 存档读回="1"）
	var g := (_flag_groups.get(group, {}) as Dictionary)
	return g.get(idx, g.get(str(idx), default))

func clear_group(group: String) -> void:
	_flag_groups.erase(group) ## "免除"=整组撤销

func has_flag(group: String, idx: int) -> bool:
	var g := (_flag_groups.get(group, {}) as Dictionary)
	return g.has(idx) or g.has(str(idx))

## —— C 通道：剧情→对决（批复③：直接打开对战）——
## cfg 形如 {"player_team": [...], "enemy_team": [...], "start_pp": 100,
##   "start_spell": 1}——缺省键不写穿（保留现行设定=叠加语义）；
## 难度不设字段（批复④=不同 thxe 内容体现）
func battle_request(cfg: Dictionary) -> void:
	var gg := get_node_or_null("/root/GameGlobals")
	if gg == null:
		push_warning("[剧情桥] GameGlobals 不可用——请求记档不生效")
		return
	if cfg.has("player_team"):
		gg.versus_player_team = cfg["player_team"]
	if cfg.has("enemy_team"):
		gg.versus_enemy_team = cfg["enemy_team"]
	if cfg.has("start_pp"):
		gg.versus_start_pp = int(cfg["start_pp"])
	if cfg.has("start_spell"):
		gg.versus_start_spell = int(cfg["start_spell"])
	print("[剧情桥] 对战请求写穿：%s → 进场" % str(cfg.keys()))
	get_tree().change_scene_to_file("res://scenes/battle_arena.tscn") ## 批复③：直接打开对战

## =============================================================
## 【m128 A/C 测试存档（作者令：本批次做 A/C 测试存档+测试面板）】
## 格式：<存档目录>/<名>.thxstory（JSON 明文）
## payload={"kind":"thx_story_save_v1","flags":{组:{序号:值}},"battle_cfg":{...}}
## 测试面板=story_test_panel（versus_menu「剧情桥测试」按钮打开）。
## 【存档目录降级链（m128 实测定案）】优先 user://storysaves；**写探针失败
## 自动降级 res://Tests/story_saves**（20261126 起作者机器对 Godot 进程写
## app_userdata 目录系统层拒绝——bash/res:// 可写、user:// 与 OS 绝对路径
## 全拒+假 0 返回=安全软件行为非代码问题；正式环境恢复后 user:// 优先）。
## =============================================================
var _story_dir := "" ## 惰性探测缓存

func story_dir() -> String:
	if _story_dir != "":
		return _story_dir
	DirAccess.make_dir_recursive_absolute("user://storysaves")
	var f := FileAccess.open("user://storysaves/_w.probe", FileAccess.WRITE)
	if f != null:
		f.close()
		DirAccess.remove_absolute("user://storysaves/_w.probe")
		_story_dir = "user://storysaves"
	else:
		DirAccess.make_dir_recursive_absolute("res://Tests/story_saves")
		_story_dir = "res://Tests/story_saves"
		push_warning("[剧情桥] user:// 不可写（进程级写拒）——存档降级 res://Tests/story_saves（开发期绕行）")
	return _story_dir

func save_story(path: String) -> bool:
	var payload := {"kind": "thx_story_save_v1", "flags": _flag_groups, "battle_cfg": _last_cfg}
	var dir := story_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	## user:// 前缀强制重定向 story_dir()（user:// 写拒降级——探针/调用方显式
	## 传 user:// 路径也落降级目录；res:// 显式尊重原位）
	var full := path if path.begins_with("res://") else dir.path_join(path.get_file())
	var f := FileAccess.open(full, FileAccess.WRITE)
	if f == null:
		push_warning("[剧情桥] 存档写失败：%s" % full)
		return false
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	print("[剧情桥] 存档已写：%s" % full)
	return true

func load_story(path: String) -> Dictionary:
	## 返回 battle_cfg（空字典=载入失败）；flag 组已回填 _flag_groups
	## 【m128】与 save 同源重定向（user:// 前缀落 story_dir——写拒降级配套）
	var full := path if path.begins_with("res://") else story_dir().path_join(path.get_file())
	if not FileAccess.file_exists(full):
		push_warning("[剧情桥] 存档不存在：%s" % full)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(full))
	if not (parsed is Dictionary) or str(parsed.get("kind", "")) != "thx_story_save_v1":
		push_warning("[剧情桥] 存档格式不符：%s" % full)
		return {}
	_flag_groups = parsed.get("flags", {})
	for g in _flag_groups:
		flag_changed.emit(str(g), -1, null) ## 组级回填通知
	_last_cfg = parsed.get("battle_cfg", {})
	print("[剧情桥] 存档已读：%s（flag 组 %d）" % [full, _flag_groups.size()])
	return _last_cfg

func apply_story(path: String) -> void:
	## C 通道一站式：读档 → battle_request（写穿+进场）——测试面板主按钮
	var cfg := load_story(path)
	if not cfg.is_empty():
		battle_request(cfg)

var _last_cfg: Dictionary = {} ## 最近一次 battle_request/读档的 cfg（save_story 回写用）

func story_save_list() -> Array[String]:
	## 测试面板下拉：存档目录下全部 .thxstory
	var out: Array[String] = []
	var dir := DirAccess.open(story_dir())
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".thxstory"):
			out.append(f)
	out.sort()
	return out
