extends Node
## spell_probe —— 主要符卡 X+C 释放链探针（m66 20261114）
## 默认角色 spell_evs 全空（数据侧待作者 scheme）——两层验证：
##   A. 释放链端到端（无时间轴兜底）：X+C 资源门路径→_apply_release("m")→
##      扣 1 符+100P→全屏消弹域→敌方瘫痪 5s→最接近敌方+1符→装填复位
##   B. 时间轴执行器（机械验证）：注入探针时间轴（tick0/tick30 各一发）→
##      手动入列→逐 tick 推进（run.tick 前进）→时间轴完成后出列
## 【跑法】godot --headless --path . res://Tests/spell_probe.tscn → SPELL_OK / SPELL_FAIL n
const RUN := 240
var arena: Node2D
var _step := 0
var _fails := 0
var _run_dict: Dictionary = {}
var _tick_advanced := false
func _ready() -> void:
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	## 【先热身 8 帧】sit_cards 为态势卡 tick 懒初始化（time_frames%6==0 首帧）——
	## 与 battle_tick_perf 同款手动 tick，先让战场进入常态再断言
	for i in 8:
		arena._physics_process(1.0 / 60.0)
	_run_a()
	_run_b()
	_run_c()
func _fail(msg: String) -> void:
	_fails += 1
	print("SPELL_FAIL: ", msg)

## A：兜底释放链（默认角色无 spell_evs 数据=纯消弹域路径）
func _run_a() -> void:
	var pl = arena.player_leader
	if pl == null:
		_fail("无 player_leader")
		return
	if pl.sit_cards == null:
		pl.sit_cards = SitCardSystem.new() ## 防御兜底（与 arena 2799 同款）
	pl.spell_cards = 1
	pl.pp = 100
	pl.sit_cards.spell_ready = true
	arena._apply_release(pl, "m")
	if int(pl.spell_cards) != 0:
		_fail("符卡未扣减（=%d）" % int(pl.spell_cards))
	if int(pl.pp) != 0:
		_fail("P 未扣减（=%d）" % int(pl.pp))
	if pl.clear_radius <= 0.0:
		_fail("全屏消弹域未生效")
	if pl.sit_cards.spell_ready:
		_fail("装填未复位")
	var para := false
	for e in arena.entities:
		if e is BattleEntity and e.side == 1 and arena._fire_is_paralyzed(e):
			para = true
	if not para:
		_fail("敌方未瘫痪")
	## 【m67】释放奖励=灰化符卡掉落（owner=释放方）——不再直接+1符
	var drop_cnt := 0
	for d in arena.drops:
		if int(d.get("owner", -1)) == 0:
			drop_cnt += 1
	if drop_cnt < 1:
		_fail("主要符卡未掉落灰化符卡（owner=0）")

## B：时间轴执行器（绕过角色数据列——直接入列）
func _run_b() -> void:
	if arena._find_event("demo_aimed") == null:
		_fail("前置：官方池无 demo_aimed（tick 无法展开）")
		return
	var tl := TimelineData.new()
	tl.tl_name = "probe_spell_tl"
	tl.slot = "spell"
	tl.set_events(0, PackedStringArray(["demo_aimed"]))
	tl.set_events(30, PackedStringArray(["demo_aimed"]))
	var pl = arena.player_leader
	if pl == null:
		return
	_run_dict = {"ent": pl, "tl": tl, "start_frame": arena.time_frames, "tick": -1}
	arena._spell_runs.append(_run_dict)

## C：m67 掉落语义（owner 禁拾）+ 内核配置 nonhuman_res_ban
var _c1_tagged := false
func _run_c() -> void:
	var pl = arena.player_leader
	if pl == null:
		return
	## C1：owner=0 掉落在我方主控脚下——规则生效=我方角色永不拾取
	##（3 帧内主控漂移 <10px：若禁拾失效必被当场拾走）
	arena._spawn_drop(pl.position, "spell", 0, 0)
	arena.drops[arena.drops.size() - 1]["probe"] = true
	_c1_tagged = true
	## C2：nonhuman_res_ban=敌方（AI）符卡授予封禁
	if _enemy_can_receive():
		THXKit.scenario_cfg["nonhuman_res_ban"] = true
		var s0 := _enemy_spell_sum()
		arena._grant_spell_random(1)
		if _enemy_spell_sum() != s0:
			_fail("nonhuman_res_ban 开启后敌方仍获得符卡")
		THXKit.scenario_cfg["nonhuman_res_ban"] = false
		arena._grant_spell_random(1)
		if _enemy_spell_sum() == s0:
			_fail("nonhuman_res_ban 关闭后敌方未获得符卡")
func _enemy_spell_sum() -> int:
	var s := 0
	for e in arena.entities:
		if e is BattleEntity and e.side == 1 and not e.dead:
			s += int(e.spell_cards)
	return s
func _enemy_can_receive() -> bool:
	for e in arena.entities:
		if e is BattleEntity and e.side == 1 and not e.dead and e.can_receive_spell():
			return true
	return false

func _process(_d: float) -> void:
	if arena == null:
		return
	_step += 1
	arena._physics_process(1.0 / 60.0)
	if _step == 3 and _c1_tagged:
		var alive := false
		for d in arena.drops:
			if d.get("probe", false):
				alive = true
		if not alive:
			_fail("owner 掉落被掉落方角色拾取（禁拾规则失效）")
	if _step == 90 and int(_run_dict.get("tick", -1)) >= 1:
		_tick_advanced = true ## tick0（第6帧）与后续 tick 已推进
	if _step >= RUN:
		if not _tick_advanced:
			_fail("时间轴 tick 未推进（执行器未跑）")
		if _arena_runs_left():
			_fail("时间轴未按时完成出列")
		if _fails == 0:
			print("SPELL_OK（A 兜底链+B 时间轴执行器 2 tick）")
			get_tree().quit(0)
		else:
			print("SPELL_FAIL %d" % _fails)
			get_tree().quit(1)
func _arena_runs_left() -> bool:
	if arena._spell_runs.is_empty():
		return false
	for r in arena._spell_runs:
		if r == _run_dict:
			return true
	return false
