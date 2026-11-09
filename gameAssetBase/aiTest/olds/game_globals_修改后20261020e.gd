extends Node
## =============================================================
## GameGlobals —— 全局单例（project.godot autoload）
## 职责：
##   1. 弹幕事件池：官方数据（gameAssetBase/danmaku_event.csv）+ .thx mod 覆盖层
##   2. 自定义对战配置（versus_menu 填写 → battle_arena 读取）
##   3. 弹幕编辑器状态跨场景保持（editor_events / preview_event）
##   4. 场景路由 goto_scene
## -------------------------------------------------------------
## 【mod 加载运算流程】（对应策划文档《弹幕编辑器》.thx 结构）
##   ① _ready：载入官方 danmaku_event.csv → official_events
##   ② 扫描 res://mods 与 user://mods 下 *.thx（zip 包）
##   ③ 逐包读 danmaku_event.csv → DanmakuEventData.parse_csv_text
##   ④ texture/ 下材质字节流 → DanmakuTex.load_from_bytes（运行时材质缓存）
##   ⑤ 事件以 event_name 为键进 mod_events（后加载覆盖先加载）
## 查询优先级：mod_events > official_events（mod 覆盖官方同名事件）
## .thx 同时是『导出为官方数据』的交换格式：编辑器可把 .thx 内容
## 直接写回 gameAssetBase/，供作者开发期作为官方数据使用。
## =============================================================

## 【CSV 拆分（作者批复 2026-10-03）】每种运行方式一份 csv：
##   danmaku_event_regular.csv / _physical / _functed / _laser / _nodes
## 旧的单文件 danmaku_event.csv 兼容读取（老 mod/官方旧包仍可用）。
const OFFICIAL_EVENT_CSV := "res://gameAssetBase/danmaku_event.csv"
const OFFICIAL_EVENT_CSVS: Dictionary = {
	DanmakuEventData.TAG_REGULAR: "res://gameAssetBase/danmaku_event_regular.csv",
	DanmakuEventData.TAG_PHYSICAL: "res://gameAssetBase/danmaku_event_physical.csv",
	DanmakuEventData.TAG_FUNCTED: "res://gameAssetBase/danmaku_event_functed.csv",
	DanmakuEventData.TAG_LASER: "res://gameAssetBase/danmaku_event_laser.csv",
	DanmakuEventData.TAG_NODES: "res://gameAssetBase/danmaku_event_nodes.csv",
}
const MOD_DIRS: Array[String] = ["res://mods", "user://mods"]

## —— 弹幕事件池 ——
var official_events: Dictionary = {} ## event_name -> DanmakuEventData
var mod_events: Dictionary = {}      ## event_name -> DanmakuEventData（覆盖层）
var loaded_mods: Array[String] = []  ## 已加载 .thx 文件名（UI 展示用）
## 【批复 2026-10-01#5】_slot_cache 曾经存在过：把 "owner|slot" -> 事件数组
##   缓存起来避免每次查询全池扫描（性能优化意图）。但它在试炼场二次进入时
##   不失效，导致编辑器改完事件后仍读到旧数据（预览缓存陈旧缺陷）。
##   经查 get_slot_events 的调用频率极低（火控每300帧重建×实体数、编辑器
##   引用查询），全池扫描开销可忽略 → 按批复注释掉缓存逻辑，直接查询。
##   若未来查询频率上升需要缓存，务必在 _on_preview 处 invalidate。

## —— 自定义对战配置（第①期：队伍战 5~6角色+5×5杂兵/侧）——
var versus_player_name := "MarisaA"
var versus_enemy_name := "ReimuA"
var versus_player_team: Array = [] ## 我方角色名列表（空=默认队伍）
var versus_enemy_team: Array = []  ## 敌方角色名列表（空=默认队伍）
var versus_privates_per_char := 5  ## 每角色杂兵数（demo 5×5）
var versus_start_pp := 100        ## 决斗开始 P 点（作者批复#7：默认100）
var versus_volley := "rotate"     ## "rotate"=轮射 / "salvo"=齐射
var arena_mode := "versus"        ## "versus" / "preview"

