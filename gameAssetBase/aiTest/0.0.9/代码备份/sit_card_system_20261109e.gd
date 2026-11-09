class_name SitCardSystem
extends RefCounted
## =============================================================
## 态势卡系统（③期·作者批复 2026-10-04 "对，就是现在实装"）
## 策划《态势卡抽卡》照抄：
##   · 环形缓冲区 30 张：每 0.1s 出一张（输出指针）；每秒优先从队尾补最多5张，
##     若未满 30 则在第 10 张后插入补全（模拟人反应：1秒反应/3秒记忆）
##   · 抽卡=正态分布：骰子×标准差S + 十六点均值 + 心情/阶段/指令P；<80=A、80~176=N、>176=D
##   · 卡组不乱排：A 段只出 a/c，D 段只出 h/d，N 只出 r；n/s 独立运算
##   · c/d 需要引力场：无引力时 c→a、d→h
##   · 心情8态 tag 分层（S/P 表）：自信/冷静/尴尬/紧张/亢奋/恐惧/安心/痛苦/崩溃
##   · 战术卡检测：每 0.1s 遍历第 16~25 号卡，At/10*Ct>1 命中（概率最大者）
## 【性能】全部数组/整数运算；正态骰子用 Box-Muller（每抽一次）。
## =============================================================

## 态势卡种类（a攻击 c巡航 r撤退 n能力 s符卡 d防御 h躲避 e应急）
const CARDS := ["a", "c", "r", "n", "s", "d", "h", "e"]
const BUF := 30

var ring: PackedStringArray = []  ## 环形卡组（index 0 = 下一张要出的）
var mood_s := 0.75                 ## 心情标准差 S（由实体心情更新）
var mood_p := 0                    ## 心情加值 P
var phase_p := 0                   ## 阶段加值 P'（远距-50/短兵50/破阵0/撤离50）
var sit_mean := 0                  ## 十六点均值（每拍刷新）
var has_apf_field := false         ## c/d 的引力场条件（无→c→a、d→h）
var charge_tick := 0               ## 装填计时（能力10s/符卡30s）
var spell_cd := 0.0
var skill_cd := 0.0
## —— 能力/符卡运行时释放（策划《态势卡》照抄；批复 2026-10-04 实装）——
var skill_load_t := 0.0        ## 能力装填（短兵起 10s）
var spell_load_t := 0.0        ## 符卡装填（短兵起 30s）
var skill_ready := false
var spell_ready := false
var apply_cd := 0.0            ## 申请检测节流（0.5s）
var pending_kind := ""         ## 申请成功待替换（"n"/"s"）
var pending_tries := 0         ## 替换尝试计数（1秒10次）
var stop_apply := 0            ## 申请成功后停止的申请次数（2次）
var rng := RandomNumberGenerator.new()

## 申请/释放公式入参由战场每拍回写
var Kp := 1.0        ## P点/上限
var Dcs := 0         ## 未来10张中D卡数
var Pcs := 0         ## 敌方剩余杂兵数
var Smn := 0.0       ## 能力倾向（十六点近似；③期换权重图）
var Sms := 0.0       ## 符卡倾向
var SL := 256.0      ## RET-SP 可用方向（战场每拍回写；0=绝路→强制 e 态势）
const ARA := 0.0     ## RET 启用乘数（未启用=0）
const PL := 0.0      ## 玩家指令提供（机控未实装）

