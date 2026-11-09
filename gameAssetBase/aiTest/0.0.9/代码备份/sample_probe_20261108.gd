extends Node
## sample_probe —— 采样平滑红线验证（0.0.9 作者设计）
##   ①一致性：N=1（逐帧）vs N=4（采样+插值）——采样时刻的弹幕位置必须一致
##   （匀速解析弹逐位一致；变速表达式弹允许低阶积分差——输出实际误差）
##   ②性能：live 阶段 N=4 与 N=1 的 phys 对比
## 用法：godot --path . res://Tests/sample_probe.tscn
var arena: Node2D
var phase := 0          ## 0=N=1 收集轨迹；1=N=4 收集采样帧 target
var step := 0
var carrier_id := 0
var traj_n1: Dictionary = {}    ## 帧 -> pos
var traj_n4: Dictionary = {}    ## 帧 -> target（采样帧）
var born_frame := -1
func _ready() -> void:
	_start_arena(1)
func _start_arena(n: int) -> void:
	seed(20261108) ## 两轮同随机序（发射器位置一致）
	GameGlobals.bullet_sample_n = n
	GameGlobals.arena_mode = "preview"
	GameGlobals.preview_event_name = "sonic_wave_like0"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
func _process(_d: float) -> void:
	step += 1
	if arena == null:
		return
	## 锁定第一颗载体（depth0 且 repeat_enabled）
	if carrier_id == 0 and step > 20:
		for b in arena.bullets:
			if b.ev != null and b.ev.event_name == "sonic_wave_like0" and b.depth == 0 and b.repeat_enabled:
				carrier_id = b.get_instance_id()
				born_frame = step
				print("[probe] 载体锁定 frame=%d phase=%d" % [step, arena._sample_n])
				break
	if carrier_id != 0:
		for b in arena.bullets:
			if b.get_instance_id() == carrier_id:
				if phase == 0:
					traj_n1[step] = Vector2(b.pos)
				elif step % 20 == 0:
					print("[n4 f=%d] elapsed=%.0f sn=%d pos=%s" % [step, b._sample_elapsed, arena._sample_n, str(b.pos)])
				else:
					## target 恒=最新采样时刻的公式位置（采样帧更新）
					traj_n4[step] = Vector2(b._pos_target)
				break
	if step >= 420:
		if phase == 0:
			print("[probe] N=1 轨迹 %d 点，切换 N=4" % traj_n1.size())
			phase = 1
			step = 0
			carrier_id = 0
			born_frame = -1
			traj_n4.clear()
			arena.queue_free()
			_start_arena(4)
		else:
			_report()
			get_tree().quit(0)
func _report() -> void:
	## 帧对齐：N=4 的采样帧（step-born)%4==0 → 对比 N=1 同 relative 帧 pos
	var born1 := -1
	for f in traj_n1.keys():
		if int(f) >= 20 and born1 < 0:
			born1 = int(f) - 1 ## 载体 born 前一帧=相对 0 近似（N=1 从 born+1 记起）
	var common := []
	for f in traj_n4.keys():
		var rel: int = int(f) - born_frame
		if rel > 0 and traj_n1.has(born1 + rel):
			common.append([rel, born1 + rel, f])
	common.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var mx := 0.0
	var sum := 0.0
	var worst_f := 0
	for c in common:
		var d: float = (traj_n1[c[1]] as Vector2).distance_to(traj_n4[c[2]] as Vector2)
		sum += d
		if d > mx:
			mx = d
			worst_f = int(c[0])
	print("========================================")
	print("SAMPLE_PROBE 共同采样帧=%d 平均偏差=%.3fpx 最大偏差=%.3fpx（帧%d）" % [
		common.size(), sum / maxf(1.0, float(common.size())), mx, worst_f])
	for ci in [0, 1, 2, 4, 8, 16, 32, 64]:
		if ci < common.size():
			var c = common[ci]
			print("  rel=%4d n1_pos=%s n4_target=%s" % [c[0], str(traj_n1[c[1]]), str(traj_n4[c[2]])])
	if mx < 1.0:
		print("SAMPLE_OK —— 采样时刻位置与逐帧运算一致（<1px）")
	elif mx < 6.0:
		print("SAMPLE_NEAR —— 低阶积分差（变速表达式弹大步进固有；<6px）")
	else:
		print("SAMPLE_FAIL —— 偏差过大")
	print("========================================")