## —— 弹幕编辑器跨场景状态 ——
var editor_events: Array[DanmakuEventData] = [] ## 编辑器当前事件列表
var editor_textures: Dictionary = {}            ## 材质名 -> PackedByteArray（导入的材质）
var editor_timelines: Array = []
var mod_timelines: Dictionary = {}    ## mod 时间轴注册表（名→TimelineData）
var official_timelines: Dictionary = {} ## 官方时间轴注册表（名→TimelineData）                ## Array[TimelineData]（能力/符卡时间轴，②期）
var preview_event_name := ""                    ## 试炼场要发射的事件名

func _ready() -> void:
	_disable_dialogic_input()
	_load_key_config()
	## 【20261003】关闭子窗口内嵌：编辑器/弹幕显示浮窗 = 真 OS 窗口
	## （内嵌模式下"独立窗口"画进主窗口、超出部分被裁剪——底栏按钮消失的根源）
	if get_tree() != null and get_tree().root != null:
		get_tree().root.gui_embed_subwindows = false
	_load_official()
	## 自动加载全部 mod（第0期简化；后续版本做 mod 勾选界面）
	for path in scan_mod_files():
		var n := load_thx(path)
		if not n.is_empty():
			loaded_mods.append(path.get_file())

## 【性能·实测热点修复】作者 2026-10-02 剖面导出（debug10021025.csv）显示
## Dialogic 输入链路（subsystem_input::is_input_blocked 等）为全场最大耗时项，
## 而游戏当前无任何剧情对话——在剧情系统接入前全局关闭其输入轮询。
## 剧情模式实装时在此恢复（set_process_input(true)）。
func _disable_dialogic_input() -> void:
	var dlg := get_node_or_null("/root/Dialogic")
	if dlg == null:
		return
	var inputs: Node = dlg.get("Inputs")
	if inputs != null:
		inputs.set_process_input(false)
		inputs.set_process_unhandled_input(false)

## 官方事件表（编辑器“导出为官方数据”的产物）
## 【修复 20261020】优先读五份分表（OFFICIAL_EVENT_CSVS——导出实际写在这里），
## 缺省回退遗留单文件。旧实现只读单文件：分表是 56 列新表头、单文件是含 owner
## 的旧表头——按名取列的单文件行错位（demo_aimed speed=0 的根因），且编辑器
## 导出的数据对战从来读不到。
func _load_official() -> void:
	var loaded := false
	for path in OFFICIAL_EVENT_CSVS.values():
		if not FileAccess.file_exists(path):
			continue
		loaded = true
		for ev in DanmakuEventData.parse_csv_text(FileAccess.get_file_as_string(path)):
			ev.compile()
			## 【20261020】同名先到先得（regular→physical→…表序）——不同分表
			## 存在同名事件时后表不再覆盖（曾致 demo_aimed 被物理表同名行顶掉）
			if not official_events.has(ev.event_name):
				official_events[ev.event_name] = ev
	if loaded:
		return
	if not FileAccess.file_exists(OFFICIAL_EVENT_CSV):
		return
	var text := FileAccess.get_file_as_string(OFFICIAL_EVENT_CSV)
	for ev in DanmakuEventData.parse_csv_text(text):
		ev.compile()
		official_events[ev.event_name] = ev

