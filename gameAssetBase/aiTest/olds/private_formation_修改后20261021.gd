class_name PrivateFormation
extends RefCounted
## =============================================================
## 杂兵排布（作者批复新增，对齐系统预设公式）
## 【杂兵模型】
##   位置 = owner.position + local_pos（角色动它们跟着动，再做相对位移）
##   系绳：所有杂兵不超出角色 0.3秒距；靠近 0.35秒距圆 4像素内 → 向角色恒为256的引力
##   t = 该点增援开始起的时间（非决斗开始）
## 【目标点 termin_point】相对角色的坐标（可表达式）；进入 termin_range 圆内引力消失
##   t=0 时若目标点已超出 0.3秒距 → 替换为连线与 0.3秒距圆的交点
## 【tpp 循环周期】t 从 0 到 tpp 做三角波；到 0.3秒距时时间参数反向
## 【privates_id()】1~5 的临时序号，同一算式对所有点取各自 id 值
## 【custom_a/b/c】玩家自定义量（表达式中直接引用变量名）
## 预设：扇形/线列/蝶翼/潮汐(公转)——参数为作者批复原文公式
## =============================================================

const PRESETS := {
	"扇形防护": {
		"termin_point_x": "(custom_a*privates_id-custom_a)*(-1)^privates_id+0.5*custom_a",
		"termin_point_y": "15+custom_b-3*custom_a*privates_id",
		"termin_range": "0.7*custom_a",
		"dict_zh": {"custom_a": "散布规模", "custom_b": "前后距离"},
	},
	"线列防护": {
		"termin_point_x": "(custom_a*privates_id-custom_a)*(-1)^privates_id+0.5*custom_a",
		"termin_point_y": "15+custom_b",
		"termin_range": "0.7*custom_a",
		"dict_zh": {"custom_a": "散布规模", "custom_b": "前后距离"},
	},
	"蝶翼防护": {
		"termin_point_x": "(privates_id-3)^0*custom_a*(-1)^privates_id",
		"termin_point_y": "(privates_id-3)^0*custom_a*(-1)^(privates_id-1)+custom_b*(abs(privates_id-3)-1)*(abs(privates_id-3)-2)",
		"termin_range": "0.7*custom_a",
		"dict_zh": {"custom_a": "散布规模"},
	},
	"潮汐防护": {
		"termin_point_x": "sin(getField(t)*0.1*custom_b)*custom_a",
		"termin_point_y": "cos(getField(t)*0.1*custom_b)*custom_a",
		"termin_range": "0.7*custom_a",
		"tpp": "10*tau",
		"dict_zh": {"custom_a": "散布规模", "custom_b": "环绕速度"},
	},
}

## 表达式变量表（排布域）：privates_id/custom_*/t/field_t + getField(t) 别名
const FORMATION_VARS: PackedStringArray = [
	"privates_id", "custom_a", "custom_b", "custom_c",
	"t", "field_t", "getField_t",
]

var owner: BattleEntity
var private_ent: BattleEntity
var preset_name := "线列防护"
var custom_vals := {"custom_a": 12.0, "custom_b": 6.0, "custom_c": 0.0}
var _ex_x: DanmakuExpr = null
var _ex_y: DanmakuExpr = null
var _ex_range: DanmakuExpr = null
var _tpp: float = 0.0 ## 循环周期（0=由 termin_point 到达0.3秒距的时间决定）

func setup(owner_ent: BattleEntity, priv: BattleEntity, preset: String, customs: Dictionary = {}) -> void:
	owner = owner_ent
	private_ent = priv
	preset_name = preset
	for k in customs:
		custom_vals[k] = customs[k]
	_compile()

func _compile() -> void:
	var preset: Dictionary = PRESETS.get(preset_name, PRESETS["线列防护"])
	_ex_x = _compile_one(preset.get("termin_point_x", "0"))
	_ex_y = _compile_one(preset.get("termin_point_y", "0"))
	_ex_range = _compile_one(preset.get("termin_range", "6"))
	var tpp_raw := str(preset.get("tpp", "0"))
	if tpp_raw.is_valid_float():
		_tpp = tpp_raw.to_float()

