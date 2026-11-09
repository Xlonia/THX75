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
const TAG_NODES_B := "NodesB" ## 【新节点类 20261020】标准物理节点（弹幕推弹幕）
const TAGS: Array[String] = [TAG_REGULAR, TAG_PHYSICAL, TAG_FUNCTED, TAG_LASER, TAG_NODES, TAG_NODES_B]

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
	"t", "t_copy", "t_r", "rate_roll", "pattern_roll", "r0", "r1", "n", "d",
	"rotate_id",
	"wpcs", "to_c", "main_lr", "sub_lr",
	"self_x", "self_y", "self_ap", "self_pp", "self_normal",
	"target_x", "target_y", "target_ap", "target_pp", "target_normal",
	"target_hpweapon", "target_hpbody", "target_hpmove",
	"target_kp", "target_sp",
	## 【get 系补全 20261025b】gettarget(dm_*)——目标角色的态势结果（出生快照）
	"target_dm_apfrepul", "target_dm_situate", "target_dm_smn", "target_dm_sms",
	## 【x_copy/y_copy（编辑器-新 20261024）】竖直水平坐标系加上弹幕旋转重复
	## 结果角度构成的坐标轴上，目标角色对弹幕事件起点的坐标——旋转副本可据
	## 此集中/平行（物理与节点类尤佳）
	"x_copy", "y_copy",
	"field_t", "field_phase",
	## 【get 系 20261020】阵营击破计数（friendly/enemy=击方视角，field=双方合计）
	"friendly_privates_collapse", "friendly_chara_collapes",
	"enemy_privates_collapse", "enemy_chara_collapes",
	"field_privates_collapse", "field_chara_collapes",
	## 态势变量 <图><环><统计>（ht 实数，其余图占位 0；命名偏离文档"1d_ht_aver"
	## ——表达式标识符不能以数字开头，已列报告）
	"ht1daver", "ht2daver", "ht5daver", "ht1dvectsum", "ht2dvectsum", "ht5dvectsum",
	"hv1daver", "hv2daver", "hv5daver", "hv1dvectsum", "hv2dvectsum", "hv5dvectsum",
	"hd1daver", "hd2daver", "hd5daver", "hd1dvectsum", "hd2dvectsum", "hd5dvectsum",
	"hr1daver", "hr2daver", "hr5daver", "hr1dvectsum", "hr2dvectsum", "hr5dvectsum",
	"hcs1daver", "hcs2daver", "hcs5daver", "hcs1dvectsum", "hcs2dvectsum", "hcs5dvectsum",
	"hct1daver", "hct2daver", "hct5daver", "hct1dvectsum", "hct2dvectsum", "hct5dvectsum",
	"he1daver", "he2daver", "he5daver", "he1dvectsum", "he2dvectsum", "he5dvectsum",
	"hp1daver", "hp2daver", "hp5daver", "hp1dvectsum", "hp2dvectsum", "hp5dvectsum",
	## 节点类返回值：动态目标相对弹幕自身坐标
	"targe_x", "targe_y",
]

## CSV 表头（54列；20261002 +laser_render_scale=47；20261015 尾部追加 rotate_* 7列
## ——【教训】新列只允许尾部追加，禁止中段插入（曾因插列导致整行字段移位事故）
const CSV_HEADER: PackedStringArray = [
	"event_name", "slot", "timeline_frame", "tag",
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
	"color_r", "color_g", "color_b", "color_ab",
	"clash", "active", "clash_ddm", "inherit_when", "release_when", "inherit",
]

## —— 元数据 ——
## 【owner 彻底废除 20261020（作者批复）】角色弹幕分配=角色侧数据
## （Characters.csv main_evs 等），事件不再携带归属；关联角色共享同一事件
## 靠多角色列表引用同一事件名。owner 列从 CSV 表头移除（旧文件由迁移脚本删列）。
var event_name := "demodanmaku1"
var slot := SLOT_REST
var timeline_frame := -1
var tag := TAG_REGULAR

