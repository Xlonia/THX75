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
	return (_flag_groups.get(group, {}) as Dictionary).get(idx, default)

func clear_group(group: String) -> void:
	_flag_groups.erase(group) ## "免除"=整组撤销

func has_flag(group: String, idx: int) -> bool:
	return (_flag_groups.get(group, {}) as Dictionary).has(idx)

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
