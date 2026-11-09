class_name CharaDB
extends RefCounted
## =============================================================
## 角色数据库（第①期：新增 poi 表达式列 + privates.csv + Enemy.csv）
## Characters.csv 列（作者已提供 poi 数据）：
##   ... Weapon_Muti, main_y, sub_x, sub_y,
##   main_poi_x, main_poi_y, sub_poi_x, sub_poi_y, Char_*, NameZH/JP/EN
## poi 列为表达式字符串（变量 wpcs/to_c），建议仅加减乘除
## Enemy.csv：敌方角色（无 ID/Team 列——不需接受队伍指挥，批复说明）
## privates.csv：杂兵（Name,Normal,Determine,Defend,NameZH/JP/EN）
## =============================================================

const CSV_PATH := "res://gameAssetBase/Characters.csv"
const ENEMY_CSV_PATH := "res://gameAssetBase/Enemy.csv"
const PRIVATES_CSV_PATH := "res://gameAssetBase/privates.csv"

const INT_COLS := ["Cruise", "Normal", "Determine", "Defend", "Mag", "Phy", "ID", "Team", "Main_Cd", "Sub_Cd"]
const FLOAT_COLS := ["Weapon_Muti", "Char_Raid", "Char_Allfire", "Char_Blitz", "Char_Cover", "Char_Elast", "Char_Delay", "Char_Feint",
	"main_para_rat", "main_seci_rat", "sub_para_rat"] ## 火力占比三列（作者 2026-10-03 提供）
const EXPR_COLS := ["main_y", "sub_x", "sub_y", "main_poi_x", "main_poi_y", "sub_poi_x", "sub_poi_y"] ## 可表达式（建议±*/）
const POI_VARS: PackedStringArray = ["wpcs", "to_c"]

static func load_all() -> Array[Dictionary]:
	return _load_csv(CSV_PATH, true)

static func load_enemies() -> Array[Dictionary]:
	return _load_csv(ENEMY_CSV_PATH, false)

static var _priv_cache: Array[Dictionary] = [] ## 【0.0.9·审计C2 20261108】privates.csv 重复读盘缓存（建队 10 次+每增援）
static func load_privates() -> Array[Dictionary]:
	if _priv_cache.is_empty():
		_priv_cache = _load_csv(PRIVATES_CSV_PATH, false)
	return _priv_cache