## 【根治 20261020】编辑器工作集 → 官方五分表 静默同步：
## 新建/编辑的弹幕事件本体只有写进分表才能跨场景、跨重启存活
## （此前只有手动"导出为官方数据"才落盘——角色列表写了名字、
## 事件本体却没写，重启后按名解析不到=不出弹，作者两次复现的根因）。
func sync_official_events(events: Array, exclude_names: PackedStringArray = PackedStringArray()) -> void:
	## 【合并式 20261020】工作集优先（同名覆盖），但不清除分表既有事件——
	## "新建"等会重建工作集的操作不得抹掉盘上其它弹幕（防数据损失）
	var existing: Array[DanmakuEventData] = []
	for path in OFFICIAL_EVENT_CSVS.values():
		if FileAccess.file_exists(path):
			existing.append_array(DanmakuEventData.parse_csv_text(FileAccess.get_file_as_string(path)))
	var merged := {}
	for ev: DanmakuEventData in existing:
		if not exclude_names.has(ev.event_name):
			merged[ev.event_name] = ev
	for ev: DanmakuEventData in events:
		if exclude_names.has(ev.event_name):
			continue
		## 【20261020】同名同标签→工作集覆盖（作者编辑）；同名不同标签→先到先得
		## （不同分表的同名行互不覆盖——曾致物理版数据写进 regular 文件的污染）
		var cur: DanmakuEventData = merged.get(ev.event_name)
		if cur == null or cur.tag == ev.tag:
			merged[ev.event_name] = ev
	var by_tag := {}
	for ev: DanmakuEventData in merged.values():
		if not by_tag.has(ev.tag):
			by_tag[ev.tag] = []
		by_tag[ev.tag].append(ev)
	for tag: String in OFFICIAL_EVENT_CSVS:
		var f := FileAccess.open(String(OFFICIAL_EVENT_CSVS[tag]), FileAccess.WRITE)
		if f == null:
			push_warning("[GameGlobals] 事件分表写入失败: " + str(OFFICIAL_EVENT_CSVS[tag]))
			continue
		var lines: Array[String] = [",".join(DanmakuEventData.CSV_HEADER)]
		for ev: DanmakuEventData in by_tag.get(tag, []):
			lines.append(ev.to_csv_row())
		f.store_string("
".join(lines) + "
")
		f.close()

## 【20261020】时间轴落盘（重命名等引用同步用；官方库存 gameAssetBase/timelines/）
func save_timeline_gd(tl: TimelineData) -> void:
	var dir := "res://gameAssetBase/timelines"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/" + tl.tl_name + ".gd", FileAccess.WRITE)
	if f == null:
		push_warning("[GameGlobals] 时间轴写入失败: " + tl.tl_name)
		return
	f.store_string(tl.to_gd())
	f.close()
	for i in editor_timelines.size():
		if editor_timelines[i] is TimelineData and editor_timelines[i].tl_name == tl.tl_name:
			editor_timelines[i] = tl
			break

## 扫描 mod 目录下全部 .thx（【A8】.thx.disabled 后缀=禁用，改名恢复；下次启动生效）
func scan_mod_files() -> Array[String]:
	var out: Array[String] = []
	for dir_path in MOD_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".thx.disabled"):
				loaded_mods.append(f + "（禁用）") ## 展示用；不加载
			elif f.ends_with(".thx"):
				out.append(dir_path.path_join(f))
			f = dir.get_next()
		dir.list_dir_end()
	return out

## 加载一个 .thx → 返回成功载入的事件名列表
func load_thx(path: String) -> Array[String]:
	var names: Array[String] = []
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		push_warning("[GameGlobals] 无法打开 .thx：%s" % path)
		return names
	## ① danmaku_event.csv → 事件池
	if zr.get_files().has("danmaku_event.csv"):
		var text := zr.read_file("danmaku_event.csv").get_string_from_utf8()
		for ev in DanmakuEventData.parse_csv_text(text):
			ev.compile()
			mod_events[ev.event_name] = ev
			names.append(ev.event_name)
	## ② texture/ 材质 → 运行时材质缓存
	for f in zr.get_files():
		if f.begins_with("texture/"):
			var tex_name := f.get_file().get_basename()
			DanmakuTex.load_from_bytes(tex_name, zr.read_file(f))
	zr.close()
	return names

