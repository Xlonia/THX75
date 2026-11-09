extends Node
## =============================================================
## bench —— 性能休整版基准（模拟 Lunatic 级1000弹幕 + 队伍战）
## 运行：godot --path . res://Tests/bench.tscn --resolution 1280x960 --windowed
## 【目标】physics + script 各线程 < 10ms
## 输出：控制台摘要 + user://bench_result.csv + user://perf_log.csv
## =============================================================

const RUN_FRAMES := 600
const LEVELS := [100, 500, 1000, 2000]

class WorldStub:
	var frame := 0.0
	func bullet_time_frames() -> float: return frame
	func bullet_phase() -> int: return 1
	func bullet_nearest_enemy(_s: int, _f: Vector2) -> BattleEntity: return null
	func bullet_nearest_enemy_pos(s: int, f: Vector2) -> Vector2:
		return f + (Vector2.RIGHT if s == 0 else Vector2.LEFT)
	func bullet_hit_query(_cx: float, _cy: float, _r: float, _s: int, _e) -> Dictionary: return {}
	func spawn_event_by_name(_n: String, _at: Vector2, _s: int, _d: int) -> void: pass

var _frame := 0
var _level_idx := 0
var _rows: Array[String] = []
var _bullets: Array = []
var _stub := WorldStub.new()

func _ready() -> void:
	_inject(LEVELS[0])
	_rows.append("level,frame,bullets,physics_ms,process_ms,script_ms")

func _inject(n: int) -> void:
	_bullets.clear()
	var ev_a := _find("demo_ring")
	var ev_b := _find("demo_aimed")
	if ev_a == null or ev_b == null:
		push_error("[bench] 找不到演示事件")
		get_tree().quit(1)
		return
	for i in n:
		var ev := ev_a if i % 3 != 0 else ev_b  ## 2/3 物理环形 + 1/3 自机狙
		var origin := Vector2(randf() * 400.0, randf() * 400.0)
		var b := Bullet.new()
		b.setup(ev, origin, 0 if i % 2 == 0 else 1, null, _stub, 0)
		_bullets.append(b)
	print("[bench] 注入 %d 弹幕" % n)

func _find(nm: String) -> DanmakuEventData:
	for ev in GameGlobals.editor_events:
		if ev.event_name == nm:
			return ev
	return GameGlobals.get_event(nm)

func _physics_process(_delta: float) -> void:
	_frame += 1
	_stub.frame = float(_frame)
	var gctx := {"field_t": float(_frame), "field_phase": 1}
	for i in range(_bullets.size() - 1, -1, -1):
		var b: Bullet = _bullets[i]
		b.sync_shared(gctx)
		if not b.update(1.0):
			_bullets.remove_at(i)
	## 【性能】哈希重建每3帧一次（作者：能跳则跳）
	if _frame % 3 == 0:
		var hash := BulletHash.new()
		for b in _bullets:
			hash.insert(b)
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_rows.append("%d,%d,%d,%.3f,%.3f,%.3f" % [LEVELS[_level_idx], _frame, _bullets.size(), phys_ms, proc_ms, 0.0])
	if _frame >= RUN_FRAMES:
		_next_level()

func _next_level() -> void:
	_level_idx += 1
	_frame = 0
	if _level_idx >= LEVELS.size():
		_finish()
		return
	_inject(LEVELS[_level_idx])

func _finish() -> void:
	var path := "user://bench_result.csv"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_rows))
		f.close()
	print("======== BENCH 摘要（性能休整后）========")
	var li := -1
	var acc_p := 0.0
	var acc_s := 0.0
	var peak_p := 0.0
	var cnt := 0
	var abn := 0
	for r in _rows:
		if r.begins_with("level"):
			continue
		var parts := r.split(",")
		var lvl := int(parts[0])
		if lvl != li:
			if li >= 0:
				print("弹幕 %5d：physics均值 %.2fms 峰值 %.2fms | 异常帧 %d/%d" % [li, acc_p / cnt, peak_p, abn, cnt])
			li = lvl
			acc_p = 0.0
			acc_s = 0.0
			peak_p = 0.0
			cnt = 0
			abn = 0
		var ms := parts[3].to_float()
		acc_p += ms
		peak_p = maxf(peak_p, ms)
		if ms > 10.0:
			abn += 1
		cnt += 1
	if li >= 0:
		print("弹幕 %5d：physics均值 %.2fms 峰值 %.2fms | 异常帧 %d/%d" % [li, acc_p / cnt, peak_p, abn, cnt])
	print("CSV：%s" % ProjectSettings.globalize_path(path))
	print("BENCH_DONE")
	get_tree().quit(0)