## —— 通用参数 ——
var texture := "tama0"
var color := "#ffffff"         ## 兼容列：HSL 十六进制（编辑器主用 hue/saturation）
## 【量纲迁移 20261019（类型一览.csv）】saturation=整数[0,256]、hue=整数[-256,256]
## （hue 相对 color 基础色相的波长偏移）；内部渲染时 /256。
var saturation := 0.0          ## HSL 之 S（0~256）
var hue := 0.0                 ## 相对 color 的色相偏移（-256~256）
## color 高级拆解（作者 20261019）：RGB 分量可独立填算式（0~256 整式），
## 非空时覆盖 color 列
var color_r_s := ""
var color_g_s := ""
var color_b_s := ""
## 【color_ab（作者 20261020）】颜色 A/B 面切换命题：未开高级=假（用 color），
## 开高级=真（用 r/g/b）；用户填写表达式则按真假动态切换；默认值由制谱器
## 保存数据决定（编辑器在高级开启且三通道有数据时存真）。某面颜色非法 →
## 忽略 color_ab 用另一面。
var color_ab_s := ""
var color_ab_def := false
var alpha := "256"
var pass_cond := ""
## 【语义修订（弹幕编辑器-新 20261015）】repeat_time=副本重复间隔（原"持续时间"歧义）；
## repeat_freq=重复发射次数（0=禁用）
## 【类型批复 20261019（数据类型一览.csv）】以下通用参数允许算式/命题——
## 数值列保留解析值（兼容直读），表达式原文存 _s 并在 compile() 编译：
## repeat_time/repeat_freq/range/dmg/x_offset/y_offset/rotate_delay=整式（向下取整）；
## danmaku_size_muti=式/命题（浮点保持）；rate=式/命题 [0,1]；pattern=式
var repeat_time := 0
var repeat_freq := 0
var repeat_time_s := ""
var repeat_freq_s := ""
var range_frames := 300
var range_s := ""
var is_abs_coord := false
var dmg := 1
var dmg_s := ""
var dmg_mode := MODE_NORMAL
var dmg_allow_moderate := true
var rate := 0.0                ## 语义（批复#11）：rate_roll<=rate 释放
var rate_specified := false
var rate_s := ""               ## 算式/命题原文（20261019）
var pattern := 0.0             ## 命题为真时 减一（批复#11）
var pattern_specified := false
var pattern_s := ""
var danmaku_size_muti := 1.0
var danmaku_size_muti_s := ""
var is_phy := false
var is_cannon := false
var x_offset := 0.0            ## 弹幕相对火力点起始x（物弹遮罩起点；批复新增）
var x_offset_s := ""
var y_offset := 0.0            ## 弹幕相对火力点起始y（同上）
var y_offset_s := ""

## —— 分类型参数 ——
var speed := ""
var x := ""
var y := ""
var func_expr := ""
var alarm := 0
var alarm_s := ""               ## 预警时长算式原文（20261019 表达式化）
var alarm_shader_alpha := 256.0 ## 预警期不透明度（0~256 整数量纲——20261019 迁移）
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
var explode_condit := ""      ## 旧列（兼容）：= inherit_when
var release_condit := ""      ## 旧列（兼容）：= release_when
var explode := ""             ## 旧列（兼容）：= inherit（引爆事件列表）
var release := ""             ## 中途释放事件列表（元素=事件名）
var can_destroy := false      ## 【20261020】clash 旧语义别名（命题化由 clash 承担）
## —— 节点类扩充（作者 20261020：对撞/激活/继承）——
var clash_s := ""             ## 对撞（命题）：真=参与检测DDM，可被物弹/敌弹摧毁；NodesB 之间对撞互推
var active_s := ""            ## 激活（命题）：真=参与检测DDM，任何弹幕接触即跳过释放条件触发释放事件
var clash_ddm_s := ""         ## 对撞弹幕图数列（占位：参与对撞检测的DDM名单）
var inherit_when_s := ""      ## 引爆条件（命题；旧列 explode_condit 兼容）
var release_when_s := ""      ## 释放条件（命题·上升沿；旧列 release_condit 兼容）
var inherit_s := ""           ## 引爆事件列表（旧列 explode 兼容）
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
var rotate_delay_s := ""

