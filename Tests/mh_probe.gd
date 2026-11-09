extends Node
## =============================================================
## mh_probe —— MotionHot 接线现状普查（真实默认队，headless 可跑）
##   每 100 帧：总弹 / frozen_ok / 已注册 C++(mh_slot>=0) / 分型
##   （oob 模式、repeat 载体、表达式色/隐身、tag）——为 C++ 完整状态
##   归属（哪些弹可整体交给 C++）提供实测分布
## 用法：godot --headless --path . res://Tests/mh_probe.tscn
## =============================================================
var arena: Node2D
var step := 0

func _ready() -> void:
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)

func _process(_d: float) -> void:
	step += 1
	if step == 30 and arena.pause_panel != null:
		arena.pause_panel.visible = false
	if step % 100 == 0 and step >= 200:
		var tot := 0
		var fz := 0
		var reg := 0
		var fz_oob := {}
		var fz_rep := 0
		var fz_expr := 0
		var fz_pure := 0
		var tags := {}
		for b in arena.bullets:
			tot += 1
			var tg := str(b.ev.tag)
			tags[tg] = int(tags.get(tg, 0)) + 1
			if b.mh_slot >= 0:
				reg += 1
			if not b.frozen_ok:
				continue
			fz += 1
			fz_oob[b.ev.oob_mode] = int(fz_oob.get(b.ev.oob_mode, 0)) + 1
			var rep: bool = b.repeat_enabled and b.repeat_freq_now > 0
			var ex: bool = b.ev.ex_alpha != null or b.ev.ex_hue != null or b.ev.ex_sat != null or b.ev.ex_pass != null
			if rep:
				fz_rep += 1
			if ex:
				fz_expr += 1
			if not rep and not ex and b.ev.oob_mode != 1 and b.ev.tag == DanmakuEventData.TAG_REGULAR:
				fz_pure += 1
		print("[mh f=%d] 弹=%d frozen=%d 已注册C++=%d | frozen 分型：oob=%s repeat载体=%d 表达式=%d 纯定值(可整体C++)=%d | tag=%s" % [
			step, tot, fz, reg, str(fz_oob), fz_rep, fz_expr, fz_pure, str(tags)])
	if step >= 900:
		get_tree().quit(0)
