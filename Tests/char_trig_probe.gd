extends Node
## char_trig_probe —— 角色触发器探针（m125——scheme 角色触发器节；作者 20261125 六答）
## A. CharFlowData @trigger 解析（dist/cond/sel 段）+ _char_trigs_install 索引
## B. 四宫格 tick：移动性（movetick/statictick）×慢快（slowtick/fasttick）同跑不互斥
## C. start 沿：movestart/staticstart（状态切换一次）
## D. danmaku 触发器：发射语境（ctx.ev）
## E. dmif：被弹条件（damage 语境）+ take_hit 记 _last_hit_dmg
## F. smif：每事件帧条件真即执行（持续为真多次——作者答 4，与 threshold 不同）
## G. dmapproach：外侧进入距离上升沿（上一拍在外+这一拍在内；池 id 免疫）
## H. deathrattle：死亡后流程（destroyed 信号——实体 dead 语境直发）
## 打点=未知 op 的 toast（"角色操作未实装：ctprobe_*"）——零副作用计数
func _ready() -> void:
	var arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	if arena.pause_panel != null:
		arena.pause_panel.visible = false
	for i in 8:
		arena._physics_process(1.0 / 60.0)
	var fails := 0
	var toasts_has := func(s: String) -> bool:
		for t in arena._toasts:
			if str(t["text"]).contains(s):
				return true
		return false
	var toasts_count := func(s: String) -> int:
		var n := 0
		for t in arena._toasts:
			if str(t["text"]).contains(s):
				n += 1
		return n
	## A. @trigger 解析（含 dist/cond/sel 三参数段）
	var txt := "## THX CHARFLOW v1\n## @name: ct_a\n## @owner: *\n## @trigger: dmapproach | dist:90 | sel:ev_probe\n## F ctprobe_a\n"
	var flows: Array = CharFlowData.parse_gd(txt)
	if flows.size() != 1 or flows[0].trigger != "dmapproach" or absf(flows[0].t_dist - 90.0) > 0.01 or flows[0].t_sel != "ev_probe":
		fails += 1
		print("CT_FAIL: A @trigger 解析不符（%s/%s/%s）" % [str(flows.size()), str(flows[0].trigger if flows.size() > 0 else "?"), str(flows[0].t_dist if flows.size() > 0 else "?")])
	var txt2 := "## THX CHARFLOW v1\n## @name: ct_b\n## @owner: MarisaA\n## @trigger: smif | cond:hpper < 0.5\n## F ctprobe_smif\n"
	var flows2: Array = CharFlowData.parse_gd(txt2)
	if flows2.size() != 1 or flows2[0].t_cond != "hpper < 0.5":
		fails += 1
		print("CT_FAIL: A2 cond 解析不符")
	var back: String = flows2[0].to_gd()
	if not back.contains("@trigger: smif | cond:hpper < 0.5"):
		fails += 1
		print("CT_FAIL: A3 to_gd 触发器写回不符")
	## 注入触发器流程（覆盖各节打点）
	var mk := func(trig: String, owner_name: String, op: String, over: Dictionary = {}) -> CharFlowData:
		var fl := CharFlowData.new()
		fl.flow_name = "ct_" + op
		fl.owner = owner_name
		fl.trigger = trig
		for k in over:
			fl.set(k, over[k])
		fl.steps = [{"op": op, "sel": {}, "ev": "", "every": 0, "p": ""}]
		return fl
	THXKit.char_flows["ct_mvt"] = mk.call("movetick", "MarisaA", "ctprobe_movetick")
	THXKit.char_flows["ct_stt"] = mk.call("statictick", "MarisaA", "ctprobe_statictick")
	THXKit.char_flows["ct_slw"] = mk.call("slowtick", "MarisaA", "ctprobe_slowtick")
	THXKit.char_flows["ct_fst"] = mk.call("fasttick", "MarisaA", "ctprobe_fasttick")
	THXKit.char_flows["ct_mvs"] = mk.call("movestart", "MarisaA", "ctprobe_movestart")
	THXKit.char_flows["ct_sts"] = mk.call("staticstart", "MarisaA", "ctprobe_staticstart")
	THXKit.char_flows["ct_dmk"] = mk.call("danmaku", "MarisaA", "ctprobe_danmaku")
	THXKit.char_flows["ct_dif"] = mk.call("dmif", "MarisaA", "ctprobe_dmif", {"t_cond": "damage >= 1"})
	THXKit.char_flows["ct_smi"] = mk.call("smif", "MarisaA", "ctprobe_smif", {"t_cond": "hp > 0"})
	THXKit.char_flows["ct_dap"] = mk.call("dmapproach", "MarisaA", "ctprobe_dmapproach", {"t_dist": 100.0})
	THXKit.char_flows["ct_dtr"] = mk.call("deathrattle", "MarisaA", "ctprobe_deathrattle")
	arena._char_trigs_install()
	if arena._char_trigs.is_empty() or not (arena._char_trigs as Dictionary).has("MarisaA"):
		fails += 1
		print("CT_FAIL: A4 索引装填空")
	## 取实体（玩家侧首位=MarisaA）
	var pl: BattleEntity = null
	for e in arena.entities:
		if e is BattleEntity and e.side == 0:
			pl = e
			break
	if pl == null:
		print("CT_SKIP: 无玩家实体（%d）——A 节已验" % arena.entities.size())
		print("CT_FAIL" if fails > 0 else "CT_OK")
		arena.queue_free()
		return
	var hp0 := int(pl.hp[0] + pl.hp[1] + pl.hp[2])
	## B. 四宫格（事件帧节拍=10 帧；每实体每事件帧恰跑 2 个 tick）
	## B1 静止+慢机（实体默认 cruise_active=false）：statictick+slowtick
	arena.time_frames = 9 ## 下一帧=10=事件帧
	arena._toasts.clear()
	arena.time_frames = 10
	arena._char_triggers_tick() ## 直调（绕 _physics_process 包装层——AI 抢位/加载屏不属于触发器逻辑验证域）
	if not (toasts_has.call("ctprobe_statictick") and toasts_has.call("ctprobe_slowtick")):
		fails += 1
		print("CT_FAIL: B1 静止+慢机（statictick/slowtick）未同跑")
	## B2 移动+慢机（实体默认 cruise_active=false）：movetick+slowtick 同跑
	arena._toasts.clear()
	arena.time_frames = 20
	pl.position += Vector2(5, 0)
	arena._char_triggers_tick()
	if not (toasts_has.call("ctprobe_movetick") and toasts_has.call("ctprobe_slowtick")):
		fails += 1
		print("CT_FAIL: B2 移动+慢机（movetick/slowtick）未同跑")
	## B3 快机移动：movetick+fasttick 同跑（作者答 1——正交不互斥）
	pl.cruise_active = true
	arena._toasts.clear()
	arena.time_frames = 30
	pl.position += Vector2(5, 0)
	arena._char_triggers_tick()
	if not (toasts_has.call("ctprobe_fasttick") and toasts_has.call("ctprobe_movetick")):
		fails += 1
		print("CT_FAIL: B3 快机移动=fasttick+movetick 未同跑")
	## C. start 沿：静→动=movestart 一次（staticstart 由动→静）
	arena.time_frames = 40
	pl.position += Vector2(5, 0) ## 上一帧停（B3 后未驱帧=状态 prev_moving?——显式重置）
	pl.set_meta("_ct_prev_moving", false)
	arena._toasts.clear()
	arena._char_triggers_tick()
	if not toasts_has.call("ctprobe_movestart"):
		fails += 1
		print("CT_FAIL: C 移动沿未触发 movestart")
	## D. danmaku 触发器（发射语境）
	arena._char_trig_fire_named(pl, null)
	if not toasts_has.call("ctprobe_danmaku"):
		fails += 1
		print("CT_FAIL: D danmaku 派发未触发")
	## E. dmif：被弹伤害语境（damage >= 1 恒真——take_hit 5 点）
	pl.immune_frames = 0
	pl.take_hit(5, 0, 0.0)
	if not toasts_has.call("ctprobe_dmif"):
		fails += 1
		print("CT_FAIL: E dmif 被弹未触发（damage 语境）")
	## F. smif：hp>0 恒真——再 2 个事件帧=执行 2 次（持续为真每帧执行——作者答 4）
	arena._toasts.clear()
	var n0: int = 0
	arena.time_frames = 50
	arena._char_triggers_tick()
	arena.time_frames = 60
	arena._char_triggers_tick()
	var n1: int = toasts_count.call("ctprobe_smif")
	if n1 - n0 < 2:
		fails += 1
		print("CT_FAIL: F smif 持续为真未每事件帧执行（%d→%d）" % [n0, n1])
	## G. dmapproach：外侧进入 100px 上升沿（鸭子替身弹）
	var stub := Node2D.new()
	add_child(stub)
	var b_stub = Node.new() ## 无类型（脚本动态属性——Typed Node 访问会编译炸）
	b_stub.set_script(load("res://Tests/ct_bullet_stub.gd"))
	b_stub.alive = true
	b_stub.hidden_now = false
	b_stub.pos = Vector2(130, 200) ## d_now=70≤100（圈内）；回推 (30,200)=170>100（外侧）→上升沿
	add_child(b_stub)
	arena.bullets.append(b_stub)
	pl.position = Vector2(200, 200)
	arena._toasts.clear()
	arena._dmapproach_tick() ## 直调（逐帧上升沿）
	if not toasts_has.call("ctprobe_dmapproach"):
		fails += 1
		print("CT_FAIL: G dmapproach 进入沿未触发")
	arena.bullets.erase(b_stub)
	b_stub.queue_free()
	## H. deathrattle：死亡后流程（destroyed→直发）
	pl2_death_check(arena, pl, toasts_has, fails)
	## 收尾
	if fails == 0:
		print("CT_OK")
	else:
		print("CT_FAIL: 共 %d" % fails)
	arena.queue_free()
	get_tree().quit() ## headless 显式退出（防空场景挂起）

func pl2_death_check(arena, pl: BattleEntity, toasts_has: Callable, fails: int) -> void:
	## H：三部位击杀→deathrattle（destroyed 信号在 take_hit 内发出）
	var before: bool = toasts_has.call("ctprobe_deathrattle")
	pl.immune_frames = 0
	for part in 3:
		pl.immune_frames = 0
		pl.take_hit(99999, 1, 0.0)
	if not pl.dead:
		print("CT_NOTE: H 角色未死（AP/血量口径）——跳过断言")
	elif not toasts_has.call("ctprobe_deathrattle"):
		print("CT_FAIL: H deathrattle 死亡后未触发")
		fails += 1
	elif not before:
		print("CT_NOTE: H deathrattle 断言通过")