## —— 编译期缓存（20261003：每发弹幕不再重复扫描 27变量×11表达式）——
var ctx_keys_used: PackedStringArray = [] ## 本事件表达式实际引用的变量全集
## 【22b 20261031d】事件级 setup 模板（compile 期一次性判定）
var tpl_motion := false
var tpl_uses_tcopy := false
var tpl_has_ex_x := false
var tpl_has_ex_y := false
var tpl_has_ex_speed := false
var tpl_has_ex_func := false
var tpl_is_regular := false
var tpl_is_reg_or_phy := false
var tpl_w_frozen_eligible := false
var tpl_table_eligible := false
## 【getChata 全量 20261020】编译期抽取的查询表：
## {token, camp("f"/"e"), locator, param, _ex_loc(懒编译)}
var chata_queries: Array = []
var _chq_counter := 0
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
## 【0.0.9·审计①-0】编译期定值折叠槽（*_is_const=true 时对应 ex_* 已置 null）
var hue_is_const := false
var hue_const := 0.0
var sat_is_const := false
var sat_const := 0.0
var alpha_is_const := false
var alpha_const := 256.0
var pass_is_const := false
var pass_const := false
var ex_lost_if: DanmakuExpr = null
var ex_asa: DanmakuExpr = null  ## 预警期不透明度比值（表达式）
var ex_lrs: DanmakuExpr = null  ## 激光渲染规模（表达式）
var ex_explode: DanmakuExpr = null
var ex_release: DanmakuExpr = null
## 旋转重复参数表达式（20261019：range/offset 浮点式、div/rate 整式、pingpong 式/命题、delay 整式）
var ex_rrot_range: DanmakuExpr = null
var ex_rrot_div: DanmakuExpr = null
var ex_rrot_rate: DanmakuExpr = null
var ex_rrot_offset: DanmakuExpr = null
var ex_rrot_pp: DanmakuExpr = null
var ex_rrot_delay: DanmakuExpr = null
## 通用参数表达式（20261019 类型批复）
var ex_repeat_time: DanmakuExpr = null
var ex_repeat_freq: DanmakuExpr = null
var ex_range: DanmakuExpr = null
var ex_dmg: DanmakuExpr = null
var ex_size: DanmakuExpr = null
var ex_xoff: DanmakuExpr = null
var ex_yoff: DanmakuExpr = null
var ex_rate: DanmakuExpr = null
var ex_pattern: DanmakuExpr = null
var ex_alarm: DanmakuExpr = null
var ex_color_r: DanmakuExpr = null
var ex_color_g: DanmakuExpr = null
var ex_color_b: DanmakuExpr = null
var ex_color_ab: DanmakuExpr = null
var ex_clash: DanmakuExpr = null
var ex_active: DanmakuExpr = null
var ex_inherit_when: DanmakuExpr = null
var ex_release_when: DanmakuExpr = null

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
		"delay": maxi(0, int(floor(_e_or(ex_rrot_delay, rotate_delay, ctx)))),
		"seq": rotate_sequence if ROT_SEQS.has(rotate_sequence) else "cw",
	}

## repeat 重复参数求值（整式，非负；整数向下取整——类型批复 20261019）
func eval_repeat_params(ctx: Dictionary) -> Dictionary:
	return {
		"time": maxi(0, int(floor(_e_or(ex_repeat_time, repeat_time, ctx)))),
		"freq": maxi(0, int(floor(_e_or(ex_repeat_freq, repeat_freq, ctx)))),
	}

## 出生时刻参数求值（dmg/规格/航程/偏移/预警——弹幕出现瞬间定值，与快照同语义）
func eval_spawn_params(ctx: Dictionary) -> Dictionary:
	return {
		## 【批复 20261020】合法超范围→极值（钳制）；非法→默认（eval_num）
		"dmg": int(floor(maxf(0.0, _e_or(ex_dmg, dmg, ctx)))),
		"size": _clampf(_e_or(ex_size, danmaku_size_muti, ctx), 0.05, 64.0),
		"xoff": int(floor(_e_or(ex_xoff, x_offset, ctx))),
		"yoff": int(floor(_e_or(ex_yoff, y_offset, ctx))),
		"range": maxi(1, int(floor(_e_or(ex_range, range_frames, ctx)))),
		"alarm": maxf(0.0, floor(_e_or(ex_alarm, alarm, ctx))),
	}

## 【颜色 A/B 面（作者 20261020）】color_ab 命题：真=用 r/g/b 面（B面）、
## 假=用 color 面（A面）；默认值=编辑器保存时高级是否开启且有数据（color_ab_def）。
## 某面颜色非法（未定义变量/除零 NA/类型不兼容）→ 忽略 color_ab 用另一面。
## 分量按"合法超范围→极值"钳 [0,256]（例：256*sin(t/60)+256 峰值取 256；
## a+5 未定义→默认；true 恒真命题→数值不兼容取默认 0——尽管 rotate_pingpong
## 同值会解析为 1，因为它支持命题处理）。
func eval_color_ab(ctx: Dictionary) -> bool:
	if ex_color_ab != null:
		return _p_or(ex_color_ab, 1.0 if color_ab_def else 0.0, ctx) > 0.5
	return color_ab_def