func _compile_one(text: String) -> DanmakuExpr:
	var e := DanmakuExpr.new()
	if not e.compile(str(text), FORMATION_VARS):
		return null
	return e

## =============================================================
## 【运算流程】每帧杂兵运动
##   ① 计算目标点（表达式求值；三角波 t）
##   ② 目标点超出 0.3秒距 → 钳到圆上（t=0 检查；批复原文交点替换）
##   ③ 引力：朝目标点移动；进入 termin_range 内引力消失
##   ④ 系绳：靠近 0.35秒距圆 4px 内 → 向角色恒为 256 的引力
##   ⑤ 位移合成 → local_pos 更新
## =============================================================
func step(delta_frames: float) -> void:
	if owner == null or private_ent == null or private_ent.dead:
		return
	var ctx := _build_ctx()
	## ① 目标点（termin_point 为角色局部坐标 x=右,y=前——批复 20261020：
	## 角色转向改变的是目标点而非杂兵本身，杂兵经引力飞往新目标点）
	var tp_local := Vector2(_eval(_ex_x, 0.0), _eval(_ex_y, 0.0))
	var tp: Vector2 = owner.frame_to_world(tp_local.x, tp_local.y)
	var tr := maxf(0.0, _eval(_ex_range, 6.0))
	## ② 0.3秒距钳制（t=0 时目标点已超出 → 圆交点替换）
	var rope_r := owner.normal_speed() * 60.0 * 0.3 ## 0.3秒距
	if tp.length() > rope_r:
		tp = tp.normalized() * rope_r
	## ③ 朝目标点引力（termin_range 内消失）
	var to_target := tp - private_ent.local_pos
	var pull := Vector2.ZERO
	if to_target.length() > tr:
		pull = to_target.normalized() * 256.0
	## 【杂兵 APF（新二 20261021）】Hd×2+owner Hcs×5 斥力（战场侧每0.2s算好）
	var apf: Vector2 = private_ent.get_meta("apf_push", Vector2.ZERO)
	## ⑤ 位移合成 → local_pos 更新（斥力方向偏置目标点引力）
	if apf != Vector2.ZERO:
		pull += apf * 256.0 ## 与 256 级引力同量纲叠加
	## ④ 0.35秒距系绳引力（恒为256，向角色）
	var leash_r := owner.normal_speed() * 60.0 * 0.35
	var dist_owner := private_ent.local_pos.length()
	if dist_owner > leash_r - 4.0:
		pull += -private_ent.local_pos.normalized() * 256.0
	## ⑤ 合成（批复：所有引力斥力皆转换为 慢机速度/256 的速度）
	var speed := private_ent.normal_speed() / 256.0
	private_ent.local_pos += pull * speed * delta_frames
	private_ent.sync_private_pos()
	## t 推进（三角波）
	private_ent.formation_t += delta_frames
	if _tpp > 0.0:
		var m := fmod(private_ent.formation_t, _tpp * 2.0)
		private_ent.formation_t = m if m <= _tpp else _tpp * 2.0 - m

func _build_ctx() -> Dictionary:
	return {
		"privates_id": float(private_ent.privates_id),
		"custom_a": custom_vals.get("custom_a", 0.0),
		"custom_b": custom_vals.get("custom_b", 0.0),
		"custom_c": custom_vals.get("custom_c", 0.0),
		"t": private_ent.formation_t,
		"field_t": private_ent.formation_t,
		"getField_t": private_ent.formation_t, ## getField(t) 别名（预设公式原文）
	}

func _eval(e: DanmakuExpr, fb: float) -> float:
	if e == null:
		return fb
	return e.execute_dict(_build_ctx(), fb)
