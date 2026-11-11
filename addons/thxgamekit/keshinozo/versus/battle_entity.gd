class_name BattleEntity
extends EntityCore ## 【0.0.9·内核化 20261111】实体底座自内核（submodule）；本类只留玩法追加
## =============================================================
## 决斗实体（第①期：角色 + 杂兵统一；getset 检测 + 修正钩子）
## 【批复采纳】
##   I类被剥甲：HP伤害=dmg÷0 → 取浮点最大值（一发重伤；批复#9）
##   后期实装道具（全光学迷彩）时：穿透伤害与 min(变量,…) 运算挂钩
##   （迷彩未失效取0/道具生效取1/否则跳过）——本类预留 impale_cap 钩子
##   杂兵：AP 5/HP 1·1·1；较强杂兵 tag → AP10 / HP 2·2·2（批复#19）
##   getset：hp/ap 赋值即检测重伤/满目疮痍/心情，无需主循环遍历
## =============================================================

## ③期 R-ETA：点向类追踪弹的规避力累积（弹幕 update 时写入；AI 读取后清零）
var reta_force := Vector2.ZERO
var sit_cards: SitCardSystem = null
var current_sit_card := "a"     ## 本拍态势（a/c/r/n/s/d/h/e）
var current_tactic := ""        ## 当前命中战术卡（空=无）

## 态势十六点（②期准备）：1d/2d 两串各16点采样值（0~255热度，Ht）。
## 【带转】偶数帧从最上端开始，奇数帧偏1/32圈（作者批复，减少采样死角）。
## ③期：AI 以此做多图加权叠加（Ht/Hd/Hcs…权重表）；现阶段仅 Ht。
var sit16_1d := PackedInt32Array()
var sit16_2d := PackedInt32Array()
var sit16_5d := PackedInt32Array()  ## ③期 RET-C：0.5秒距第三圈（48 采样=16×3）
## 【v0.0.8 RET 基底】快速探索树（RET-C 引力点 / RET-SP Sl；10Hz 由战场刷新）
var ret: RetSystem = null
## 【Hcs/Hct 20261020（游戏逻辑介绍）】角色 0.5秒距范围内的弹幕未来 1s 时空分布
## ——49 点（三环48+中心）分析式求值：Hcs=Σ255·覆盖帧/60 再 sqrt·16 取整；
## Hct=Hcs+移动方向重合采样点 +64（钳255）。逐实体独立、0.2s 交错刷新（性能红线）。
var hcs_pts := PackedFloat32Array()
var hct_pts := PackedFloat32Array()
var hcs_at := 0.0
var hct_at := 0.0
## 【0.0.9·基础规避 BC（新三 213-218）20261109】四弧（上/下/左/右）阻断比例
## （0=无弹 1=贴身；每 0.05 秒检测，结果保持至下次检测——"接下来的 0.05 秒"）
var bc_block := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

## =============================================================
## ②期经济：P点与符卡（scheme《符卡与P点》；作者批复 2026-10-02 启动）
## 满目疮痍/撤退角色不参与接收（接收函数由战场侧过滤 dead）。
## =============================================================
## PP_CAP=EntityCore 常量（内核随 pp 体系入核）
const SPELL_CARRY_MAX := 16        ## 每角色每次决斗最多携带16张
var spell_cards := 2               ## 开局携带符卡（暂定2，待作者定数）
var spell_received := 0            ## 本场已接收符卡数
var spell_receive_cap := 5         ## 默认最多接受5张（可被存档/难度覆盖）

func can_receive_spell() -> bool:
	if dead:
		return false ## 满目疮痍/撤退者完全不参与接收
	return spell_received < spell_receive_cap and spell_cards < SPELL_CARRY_MAX

func receive_spell() -> void:
	spell_cards += 1
	spell_received += 1

## =============================================================
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
	"avoid_phys_pair": false,   # 【BC 第⑤问】true=BC 用弹幕本体口径（从物弹角色身边推开=阻止搭档）
}
var ai_target: BattleEntity = null ## 选择器当前命中（每0.5s刷新）