## B 面颜色（r/g/b 算式）；无可用的 B 面数据 → Color(-1,-1,-1)（无效标记）
func eval_color_b(ctx: Dictionary) -> Color:
	if color_r_s == "" and color_g_s == "" and color_b_s == "":
		return Color(-1, -1, -1)
	var r := _e_or(ex_color_r, 0.0, ctx)
	var g := _e_or(ex_color_g, 0.0, ctx)
	var b := _e_or(ex_color_b, 0.0, ctx)
	if ex_color_r != null and ex_color_r.last_failed:
		return Color(-1, -1, -1) ## 该面非法 → 回退另一面
	if ex_color_g != null and ex_color_g.last_failed:
		return Color(-1, -1, -1)
	if ex_color_b != null and ex_color_b.last_failed:
		return Color(-1, -1, -1)
	return Color(_clampf(r, 0, 256) / 256.0, _clampf(g, 0, 256) / 256.0, _clampf(b, 0, 256) / 256.0)

## 颜色裁决：color_ab 真→B面（非法则A面）；假→A面（A面无hex且B面有数据→B面）
func resolve_color(ctx: Dictionary) -> Color:
	var cb := eval_color_b(ctx)
	var ca := Color.from_string(color, Color(-1, -1, -1)) ## A面非法标记
	if eval_color_ab(ctx):
		return cb if cb.r >= 0.0 else (ca if ca.r >= 0.0 else Color.WHITE)
	if ca.r >= 0.0:
		return ca
	return cb if cb.r >= 0.0 else Color.WHITE

func base_hue() -> float:
	return resolve_color({}).h

## 概率门求值（式/命题；命题=0/1 浮点；rate 钳 [0,1]）
func eval_rate(ctx: Dictionary) -> float:
	return clampf(_e_or(ex_rate, rate, ctx), 0.0, 1.0)
func eval_pattern(ctx: Dictionary) -> float:
	return maxf(0.0, _e_or(ex_pattern, pattern, ctx))

func _e_or(e: DanmakuExpr, d: float, ctx: Dictionary) -> float:
	if e != null:
		return e.eval_num(ctx, d) ## 严格数值：非法/布尔 → 默认（批复 20261020）
	return d

func _p_or(e: DanmakuExpr, d: float, ctx: Dictionary) -> float:
	if e != null:
		return e.eval_prop(ctx, d) ## 命题：布尔→1/0（rotate_pingpong/color_ab 等）
	return d

static func _clampf(v: float, lo: float, hi: float) -> float:
	return clampf(v, lo, hi)

## 类型专属参数归属（作者批复 20261019：切换运动方式/导出分表时清除不兼容数据
## ——修复 regular 行残留 nodes 失锁参数之类的占位）。共享参数（speed/x/y 等）不清。
const TAG_OWNED := {
	TAG_FUNCTED: ["func_expr"],
	TAG_LASER: ["laser_n_step", "alarm", "alarm_shader_alpha", "alarm_shader_alpha_s",
		"laser_render_scale", "laser_render_scale_s"],
	TAG_NODES: ["targe", "targe_offsetx", "targe_offsety", "acc", "turn_arg", "speed_max",
		"lost_max", "lost_min", "lost_if", "explode_condit", "release_condit",
		"explode", "release", "can_destroy"],
}

