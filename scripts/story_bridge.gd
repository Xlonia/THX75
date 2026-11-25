class_name StoryBridge
extends RefCounted
## =============================================================
## 【m126 剧情桥骨架（1122 目标书 C 项——剧情对接桥接层）】
## Dialogic flag ↔ 游戏数据 三通道桥（作者"尽力"项——本文件=骨架+清单，
## 细接等作者 Dialogic 侧约定（flag 命名/变量空间/触发时机）后填实现）。
## 三通道（对应 20261126_剧情桥接清单.md）：
##   A flag ↔ GameGlobals：故事进度开关（道具/元件=开关——作者批复 20261121
##     "按序号+优先级组叠加/覆盖/免除"）
##   B flag ↔ 场地规则：剧情场次开场时写 field_rules 快照（支援框等）
##   C flag ↔ 对战配置：剧情→对决（阵容/难度/P 点/符卡数写 versus_* → 进场）
## 【Dialogic 挂接点（待作者约定后实装）】
##   - Dialogic 启动时注入本桥（autoload 或单一入口）
##   - flag 变化事件 → set_flag（Dialogic variable changed 信号或轮询）
##   - 战斗请求 → battle_request（Dialogic event 命令或剧情脚本调）
## 本桥不依赖 Dialogic：纯静态 flag 存储 + 写穿函数（Dialogic 侧适配后接）。
## =============================================================

## —— A 通道：故事 flag 存储（序号+优先级组：组内后写覆盖先写；"免除"=组删除）——
## flags 结构：组名 → {序号 → 值}（作者批复口径的"序号+优先级组叠加/覆盖/免除"）
static var _flag_groups: Dictionary = {}

static func set_flag(group: String, idx: int, value: Variant) -> void:
	if not _flag_groups.has(group):
		_flag_groups[group] = {}
	(_flag_groups[group] as Dictionary)[idx] = value ## 组内后写覆盖先写

static func get_flag(group: String, idx: int, default: Variant = null) -> Variant:
	return (_flag_groups.get(group, {}) as Dictionary).get(idx, default)

static func clear_group(group: String) -> void:
	_flag_groups.erase(group) ## "免除"=整组撤销

static func has_flag(group: String, idx: int) -> bool:
	return (_flag_groups.get(group, {}) as Dictionary).has(idx)

## —— C 通道：剧情→对决（写穿 GameGlobals versus_*；进场由宿主路由）——
## cfg 形如 {"player_team": [...], "enemy_team": [...], "start_pp": 100,
##   "start_spell": 1, "field_rules_csv": "user://story_3_rules.csv"}
## 约定：cfg 缺省键不写穿（保留现行设定——叠加语义）
static func battle_request(cfg: Dictionary) -> void:
	var gg := _globals()
	if gg == null:
		push_warning("[剧情桥] GameGlobals 不可用（非宿主环境）——请求记档不生效")
		return
	if cfg.has("player_team"):
		gg.versus_player_team = cfg["player_team"]
	if cfg.has("enemy_team"):
		gg.versus_enemy_team = cfg["enemy_team"]
	if cfg.has("start_pp"):
		gg.versus_start_pp = int(cfg["start_pp"])
	if cfg.has("start_spell"):
		gg.versus_start_spell = int(cfg["start_spell"])
	print("[剧情桥] 对战请求写穿：%s" % str(cfg.keys()))

static func _globals() -> Node:
	var gg := Engine.get_main_loop() as SceneTree
	return gg.root.get_node_or_null("/root/GameGlobals") if gg != null else null