## 事件查询（mod 覆盖官方）
func get_event(event_name: String) -> DanmakuEventData:
	if mod_events.has(event_name):
		return mod_events[event_name]
	return official_events.get(event_name)

## 取某角色某火力槽的全部事件
## 优先级：编辑器事件（仅试炼场模式，实时改参可见）> mod > 官方；同名去重
## 【批复 2026-10-01#5】原 _slot_cache 逻辑已注释移除（见类头说明）——
##   旧代码：`if _slot_cache.has(key): return _slot_cache[key]` …
##   `_slot_cache[key] = out`（试炼场二次进入不失效 → 陈旧预览）。
func get_slot_events(owner_name: String, slot: String, row: Dictionary = {}) -> Array[DanmakuEventData]:
	## 【重写 20261020（作者批复）】角色弹幕分配=角色侧数据：Characters.csv 的
	## main_evs/sub_evs/rest_evs 三列（分号分隔的事件名列表）。
	## 事件按名解析：编辑器工作集 → Mod → 官方（工作集优先，去重）。
	## 旧的"事件 owner 标记绑定"逻辑全部废除（owner 列仅作数据兼容展示）；
	## '*' 通配不再产生任何绑定（根治"把所有弹幕都放了个遍"）。
	var out: Array[DanmakuEventData] = []
	if row.is_empty():
		row = CharaDB.get_by_name(owner_name)
	if row.is_empty():
		return out
	var col: String = {"main": "main_evs", "sub": "sub_evs", "rest": "rest_evs"}.get(slot, "")
	if col == "":
		return out
	for nm in String(row.get(col, "")).split(";", false):
		var ev_name: String = nm.strip_edges()
		if ev_name == "":
			continue
		var ev := resolve_event_by_name(ev_name)
		if ev != null:
			out.append(ev)
	return out

## 按事件名解析（编辑器工作集 → Mod → 官方）
func resolve_event_by_name(ev_name: String) -> DanmakuEventData:
	for ev: DanmakuEventData in editor_events:
		if ev.event_name == ev_name:
			return ev
	if mod_events.has(ev_name):
		return mod_events[ev_name]
	if official_events.has(ev_name):
		return official_events[ev_name]
	return null

## 能力/符卡时间轴事件（timeline_frame≥0，按帧排序）
func get_timeline_events(chara_name: String, slot: String, row: Dictionary = {}) -> Array[DanmakuEventData]:
	## 【重写 20261020】能力/符卡时间轴=角色侧列表：Characters.csv 的
	## skill_evs/spell_evs（分号分隔的【时间轴名】列表；每个时间轴 0.1秒一帧、
	## 每帧是弹幕事件列表——与火力点模型同构）。
	## 时间轴按名解析：编辑器工作集 → Mod → 官方；其 tick 内事件逐个返回
	## （事件需在编辑器工作集/官方池中有同名定义）。
	var out: Array[DanmakuEventData] = []
	var col: String = {"skill": "skill_evs", "spell": "spell_evs"}.get(slot, "")
	if col == "":
		return out
	if row.is_empty():
		row = CharaDB.get_by_name(chara_name)
	if row.is_empty():
		return out
	for tl_name in String(row.get(col, "")).split(";", false):
		var tl := resolve_timeline(tl_name.strip_edges())
		if tl == null:
			continue
		for tick in tl.ticks:
			for ev_name in tl.ticks[tick]:
				var ev := resolve_event_by_name(ev_name.strip_edges())
				if ev != null:
					out.append(ev)
	return out

## 按时间轴名解析（工作集 → Mod → 官方）
func resolve_timeline(tl_name: String) -> TimelineData:
	for tl: TimelineData in editor_timelines:
		if tl.tl_name == tl_name:
			return tl
	if mod_timelines.has(tl_name):
		return mod_timelines[tl_name]
	if official_timelines.has(tl_name):
		return official_timelines[tl_name]
	return null