## 清除"其它运动方式"的专属参数（恢复默认值）；导出与切类型共用
func sanitize_for_tag() -> void:
	var fresh := DanmakuEventData.new()
	for tag2 in TAG_OWNED:
		if tag2 == tag:
			continue
		for k in TAG_OWNED[tag2]:
			if k in self:
				set(k, fresh.get(k))

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
	saturation = _f(cells, idx, "saturation", 0.0) ## 0~256（20261019 量纲）
	hue = _f(cells, idx, "hue", 0.0)                ## -256~256 相对偏移
	color_r_s = _s(cells, idx, "color_r", "")
	color_g_s = _s(cells, idx, "color_g", "")
	color_b_s = _s(cells, idx, "color_b", "")
	color_ab_s = _expr_cell(cells, idx, "color_ab") ## 空=按编辑器保存的默认面
	alpha = _s(cells, idx, "alpha", "256")
	pass_cond = _s(cells, idx, "pass", "")
	## 【类型批复 20261019】数值列=纯数字直存 / 算式原文存 _s（编译后求值）
	var pt := _num_or_expr(cells, idx, "repeat_time", 0)
	repeat_time = int(pt[0]); repeat_time_s = pt[1]
	var pf := _num_or_expr(cells, idx, "repeat_freq", 0)
	repeat_freq = int(pf[0]); repeat_freq_s = pf[1]
	var pr := _num_or_expr(cells, idx, "range", 300)
	range_frames = int(pr[0]); range_s = pr[1]
	is_abs_coord = _b(cells, idx, "is_abs_coord", false)
	var pd := _num_or_expr(cells, idx, "dmg", 1)
	dmg = int(pd[0]); dmg_s = pd[1]
	var dm := _s(cells, idx, "dmg_mode", MODE_NORMAL)
	if MODES.has(dm):
		dmg_mode = dm
	dmg_allow_moderate = _b(cells, idx, "dmg_allow_moderate", true)
	rate_specified = _has(cells, idx, "rate") and _s(cells, idx, "rate", "") != ""
	var prr := _num_or_expr(cells, idx, "rate", 0.0)
	rate = prr[0]; rate_s = prr[1]
	pattern_specified = _has(cells, idx, "pattern") and _s(cells, idx, "pattern", "") != ""
	var ppa := _num_or_expr(cells, idx, "pattern", 0.0)
	pattern = ppa[0]; pattern_s = ppa[1]
	var psz := _num_or_expr(cells, idx, "danmaku_size_muti", 1.0)
	danmaku_size_muti = psz[0]; danmaku_size_muti_s = psz[1]
	is_phy = _b(cells, idx, "is_phy", false)
	is_cannon = _b(cells, idx, "is_cannon", false)
	var pxo := _num_or_expr(cells, idx, "x_offset", 0.0)
	x_offset = pxo[0]; x_offset_s = pxo[1]
	var pyo := _num_or_expr(cells, idx, "y_offset", 0.0)
	y_offset = pyo[0]; y_offset_s = pyo[1]
	speed = _s(cells, idx, "speed", "")
	x = _s(cells, idx, "x", "")
	y = _s(cells, idx, "y", "")
	func_expr = _s(cells, idx, "func", "")
	var pam := _num_or_expr(cells, idx, "alarm", 0)
	alarm = int(pam[0]); alarm_s = pam[1]
	## 激光参数可变（作者批复 20261003）：数值或表达式
	## 【量纲迁移 20261019】alarm_shader_alpha 0~256 整数
	alarm_shader_alpha_s = _s(cells, idx, "alarm_shader_alpha", "")
	if alarm_shader_alpha_s.is_valid_float():
		alarm_shader_alpha = maxf(0.0, alarm_shader_alpha_s.to_float())
		alarm_shader_alpha_s = ""
	else:
		alarm_shader_alpha = 256.0
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
	## 节点类扩充（20261020）：新列优先，旧列回退
	clash_s = _expr_cell(cells, idx, "clash")
	if clash_s == "0" and can_destroy:
		clash_s = "1" ## 旧 can_destroy 勾选 → 对撞真
	active_s = _expr_cell(cells, idx, "active")
	clash_ddm_s = _s(cells, idx, "clash_ddm", "")
	inherit_when_s = _s(cells, idx, "inherit_when", "")
	if inherit_when_s == "0":
		inherit_when_s = explode_condit if explode_condit != "" else "0"
	release_when_s = _s(cells, idx, "release_when", "")
	if release_when_s == "0":
		release_when_s = release_condit if release_condit != "" else "0"
	inherit_s = _s(cells, idx, "inherit", "")
	if inherit_s == "":
		inherit_s = explode
	oob_mode = clampi(_i(cells, idx, "oob_mode", 0), 0, 2)
	## 旋转重复（20261015 列尾追加；20261019 起为表达式原文——数字即退化为常量式）
	rotate_range = _expr_cell(cells, idx, "rotate_range")
	rotate_div = _expr_cell(cells, idx, "rotate_div")
	rotate_rate = _expr_cell(cells, idx, "rotate_rate")
	rotate_offset = _expr_cell(cells, idx, "rotate_offset")
	var sq := _s(cells, idx, "rotate_sequence", "cw")
	rotate_sequence = sq if ROT_SEQS.has(sq) else "cw"
	rotate_pingpong = _expr_cell(cells, idx, "rotate_pingpong")
	var prd := _num_or_expr(cells, idx, "rotate_delay", 0)
	rotate_delay = int(prd[0]); rotate_delay_s = prd[1]
	return OK

