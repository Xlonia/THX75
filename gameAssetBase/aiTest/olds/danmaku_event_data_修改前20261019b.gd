class_name DanmakuEventData
extends RefCounted
## =============================================================
## 弹幕事件数据（第①期扩充，对齐作者批复与新版编辑器文档）
## 新增列（相对0期）：x_offset y_offset saturation hue lost_if laser_n_step
## 变更（批复确认）：
##   rate 语义：rate_roll<=rate 释放（randf()<rate 即释放）
##   pattern：pattern_roll+=pattern；命题为真时 减一；rate 与 pattern 均为真才释放
##   color_render 更名 saturation（HSL之S）；新增 hue（HSL之H）；亮度=隐藏 lightness
##   槽位：wing → sub（僚机=次要武器，作者：wing可以不用了）
##   激光：x/y 表达式 + n(k) 遍历换元；range=xy渲染像素规模；材质=单像素线条
## 【damage_arr 消歧义（作者批复）】所有弹幕父类提交 damage_arr=[dmg,nis]，
##   nis∈{n,i,s}小写单字符；不同容器注册不同伤害弹幕图。
## =============================================================

const TAG_REGULAR := "IsDanmakuRegular"
const TAG_PHYSICAL := "IsDanmakuPhysical"
const TAG_FUNCTED := "IsDanmakuFuncted"
const TAG_LASER := "IsDanmakuLaser"
const TAG_NODES := "Nodes"
const TAGS: Array[String] = [TAG_REGULAR, TAG_PHYSICAL, TAG_FUNCTED, TAG_LASER, TAG_NODES]

const MODE_NORMAL := "N"
const MODE_IMPALE := "I"
const MODE_SPALLING := "S"
const MODES: Array[String] = [MODE_NORMAL, MODE_IMPALE, MODE_SPALLING]

## 火力槽（第①期：sub 取代 wing）
const SLOT_MAIN := "main"
const SLOT_SUB := "sub"
const SLOT_REST := "rest"
const SLOT_SKILL := "skill"
const SLOT_SPELL := "spell"
const SLOTS: Array[String] = [SLOT_MAIN, SLOT_SUB, SLOT_REST, SLOT_SKILL, SLOT_SPELL]

## 表达式变量表（①期基础；20261003 + d=目标距离向量模长）
## 【20261015·语义修订（作者：弹幕编辑器-新）】t/t_r/rate_roll/pattern_roll 为
## "弹幕在运行时返回的变量"（原"弹幕自变量"有歧义）——只读、可在运动表达式引用、
## 不可手动设定；新增 rotate_id（旋转副本标号，同为运行时返回）。
const EXPR_VARS: PackedStringArray = [
	"t", "t_r", "rate_roll", "pattern_roll", "r0", "r1", "n", "d",
	"rotate_id",
	"wpcs", "to_c", "main_lr", "sub_lr",
	"self_x", "self_y", "self_ap", "self_pp", "self_normal",
	"target_x", "target_y", "target_ap", "target_pp", "target_normal",
	"target_hpweapon", "target_hpbody", "target_hpmove",
	"field_t", "field_phase",
]

## CSV 表头（54列；20261002 +laser_render_scale=47；20261015 尾部追加 rotate_* 7列
## ——【教训】新列只允许尾部追加，禁止中段插入（曾因插列导致整行字段移位事故）
const CSV_HEADER: PackedStringArray = [
	"event_name", "owner", "slot", "timeline_frame", "tag",
	"texture", "color", "saturation", "hue", "alpha", "pass",
	"repeat_time", "repeat_freq", "range", "is_abs_coord",
	"dmg", "dmg_mode", "dmg_allow_moderate", "rate", "pattern", "danmaku_size_muti",
	"is_phy", "is_cannon", "x_offset", "y_offset",
	"speed", "x", "y", "func",
	"alarm", "alarm_shader_alpha", "laser_n_step", "laser_render_scale",
	"targe", "targe_offsetx", "targe_offsety",
	"acc", "turn_arg", "speed_max", "lost_max", "lost_min", "lost_if",
	"explode_condit", "release_condit", "explode", "release", "can_destroy",
	"oob_mode",
	"rotate_range", "rotate_div", "rotate_rate", "rotate_offset",
	"rotate_sequence", "rotate_pingpong", "rotate_delay",
]