## 事件池整体变更后清缓存（编辑器导出官方数据后调用）
## 【批复 2026-10-01#5】缓存已移除，本函数保留为兼容空操作（调用方不改动）
func invalidate_caches() -> void:
	pass

## 重载官方事件表（编辑器『导出为官方数据』后调用，即时生效）
func reload_official() -> void:
	official_events.clear()
	_load_official()
	invalidate_caches()

## —— 高火力演习（作者批复 2026-10-02：更恶劣情况演练 + 运行时覆写验证）——
## 把官方事件复制一份覆写进 mod 池：repeat_freq+2（更密）、range×2（存活更久），
## 以 mod_events 覆盖 official_events 的同名事件——正好验证
## "存档/运行时覆写原始弹幕参数"的完整链路。
var _stress_names: Array[String] = [] ## 本功能覆写过的事件名（关闭时还原）

func apply_stress_override(on: bool) -> void:
	if on:
		for ev: DanmakuEventData in official_events.values():
			var c := DanmakuEventData.new()
			c.from_csv_row(DanmakuEventData.split_csv_line(ev.to_csv_row()))
			c.repeat_freq = ev.repeat_freq + 2
			c.range_frames = ev.range_frames * 2
			mod_events[c.event_name] = c
			if not _stress_names.has(c.event_name):
				_stress_names.append(c.event_name)
	else:
		for n in _stress_names:
			mod_events.erase(n)
		_stress_names.clear()

## 统一场景跳转
func goto_scene(res_path: String) -> void:
	get_tree().change_scene_to_file(res_path)

## =============================================================
## 【内存泄漏修复（作者 2026-10-04：反复预览/弹幕显示 → 提交 11G 死机）】
## 战场每次实例化都 create_local_rendering_device() 新建整个本地 Vulkan
## 设备且从不释放——每次预览泄漏一个设备（驱动堆预留 GB 级提交）。
## 现改为全局共享单例设备（一次创建、常驻到退出、提交恒定）。
## =============================================================
var _arena_rd: RenderingDevice = null

func arena_rendering_device() -> RenderingDevice:
	if _arena_rd == null:
		_arena_rd = RenderingServer.create_local_rendering_device()
	return _arena_rd


## =============================================================
## 【批复 2026-10-13】键位设置：单功能键可用按钮修改；
## 双击类（W/S/A/D）与修饰键（Ctrl/Shift/Enter/Esc）暂不开放修改。
## 持久化：user://keybinds.cfg
## =============================================================
const KEY_DEFAULTS := {
	"增援": KEY_R, "自动增援": KEY_T, "早苗技能": KEY_H,
	"指定位置进攻": KEY_G, "指定位置防御": KEY_B,
	"轮射齐射切换": KEY_V,
	"热力图显示": KEY_F1, "选取高亮": KEY_F2, "弹幕图显示": KEY_F3,
}
const KEY_MODIFIABLE := ["增援", "自动增援", "早苗技能", "指定位置进攻", "指定位置防御",
	"轮射齐射切换", "热力图显示", "选取高亮", "弹幕图显示"]
var key_config: Dictionary = {}

func _load_key_config() -> void:
	key_config = KEY_DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load("user://keybinds.cfg") == OK:
		for k in KEY_MODIFIABLE:
			key_config[k] = int(cf.get_value("keys", k, key_config[k]))

func get_key(action: String) -> int:
	return int(key_config.get(action, KEY_DEFAULTS.get(action, 0)))

func set_key(action: String, keycode: int) -> void:
	key_config[action] = keycode
	var cf := ConfigFile.new()
	cf.load("user://keybinds.cfg") ## 已有项保留
	for k in KEY_MODIFIABLE:
		cf.set_value("keys", k, int(key_config.get(k, KEY_DEFAULTS.get(k, 0))))
	cf.save("user://keybinds.cfg")