static func _load_csv(path: String, full: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[CharaDB] 表格无法读取：%s" % path)
		return out
	var header: PackedStringArray = []
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() == 0:
			continue
		var first: String = row[0].strip_edges()
		if first.is_empty() or first.begins_with("#"):
			continue
		if header.is_empty():
			header = row
			continue
		var d := {}
		for i in header.size():
			if i >= row.size() or header[i].is_empty():
				continue
			d[header[i]] = row[i] if i < row.size() else ""
		if full:
			_cast(d)
		out.append(d)
	file.close()
	return out

static func _cast(d: Dictionary) -> Dictionary:
	for k in INT_COLS:
		d[k] = int(String(d.get(k, "0")).to_float())
	for k in FLOAT_COLS:
		d[k] = String(d.get(k, "0")).to_float()
	## poi 列保持字符串（表达式），缺失补 "0"
	for k in EXPR_COLS:
		var raw := String(d.get(k, "0")).strip_edges()
		d[k] = raw if not raw.is_empty() else "0"
	return d

## 列默认值表（作者批复 2026-10-03：事故丢失/不可用的数据拟默认值）
## 数值列→合理零值；性格默认 0.2（无偏好）；poi/修改值→"0"；名称→占位
const COL_DEFAULTS := {
	"Cruise": "3", "Normal": "2", "Determine": "3", "Defend": "1",
	"Mag": "0", "Phy": "0", "ID": "0", "Team": "0",
	"Main_Cd": "4", "Sub_Cd": "2", "Weapon_Muti": "1",
	"main_y": "0", "sub_x": "0", "sub_y": "0",
	"main_poi_x": "0", "main_poi_y": "0", "sub_poi_x": "0", "sub_poi_y": "0",
	"Char_Raid": "0.2", "Char_Allfire": "0.2", "Char_Blitz": "0.2", "Char_Cover": "0.2",
	"Char_Elast": "0.2", "Char_Delay": "0.2", "Char_Feint": "0.2",
	"main_para_rat": "0.3", "main_seci_rat": "0.3", "sub_para_rat": "0.3",
	"NameZH": "未命名", "NameJP": "未命名", "NameEN": "Unnamed",
}

## 取列值：缺失/无效（数值列填了非数字、非法负值）→ 拟默认值
static func _cell_or_default(row: Dictionary, key: String) -> String:
	var raw := str(row.get(key, "")).strip_edges()
	var dflt: String = COL_DEFAULTS.get(key, "")
	if raw.is_empty():
		return dflt
	if key in INT_COLS or key in FLOAT_COLS:
		if not raw.is_valid_float():
			return dflt ## 不可用的值 → 默认
		if raw.to_float() < 0.0:
			return dflt ## 非法负值（全部数值列均非负语义，ID/Team=0 合法）→ 默认
	return raw

## 【20261003】写回单个角色行（编辑器角色页）：仅替换该行，其余原样保留；
## 字段值经 CSV 转义（poi 表达式可含逗号）。成功返回 true。
static func save_row(chara_name: String, row: Dictionary) -> bool:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[CharaDB] 无法读取：%s" % CSV_PATH)
		return false
	var header_line := ""
	var header: PackedStringArray = []
	var body: Array[String] = []
	while not f.eof_reached():
		var line := f.get_line()
		if header.is_empty() and line.strip_edges().replace("﻿", "").begins_with("Name"):
			header_line = line ## 表头原样写回（含 BOM/原始格式）
			header = line.split(",")
			continue
		body.append(line)
	f.close()
	if header.is_empty():
		return false
	## 【自愈 20261020】角色弹幕列表列缺失时补入表头（写侧迁移——
	## 防旧表无列时绑定数据被丢弃；新建表头含列的文件原样）
	var need := ["main_evs", "sub_evs", "rest_evs", "skill_evs", "spell_evs"]
	var hdr_keys := []
	for h in header:
		hdr_keys.append(String(h).strip_edges().replace("﻿", ""))
	for nk in need:
		if not hdr_keys.has(nk):
			header.append(nk)
			header_line = header_line + "," + nk
	var new_cells := PackedStringArray()
	for h in header:
		## 注意 BOM：表头首列可能是 "﻿Name"，查字典前必须剥掉
		var key := String(h).strip_edges().replace("﻿", "")
		if key.is_empty():
			new_cells.append("")
		else:
			## 【20261003】缺失/无效的值拟默认值（含 Name 首列兜底）
			var v := _cell_or_default(row, key)
			if key == "Name" and v.is_empty():
				v = chara_name
			new_cells.append(_csv_cell(v))
	var target := -1
	for i in body.size():
		var line := body[i]
		if line.strip_edges().is_empty():
			continue
		if line.split(",")[0].strip_edges().replace("﻿", "") == chara_name:
			target = i
			break
	if target < 0:
		return false
	body[target] = ",".join(new_cells)
	while not body.is_empty() and body[body.size() - 1].strip_edges().is_empty():
		body.pop_back() ## get_line 的 eof 特性会多出一个尾随空行，写回前剥掉
	var w := FileAccess.open(CSV_PATH, FileAccess.WRITE)
	if w == null:
		return false
	w.store_line(header_line) ## 【修复 20261003】表头必须写回（旧版丢失 → 全表变称号）
	for line in body:
		w.store_line(line)
	w.close()
	return true

static func _csv_cell(v) -> String:
	var s := str(v)
	if s.contains(",") or s.contains("\""):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s

static func get_by_name(chara_name: String) -> Dictionary:
	for d in load_all():
		if d["Name"] == chara_name:
			return d
	return {}

## 【杂兵编辑+弹幕分配 20261020】私兵行保存（编辑器杂兵页用；表头自愈含 shoot_evs）
const PRIVATES_REQUIRED := ["ShootCd", "shoot_evs"]
static func save_private_row(private_name: String, row: Dictionary) -> bool:
	var f := FileAccess.open(PRIVATES_CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[CharaDB] 无法读取：%s" % PRIVATES_CSV_PATH)
		return false
	var header_line := ""
	var header: PackedStringArray = []
	var body: Array[String] = []
	while not f.eof_reached():
		var line := f.get_line()
		if header.is_empty() and line.strip_edges().replace("﻿", "").begins_with("Name"):
			header_line = line
			header = line.split(",")
			continue
		body.append(line)
	f.close()
	if header.is_empty():
		return false
	## 表头自愈：缺列自动补（ShootCd/shoot_evs）
	var hdr_keys := []
	for h in header:
		hdr_keys.append(String(h).strip_edges().replace("﻿", ""))
	for nk in PRIVATES_REQUIRED:
		if not hdr_keys.has(nk):
			header.append(nk)
			header_line = header_line + "," + nk
	var new_cells := PackedStringArray()
	for h in header:
		var key := String(h).strip_edges().replace("﻿", "")
		if key.is_empty():
			new_cells.append("")
		else:
			var v := _cell_or_default(row, key)
			if key == "Name" and v.is_empty():
				v = private_name
			new_cells.append(_csv_cell(v))
	var target := -1
	for i in body.size():
		var cells := body[i].split(",")
		if cells.size() > 0 and cells[0].strip_edges() == private_name:
			target = i
			break
	var line2 := ",".join(new_cells)
	if target >= 0:
		body[target] = line2
	else:
		body.append(line2)
	var w := FileAccess.open(PRIVATES_CSV_PATH, FileAccess.WRITE)
	if w == null:
		push_error("[CharaDB] 无法写入：%s" % PRIVATES_CSV_PATH)
		return false
	w.store_string(header_line + "
")
	for b in body:
		if b.strip_edges() != "":
			w.store_string(b + "
")
	w.close()
	return true

static func get_private_by_name(n: String) -> Dictionary:
	for d in load_privates():
		if d["Name"] == n:
			return d
	return {}

static func get_enemy_by_name(n: String) -> Dictionary:
	for d in load_enemies():
		if d["Name"] == n:
			return d
	return {}

## poi 表达式编译工具（FireControl 复用；错误返回 null）
static func compile_poi(row: Dictionary, col: String) -> DanmakuExpr:
	var raw := String(row.get(col, "0")).strip_edges()
	if raw.is_empty():
		raw = "0"
	var e := DanmakuExpr.new()
	if not e.compile(raw, POI_VARS):
		return null
	return e