## —— 能力/符卡效果域（批复 2026-10-13：屏蔽改为"消除范围内弹幕"）——
## 能力 80px / 次级符卡 200px / 主要符卡全屏（=500px 覆盖全场）；持续期内重复触发只消弹
var clear_radius := 0.0         ## 消弹半径（0=无；500=全屏）
var clear_frames := 0

func apply_clear(radius: float, seconds: float) -> void:
	clear_radius = maxf(clear_radius, radius)
	clear_frames = maxi(clear_frames, int(seconds * 60.0))

func clear_active() -> bool:
	return clear_frames > 0 and clear_radius > 0.0

## 加P点=EntityCore.add_pp（pp_cap 默认 500）


## 杂兵排布/系绳公式=PrivateFormation（玩法插件自带的运行时半部）

## 【自走棋插件语义】结界半径=判定+Defend 列（作者 schema：Defend 本体非必填）
func barrier_radius() -> float:
	return judge_radius() + float(db.get("Defend", 1))

## damaged/destroyed/barrier_shattered 信号=EntityCore（内核）

## 移动（角色：慢机/快机；机动折损→20%；杂兵：世界坐标由跟随+位移合成）
## dist_scale：时间尺度地基（批复 2026-10-01#8：月之怀表/须臾枝/时之魔珠类道具
## 要求"敌方速度、行进、AI、态势、已释放弹幕整体同步缩放"，不可只慢移动）。
## ②期先接 敌AI 移动与火控 delta；弹幕逐侧 dt 缩放随道具系统实装。
## speed_k：慢机速度比例（0~1；基础规避 BC 合力换算的比例速度——新三 218
## "标量×慢机速度/256，大于慢机速度则返回慢机速度"）；快机不受此比例
## 【心情 8 态（③期·策划 S/P 参数表）】tag 分层：
##   一层(状态源)：自信/冷静/尴尬/满目疮痍；二层：安心/紧张；三层：亢奋/恐惧；四层：痛苦/崩溃
##   同层互斥；低序号 tag 移除时清除更高序号；显示最高 tag。
var _mood_tags: PackedStringArray = []
var mood_tense_frames := 0     ## 紧张持续计时（>600=痛苦）
var mood_calm_frames := 0      ## 安心计时（4s 后消失）

const MOOD_SP := {
	"自信": [0.5, 0], "冷静": [0.75, 50], "尴尬": [1.0, 100], "紧张": [0.75, 100],
	"亢奋": [0.5, 100], "恐惧": [1.0, 100], "安心": [0.75, 25], "痛苦": [2.0, 100],
	"崩溃": [0.75, 150], "满目疮痍": [2.0, 200],
}

func _mood_check() -> void:
	if dead:
		return
	## 一层：状态源
	var layer1 := "自信"
	if barrier_broken:
		layer1 = "尴尬"
	elif ap < _initial_ap() / 2.0:
		layer1 = "冷静"
	## 二层：紧张（十六点均值>128 由战场每拍回写 sit_mean；应急先看 tag）
	if has_meta("sit_mean") and int(get_meta("sit_mean")) > 128:
		layer1 = "紧张"
		mood_tense_frames += 1
	else:
		mood_tense_frames = 0
	_mood_tags = [layer1]
	## 三层：亢奋/恐惧（在紧张基础上分 AP 高低）
	if layer1 == "紧张":
		_mood_tags = ["紧张", ("亢奋" if ap >= _initial_ap() / 2.0 else "恐惧")]
	## 四层：痛苦（紧张持续10s）
	if mood_tense_frames > 600:
		_mood_tags = ["紧张", "恐惧", "痛苦"]
		if barrier_broken and mood_tense_frames > 720:
			_mood_tags.append("崩溃")

func mood() -> String:
	if dead:
		return "满目疮痍"
	if _mood_tags.is_empty():
		_mood_check()
	return _mood_tags[_mood_tags.size() - 1] ## 显示最高 tag

## 心情的 S/P（态势抽卡用）
func mood_sp() -> Array:
	var key := mood()
	return MOOD_SP.get(key, [0.75, 0])

func _initial_ap() -> int:
	match kind:
		Kind.PLAYER: return 50
		Kind.PRIVATE: return 10 if is_elite_private else 5
		_: return 25
