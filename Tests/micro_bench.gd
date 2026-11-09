extends Node
## 微基准：分解弹幕各环节的单帧成本（不带arena，纯净环境）
## ① Expression 求值吞吐　② 纯运动学　③ 哈希重建

func _ready() -> void:
	var e := DanmakuExpr.new()
	e.compile("cos(r0+t*0.25)*2", ["r0", "t"])
	var ctx := {"r0": 1.0, "t": 60.0}
	## ① Expression 吞吐
	var n := 20000
	var t0 := Time.get_ticks_usec()
	for i in n:
		e.execute_dict(ctx, 0.0)
	var dt1 := Time.get_ticks_usec() - t0
	print("① Expression 求值：%d 次 / %d ms = %.1f μs/次" % [n, dt1 / 1000, float(dt1) / float(n)])
	## 常量折叠对照
	var e2 := DanmakuExpr.new()
	e2.compile("256", [])
	t0 = Time.get_ticks_usec()
	for i in n:
		e2.execute_dict({}, 0.0)
	var dt1b := Time.get_ticks_usec() - t0
	print("① 常量折叠后：%d 次 / %d ms = %.2f μs/次" % [n, dt1b / 1000, float(dt1b) / float(n)])
	## ② 哈希重建（4000弹）
	var hash := BulletHash.new()
	var dummy: Array = []
	for i in 4000:
		dummy.append(Vector2(randf() * 400, randf() * 400))
	t0 = Time.get_ticks_usec()
	for j in 60:
		hash.clear()
	print("② 哈希 clear×60：%d μs" % (Time.get_ticks_usec() - t0))
	print("MICRO_DONE")
	get_tree().quit(0)