## 表达式列取原文（空缺/旧布尔 true 视为 "1"——20261015 曾用布尔语义）
static func _expr_cell(cells: PackedStringArray, idx: Dictionary, col: String) -> String:
	var s := _s(cells, idx, col, "")
	if s == "":
		return "0"
	if s in ["true", "TRUE", "True"]:
		return "1"
	return s

## 【类型批复 20261019】数值列解析：纯数字→数值+原文清空；算式→数值取默认+原文保留
static func _num_or_expr(cells: PackedStringArray, idx: Dictionary, col: String, dflt: float) -> Array:
	var raw := _s(cells, idx, col, "")
	if raw == "":
		return [dflt, ""]
	if raw.is_valid_float():
		return [raw.to_float(), ""]
	return [dflt, raw]

func to_csv_row() -> String:
	## 【类型批复 20261019】有算式原文的列写原文（否则写解析值）
	var vals := [
		event_name, slot, timeline_frame, tag,
		texture, color, saturation, hue, alpha, pass_cond,
		(_s_if(repeat_time_s, repeat_time)), (_s_if(repeat_freq_s, repeat_freq)),
		(_s_if(range_s, range_frames)), int(is_abs_coord),
		(_s_if(dmg_s, dmg)), dmg_mode, int(dmg_allow_moderate),
		("" if not rate_specified else (rate_s if rate_s != "" else _num(rate))),
		("" if not pattern_specified else (pattern_s if pattern_s != "" else _num(pattern))),
		(_s_if(danmaku_size_muti_s, danmaku_size_muti)), int(is_phy), int(is_cannon),
		(_s_if(x_offset_s, x_offset)), (_s_if(y_offset_s, y_offset)),
		speed, x, y, func_expr,
		(_s_if(alarm_s, alarm)), (alarm_shader_alpha_s if alarm_shader_alpha_s != "" else _num(alarm_shader_alpha)),
		laser_n_step, (laser_render_scale_s if laser_render_scale_s != "" else _num(laser_render_scale)),
		targe, targe_offsetx, targe_offsety,
		acc, turn_arg, speed_max, lost_max, lost_min, lost_if,
		explode_condit, release_condit, explode, release, int(can_destroy), oob_mode,
		rotate_range, rotate_div, rotate_rate, rotate_offset,
		rotate_sequence, rotate_pingpong, (_s_if(rotate_delay_s, rotate_delay)),
		color_r_s, color_g_s, color_b_s, color_ab_s,
		clash_s, active_s, clash_ddm_s, inherit_when_s, release_when_s, inherit_s,
	]
	var parts: Array[String] = []
	for v in vals:
		parts.append(csv_escape(v))
	return ",".join(parts)

