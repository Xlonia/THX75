extends Node
## =============================================================
## ghost_census_probe —— 真实默认队长跑"无弹之章"普查（20261109 根因验证）
##   每 20 帧（窗口模式，需 GPU）：
##   ①实际幽灵：GPU DDM 回读白像素 ∖ 本拍上传印章覆盖（r+1.5 盘）
##     ——修复后必须恒 0（所见即所判：DDM 每个白点都有一枚本拍印章）
##   ②反事实（旧守卫）：读回印章缓冲尾部 [n, ⌈n/64⌉·64)——旧 shader 会
##     把这些以前帧残留印章画上 DDM；统计其中场内且不与本拍印章重合的数量
##     =修复前此刻会出现的幽灵弹数（无需回退 shader 的修复前对照）
##   f=300 / f=900 玩家释放消弹，分区统计消弹区内的幽灵/反事实
## 用法：godot --path . res://Tests/ghost_census_probe.tscn
## =============================================================
const END := 1500
var arena: Node2D
var step := 0
var zones: Array = []          ## [[pos, r, f0]]
var max_ghost := [0, 0]
var sum_ghost := [0, 0]
var cf_total := [0, 0]         ## 反事实幽灵印章累计（两侧）
var cf_zone := 0               ## 反事实落在消弹区内
var cf_max := [0, 0]
var checks := 0

func _ready() -> void:
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)

func _process(_d: float) -> void:
	if arena == null:
		return
	step += 1
	if step == 30 and arena.pause_panel != null:
		arena.pause_panel.visible = false
	if not arena.gpu_ok:
		if step == 40:
			print("GHOST_SKIP —— GPU 不可用（headless）")
			get_tree().quit(0)
		return
	if step == 300 or step == 900:
		var p: BattleEntity = arena.player_leader
		if p != null and not p.dead:
			p.spell_cards = maxi(p.spell_cards, 1)
			zones.append([p.position, 208.0, step])
			arena._apply_release(p, "s")
			print("[census f=%d] 消弹释放 at %s" % [step, str(p.position)])
	if step % 20 == 0 and step >= 60:
		checks += 1
		var line := "[census f=%d] 弹=%d" % [step, arena.bullets.size()]
		for side in 2:
			var ddm: DdmGpu = arena.ddm_gpu0 if side == 0 else arena.ddm_gpu1
			var buf: PackedFloat32Array = arena._stamp_buf0 if side == 0 else arena._stamp_buf1
			var r := _census(ddm, buf)
			max_ghost[side] = maxi(max_ghost[side], r[0])
			sum_ghost[side] += r[0]
			cf_total[side] += r[1]
			cf_max[side] = maxi(cf_max[side], r[1])
			cf_zone += r[2]
			line += " | 图%d 章=%d 实际幽灵px=%d 反事实旧守卫幽灵章=%d(消弹区内%d)" % [side, r[3], r[0], r[1], r[2]]
		if step % 100 == 0 or line.find("实际幽灵px=0") < 0:
			print(line)
	if step >= END:
		print("=== 普查汇总（%d 次检查，两次消弹）===" % checks)
		print("  实际幽灵像素：图0 峰值=%d 累计=%d | 图1 峰值=%d 累计=%d" % [max_ghost[0], sum_ghost[0], max_ghost[1], sum_ghost[1]])
		print("  反事实（修复前旧守卫）幽灵印章：图0 累计=%d 峰值=%d | 图1 累计=%d 峰值=%d | 落在消弹区内累计=%d" % [
			cf_total[0], cf_max[0], cf_total[1], cf_max[1], cf_zone])
		if max_ghost[0] == 0 and max_ghost[1] == 0:
			print("GHOST_OK")
			get_tree().quit(0)
		else:
			print("GHOST_FAIL")
			get_tree().quit(1)

## 返回 [实际幽灵px, 反事实幽灵章数, 反事实落消弹区内数, 本拍章数]
func _census(ddm: DdmGpu, buf: PackedFloat32Array) -> Array:
	var rd: RenderingDevice = arena.shared_rd
	var n: int = mini(buf.size() >> 2, DdmGpu.MAX_STAMPS)
	## 本拍覆盖掩膜（r+1.5 盘）
	var cov := PackedByteArray()
	cov.resize(400 * 400)
	for k in n:
		var cx: float = buf[k * 4]
		var cy: float = buf[k * 4 + 1]
		var rr: float = maxf(buf[k * 4 + 2], 0.5) + 1.5
		var x0 := maxi(0, int(floorf(cx - rr)))
		var x1 := mini(399, int(ceilf(cx + rr)))
		var y0 := maxi(0, int(floorf(cy - rr)))
		var y1 := mini(399, int(ceilf(cy + rr)))
		var r2 := rr * rr
		for y in range(y0, y1 + 1):
			var dy := float(y) + 0.5 - cy
			for x in range(x0, x1 + 1):
				var dx := float(x) + 0.5 - cx
				if dx * dx + dy * dy <= r2:
					cov[y * 400 + x] = 1
	## ①实际幽灵
	var raw: PackedByteArray = rd.texture_get_data(ddm.image_rid(), 0)
	var ghost := 0
	for i in raw.size():
		if raw[i] > 128 and cov[i] == 0:
			ghost += 1
	## ②反事实：旧守卫会额外读的尾部 [n, ⌈n/64⌉·64)
	var cf := 0
	var cfz := 0
	if n > 0:
		var tail_end: int = mini(((n + 63) >> 6) << 6, DdmGpu.MAX_STAMPS)
		if tail_end > n:
			var bytes: PackedByteArray = rd.buffer_get_data(ddm._stamp_buffer, n * 16, (tail_end - n) * 16)
			var tail := bytes.to_float32_array()
			for k2 in range(0, tail.size(), 4):
				var tx: float = tail[k2]
				var ty: float = tail[k2 + 1]
				var tr: float = tail[k2 + 2]
				if tr <= 0.0 and tx == 0.0 and ty == 0.0:
					continue ## 从未写过的零条目（旧守卫下也不出像素）
				if tx < 0.0 or tx >= 400.0 or ty < 0.0 or ty >= 400.0:
					continue
				if cov[int(ty) * 400 + int(tx)] == 1:
					continue ## 恰与本拍真弹重合——不算幽灵
				cf += 1
				for z in zones:
					if Vector2(tx, ty).distance_to(z[0]) <= float(z[1]):
						cfz += 1
						break
	return [ghost, cf, cfz, n]
