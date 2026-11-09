extends Node
## live_smoke —— 真渲染默认对战长跑探针（Hd 视图全程开）
const RUN := 3600 ## 60 秒（对照作者 CSV 的 200ms 冻结段）
var arena: Node2D
var _step := 0
var _last := 0
var _dts: Array = []
func _ready() -> void:
	GameGlobals.arena_mode = "versus"
	arena = load("res://scenes/battle_arena.tscn").instantiate()
	add_child(arena)
func _process(_d: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _last > 0:
		_dts.append(float(now - _last) / 1000.0)
	_last = now
	_step += 1
	if _step % 300 == 0:
		print("[live f=%d] 弹=%d ents=%d" % [_step, arena.bullets.size(), arena.entities.size()])
	if _step >= RUN:
		var srt: Array = _dts.duplicate()
		srt.sort()
		print("FRAME_MS p50=%.1f p90=%.1f p99=%.1f max=%.1f" % [
			srt[srt.size() / 2], srt[int(srt.size() * 0.9)], srt[int(srt.size() * 0.99)], srt[srt.size() - 1]])
		print("LIVE_DONE")
		get_tree().quit(0)