static func _s_if(s: String, v: float) -> String:
	return s if s != "" else _num(v)

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
	chata_queries.clear()
	_chq_counter = 0
	ex_alpha = _compile_one(alpha, errs, "alpha")
	ex_pass = _compile_one(pass_cond, errs, "pass")
	ex_speed = _compile_one(speed, errs, "speed")
	ex_x = _compile_one(x, errs, "x")
	ex_y = _compile_one(y, errs, "y")
	ex_func = _compile_one(func_expr, errs, "func")
	ex_hue = _compile_one(_expr_str(hue), errs, "hue") if _is_expr_str(hue) else null
	ex_sat = _compile_one(_expr_str(saturation), errs, "saturation") if _is_expr_str(saturation) else null
	## 【0.0.9·审计①-0 定值折叠 20261109】色相/对比度/透明度/pass 表达式若
	## 不含任何变量（纯算式如 "256"/"50+6"），求值一次即为终值——低频通道
	## 每 6 帧的求值、渲染侧每帧颜色重算都是纯浪费。编译期探测：无变量→
	## 降为定值槽+表达式置 null（实测默认队 frozen 弹 100% 带此类"表达式"
	## =「定值预计算」从未生效、也无一弹满足 C++ 整体接管条件）
	hue_is_const = false
	if ex_hue != null and ex_hue.is_constant():
		hue_is_const = true
		hue_const = ex_hue.const_value()
		ex_hue = null
	sat_is_const = false
	if ex_sat != null and ex_sat.is_constant():
		sat_is_const = true
		sat_const = ex_sat.const_value()
		ex_sat = null
	alpha_is_const = false
	if ex_alpha != null and ex_alpha.is_constant():
		alpha_is_const = true
		alpha_const = clampf(ex_alpha.const_value(), 0.0, 256.0)
		ex_alpha = null
	pass_is_const = false
	if ex_pass != null and ex_pass.is_constant():
		pass_is_const = true
		pass_const = ex_pass.const_value() > 0.5
		ex_pass = null
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
	ex_rrot_delay = _compile_one(rotate_delay_s, errs, "rotate_delay")
	## 通用参数表达式（20261019 类型批复：repeat 系/航程/伤害/规格/偏移/概率门）
	ex_repeat_time = _compile_one(repeat_time_s, errs, "repeat_time")
	ex_repeat_freq = _compile_one(repeat_freq_s, errs, "repeat_freq")
	ex_range = _compile_one(range_s, errs, "range")
	ex_dmg = _compile_one(dmg_s, errs, "dmg")
	ex_size = _compile_one(danmaku_size_muti_s, errs, "danmaku_size_muti")
	ex_xoff = _compile_one(x_offset_s, errs, "x_offset")
	ex_yoff = _compile_one(y_offset_s, errs, "y_offset")
	ex_rate = _compile_one(rate_s, errs, "rate")
	ex_pattern = _compile_one(pattern_s, errs, "pattern")
	ex_alarm = _compile_one(alarm_s, errs, "alarm")
	ex_color_r = _compile_one(color_r_s, errs, "color_r")
	ex_color_g = _compile_one(color_g_s, errs, "color_g")
	ex_color_b = _compile_one(color_b_s, errs, "color_b")
	ex_color_ab = _compile_one("" if color_ab_s in ["", "0"] else color_ab_s, errs, "color_ab")
	ex_clash = _compile_one("" if clash_s in ["", "0"] else clash_s, errs, "clash")
	ex_active = _compile_one("" if active_s in ["", "0"] else active_s, errs, "active")
	## 【0.0.9·审计】参数类表达式不走 C++ 热路径（事件级一次求值；且其
	## fallback=0 会把 rotate plan 塌缩成单弹——作者实测重复故障）
	for _pe in [ex_repeat_time, ex_repeat_freq, ex_rrot_range, ex_rrot_offset,
			ex_rrot_div, ex_rrot_rate, ex_rrot_pp, ex_rrot_delay,
			ex_dmg, ex_size, ex_xoff, ex_yoff, ex_range, ex_alarm]:
		if _pe != null:
			(_pe as DanmakuExpr)._no_hot = true
	ex_inherit_when = _compile_one("" if inherit_when_s in ["", "0"] else inherit_when_s, errs, "inherit_when")
	ex_release_when = _compile_one("" if release_when_s in ["", "0"] else release_when_s, errs, "release_when")
	## 变量引用全集 + 运动时间依赖（供 Bullet 快照/冻结判定，事件级一次）
	var all_exprs: Array = [ex_alpha, ex_pass, ex_speed, ex_x, ex_y, ex_func,
		ex_hue, ex_sat, ex_lost_if, ex_explode, ex_release,
		ex_rrot_range, ex_rrot_div, ex_rrot_rate, ex_rrot_offset, ex_rrot_pp, ex_rrot_delay,
		ex_repeat_time, ex_repeat_freq, ex_range, ex_dmg, ex_size, ex_xoff, ex_yoff,
		ex_rate, ex_pattern, ex_alarm, ex_color_r, ex_color_g, ex_color_b,
		ex_color_ab, ex_clash, ex_active, ex_inherit_when, ex_release_when]
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
	## 【22b 20261031d·事件级 setup 模板】（架构改造第一步：setup 从
	## "每发解释"变"查模板+填快照"）——编译期一次性判定，Bullet.setup 免去
	## 26 处 uses_variable/属性重读：
	tpl_motion = motion_time_bound
	tpl_uses_tcopy = (ex_x != null and (ex_x as DanmakuExpr).uses_variable("t_copy")) 		or (ex_y != null and (ex_y as DanmakuExpr).uses_variable("t_copy"))
	tpl_has_ex_x = ex_x != null
	tpl_has_ex_y = ex_y != null
	tpl_has_ex_speed = ex_speed != null
	tpl_has_ex_func = ex_func != null
	tpl_is_regular = tag == TAG_REGULAR
	tpl_is_reg_or_phy = tag == TAG_REGULAR or tag == TAG_PHYSICAL
	tpl_w_frozen_eligible = tpl_is_regular and _xy_in_motion_flag() 		and not _motion_depends_on_dynamic()
	tpl_table_eligible = (tpl_motion or tpl_uses_tcopy) and (tpl_has_ex_x or tpl_has_ex_y) 		and not tpl_w_frozen_eligible
	return errs

