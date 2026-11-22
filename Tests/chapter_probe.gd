extends Node
## chapter_probe —— 章节系统探针（m116 地基 → m117 触发器/条目 → m118 跳转并列/音乐/背景/运动）
## A. ChapterData：CSV 装载/ordered 排序/覆盖注册 + m118 解析助手（goto/skip/moves）
## B. 行为检测底座：add/settle（noreset 标签）/display/behaviorReset/reached
## C. 章节流转：顺序块扫描→下一章 / loop 重进（_loops+条目状态清）/ slug 冻结+trigged
## D. 入场片段：resolve_clip 命中→playclips 条目挂载（clip_sched 非空）
## E. 触发器执行器：ticker/threshold(chaptertime)/feedback + starter/finner/stage/settle/next
## F. 角色条目（章节局部帧）+ 运动关键帧（二次贝塞尔）
## G. 跳转/并列：skip（无条件/条件）/goto（目标/the_fin/条件）/select（择一/全否跳块/空兜底）/fix（同屏独立）+ michihit/clear 语境
## H. 音乐方案（hard/continue/loop 区间）+ 背景画面（换/恢复）
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
	## 测试助手（行构造/安装/吐司查询）
	var mkrow := func(id: String, order: int, over: Dictionary = {}) -> Dictionary:
		var r := {"id": id, "name": id, "order": str(order), "transition": "next", "loop": "flow",
			"goto": "", "skip": "", "select": "", "fix": "", "music_plan": "", "music_track": "",
			"music_start": "", "entrance_clips": "", "chars": "", "local_triggers": "",
			"globe_triggers": "", "enemypcs": "", "boss_data": "", "background": "", "moves": ""}
		for k in over:
			r[k] = over[k]
		return r
	var install := func(rows: Array) -> void:
		arena._chapters_active = rows
		arena._chapter_idx = -1
		arena._ch_run = []
		arena._ch_done = false ## 完结门复位（C 节 the_fin 后的各节复用）
		arena._skip_plans = []
		arena._fb_seen.clear()
		arena._trig_memo.clear()
		for r2 in rows:
			for sk in ChapterData.parse_skip_cell(str(r2.get("skip", ""))):
				arena._skip_plans.append(sk)
	var toasts_has := func(s: String) -> bool:
		for t in arena._toasts:
			if str(t["text"]).contains(s):
				return true
		return false
	## A. ChapterData
	ChapterData.clear()
	var chp: String = THXKit.kpath("res://addons/thx_gamekit/data/chapters.csv")
	print("CHAP_NOTE: path=", chp, " exists=", FileAccess.file_exists(chp))
	var n: int = ChapterData.load_csv(chp)
	if n < 1:
		fails += 1
		print("CHAP_FAIL: A chapters.csv 装载不足（%d）" % n)
	var ordered: Array = ChapterData.ordered()
	if ordered.size() != n:
		fails += 1
		print("CHAP_FAIL: A ordered 序不符")
	## A2. 同 order 稳定邻接（m118 块扫描依赖）+ 解析助手
	ChapterData.clear()
	ChapterData.register({"id": "s1", "order": "5"})
	ChapterData.register({"id": "s0", "order": "1"})
	ChapterData.register({"id": "s2", "order": "5"})
	var od2: Array = ChapterData.ordered()
	if str(od2[0].get("id")) != "s0" or str(od2[1].get("id")) != "s1" or str(od2[2].get("id")) != "s2":
		fails += 1
		print("CHAP_FAIL: A2 同序邻接/排序不符（%s/%s/%s）" % [str(od2[0].get("id")), str(od2[1].get("id")), str(od2[2].get("id"))])
	var g0 := ChapterData.parse_goto_cell("chapter_3|time_frames>>=10")
	if str(g0.get("target")) != "chapter_3" or str(g0.get("cond")) != "time_frames>>=10":
		fails += 1
		print("CHAP_FAIL: A2 goto 解析不符")
	var sk0: Array = ChapterData.parse_skip_cell("a; b|cond2")
	if sk0.size() != 2 or str(sk0[0].get("id")) != "a" or str(sk0[1].get("cond")) != "cond2":
		fails += 1
		print("CHAP_FAIL: A2 skip 解析不符")
	var mv0: Array = ChapterData.parse_moves("MarisaA@10:300,200|260,100; Sanae@5:1,2")
	if mv0.size() != 2 or str(mv0[0].get("name")) != "MarisaA" or int(mv0[0].get("tick")) != 10 \
			or (mv0[0].get("pos") as Vector2) != Vector2(300, 200) \
			or not bool(mv0[0].get("has_ctrl")) or (mv0[0].get("ctrl") as Vector2) != Vector2(260, 100) \
			or bool(mv0[1].get("has_ctrl")):
		fails += 1
		print("CHAP_FAIL: A2 moves 解析不符")
	## B. 行为检测底座
	BehaviorScore.clear()
	BehaviorScore.add("graze", 3)
	BehaviorScore.add("miss", 1)
	if BehaviorScore.settle("graze") != 3:
		fails += 1
		print("CHAP_FAIL: B settle 读取不符")
	if int(BehaviorScore.settle("graze")) != 0:
		fails += 1
		print("CHAP_FAIL: B settle 未重置")
	BehaviorScore.set_noreset("miss", true)
	if BehaviorScore.settle("miss") != 1 or BehaviorScore.settle("miss") != 1:
		fails += 1
		print("CHAP_FAIL: B noreset 标签未豁免重置")
	if BehaviorScore.display_score("miss") < 1:
		fails += 1
		print("CHAP_FAIL: B display 副本不符")
	BehaviorScore.add("graze", 2)
	if not BehaviorScore.reached("graze", 2):
		fails += 1
		print("CHAP_FAIL: B 阈值查询不符")
	BehaviorScore.behavior_reset()
	if BehaviorScore.settle("graze") != 0:
		fails += 1
		print("CHAP_FAIL: B behaviorReset 未清")
	## C. 章节流转（块扫描→下一章 / loop 重进 / slug 冻结+trigged）
	arena._chapters_start()
	if arena._chapters_active.is_empty():
		fails += 1
		print("CHAP_FAIL: C 运行时未装载章节")
	else:
		arena._chapters_active = [mkrow.call("c1", 1), mkrow.call("c2", 2)]
		arena._skip_plans = []
		arena._chapter_idx = -1
		arena._ch_run = []
		arena._chapter_advance()
		if arena._ch_run.size() != 1 or str(arena._ch_run[0].get("id")) != "c1":
			fails += 1
			print("CHAP_FAIL: C 首章未装载")
		arena._ch_run[0]["_until_frame"] = arena.time_frames + 2 ## 压缩 flow 时长
		for fr in 4:
			arena._physics_process(1.0 / 60.0)
		if arena._ch_run.is_empty() or str(arena._ch_run[0].get("id")) != "c2":
			fails += 1
			print("CHAP_FAIL: C flow 流转未进下一章")
		arena._ch_run[0]["loop"] = "loop"
		arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
		for fr2 in 4:
			arena._physics_process(1.0 / 60.0)
		if arena._ch_run.is_empty() or int(arena._ch_run[0].get("_loops", 0)) < 1:
			fails += 1
			print("CHAP_FAIL: C loop 章未重进（_loops=%s）" % str(arena._ch_run[0].get("_loops", -1) if not arena._ch_run.is_empty() else -1))
		arena._ch_run[0]["loop"] = "slug"
		arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
		for fr3 in 6:
			arena._physics_process(1.0 / 60.0)
		if arena._ch_run.is_empty() or str(arena._ch_run[0].get("id")) != "c2":
			fails += 1
			print("CHAP_FAIL: C slug 章未冻结（提前流转）")
		arena._chapter_trigged()
		if not arena._ch_run.is_empty():
			fails += 1
			print("CHAP_FAIL: C trigged 唤起未流转（the_fin 完结）")
	## D. 入场片段：章节条目挂 playclips（clip_sched 非空）
	install.call([mkrow.call("ch_d", 1, {"entrance_clips": "clip_MarisaA_sub_demo_missile"})])
	arena._chapter_advance()
	var runs0: int = arena._spell_runs.size()
	var run_ok := false
	if arena._spell_runs.size() > 0:
		var run: Dictionary = arena._spell_runs[arena._spell_runs.size() - 1]
		run_ok = int(run.get("clip_sched", []).size()) > 0
	if not run_ok:
		fails += 1
		print("CHAP_FAIL: D 入场片段未挂 playclips 条目")
	else:
		print("CHAP_NOTE: 入场片段条目=%d" % runs0)
	## E. 触发器执行器：ticker/threshold(chaptertime)/feedback + starter/finner/stage/settle/next
	arena._toasts.clear()
	BehaviorScore.clear()
	install.call([mkrow.call("ch_trig", 1, {
		"local_triggers": "starter:toast(章开始);finner:toast(章结束);ticker:toast(章节ticker在拍);threshold:chaptertime>>=2=toast(章时阈值);feedback:miss=toast(自机被弹反馈)",
		"globe_triggers": "stage:toast(关卡开始);settle:toast(关卡结算);next:toast(公共转场)",
	}), mkrow.call("ch_trig2", 2)])
	arena._globe_level_exec("stage")
	if not toasts_has.call("关卡开始"):
		fails += 1
		print("CHAP_FAIL: E stage 触发器未执行")
	arena._chapter_advance() ## → ch_trig（starter）
	if not toasts_has.call("章开始"):
		fails += 1
		print("CHAP_FAIL: E starter 触发器未执行")
	var pl = arena.player_leader
	for fr5 in 3:
		arena._physics_process(1.0 / 60.0) ## chaptertime 1/2/3 → threshold 拍
	if not toasts_has.call("章时阈值"):
		fails += 1
		print("CHAP_FAIL: E threshold(chaptertime) 未触发")
	if not toasts_has.call("章节ticker在拍"):
		fails += 1
		print("CHAP_FAIL: E ticker 未执行")
	pl.take_hit(1, 0, 0.0) ## 自机被弹（feedback:miss）
	pl.immune_frames = 0
	arena._physics_process(1.0 / 60.0)
	if not toasts_has.call("自机被弹反馈"):
		fails += 1
		print("CHAP_FAIL: E feedback:miss 未触发")
	arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
	for fr6 in 4:
		arena._physics_process(1.0 / 60.0) ## finner+next 转场 → ch_trig2
	if not toasts_has.call("章结束"):
		fails += 1
		print("CHAP_FAIL: E finner 触发器未执行")
	if not toasts_has.call("公共转场"):
		fails += 1
		print("CHAP_FAIL: E next 转场触发器未执行")
	if arena._ch_run.is_empty() or str(arena._ch_run[0].get("id")) != "ch_trig2":
		fails += 1
		print("CHAP_FAIL: E next 转场后未进下一章")
	arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
	for fr7 in 4:
		arena._physics_process(1.0 / 60.0) ## → the_fin（settle）
	if not toasts_has.call("关卡结算"):
		fails += 1
		print("CHAP_FAIL: E settle 触发器未执行")
	if not arena._ch_run.is_empty():
		fails += 1
		print("CHAP_FAIL: E the_fin 未完结")
	## F. 角色条目（章节局部帧）+ 运动关键帧（二次贝塞尔）
	BehaviorScore.clear()
	arena._toasts.clear()
	install.call([mkrow.call("ch_chars", 1, {
		"chars": "MarisaA:0:9999:100,100:stay",
		"moves": "MarisaA@10:300,200|260,100",
	})])
	arena._chapter_advance()
	var tgt = null
	for e6 in arena.player_ents:
		if e6 is BattleEntity and e6.chara_name() == "MarisaA":
			tgt = e6
			break
	if tgt != null:
		tgt.dead = false
		arena.time_frames += 1
		arena._chapters_tick() ## 直驱章节拍（不跑战斗模拟——编排位不被实体自身运动积分漂移）
		if tgt.dead:
			fails += 1
			print("CHAP_FAIL: F 角色出场失败（dead）")
		## 注：有 moves 时编排自首拍接管——出场位=(100,100) 即贝塞尔 P0，
		## lt=1 处位置=(130.8,101)（曲线 1/10 处）——进场摆位由下方 t=0.5
		## 精确命中隐式验证（若未出场则不驱动，位置不会落在线上）
		for fr8 in 4:
			arena.time_frames += 1
			arena._chapters_tick() ## 局部帧累计至 5 → 贝塞尔 t=0.5
		## (100,100)→弯(260,100)→(300,200) t=0.5 = 0.25P0+0.5C+0.25P1 = (230,125)
		if (tgt.position - Vector2(230, 125)).length() > 2.0:
			fails += 1
			print("CHAP_FAIL: F 运动关键帧贝塞尔不符（@ %s）" % str(tgt.position))
		print("CHAP_NOTE: F 编排位=%s（lt=1 时=(130.8,101)）" % str(tgt.position))
	else:
		print("CHAP_SKIP: F 无 MarisaA 成员可测")
	## G. 跳转/并列
	BehaviorScore.clear()
	arena._toasts.clear()
	## G1 skip：无条件/条件不满足
	install.call([mkrow.call("g1a", 1, {"skip": "g1b"}), mkrow.call("g1b", 2), mkrow.call("g1c", 3)])
	arena._chapter_advance()
	arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
	for fr9 in 4:
		arena._physics_process(1.0 / 60.0)
	if arena._ch_run.is_empty() or str(arena._ch_run[0].get("id")) != "g1c":
		fails += 1
		print("CHAP_FAIL: G1 skip 未跳过 g1b（%s）" % str(arena._ch_run[0].get("id") if not arena._ch_run.is_empty() else "无"))
	install.call([mkrow.call("g1d", 1, {"skip": "g1e|time_frames>>=999999"}), mkrow.call("g1e", 2)])
	arena._chapter_advance()
	arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
	for fr10 in 4:
		arena._physics_process(1.0 / 60.0)
	if arena._ch_run.is_empty() or str(arena._ch_run[0].get("id")) != "g1e":
		fails += 1
		print("CHAP_FAIL: G1 skip 条件不满足仍跳过（%s）" % str(arena._ch_run[0].get("id") if not arena._ch_run.is_empty() else "无"))
	## G2 goto：目标/the_fin/条件不满足
	install.call([mkrow.call("g2a", 1, {"goto": "g2c"}), mkrow.call("g2b", 2), mkrow.call("g2c", 3)])
	arena._chapter_advance()
	arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
	for fr11 in 4:
		arena._physics_process(1.0 / 60.0)
	if arena._ch_run.is_empty() or str(arena._ch_run[0].get("id")) != "g2c":
		fails += 1
		print("CHAP_FAIL: G2 goto 未跳转（%s）" % str(arena._ch_run[0].get("id") if not arena._ch_run.is_empty() else "无"))
	arena._toasts.clear()
	install.call([mkrow.call("g2d", 1, {"goto": "the_fin", "globe_triggers": "settle:toast(关卡结算)"}), mkrow.call("g2e", 2)])
	arena._chapter_advance()
	arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
	for fr12 in 4:
		arena._physics_process(1.0 / 60.0)
	if not arena._ch_run.is_empty() or not toasts_has.call("关卡结算"):
		fails += 1
		print("CHAP_FAIL: G2 goto the_fin 未直达完结")
	install.call([mkrow.call("g2f", 1, {"goto": "g2h|time_frames>>=999999"}), mkrow.call("g2g", 2), mkrow.call("g2h", 3)])
	arena._chapter_advance()
	arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
	for fr13 in 4:
		arena._physics_process(1.0 / 60.0)
	if arena._ch_run.is_empty() or str(arena._ch_run[0].get("id")) != "g2g":
		fails += 1
		print("CHAP_FAIL: G2 goto 条件不满足仍跳转（%s）" % str(arena._ch_run[0].get("id") if not arena._ch_run.is_empty() else "无"))
	## G3 select：择一/全否跳块/空兜底
	install.call([mkrow.call("g3a", 1, {"select": "1.0>0.5"}), mkrow.call("g3b", 1, {"select": "1.0<0.5"}), mkrow.call("g3c", 2)])
	arena._chapter_advance()
	if arena._ch_run.size() != 1 or str(arena._ch_run[0].get("id")) != "g3a":
		fails += 1
		print("CHAP_FAIL: G3 select 未择一（%s）" % str(arena._ch_run[0].get("id") if not arena._ch_run.is_empty() else "无"))
	install.call([mkrow.call("g3d", 1, {"select": "1.0<0.5"}), mkrow.call("g3e", 1, {"select": "2.0<0.5"}), mkrow.call("g3f", 2)])
	arena._chapter_advance()
	if arena._ch_run.size() != 1 or str(arena._ch_run[0].get("id")) != "g3f":
		fails += 1
		print("CHAP_FAIL: G3 select 均不满足未整块跳过（%s）" % str(arena._ch_run[0].get("id") if not arena._ch_run.is_empty() else "无"))
	install.call([mkrow.call("g3g", 1, {"select": "1.0<0.5"}), mkrow.call("g3h", 1), mkrow.call("g3i", 2)])
	arena._chapter_advance()
	if arena._ch_run.size() != 1 or str(arena._ch_run[0].get("id")) != "g3h":
		fails += 1
		print("CHAP_FAIL: G3 select 空条件未兜底（%s）" % str(arena._ch_run[0].get("id") if not arena._ch_run.is_empty() else "无"))
	## G4 fix：并列混合（同序同屏，各自独立结束）
	install.call([mkrow.call("g4a", 1, {"fix": "the_start,the_fin"}), mkrow.call("g4b", 1, {"fix": "the_start,the_fin"}), mkrow.call("g4c", 2)])
	arena._chapter_advance()
	if arena._ch_run.size() != 2:
		fails += 1
		print("CHAP_FAIL: G4 fix 未并列同屏（%d）" % arena._ch_run.size())
	else:
		arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
		arena._ch_run[1]["_until_frame"] = arena.time_frames + 10
		for fr14 in 4:
			arena._physics_process(1.0 / 60.0)
		if arena._ch_run.size() != 1 or str(arena._ch_run[0].get("id")) != "g4b":
			fails += 1
			print("CHAP_FAIL: G4 fix 成员未独立结束（%d/%s）" % [arena._ch_run.size(),
				str(arena._ch_run[0].get("id")) if not arena._ch_run.is_empty() else "无"])
		if not arena._ch_run.is_empty():
			arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
			for fr15 in 4:
				arena._physics_process(1.0 / 60.0)
	## G5 michihit/clear 语境（道中=非末块/关底=末块或 goto the_fin）
	install.call([mkrow.call("g5a", 1), mkrow.call("g5b", 2)])
	arena._chapter_advance()
	if arena._chapter_is_final():
		fails += 1
		print("CHAP_FAIL: G5 道中语境误判为关底")
	arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
	for fr16 in 4:
		arena._physics_process(1.0 / 60.0)
	if arena._ch_run.is_empty() or not arena._chapter_is_final():
		fails += 1
		print("CHAP_FAIL: G5 关底语境未判定（%s）" % str(arena._ch_run[0].get("id") if not arena._ch_run.is_empty() else "无"))
	## H. 音乐方案 + 背景画面
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var pcm := PackedByteArray()
	pcm.resize(22050 * 2) ## 1 秒 16-bit 单声道
	for i in 22050:
		pcm.encode_s16(i * 2, int(sin(float(i) * TAU * 440.0 / 22050.0) * 8000.0))
	wav.data = pcm
	wav.save_to_wav("user://chap_music_test.wav")
	install.call([mkrow.call("h1", 1, {"music_plan": "hard", "music_track": "user://chap_music_test.wav", "music_start": "0.25"})])
	arena._chapter_advance()
	if arena._music_a == null or not arena._music_a.playing:
		fails += 1
		print("CHAP_FAIL: H1 音乐 hard 起始未播放")
	install.call([mkrow.call("h2", 2, {"music_track": "user://chap_music_test.wav"})])
	arena._chapter_advance() ## 进入 h2（continue：同轨继续不重启）
	arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
	for fr17 in 4:
		arena._physics_process(1.0 / 60.0) ## 进入 h2（continue：同轨继续不重启）
	if arena._music_a == null or not arena._music_a.playing or arena._music_track != "user://chap_music_test.wav":
		fails += 1
		print("CHAP_FAIL: H2 音乐 continue 语义不符")
	install.call([mkrow.call("h3", 3, {"music_plan": "loop:0.2,0.8", "music_track": "user://chap_music_test.wav"})])
	arena._chapter_advance()
	if arena._music_loop_range.size() != 2 or absf(arena._music_loop_range[0] - 0.2) > 0.01 or absf(arena._music_loop_range[1] - 0.8) > 0.01:
		fails += 1
		print("CHAP_FAIL: H3 内循环区间未登记（%s）" % str(arena._music_loop_range))
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.9))
	img.save_png("user://chap_bg_test.png")
	install.call([mkrow.call("h4a", 1, {"background": "user://chap_bg_test.png"})])
	arena._chapter_advance()
	if arena._ch_bg_sprite == null or arena._ch_bg_sprite.texture == null or not arena._ch_bg_sprite.visible:
		fails += 1
		print("CHAP_FAIL: H4 章节背景未应用")
	install.call([mkrow.call("h4b", 2)])
	arena._chapter_advance()
	if arena._ch_bg_sprite != null and arena._ch_bg_default == null and (arena._ch_bg_sprite.visible or arena._ch_bg_sprite.texture != null):
		fails += 1
		print("CHAP_FAIL: H4 空背景未恢复默认（无默认=隐藏）")
	if not arena._ch_run.is_empty():
		arena._ch_run[0]["_until_frame"] = arena.time_frames + 2
		for fr18 in 4:
			arena._physics_process(1.0 / 60.0) ## the_fin → 恢复默认
	if fails == 0:
		print("CHAP_OK: ChapterData/行为检测/块流转/入场片段/触发器全类/角色条目/运动关键帧/跳转并列/音乐方案/背景画面 全过")
	else:
		print("CHAP_SUMMARY: fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