## —— 元数据 ——
var event_name := "demodanmaku1"
var owner := "*"
var slot := SLOT_REST
var timeline_frame := -1
var tag := TAG_REGULAR

## —— 通用参数 ——
var texture := "tama0"
var color := "#ffffff"         ## 兼容列：HSL 十六进制（编辑器主用 hue/saturation）
var saturation := 1.0          ## HSL 之 S（原 color_render）
var hue := 0.0                 ## HSL 之 H（0~1）
var alpha := "256"
var pass_cond := ""
## 【语义修订（弹幕编辑器-新 20261015）】repeat_time=副本重复间隔（原"持续时间"歧义）；
## repeat_freq=重复发射次数（0=禁用）
var repeat_time := 0
var repeat_freq := 0
var range_frames := 300
var is_abs_coord := false
var dmg := 1
var dmg_mode := MODE_NORMAL
var dmg_allow_moderate := true
var rate := 0.0                ## 语义（批复#11）：rate_roll<=rate 释放
var rate_specified := false
var pattern := 0.0             ## 命题为真时 减一（批复#11）
var pattern_specified := false
var danmaku_size_muti := 1.0
var is_phy := false
var is_cannon := false
var x_offset := 0.0            ## 弹幕相对火力点起始x（物弹遮罩起点；批复新增）
var y_offset := 0.0            ## 弹幕相对火力点起始y（同上）

## —— 分类型参数 ——
var speed := ""
var x := ""
var y := ""
var func_expr := ""
var alarm := 0
var alarm_shader_alpha := 1.0  ## 预警期不透明度比值（数值或表达式，20261003 可变）
var laser_n_step := 1          ## n(数值)：激光遍历采样频率（每几像素采样）
var laser_render_scale := 1.0  ## 渲染规模（1像素线材质缩放；数值或表达式，20261003 可变）
## 表达式原文（非数值时保存；compile() 编译为 ex_asa/ex_lrs）
var alarm_shader_alpha_s := ""
var laser_render_scale_s := ""
var targe := ""
var targe_offsetx := 0.0
var targe_offsety := 0.0
var acc := 0.0
var turn_arg := 0.0
var speed_max := 0.0
var lost_max := 0.0
var lost_min := 0.0
var lost_if := ""              ## 命题：真=暂时失锁（批复新增）
var explode_condit := ""
var release_condit := ""
var explode := ""
var release := ""
var can_destroy := false
## 【批复 2026-10-13·A7】出界处理：0=出界销毁（默认；超画布 400±弹实际大小即毁）
## 1=出界后反射（回马枪/反弹类）2=出界不处理（保守）
var oob_mode := 0

## —— 通用弹幕旋转重复参数（弹幕编辑器-新 20261015；列在 CSV 尾部）——
## 【数据类型（作者批复 20261019）】
##   rotate_range / rotate_offset：表达式，计算结果为浮点值
##   rotate_div / rotate_rate：表达式，计算结果为整数（浮点结果向下取整）
##   rotate_pingpong：表达式或命题（数字向下取整；真命题=1 假命题=0）
##   ——与弹幕运行表达式同体系：可以是单个数字，支持局部/外部变量；
##   释放时刻求值一次。rotate_delay 保持普通整数（帧）。
## rotate_range：旋转散布范围（弧度，两侧之和，合法最高 π；≥π 视为全圆、从0°起分）
## rotate_div：旋转等分（0=不旋转重复，仅 rotate_offset 生效）
## rotate_rate：旋转重复总次数（0=按等分全部一次；>等分时按步序循环）
## rotate_offset：旋转偏差（弧度，全体副本附加）
## rotate_sequence：时序方式 cw/ccw/mid_sync/mid_left/mid_right
## rotate_pingpong：回弹基数（0=不回弹；id 命中非零倍数→反序剩余）
## rotate_delay：旋转重复时间延时（帧；0=全部同帧）
var rotate_range := "0"
var rotate_div := "0"
var rotate_rate := "0"
var rotate_offset := "0"
var rotate_sequence := "cw"
var rotate_pingpong := "0"
var rotate_delay := 0