## 模板辅助：x/y 是否引用 x_copy/y_copy（帧控判定的事件级版本）
func _xy_in_motion_flag() -> bool:
	return (ex_x != null and ((ex_x as DanmakuExpr).uses_variable("x_copy") or (ex_x as DanmakuExpr).uses_variable("y_copy"))) 		or (ex_y != null and ((ex_y as DanmakuExpr).uses_variable("x_copy") or (ex_y as DanmakuExpr).uses_variable("y_copy")))

## 模板辅助：w 冻结的动态键排除——x/y 引用的变量里有非静态键（t 系等）
func _motion_depends_on_dynamic() -> bool:
	var st: Array[String] = []
	for v in EXPR_VARS:
		if v.begins_with("target_") or v.begins_with("self_") 				or v == "x_copy" or v == "y_copy" or v == "d" or v == "n":
			st.append(v)
	for e in [ex_x, ex_y]:
		if e == null:
			continue
		for v in EXPR_VARS:
			if (e as DanmakuExpr).uses_variable(v) and not st.has(v):
				return true
	return false

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
	var t := _extract_chata(text)
	var e := DanmakuExpr.new()
	if not e.compile(t, EXPR_VARS):
		errs.append("%s「%s」表达式解析失败" % [event_name, field])
		return null
	return e

## 【getChata 20261020】getchatafriend/enemy(locator,param) → 合法占位标识符
## _chq_f_N / _chq_e_N；查询登记到 chata_queries（运行时按阵营角色求值）
func _extract_chata(text: String) -> String:
	var out := text
	while true:
		var i_f := out.find("getchatafriend(")
		var i_e := out.find("getchataenemy(")
		var i_r := out.find("randomchara(")
		var pos := -1
		var camp := "f"
		var head := "getchatafriend("
		if i_f >= 0 and (i_e < 0 or i_f < i_e) and (i_r < 0 or i_f < i_r):
			pos = i_f
		elif i_e >= 0 and (i_r < 0 or i_e < i_r):
			pos = i_e
			camp = "e"
			head = "getchataenemy("
		elif i_r >= 0:
			pos = i_r
			camp = "r"
			head = "randomchara("
		if pos < 0:
			return out
		var depth := 0
		var j := pos + head.length() - 1
		var close := -1
		while j < out.length():
			var ch := out[j]
			if ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
				if depth == 0:
					close = j
					break
			j += 1
		if close < 0:
			return out
		var inner := out.substr(pos + head.length(), close - pos - head.length())
		## 顶层逗号切分（容忍引号内逗号）
		var args := _split_top(inner)
		var loc := args[0].strip_edges().replace("'", "").replace('"', "")
		var par := "fieldid" ## randomchara 返回所选角色的场地方位id（实体引用）
		if camp != "r":
			if args.size() < 2:
				return out
			par = args[1].strip_edges().replace("'", "").replace('"', "")
		var token := "_chq_%s_%d" % [camp, _chq_counter]
		_chq_counter += 1
		chata_queries.append({"token": token, "camp": camp, "locator": loc, "param": par})
		out = out.substr(0, pos) + token + out.substr(close + 1)
	return out

static func _split_top(inner: String) -> PackedStringArray:
	var parts: PackedStringArray = []
	var cur := ""
	var depth := 0
	var q := false
	for ch in inner:
		if ch == '"':
			q = not q
		if not q:
			if ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
			elif ch == "," and depth == 0:
				parts.append(cur)
				cur = ""
				continue
		cur += ch
	parts.append(cur)
	return parts

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
	return "%s [%s·%s]" % [event_name, slot, tag]

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
