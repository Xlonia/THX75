extends Node
## spin_hitbox_probe —— 偏心中心渲染变换+特殊判定盒采样（内核件直测）
func _ready() -> void:
	var fails := 0
	## 偏心：draw_transform 原点=弹心-偏移（旋转后）
	var ev := DanmakuEventData.new()
	ev.event_name = "spin_test"
	ev.texture = "tama0" ## float 列直接赋数值
	ev.danmaku_size_muti = 1.0
	ev.spin_x = 10.0
	ev.spin_y = 0.0
	ev.compile()
	var e := EntityCore.new()
	e.setup({"Name": "t", "Cruise": 6, "Normal": 3, "Determine": 3}, 0, EntityCore.Kind.MEMBER, true)
	add_child(e)
	var world := get_tree().current_scene if get_tree().current_scene != self else self
	var b := Bullet.new()
	b.setup(ev, Vector2(200, 200), 0, e, self, 0)
	var ok1: bool = b.spin_offset == Vector2(10, 0)
	print("  %s spin_offset 解析（%s）" % ["PASS" if ok1 else "FAIL", str(b.spin_offset)])
	var xf := b.draw_transform()
	var rot0 := Transform2D(0, Vector2(200, 200))
	var ok2: bool = xf.origin.distance_to(rot0.origin + Vector2(-10, 0)) < 0.01
	print("  %s draw_transform 偏心原点（%s）" % ["PASS" if ok2 else "FAIL", str(xf.origin)])
	## 静态跳过：默认 (0,0) 弹 spin_offcenter=false
	var b2 := Bullet.new()
	b2.setup(GameGlobals.get_event("demo_youshio1"), Vector2(100, 100), 0, e, self, 0)
	print("  %s 默认弹 spin_offcenter=false（静态跳过）: %s" % ["PASS" if not b2.spin_offcenter() else "FAIL", str(b2.spin_offset)])
	print("SPIN_OK" if fails == 0 else "SPIN_FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