## —— 编译期缓存（20261003：每发弹幕不再重复扫描 27变量×11表达式）——
var ctx_keys_used: PackedStringArray = [] ## 本事件表达式实际引用的变量全集
var motion_time_bound := false            ## 普通/物理弹的 x/y/speed 是否依赖 t/t_r（否=可冻结）
var laser_time_bound := false             ## 瞬时类 x/y 是否依赖 t（否=几何一次成型）

## —— 编译后的表达式 ——
var ex_alpha: DanmakuExpr = null
var ex_pass: DanmakuExpr = null
var ex_speed: DanmakuExpr = null
var ex_x: DanmakuExpr = null
var ex_y: DanmakuExpr = null
var ex_func: DanmakuExpr = null
var ex_hue: DanmakuExpr = null
var ex_sat: DanmakuExpr = null
var ex_lost_if: DanmakuExpr = null
var ex_asa: DanmakuExpr = null  ## 预警期不透明度比值（表达式）
var ex_lrs: DanmakuExpr = null  ## 激光渲染规模（表达式）
var ex_explode: DanmakuExpr = null
var ex_release: DanmakuExpr = null
## 旋转重复参数表达式（20261019：range/offset 浮点式、div/rate 整式、pingpong 式/命题）
var ex_rrot_range: DanmakuExpr = null
var ex_rrot_div: DanmakuExpr = null
var ex_rrot_rate: DanmakuExpr = null
var ex_rrot_offset: DanmakuExpr = null
var ex_rrot_pp: DanmakuExpr = null

## =============================================================
## 通用弹幕旋转重复（弹幕编辑器-新 20261015；类型修订 20261019）
##   目的：一个事件实现东方原作道中常见的弧形/扇形/"之"字形等散布。
##   rp = eval_rotate_params(ctx) 的结果字典：
##     {range: float, div: int, rate: int, offset: float, pp: float, seq: String}
##   rotate_positions：角度副本位置（相对事件原始方向的偏差，弧度）
##     - div=0 → 仅原始方向（旋转不发生，offset 仍生效）
##     - range≥π → 全圆：div 个副本从 0° 起分（首尾边缘不重复）
##     - 其余 → div 等分 → div+1 条边缘（含左右边缘）
##   rotate_steps：释放步序；每步=同时释放的 [位置序号, rotate_id] 列表
##     id 编号随时序方式：cw 左缘0顺数 / ccw 右缘0逆数 / 中间系中线0向两侧、左侧先编号
##   rotate_release_plan：rate 循环行走 + 回弹基数（id 命中非零倍数→反序剩余）
##   纯静态无副作用——战场发射与编辑器预览共用，smoke 直测。
## =============================================================
const ROT_SEQS: Array[String] = ["cw", "ccw", "mid_sync", "mid_left", "mid_right"]

## 释放时刻求值一次（作者批复 20261019：与弹幕运行表达式同体系——
## 单个数字即常量式；range/offset 取浮点、div/rate 向下取整为整数、
## pingpong 数字取整/命题真1假0——命题求值即 0/1 浮点，取整后同义）
func eval_rotate_params(ctx: Dictionary) -> Dictionary:
	var rng := ex_rrot_range.execute_dict(ctx, 0.0) if ex_rrot_range != null else _raw_f(rotate_range)
	var off := ex_rrot_offset.execute_dict(ctx, 0.0) if ex_rrot_offset != null else _raw_f(rotate_offset)
	var div := ex_rrot_div.execute_dict(ctx, 0.0) if ex_rrot_div != null else _raw_f(rotate_div)
	var rate := ex_rrot_rate.execute_dict(ctx, 0.0) if ex_rrot_rate != null else _raw_f(rotate_rate)
	var pp := ex_rrot_pp.execute_dict(ctx, 0.0) if ex_rrot_pp != null else _raw_f(rotate_pingpong)
	return {
		"range": maxf(0.0, rng),
		"offset": off,
		"div": maxi(0, int(floor(div))),
		"rate": maxi(0, int(floor(rate))),
		"pp": maxf(0.0, floor(pp)),
		"seq": rotate_sequence if ROT_SEQS.has(rotate_sequence) else "cw",
	}