## 每 0.1s：装填 + 申请 + 替换推进；返回本拍需要写入卡组的替换（""=无）
func release_tick(phase: int) -> String:
	if phase < 2: ## 短兵阶段才开始装填
		return ""
	skill_load_t += 0.1
	spell_load_t += 0.1
	if not skill_ready and skill_load_t >= 10.0:
		skill_ready = true
	if not spell_ready and spell_load_t >= 30.0:
		spell_ready = true
	## 替换推进（申请成功后 1 秒内每 0.1s 尝试换掉下一张；比率+随机>1，末帧 Nf/Df）
	if pending_kind != "":
		pending_tries += 1
		var na: float = (100.0 * Kp + Pcs) / (SL + 1.0)
		var da: float = sqrt(maxf((256.0 - Sms) * SL, 0.0)) + 1.0
		var ratio_a: float = 65536.0 if da <= 0.0 else na / da
		var last_frame := pending_tries >= 10
		var nf: float = Kp * Pcs
		var ratio_f: float = nf / 160.0
		var roll2 := rng.randf()
		if ratio_a + roll2 > 1.0 or (last_frame and ratio_f + roll2 > 1.0):
			var kind := pending_kind
			pending_kind = ""
			pending_tries = 0
			return kind ## 顶替下一张态势卡（同拍弹出即触发）
		if pending_tries >= 10:
			pending_kind = ""
			pending_tries = 0
		return ""
	## 每 0.5s 申请检测
	apply_cd += 0.1
	if apply_cd < 0.5:
		return ""
	apply_cd = 0.0
	if stop_apply > 0:
		stop_apply -= 1
		return ""
	if not (skill_ready or spell_ready):
		return ""
	## 【e 态势（策划）】Sl=0 → 应急符卡立即生效，忽略申请
	if SL <= 0.0:
		pending_kind = "s"
		pending_tries = 10
		return "s"
	## 申请判定（策划语义：比率数 + 系统随机数 > 1 = 申请成功；为负/除零→65536）
	var smn := Smn
	var sms := Sms
	var nnr: float = sqrt(Kp) * (16.0 * Dcs / maxf(SL, 1.0) + 128.0 * smn / pow(0.5 * SL + 1.0, 2.0))
	var dnr := 512.0 - smn - 128.0 * ARA
	var nsr: float = 2.0 * Kp * sms / (SL + 1.0) + 64.0 * Dcs / (0.5 * SL + 1.0)
	var dsr := 768.0 + 0.25 * Pcs - 4.0 * sms - 4.0 * SL
	var ratio_n: float = 65536.0 if dnr <= 0.0 else nnr / dnr
	var ratio_s: float = 65536.0 if dsr <= 0.0 else nsr / dsr
	var roll := rng.randf()
	var want := ""
	if skill_ready and ratio_n + roll > 1.0:
		want = "n"
	if spell_ready and ratio_s + roll > 1.0 and ratio_s >= ratio_n:
		want = "s" ## 同时申请成功→概率大者
	if want != "":
		pending_kind = want
		pending_tries = 0
		stop_apply = 2
	return ""

## 【策划】替换后的释放尝试：Ns=0.2Sms+1000Pl，Ds=Sl+1；比率+随机>1 成功
## 每 0.1s 拍内 6 帧尝试，全失败则该卡消耗、无效果。Pl=1（机控/接管）时必成。
func release_attempt(sms: float, pl: float) -> bool:
	var ns: float = 0.2 * sms + 1000.0 * pl
	var ds: float = SL + 1.0
	var ratio: float = ns / ds
	for f in 6:
		if ratio + rng.randf() > 1.0:
			return true
	return false

## 释放成功（战场侧调用）：装填复位
func on_released(kind: String) -> void:
	if kind == "n":
		skill_ready = false
		skill_load_t = 0.0
	elif kind == "s":
		spell_ready = false
		spell_load_t = 0.0

func _init() -> void:
	## 【0.0.9·测试台确定性 20261109】种子取自全局 RNG（randi）——正常游戏
	## 全局 RNG 启动即随机化=仍然随机；测试 seed() 后全场可复现（A/B 对账前提）
	rng.seed = randi()
	ring.resize(BUF)
	for i in BUF:
		ring[i] = "a" ## 开局全 a（策划：缓冲区空=全a）

## 每 0.1 秒：出一张（队首），补卡（1秒一次：尾补5 + 第10位后插补）
## 【根因修复 2026-10-13】旧版出卡后无条件补 "a"——出卡 10/秒 vs 真卡补充 5/秒，
## 卡组被硬 "a" 灌满（ring 恒全红、N/D 永不出现）。按策划原文重写：
##   出卡后立即从队尾抽一张真卡补位（祖玛：屁股后面补）；每秒额外的
##   "第 10 张后插入"补全仍保留（模拟反应记忆）。
func pop_card() -> String:
	var out: String = ring[0]
	ring.remove_at(0)
	ring.append(_draw_one()) ## 出一张补一张（真卡，非硬 a）
	charge_tick += 1
	if charge_tick % 10 == 0:
		_refill()
	return out

func _refill() -> void:
	## 策划：每秒优先跳最后往最后补最多 5 张直至 30 张——环形缓冲保持在 30 上限，
	## 故此处做"队尾 5 张重抽"（替换最旧的 5 张为新鲜抽卡，模拟 1 秒反应窗）
	for i in mini(5, ring.size()):
		ring[ring.size() - 1 - i] = _draw_one()
	## 第 10 张后插入补全（不足 30 时；正常满员不触发）
	while ring.size() < BUF:
		ring.insert(mini(10, ring.size()), _draw_one())

