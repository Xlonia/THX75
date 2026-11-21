extends Node
## chapter_probe —— 章节系统探针（m116·0.2.0 第一批）
## A. ChapterData：CSV 装载/ordered 排序/覆盖注册
## B. 行为检测底座：add/settle（noreset 标签）/display/behaviorReset/reached
## C. 章节运行时：starter→flow 流转→finner→下一章→the_fin（30s 下限压缩测=直接改 until）
## D. 入场片段：resolve_clip 命中→playclips 条目挂载（clip_sched 非空）
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
	## A. ChapterData
	ChapterData.clear()
	var chp: String = THXKit.kpath("res://addons/thx_gamekit/data/chapters.csv")
	print("CHAP_NOTE: path=", chp, " exists=", FileAccess.file_exists(chp))
	var n: int = ChapterData.load_csv(chp)
	if n < 2:
		fails += 1
		print("CHAP_FAIL: A chapters.csv 装载不足（%d）" % n)
	var ordered: Array = ChapterData.ordered()
	if ordered.size() != n:
		fails += 1
		print("FRULE_FAIL: A ordered 序不符")
	if str(ordered[0].get("id", "")) != "chapter_1":
		fails += 1
		print("FRULE_FAIL: A 排序首章不符（%s）" % str(ordered[0].get("id", "")))
	## B. 行为检测底座
	BehaviorScore.clear()
	BehaviorScore.add("graze", 3)
	BehaviorScore.add("miss", 1)
	if BehaviorScore.settle("graze") != 3:
		fails += 1
		print("FRULE_FAIL: B settle 读取不符")
	if int(BehaviorScore.settle("graze")) != 0:
		fails += 1
		print("FRULE_FAIL: B settle 未重置")
	BehaviorScore.set_noreset("miss", true)
	if BehaviorScore.settle("miss") != 1 or BehaviorScore.settle("miss") != 1:
		fails += 1
		print("FRULE_FAIL: B noreset 标签未豁免重置")
	if BehaviorScore.display_score("miss") < 1:
		fails += 1
		print("FRULE_FAIL: B display 副本不符")
	BehaviorScore.add("graze", 2)
	if not BehaviorScore.reached("graze", 2):
		fails += 1
		print("FRULE_FAIL: B 阈值查询不符")
	BehaviorScore.behavior_reset()
	if BehaviorScore.settle("graze") != 0:
		fails += 1
		print("FRULE_FAIL: B behaviorReset 未清")
	## C. 章节运行时：压缩流转（直接改 until）
	arena._chapters_start()
	if arena._chapters_active.is_empty():
		fails += 1
		print("CHAP_FAIL: C 运行时未装载章节")
	else:
		var idx0: int = arena._chapter_idx
		arena._chapter_until = arena.time_frames + 2 ## 压缩 flow 时长
		for fr in 4:
			arena._physics_process(1.0 / 60.0)
		if arena._chapter_idx != idx0 + 1:
			fails += 1
			print("CHAP_FAIL: C flow 流转未进下一章（%d→%d）" % [idx0, arena._chapter_idx])
		## 循环章：改 loop=loop → 重进当前
		arena._chapters_active[arena._chapter_idx]["loop"] = "loop"
		arena._chapter_until = arena.time_frames + 2
		for fr2 in 4:
			arena._physics_process(1.0 / 60.0)
		if arena._chapter_idx != idx0 + 1:
			fails += 1
			print("CHAP_FAIL: C loop 章未重进")
	## D. 入场片段：章节条目挂 playclips（clip_sched 非空）
	arena._chapters_active = [{"id": "ch_t", "name": "测试", "loop": "flow",
		"entrance_clips": "clip_MarisaA_sub_demo_missile"}]
	arena._chapter_idx = -1
	var runs0: int = arena._spell_runs.size()
	arena._chapter_advance()
	var run: Dictionary = arena._spell_runs[arena._spell_runs.size() - 1] if arena._spell_runs.size() > runs0 else {}
	if run.is_empty() or int(run.get("clip_sched", []).size()) == 0:
		fails += 1
		print("CHAP_FAIL: D 入场片段未挂 playclips 条目")
	else:
		print("CHAP_NOTE: 入场片段条目=%d" % int(run["clip_sched"].size()))
	if fails == 0:
		print("CHAP_OK: ChapterData/行为检测/章节流转/入场片段 全过")
	get_tree().quit(1 if fails > 0 else 0)