static func _raw_f(s: String) -> float:
	var t := s.strip_edges()
	return t.to_float() if t != "" else 0.0

static func rotate_positions(rp: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d: int = int(rp.get("div", 0))
	var rng: float = float(rp.get("range", 0.0))
	if d <= 0:
		out.append(0.0)
		return out
	if rng >= PI:
		for k in d: ## 全圆：等分从 0° 起，不重复首尾边缘
			out.append(float(k) * rng / float(d))
	else:
		for k in d + 1: ## 扇形：d 等分 → d+1 条边缘
			out.append(-rng * 0.5 + float(k) * rng / float(d))
	return out

static func rotate_steps(rp: Dictionary) -> Array:
	var pos := rotate_positions(rp)
	var n := pos.size()
	if n <= 0:
		return []
	var seq: String = rp.get("seq", "cw")
	var steps: Array = []
	if seq == "cw":
		for k in n:
			steps.append([[k, k]])
	elif seq == "ccw":
		for k in n:
			steps.append([[n - 1 - k, k]])
	else:
		var m_idx := int(floor(float(n - 1) / 2.0))
		var has_mid := n % 2 == 1
		var j0 := 1 if has_mid else 0
		if has_mid:
			steps.append([[m_idx, 0]]) ## 过中线的未旋转副本 id=0
		for j in range(j0, m_idx + 1):
			var lid := 2 * (j - j0) + 1 ## 左侧先编号（解决奇数等分无中线副本的编号）
			var left := m_idx - j
			var right := (m_idx + j) if has_mid else (m_idx + 1 + j)
			if seq == "mid_sync":
				steps.append([[left, lid], [right, lid + 1]]) ## 同数字时序并列
			elif seq == "mid_left":
				steps.append([[left, lid]])
				steps.append([[right, lid + 1]])
			else: ## mid_right
				steps.append([[right, lid + 1]])
				steps.append([[left, lid]])
	return steps

static func _step_hits_pingpong(step: Array, p_base: int) -> bool:
	for pair in step:
		var id: int = int(pair[1])
		if id > 0 and posmod(id, p_base) == 0:
			return true
	return false

static func _steps_total(steps: Array) -> int:
	var n := 0
	for s in steps:
		n += (s as Array).size()
	return n

## 释放计划：plan[i] = 第 i 步同时释放的 [[位置序号, rotate_id], ...]
## rate>0 → 总释放数=rate（步序耗尽后循环）；否则全部位置一次
static func rotate_release_plan(rp: Dictionary) -> Array:
	var steps: Array = rotate_steps(rp)
	if steps.is_empty():
		return []
	var p_base := int(float(rp.get("pp", 0.0)))
	var total: int = int(rp.get("rate", 0)) if int(rp.get("rate", 0)) > 0 else _steps_total(steps)
	var remaining: Array = []
	var out: Array = []
	for i in total:
		if remaining.is_empty():
			remaining = steps.duplicate(true)
		var nxt: Array = remaining[0]
		if p_base > 0 and _step_hits_pingpong(nxt, p_base):
			remaining.reverse() ## 回弹：命中倍数即反序剩余（先发者不变）
		out.append(remaining[0])
		remaining.remove_at(0)
	return out

## =============================================================
## CSV ⇄ 对象
## =============================================================

static func split_csv_line(line: String) -> PackedStringArray:
	var cells: PackedStringArray = []
	var cur := ""
	var in_quotes := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if in_quotes:
			if c == "\"":
				if i + 1 < line.length() and line[i + 1] == "\"":
					cur += "\""
					i += 1
				else:
					in_quotes = false
			else:
				cur += c
		else:
			if c == "\"":
				in_quotes = true
			elif c == ",":
				cells.append(cur)
				cur = ""
			else:
				cur += c
		i += 1
	cells.append(cur)
	return cells

static func csv_escape(v) -> String:
	var s := str(v)
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s

static func parse_csv_text(text: String) -> Array[DanmakuEventData]:
	var out: Array[DanmakuEventData] = []
	var lines := text.split("\n", false)
	for li in lines.size():
		var line: String = lines[li].strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("event_name"):
			continue
		var cells := split_csv_line(line)
		var ev := DanmakuEventData.new()
		if ev.from_csv_row(cells) == OK:
			out.append(ev)
		else:
			push_warning("[DanmakuEventData] 第 %d 行解析失败，已跳过" % (li + 1))
	return out

func from_csv_row(cells: PackedStringArray) -> Error:
	if cells.is_empty() or cells[0].strip_edges().is_empty():
		return FAILED
	var idx := {}
	for i in CSV_HEADER.size():
		idx[CSV_HEADER[i]] = i
	event_name = _s(cells, idx, "event_name", "demodanmaku1")
	owner = _s(cells, idx, "owner", "*")
	var sl := _s(cells, idx, "slot", SLOT_REST)
	if sl == "wing":
		sl = SLOT_SUB ## 旧数据兼容：wing→sub
	slot = sl
	timeline_frame = _i(cells, idx, "timeline_frame", -1)
	var tg := _s(cells, idx, "tag", TAG_REGULAR)
	if TAGS.has(tg):
		tag = tg
	texture = _s(cells, idx, "texture", "tama0")
	color = _s(cells, idx, "color", "#ffffff")
	saturation = _f(cells, idx, "saturation", 1.0)
	hue = _f(cells, idx, "hue", 0.0)
	alpha = _s(cells, idx, "alpha", "256")
	pass_cond = _s(cells, idx, "pass", "")
	repeat_time = _i(cells, idx, "repeat_time", 0)
	repeat_freq = _i(cells, idx, "repeat_freq", 0)
	range_frames = _i(cells, idx, "range", 300)
	is_abs_coord = _b(cells, idx, "is_abs_coord", false)
	dmg = _i(cells, idx, "dmg", 1)
	var dm := _s(cells, idx, "dmg_mode", MODE_NORMAL)
	if MODES.has(dm):
		dmg_mode = dm
	dmg_allow_moderate = _b(cells, idx, "dmg_allow_moderate", true)
	rate_specified = _has(cells, idx, "rate") and _s(cells, idx, "rate", "") != ""
	rate = _f(cells, idx, "rate", 0.0)
	pattern_specified = _has(cells, idx, "pattern") and _s(cells, idx, "pattern", "") != ""
	pattern = _f(cells, idx, "pattern", 0.0)
	danmaku_size_muti = _f(cells, idx, "danmaku_size_muti", 1.0)
	is_phy = _b(cells, idx, "is_phy", false)
	is_cannon = _b(cells, idx, "is_cannon", false)
	x_offset = _f(cells, idx, "x_offset", 0.0)
	y_offset = _f(cells, idx, "y_offset", 0.0)
	speed = _s(cells, idx, "speed", "")
	x = _s(cells, idx, "x", "")
	y = _s(cells, idx, "y", "")
	func_expr = _s(cells, idx, "func", "")
	alarm = _i(cells, idx, "alarm", 0)
	## 激光参数可变（作者批复 20261003）：数值或表达式
	alarm_shader_alpha_s = _s(cells, idx, "alarm_shader_alpha", "")
	if alarm_shader_alpha_s.is_valid_float():
		alarm_shader_alpha = maxf(0.0, alarm_shader_alpha_s.to_float())
		alarm_shader_alpha_s = ""
	else:
		alarm_shader_alpha = 1.0
	laser_n_step = maxi(1, _i(cells, idx, "laser_n_step", 1))
	laser_render_scale_s = _s(cells, idx, "laser_render_scale", "")
	if laser_render_scale_s.is_valid_float():
		laser_render_scale = maxf(0.5, laser_render_scale_s.to_float())
		laser_render_scale_s = ""
	else:
		laser_render_scale = 1.0
	targe = _s(cells, idx, "targe", "")
	targe_offsetx = _f(cells, idx, "targe_offsetx", 0.0)
	targe_offsety = _f(cells, idx, "targe_offsety", 0.0)
	acc = _f(cells, idx, "acc", 0.0)
	turn_arg = _f(cells, idx, "turn_arg", 0.0)
	speed_max = _f(cells, idx, "speed_max", 0.0)
	lost_max = _f(cells, idx, "lost_max", 0.0)
	lost_min = _f(cells, idx, "lost_min", 0.0)
	lost_if = _s(cells, idx, "lost_if", "")
	explode_condit = _s(cells, idx, "explode_condit", "")
	release_condit = _s(cells, idx, "release_condit", "")
	explode = _s(cells, idx, "explode", "")
	release = _s(cells, idx, "release", "")
	can_destroy = _b(cells, idx, "can_destroy", false)
	oob_mode = clampi(_i(cells, idx, "oob_mode", 0), 0, 2)
	## 旋转重复（20261015 列尾追加；20261019 起为表达式原文——数字即退化为常量式）
	rotate_range = _expr_cell(cells, idx, "rotate_range")
	rotate_div = _expr_cell(cells, idx, "rotate_div")
	rotate_rate = _expr_cell(cells, idx, "rotate_rate")
	rotate_offset = _expr_cell(cells, idx, "rotate_offset")
	var sq := _s(cells, idx, "rotate_sequence", "cw")
	rotate_sequence = sq if ROT_SEQS.has(sq) else "cw"
	rotate_pingpong = _expr_cell(cells, idx, "rotate_pingpong")
	rotate_delay = maxi(0, _i(cells, idx, "rotate_delay", 0))
	return OK

## 表达式列取原文（空缺/旧布尔 true 视为 "1"——20261015 曾用布尔语义）
static func _expr_cell(cells: PackedStringArray, idx: Dictionary, col: String) -> String:
	var s := _s(cells, idx, col, "")
	if s == "":
		return "0"
	if s in ["true", "TRUE", "True"]:
		return "1"
	return s

func to_csv_row() -> String:
	var vals := [
		event_name, owner, slot, timeline_frame, tag,
		texture, color, saturation, hue, alpha, pass_cond,
		repeat_time, repeat_freq, range_frames, int(is_abs_coord),
		dmg, dmg_mode, int(dmg_allow_moderate),
		(_num(rate) if rate_specified else ""), (_num(pattern) if pattern_specified else ""),
		danmaku_size_muti, int(is_phy), int(is_cannon), x_offset, y_offset,
		speed, x, y, func_expr,
		alarm, (alarm_shader_alpha_s if alarm_shader_alpha_s != "" else _num(alarm_shader_alpha)),
		laser_n_step, (laser_render_scale_s if laser_render_scale_s != "" else _num(laser_render_scale)),
		targe, targe_offsetx, targe_offsety,
		acc, turn_arg, speed_max, lost_max, lost_min, lost_if,
		explode_condit, release_condit, explode, release, int(can_destroy), oob_mode,
		rotate_range, rotate_div, rotate_rate, rotate_offset,
		rotate_sequence, rotate_pingpong, rotate_delay,
	]
	var parts: Array[String] = []
	for v in vals:
		parts.append(csv_escape(v))
	return ",".join(parts)

static func build_csv(events: Array[DanmakuEventData]) -> String:
	var lines: Array[String] = []
	lines.append(",".join(CSV_HEADER))
	for e in events:
		lines.append(e.to_csv_row())
	return "\n".join(lines) + "\n"

## =============================================================
## 表达式编译
## =============================================================
func compile() -> Array[String]:
	var errs: Array[String] = []
	ex_alpha = _compile_one(alpha, errs, "alpha")
	ex_pass = _compile_one(pass_cond, errs, "pass")
	ex_speed = _compile_one(speed, errs, "speed")
	ex_x = _compile_one(x, errs, "x")
	ex_y = _compile_one(y, errs, "y")
	ex_func = _compile_one(func_expr, errs, "func")
	ex_hue = _compile_one(_expr_str(hue), errs, "hue") if _is_expr_str(hue) else null
	ex_sat = _compile_one(_expr_str(saturation), errs, "saturation") if _is_expr_str(saturation) else null
	ex_lost_if = _compile_one(lost_if, errs, "lost_if")
	## 激光参数表达式（作者批复：透明度与渲染规模可变）
	ex_asa = _compile_one(alarm_shader_alpha_s, errs, "alarm_shader_alpha") if alarm_shader_alpha_s != "" else null
	ex_lrs = _compile_one(laser_render_scale_s, errs, "laser_render_scale") if laser_render_scale_s != "" else null
	ex_explode = _compile_one(explode_condit, errs, "explode_condit")
	ex_release = _compile_one(release_condit, errs, "release_condit")
	## 旋转重复参数（20261019 表达式化）
	ex_rrot_range = _compile_one(rotate_range, errs, "rotate_range")
	ex_rrot_div = _compile_one(rotate_div, errs, "rotate_div")
	ex_rrot_rate = _compile_one(rotate_rate, errs, "rotate_rate")
	ex_rrot_offset = _compile_one(rotate_offset, errs, "rotate_offset")
	ex_rrot_pp = _compile_one(rotate_pingpong, errs, "rotate_pingpong")
	## 变量引用全集 + 运动时间依赖（供 Bullet 快照/冻结判定，事件级一次）
	var all_exprs: Array = [ex_alpha, ex_pass, ex_speed, ex_x, ex_y, ex_func,
		ex_hue, ex_sat, ex_lost_if, ex_explode, ex_release,
		ex_rrot_range, ex_rrot_div, ex_rrot_rate, ex_rrot_offset, ex_rrot_pp]
	ctx_keys_used.clear()
	## 激光动态重采样判定（20261004：仅 x/y 依赖 t 才每6帧重建；上限保护）
	laser_time_bound = false
	for e in [ex_x, ex_y]:
		if e != null and (e as DanmakuExpr).uses_variable("t"):
			laser_time_bound = true
			break
	for v in EXPR_VARS:
		for e in all_exprs:
			if e != null and (e as DanmakuExpr).uses_variable(v):
				ctx_keys_used.append(v)
				break
	motion_time_bound = false
	for e: DanmakuExpr in [ex_x, ex_y, ex_speed]:
		if e != null and (e.uses_variable("t") or e.uses_variable("t_r")):
			motion_time_bound = true
			break
	return errs

## hue/saturation 支持表达式（作者：这两个都是可变数值）
func _expr_str(v) -> String:
	return str(v)
func _is_expr_str(v) -> bool:
	var s := str(v).strip_edges()
	if s.is_empty():
		return false
	return not s.is_valid_float()

func _compile_one(text: String, errs: Array[String], field: String) -> DanmakuExpr:
	if text.strip_edges().is_empty():
		return null
	var e := DanmakuExpr.new()
	if not e.compile(text, EXPR_VARS):
		errs.append("%s「%s」表达式解析失败" % [event_name, field])
		return null
	return e

## =============================================================
## 取值辅助
## =============================================================
## 瞬时类当前伤害（照抄文档）：t∈[0,alarm] → -1；否则 min(16,dmg)
func laser_damage(t_now: int) -> int:
	if t_now <= alarm:
		return -1
	return mini(16, dmg)

## damage_arr 消歧义容器（作者批复）：[dmg, nis小写字符]
func damage_arr() -> Array:
	return [dmg, dmg_mode.to_lower()]

func display_label() -> String:
	return "%s [%s·%s·%s]" % [event_name, owner, slot, tag]

## —— CSV 单元格取值小工具 ——
static func _has(cells: PackedStringArray, idx: Dictionary, col: String) -> bool:
	return idx.has(col) and idx[col] < cells.size()
static func _s(cells: PackedStringArray, idx: Dictionary, col: String, d: String) -> String:
	if _has(cells, idx, col) and cells[idx[col]].strip_edges() != "":
		return cells[idx[col]].strip_edges()
	return d
static func _i(cells: PackedStringArray, idx: Dictionary, col: String, d: int) -> int:
	if _has(cells, idx, col) and cells[idx[col]].strip_edges() != "":
		return int(cells[idx[col]].to_float())
	return d
static func _f(cells: PackedStringArray, idx: Dictionary, col: String, d: float) -> float:
	if _has(cells, idx, col) and cells[idx[col]].strip_edges() != "":
		return cells[idx[col]].to_float()
	return d
static func _b(cells: PackedStringArray, idx: Dictionary, col: String, d: bool) -> bool:
	if _has(cells, idx, col) and cells[idx[col]].strip_edges() != "":
		return cells[idx[col]].strip_edges() in ["1", "true", "TRUE", "True"]
	return d
static func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return str(v)
