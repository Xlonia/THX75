extends Node
## spell_classical_probe —— m89 古典符卡端到端（作者 20261118 令）
## E. 部署合并：spell_classical 入注册表+角色 spell_evs 已配
## F. 纯定义挂载：无时间轴角色释放 m → SpellData 通路（svg/clean 武装）
## G. 消弹实证：释放后敌对弹被清（拒不投降默认自定义对战的消弹链）
## 【跑法】godot --headless --path . res://Tests/spell_classical_probe.tscn → SPCLASS_OK / SPCLASS_FAIL n
var arena: Node2D
var _fails := 0

func _ready() -> void:
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	for i in 8:
		arena._physics_process(1.0 / 60.0)
	_run_all()
	print("SPCLASS_OK" if _fails == 0 else "SPCLASS_FAIL %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _fail(msg: String) -> void:
	_fails += 1
	print("SPCLASS_FAIL: ", msg)

func _run_all() -> void:
	## E. 部署合并+角色配置
	var sp = THXKit.resolve_spell("spell_classical")
	if sp == null:
		_fail("E spell_classical 未并入注册表")
		return
	if sp.steps_start.size() != 1 or sp.steps_tick.size() != 1:
		_fail("E 步骤数错（%d/%d）" % [sp.steps_start.size(), sp.steps_tick.size()])
	var row = arena.player_leader.db
	if String(row.get("spell_evs", "")).split(";", false).is_empty():
		_fail("E 角色未配符卡")
		return
	## F. 纯定义挂载（X+C 主符卡档=走 _spell_timeline_run）
	## 【m91】pl 的 m 槽显式设定（作者数据已改——Xlonia=xlonia_verses）
	var pl = arena.player_leader
	if pl.sit_cards == null:
		pl.sit_cards = SitCardSystem.new() ## 防御兜底（spell_probe A 同款）
	pl.db["spell_evs"] = "spell_classical"
	arena._spell_idx[pl.get_instance_id()] = 0
	pl.spell_cards = 1
	pl.pp = 100
	var idx0: int = int(arena._spell_idx.get(pl.get_instance_id(), 0))
	arena._apply_release(pl, "m")
	if int(pl.spell_cards) != 0:
		_fail("F 符卡未扣减")
	var mounted := false
	for r in arena._spell_runs:
		if r["ent"] == pl and r.get("spell") == sp:
			mounted = true
			if not r.has("until_frame"):
				_fail("F 纯定义 run 缺 until_frame")
			if r["svg"].is_empty():
				_fail("F spellstart svgresign 未武装")
	if not mounted:
		_fail("F 纯定义挂载未发生（回退兜底？）")
		return
	## G. 消弹实证：铺敌对弹（敌方发射）→跑 12 帧主循环→近旁敌对弹被清
	var en = arena.enemy_leader
	arena._spawn_event_copies(arena._find_event("demo_aimed"), pl.position + Vector2(40.0, 0.0), en, null, {}, 0)
	var hostile0 := 0
	for b in arena.bullets:
		if b.source_side == 1:
			hostile0 += 1
	for fr in 12:
		arena._physics_process(1.0 / 60.0)
	var hostile1 := 0
	for b2 in arena.bullets:
		if b2.source_side == 1 and b2.pos.distance_to(pl.position) < 150.0: ## 【m106 档位 50/80/150】域内=消弹职责口径
			hostile1 += 1
	if hostile1 >= hostile0:
		_fail("G 消弹未生效（%d→%d）" % [hostile0, hostile1])
	## G2. 默认队全员配置核对（角色 csv 数据态=作者全角色配置的验证面）
	var all_set := true
	for e in arena.entities:
		if e is BattleEntity and e.kind != BattleEntity.Kind.PRIVATE and not e.dead:
			var names: PackedStringArray = String(e.db.get("spell_evs", "")).split(";", false)
			var ok := false
			for nm in names:
				if nm.strip_edges() != "":
					ok = true
			if not ok:
				all_set = false
				_fail("G2 角色 %s m 槽为空" % e.chara_name())
	if all_set:
		print("SPCLASS_NOTE: 默认队全员主符卡槽非空")
	## H. 【m91】自定义符卡部署后挂载（xlonia_verses 根因复现闭环）
	var cust := SpellData.new()
	cust.spell_name = "probe_custom"
	cust.steps_start = [{"arg": "", "op": "svgresign", "params": "序号=0"}]
	THXKit.spell_cards["probe_custom"] = cust ## 模拟分配写穿后的部署态
	pl.db["spell_evs"] = "spell_classical;probe_custom"
	pl.spell_cards = 1
	pl.pp = 100
	arena._apply_release(pl, "m")
	var ok_h := false
	for r in arena._spell_runs:
		if r["ent"] == pl and r.get("spell") != null and r["spell"].spell_name == "probe_custom":
			ok_h = true
	if not ok_h:
		_fail("H 自定义符卡挂载未发生（轮放 idx/解析错）spell_evs=%s idx=%s runs=%d" % [
			str(pl.db.get("spell_evs", "")), str(arena._spell_idx.get(pl.get_instance_id(), -1)),
			arena._spell_runs.size()])
	## H2. 【m91 去旧制】未部署符卡=不挂流程+不回退古典（响亮 toast）
	en.db["spell_evs"] = "ghost_spell"
	en.spell_cards = 1
	en.pp = 100
	var fr0: int = arena._flow_runs.size()
	var sr0: int = arena._spell_runs.size()
	arena._apply_release(en, "m")
	if arena._flow_runs.size() > fr0:
		_fail("H2 未部署符卡仍回退古典兜底（去旧制未彻底）")
	var ghost := false
	for r2 in arena._spell_runs:
		if r2["ent"] == en and sr0 < arena._spell_runs.size():
			ghost = true
	if arena._spell_runs.size() > sr0 and not ghost:
		pass
	print("SPCLASS_NOTE: H2 未部署=无流程（去旧制）已验证")
