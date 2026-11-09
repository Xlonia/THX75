# -*- coding: utf-8 -*-
# ① BattleEntity：ai_logic 结构（角色逻辑AI——决斗设定-新 20261024）
p = 'scripts/versus/battle_entity.gd'
s = open(p, encoding='utf-8').read()
old = '''## —— 能力/符卡效果域（批复 2026-10-13：屏蔽改为"消除范围内弹幕"）——'''
new = '''## =============================================================
## 【角色逻辑AI（决斗设定-新 20261024）】方位逻辑+攻击逻辑+目标选择器。
## 系数由 AI 侧设定（作者授权），理由见 aiTest/角色逻辑AI与系数报告：
##   方位（第二级APF小力，总乘 0.35）：
##     approach 近身：引力 0.45 —— 压过冷点引力(0.5)需×0.35→0.157？
##     实取直接力度（不叠加限幅前的 1.0 竞争）：
##       approach=0.45 / standoff 近斥 0.60 远引 0.35（斥>引：防被反近身）
##       flee(对峙距0)=0.80 / none=0.15（向场心）
##   攻击：aim=替换锚定目标（沿用锚定权重）；volley=齐射；cruise=攻击时快机
## =============================================================
const AI_METRICS := ["hp_max", "ap_max", "hp_any_low", "ap_ratio_low", "dist_min", "dist_max"]
var ai_logic := {
	"stance": "standoff",       # approach 近身 / standoff 对峙 / none 无目标
	"stance_dist": 180.0,       # 对峙距离（0=回避）
	"metric": "hp_max",         # 目标选择器（比较量）
	"aim": true,                # 攻击目标（优先瞄准选择器命中者）
	"volley": false,            # 齐射逻辑
	"cruise": false,            # 巡航目标（攻击时优先快机）
}
var ai_target: BattleEntity = null ## 选择器当前命中（每0.5s刷新）

## —— 能力/符卡效果域（批复 2026-10-13：屏蔽改为"消除范围内弹幕"）——'''
assert old in s
s = s.replace(old, new)
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("entity ok")

# ② 战场：选择器评估 + 第二级力 + 攻击逻辑接线
p2 = 'scripts/versus/battle_arena.gd'
s2 = open(p2, encoding='utf-8').read()
old2 = '''	## 【绝对躲避层（新二 20261021）】敌方角色 0.25秒距圆热度强制 255——'''
new2 = '''	## 【角色逻辑AI·第二级（决斗设定-新 20261024）】第一级合力之上的小力：
	## 方位逻辑按选择器目标施加（系数见 BattleEntity.ai_logic 注释）
	if time_frames % 30 == 0:
		_refresh_ai_target(ent) ## 0.5s 刷新选择器
	var ai_t: BattleEntity = ent.ai_target
	if ai_t != null and not ai_t.dead:
		var to_t2: Vector2 = ai_t.position - ent.position
		var dd := to_t2.length()
		var dir_t := to_t2 / dd if dd > 0.01 else Vector2.ZERO
		match String(ent.ai_logic.get("stance", "standoff")):
			"approach":
				push += dir_t * 0.45
			"standoff":
				var want_d: float = float(ent.ai_logic.get("stance_dist", 180.0))
				if want_d <= 0.01:
					push -= dir_t * 0.80 ## 对峙距0=回避
				elif dd < want_d * 0.8:
					push -= dir_t * 0.60 ## 过近：斥（>引，防被反近身）
				elif dd > want_d * 1.2:
					push += dir_t * 0.35 ## 过远：引
			"none":
				push += (Vector2(200, 200) - ent.position).normalized() * 0.15
	## 【绝对躲避层（新二 20261021）】敌方角色 0.25秒距圆热度强制 255——'''
assert old2 in s2
s2 = s2.replace(old2, new2, 1)

# 选择器评估函数
old3 = '''func _show_hcs_view() -> bool:'''
new3 = '''## 【角色逻辑AI 20261024】目标选择器（决斗设定-新）：比较敌方角色选取量
func _refresh_ai_target(ent: BattleEntity) -> void:
	var best: BattleEntity = null
	var best_v := -INF
	var metric := String(ent.ai_logic.get("metric", "hp_max"))
	for o in entities:
		if not (o is BattleEntity) or o.dead or o.side == ent.side \\
				or o.kind == BattleEntity.Kind.PRIVATE or o == emitter_ent:
			continue
		var v := 0.0
		match metric:
			"hp_max": v = float(o.hp[0] + o.hp[1] + o.hp[2])
			"ap_max": v = float(o.ap)
			"hp_any_low":
				v = -minf(o.hp[0] + o.hp[1] + o.hp[2], 999.0) ## 任一HP低者优先（围剿近似=总HP低）
			"ap_ratio_low": v = -float(o.ap)
			"dist_min": v = -ent.position.distance_squared_to(o.position)
			"dist_max": v = ent.position.distance_squared_to(o.position)
			_: v = float(o.hp[0] + o.hp[1] + o.hp[2])
		if v > best_v:
			best_v = v
			best = o
	ent.ai_target = best

func _show_hcs_view() -> bool:'''
assert old3 in s2
s2 = s2.replace(old3, new3, 1)

# 攻击逻辑：锚定目标换 ai_target（aim=true 时）；齐射/巡航接线
old4 = '''	var tgt_pos: Vector2 = target.position
	## 【攻击夹角（新二 20261021）】攻击方向与朝向夹角<1 弧度不发起攻击'''
new4 = '''	## 【角色逻辑AI 20261024】攻击目标：选择器命中者替换锚定目标（aim=true）
	var anchor_src: BattleEntity = target
	if bool(ent.ai_logic.get("aim", true)) and ent.ai_target != null and not ent.ai_target.dead:
		anchor_src = ent.ai_target
	if bool(ent.ai_logic.get("cruise", false)) and ent.current_sit_card in ["a", "c"]:
		ent.cruise_active = true ## 巡航目标：攻击时优先快机
	var tgt_pos: Vector2 = anchor_src.position
	## 【攻击夹角（新二 20261021）】攻击方向与朝向夹角<1 弧度不发起攻击'''
assert old4 in s2
s2 = s2.replace(old4, new4, 1)
# 攻击夹角用 anchor_src
s2 = s2.replace('\tvar tgt_dir2 := target.position - ent.position',
                '\tvar tgt_dir2 := anchor_src.position - ent.position')

# 齐射逻辑：setup 后按 ai_logic.volley 设模式
old5 = '''		fc.fired.connect(_on_fire)'''
cnt = s2.count(old5)
s2 = s2.replace(old5, '''		fc.fired.connect(_on_fire)
		if bool(ent.ai_logic.get("volley", false)):
			fc.set_mode("salvo") ## 【角色逻辑AI 20261024】齐射逻辑''')
open(p2, 'w', encoding='utf-8', newline='\n').write(s2)
print("arena ok; volley hooks:", cnt)
