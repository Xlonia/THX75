extends Node
## clip_probe —— m85 片段化+渲染界线探针（20261117）
## A. ClipData CSV 往返（to_csv_row→parse_csv 字段保持）
## B. 部署合并：THXKit.clips 含 clip_ReisenA_main_demo_aimed（length=10/ticks0=demo_aimed）
## C. get_slot_events 经片段平铺（ReisenA main → [demo_aimed]）
## D. get_slot_entries 条目式（[{tick:0, ev}]）
## E. FireControl 条目落地（weapon_points[].entries 非空且含 demo_aimed）
## F. 渲染界线 _render_in_field：中心弹渲染/界外半尺寸关闭/压边渲染
## G. 齐射只过 rate 不过 pattern（pattern 累加永不中→轮射拒/齐射放）
## 【跑法】godot --headless --path . res://Tests/clip_probe.tscn → CLIP_OK / CLIP_FAIL n
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
	_run_all()
	print("CLIP_OK" if _fails == 0 else "CLIP_FAIL %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _fail(msg: String) -> void:
	_fails += 1
	print("CLIP_FAIL: ", msg)

func _run_all() -> void:
	## A. CSV 往返
	var cd := ClipData.new()
	cd.clip_name = "rt_clip"
	cd.length_ticks = 10
	cd.ticks = {0: ["demo_aimed"], 3: ["spell_sanae"]}
	var text := "clip_name,length,ticks\n" + cd.to_csv_row() + "\n"
	var back: Array = ClipData.parse_csv(text)
	if back.size() != 1 or back[0].clip_name != "rt_clip" or back[0].length_ticks != 10:
		_fail("A 往返失败")
		return
	var ents: Array = back[0].flat_entries()
	if ents.size() != 2 or int(ents[0]["tick"]) != 0 or ents[0]["name"] != "demo_aimed" \
			or int(ents[1]["tick"]) != 3 or ents[1]["name"] != "spell_sanae":
		_fail("A flat_entries 顺序/内容错")
	## B. 部署合并
	var reg = THXKit.clips.get("clip_ReisenA_main_demo_aimed")
	if reg == null:
		_fail("B 部署片段未并入注册表")
		return
	if reg.length_ticks != 10 or reg.flat_entries().size() != 1 \
			or reg.flat_entries()[0]["name"] != "demo_aimed":
		_fail("B 字段错（length=%d）" % reg.length_ticks)
	## C. 平铺解析
	var flat: Array = GameGlobals.get_slot_events("ReisenA", DanmakuEventData.SLOT_MAIN)
	if flat.size() != 1 or flat[0].event_name != "demo_aimed":
		_fail("C 平铺解析错（n=%d）" % flat.size())
	## D. 条目解析
	var entries: Array = GameGlobals.get_slot_entries("ReisenA", DanmakuEventData.SLOT_MAIN)
	if entries.size() != 1 or int(entries[0]["tick"]) != 0 or entries[0]["ev"].event_name != "demo_aimed":
		_fail("D 条目解析错（n=%d）" % entries.size())
	## E. FireControl 条目落地（找含 demo_aimed 的 fc——ReisenA）
	var found := false
	for fc in arena.fire_controls:
		for p in fc.weapon_points:
			var hit_e: bool = false
			for e2 in p.entries:
				if e2["ev"].event_name == "demo_aimed":
					hit_e = true
			if hit_e and p.events.size() == 1:
				found = true
	if not found:
		_fail("E 火力点条目未落地")
	## F. 渲染界线（中心±(200+素材*缩放*0.5)——draw_radius=8 的假弹）
	var bl := Bullet.new()
	bl.pos = Vector2(200, 200)
	bl.draw_radius = 8.0
	if not arena._render_in_field(bl):
		_fail("F 中心弹被关渲染")
	bl.pos = Vector2(407.9, 200) ## 压边（<400+8 界内）→渲染
	if not arena._render_in_field(bl):
		_fail("F 压边弹被关渲染（应含半尺寸）")
	bl.pos = Vector2(408.1, 200) ## 越界（>400+8）→关闭
	if arena._render_in_field(bl):
		_fail("F 界外弹未被关渲染")
	## G. 齐射只过 rate 不过 pattern（spell_sanae pattern 改 0.001=累加永不中）
	var ev_s = arena._find_event("spell_sanae")
	if ev_s == null:
		_fail("G spell_sanae 未解析")
		return
	var old_pat: float = float(ev_s.pattern)
	var old_spec: bool = ev_s.pattern_specified
	ev_s.pattern = 0.001
	ev_s.pattern_specified = true
	var fc0 = arena.fire_controls[0]
	var p0 = fc0.weapon_points[0]
	fc0.mode = "rotate"
	if fc0._gate(ev_s, p0):
		_fail("G 轮射应拒（pattern 永不中）")
	fc0.mode = "salvo"
	if not fc0._gate(ev_s, p0):
		_fail("G 齐射应放（不考虑 pattern）")
	ev_s.pattern = old_pat
	ev_s.pattern_specified = old_spec
	## H. 宿主工作集解析优先（m86）：GameGlobals.editor_clips 同名片段压过注册表
	var ws := ClipData.new()
	ws.clip_name = "clip_ReisenA_main_demo_aimed"
	ws.length_ticks = 99
	ws.ticks = {0: ["demo_aimed"], 2: ["demo_aimed"]}
	GameGlobals.editor_clips = [ws]
	var ws_ents: Array = GameGlobals.get_slot_entries("ReisenA", DanmakuEventData.SLOT_MAIN)
	if ws_ents.size() != 2 or int(ws_ents[0]["tick"]) != 0 or int(ws_ents[1]["tick"]) != 2:
		_fail("H 工作集未压过注册表（n=%d）" % ws_ents.size())
	GameGlobals.editor_clips = []
	var rt_ents: Array = GameGlobals.get_slot_entries("ReisenA", DanmakuEventData.SLOT_MAIN)
	if rt_ents.size() != 1 or int(rt_ents[0]["tick"]) != 0:
		_fail("H 清空工作集后未回落注册表（n=%d）" % rt_ents.size())
	## I. group 列往返+长度上限 256（m87：legacy 分组/解析 clamp）
	var cdg := ClipData.new()
	cdg.clip_name = "clip_g"
	cdg.length_ticks = 300
	cdg.group = "legacy"
	cdg.add_event(0, "demo_aimed")
	var gt := ClipData.save_csv([cdg])
	var gb: Array = ClipData.parse_csv(gt)
	if gb.size() != 1 or gb[0].group != "legacy" or gb[0].length_ticks != 256:
		_fail("I group 往返/上限错（g=%s len=%d）" % [
			str(gb[0].group) if gb.size() > 0 else "?", gb[0].length_ticks if gb.size() > 0 else -1])
	## J. playclips 执行器：条目入 run 延时队列→倒计时到点出弹
	var evp = arena._find_event("demo_aimed")
	if evp == null:
		_fail("J demo_aimed 未解析")
		return
	var run_j := {"ent": arena.player_leader, "tl": {"tl_name": "probe_tl", "ticks": {"0": []}, "flow_start": "", "flow_every": ""},
		"start_frame": arena.time_frames, "tick": -1, "svg": {}, "r": 80.0, "steps_tick": []}
	arena._spell_runs.append(run_j)
	arena._exec_flow_step(arena.player_leader, {"op": "playclips", "arg": "clip_ReisenA_main_demo_aimed", "params": ""}, run_j)
	var sched: Array = run_j.get("clip_sched", [])
	if sched.size() != 1 or int(sched[0]["frames"]) != 0:
		_fail("J 条目未入队（n=%d）" % sched.size())
	else:
		var n0: int = arena.bullets.size()
		for fr in 8:
			arena.time_frames += 1
			arena._spell_runs_tick()
		if arena.bullets.size() <= n0:
			_fail("J 延时到点未出弹")
	arena._spell_runs.erase(run_j)
	## K. loopclips：run 登记+循环周期=片段长度（10 tick）
	var run_k := {"ent": arena.player_leader, "tl": {"tl_name": "probe_tl", "ticks": {"0": []}, "flow_start": "", "flow_every": ""}, "start_frame": arena.time_frames,
		"tick": -1, "svg": {}, "r": 80.0, "steps_tick": []}
	arena._exec_flow_step(arena.player_leader, {"op": "loopclips", "arg": "clip_ReisenA_main_demo_aimed", "params": ""}, run_k)
	if not run_k.has("loop_clip") or arena._clip_cycle_ticks(run_k["loop_clip"]) != 10:
		_fail("K loopclips 登记/周期错")