## 抽一张：正态骰子×S×25 + 十六点均值 + P → A/N/D → 段内定卡
func _draw_one() -> String:
	var roll := _gauss() * mood_s * 25.0 + float(sit_mean) + float(mood_p + phase_p)
	var zone: String
	if roll < 80.0:
		zone = "A"
	elif roll <= 176.0:
		zone = "N"
	else:
		zone = "D"
	match zone:
		"A":
			if not has_apf_field:
				return "a" ## c→a（无引力场）
			return "a" if rng.randf() < 0.5 else "c"
		"N":
			return "r" ## 【策划】中性只抽 r；n/s 不入普通抽卡（独立运算=申请→顶替→瞬发）
		"D":
			if not has_apf_field:
				return "h" ## d→h
			return "d" if rng.randf() < 0.5 else "h"
	return "a"

func _gauss() -> float:
	return sqrt(-2.0 * log(maxf(rng.randf(), 1e-9))) * cos(TAU * rng.randf())

## —— 战术卡检测（每 0.1s 遍历第 16~25 号卡）——
## 预设：奇袭10A / 火力覆盖10A / 闪击战8A / 接受协同2A / 交替掩护6N /
##       能力协同1N3D+1n / 符卡协同3D+1s / 机动防御1A4D / 迟滞8D / 佯攻8D
const TACTICS := [
	{"name": "奇袭", "req": {"A": 10}, "key": "Char_Raid"},
	{"name": "火力覆盖", "req": {"A": 10}, "key": "Char_Allfire"},
	{"name": "闪击战", "req": {"A": 8}, "key": "Char_Blitz"},
	{"name": "接受协同", "req": {"A": 2}, "key": "Char_Cover"},
	{"name": "交替掩护", "req": {"N": 6}, "key": "Char_Cover"},
	{"name": "能力协同", "req": {"N": 1, "D": 3}, "key": "Char_Cover"},
	{"name": "符卡协同", "req": {"D": 3}, "key": "Char_Cover"},
	{"name": "机动防御", "req": {"A": 1, "D": 4}, "key": "Char_Elast"},
	{"name": "迟滞", "req": {"D": 8}, "key": "Char_Delay"},
	{"name": "佯攻", "req": {"D": 8}, "key": "Char_Feint"},
]

## 战术卡号召值（策划：号召=按战术而定的引力系数，1~4）
const TACTIC_APPEAL := {
	"奇袭": 1.0, "火力覆盖": 1.0, "闪击战": 1.0, "接受协同": 1.0,
	"交替掩护": 0.0, "能力协同": 1.0, "符卡协同": 4.0,
	"机动防御": 0.0, "迟滞": 0.0, "佯攻": 0.0,
}

## 返回 {"name":…, "prob":…} 或 null；db=角色行（性格倾向 Ct）
func check_tactic(db: Dictionary) -> Dictionary:
	var counts := {"A": 0, "N": 0, "D": 0}
	for i in range(15, mini(25, ring.size())): ## 第 16~25 号卡
		var c: String = ring[i]
		match c:
			"a", "c":
				counts["A"] += 1
			"r", "n", "s":
				counts["N"] += 1
			"d", "h":
				counts["D"] += 1
	var best: Dictionary = {}
	var best_prob := 0.0
	for tac in TACTICS:
		var ok := true
		for zone in tac["req"]:
			if counts[zone] < tac["req"][zone]:
				ok = false
				break
		if not ok:
			continue
		var at: int = 0
		for zone in tac["req"]:
			at += tac["req"][zone]
		var ct := float(db.get(tac["key"], 0.2))
		var prob := float(at) / 10.0 * ct
		if prob > best_prob:
			best_prob = prob
			best = {"name": tac["name"], "prob": prob}
	return best if best_prob > 1.0 else {} ## 命中命题 At/10*Ct > 1

## 能力/符卡装填（短兵阶段开始；能力10s/符卡30s）
func charge_tick_pass(delta_sec: float, phase: int) -> void:
	if phase >= 2:
		skill_cd = maxf(skill_cd + delta_sec, 0.0) if skill_cd > 0.0 else 0.0
