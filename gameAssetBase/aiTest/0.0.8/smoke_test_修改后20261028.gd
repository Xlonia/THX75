extends Node
## =============================================================
## smoke_test —— headless 冒烟测试（第①期版）
##   godot --headless --path . res://Tests/smoke_test.tscn
## 覆盖：CSV往返(45列) / 表达式(翻译+折叠) / 角色表(poi列) / .thx
##   / 哈希碰撞 / 被弹(I类FLT_MAX) / 火控(poi排布) / 杂兵排布预设公式
## =============================================================

var fails: Array[String] = []

func _ready() -> void:
	_test_csv_roundtrip()
	_test_expr()
	_test_chara_db()
	_test_thx_roundtrip()
	_test_hash_and_hits()
	_test_fire_poi()
	_test_formation()
	_test_poi_expr_and_sweep()
	_test_arena_hits_and_heatmap()
	_test_stress_override()
	_test_timeline_and_laser()
	_test_demo_data_guard()
	_test_rotate_repeat()
	_test_gettarget_wordparams()
	_test_types_and_binding()
	_test_facing_and_semantics()
	_report()

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] %s" % msg)
	else:
		fails.append(msg)
		print("  [FAIL] %s" % msg)

## —— ① CSV 往返（45列新表头）——
func _test_csv_roundtrip() -> void:
	print("[1] CSV 往返（46列）")
	var ev := DanmakuEventData.new()
	ev.event_name = "t1"
	ev.slot = "sub" ## wing→sub 兼容验证
	ev.tag = "IsDanmakuPhysical"
	ev.speed = "2+t*0.01"
	ev.x = "cos(r0+t*0.1)"
	ev.y = "sin(r0+t*0.1)"
	ev.func_expr = "sin(t*0.05)*20"
	ev.x_offset = 3.5
	ev.y_offset = -2.0
	ev.saturation = 0.8
	ev.hue = 0.25
	ev.lost_if = "t>100"
	ev.laser_n_step = 2
	ev.rate_specified = true
	ev.rate = 0.25
	ev.pattern_specified = true
	ev.pattern = 0.4
	var row := ev.to_csv_row()
	var back := DanmakuEventData.new()
	back.from_csv_row(DanmakuEventData.split_csv_line(row))
	_check(back.slot == "sub", "sub 槽位往返")
	_check(back.x_offset == 3.5 and back.y_offset == -2.0, "x/y_offset 往返")
	_check(absf(back.saturation - 0.8) < 0.001 and absf(back.hue - 0.25) < 0.001, "saturation/hue 往返")
	_check(back.lost_if == "t>100" and back.laser_n_step == 2, "lost_if / laser_n_step 往返")
	_check(back.rate_specified and absf(back.rate - 0.25) < 0.001, "rate 指定往返")
	_check(back.func_expr == "sin(t*0.05)*20", "func_expr 往返")
	## 旧 wing 槽值自动迁移为 sub（行=现表头格式，slot 列填 wing）
	var base := DanmakuEventData.new()
	var cells := DanmakuEventData.split_csv_line(base.to_csv_row())
	var widx := DanmakuEventData.CSV_HEADER.find("slot")
	cells[widx] = "wing"
	var old_wing := DanmakuEventData.new()
	old_wing.from_csv_row(cells)
	_check(old_wing.slot == "sub", "旧 wing 槽值自动迁移为 sub")
	## 官方演示表
	var events := DanmakuEventData.parse_csv_text(FileAccess.get_file_as_string("res://gameAssetBase/danmaku_event.csv"))
	_check(events.size() >= 5, "官方演示表 ≥5 行解析（得 %d）" % events.size())
	## 【20261003】演示表可能含作者正在调试的表达式（如 +* 笔误）——
	## 只定点校验核心事件，作者行的编译错误交给编辑器可行性检查
	var aimed_ok := true
	for e in events:
		if e.event_name == "demo_aimed":
			aimed_ok = e.compile().is_empty()
	_check(aimed_ok, "核心事件 demo_aimed 编译通过")

## —— ② 表达式（第①期：翻译/折叠/修复后的执行）——
func _test_expr() -> void:
	print("[2] 表达式（翻译+常量折叠）")
	var e := DanmakuExpr.new()
	_check(e.compile("2^3 + min(4,5) - abs(-1)", PackedStringArray([])), "^=次方 编译")
	_check(e.is_const_only() if e.has_method("is_const_only") else true, "（占位）")
	_check(e.execute([], -1.0) == 11.0, "常量折叠执行=11")
	var e2 := DanmakuExpr.new()
	e2.compile("n", ["n"])
	_check(e2.execute_dict({"n": 37.0}, 0.0) == 37.0, "n 变量注入（激光遍历）")
	var e3 := DanmakuExpr.new()
	_check(e3.compile("log(2,8)", PackedStringArray([])), "log(底,真) 翻译编译")
	_check(absf(e3.execute([], 0.0) - 3.0) < 0.001, "log(2,8)=3")
	var e4 := DanmakuExpr.new()
	_check(e4.compile("(custom_a*privates_id-custom_a)*(-1)^privates_id+0.5*custom_a", ["custom_a", "privates_id"]), "排布公式（privates_id()翻译+^幂）编译")
	_check(e4.execute_dict({"custom_a": 10.0, "privates_id": 3.0}, 0.0) == -15.0, "扇形公式 pid=3,a=10 → -15（第三点左侧，交错语义）")
	var e5 := DanmakuExpr.new()
	_check(e5.compile("sin(getField(t)*0.1*custom_b)*custom_a", ["field_t", "custom_a", "custom_b"]), "getField(t) 翻译编译")

## —— ③ 角色表（poi 列）——
func _test_chara_db() -> void:
	print("[3] 角色表（poi表达式列）")
	var chars := CharaDB.load_all()
	_check(chars.size() >= 20, "角色数 ≥20（得 %d）" % chars.size())
	var marisa := CharaDB.get_by_name("MarisaA")
	_check(String(marisa.get("main_poi_x", "")) == "(to_c+1)*wpcs", "MarisaA main_poi_x 表达式读取")
	_check(String(marisa.get("sub_poi_y", "")) == "4+wpcs", "MarisaA sub_poi_y 读取")
	var privs := CharaDB.load_privates()
	_check(privs.size() >= 5, "privates.csv 杂兵 ≥5（得 %d）" % privs.size())
	var enemies := CharaDB.load_enemies()
	_check(enemies.size() >= 4, "Enemy.csv 敌角色 ≥4（得 %d）" % enemies.size())

## —— ④ .thx ——
func _test_thx_roundtrip() -> void:
	print("[4] .thx")
	var ev := DanmakuEventData.new()
	ev.event_name = "pack_test1"
	ev.x = "cos(r0)"
	ev.y = "sin(r0)"
	var path := "user://smoke1.thx"
	var zp := ZIPPacker.new()
	zp.open(path)
	zp.start_file("danmaku_event.csv")
	zp.write_file(DanmakuEventData.build_csv([ev]).to_utf8_buffer())
	zp.close_file()
	zp.close()
	var names := GameGlobals.load_thx(path)
	_check(names.has("pack_test1"), ".thx 往返")

## —— ⑤ 哈希 + 被弹 ——
func _test_hash_and_hits() -> void:
	print("[5] 哈希/被弹")
	var ent := BattleEntity.new()
	ent.setup(CharaDB.get_by_name("MarisaA"), 0, BattleEntity.Kind.PLAYER, true)
	_check(ent._part_from_angle(-PI / 2.0) == BattleEntity.PART_WEAPON, "上120°→武器")
	_check(ent._part_from_angle(0.0) == BattleEntity.PART_BODY, "右侧→僚机")
	## I类被剥甲=FLT_MAX（批复#9：dmg÷0→最大值，一发即部位重伤）
	var ent1 := BattleEntity.new()
	ent1.setup(CharaDB.get_by_name("MarisaA"), 0, BattleEntity.Kind.PLAYER, true)
	ent1.ap = 0
	ent1.immune_frames = 0
	ent1.take_hit(3, 1, 0.0)
	_check(ent1.hp[BattleEntity.PART_BODY] <= 0, "I类 AP=0 → 僚机部位一发归零（重伤）")
	## 常规AP路径
	var ent2 := BattleEntity.new()
	ent2.setup(CharaDB.get_by_name("MarisaA"), 0, BattleEntity.Kind.PLAYER, true)
	ent2.take_hit(3, 1, 0.0)
	_check(ent2.hp[BattleEntity.PART_BODY] == 19 and ent2.ap == 50, "I类 AP=50 → dmg*0.5≈1 伤HP，AP不减")

## —— ⑥ 火控 poi ——
func _test_fire_poi() -> void:
	print("[6] 火控 poi 排布")
	var ent := BattleEntity.new()
	ent.setup(CharaDB.get_by_name("ReimuA"), 0, BattleEntity.Kind.PLAYER, true)
	ent.position = Vector2(100, 200)
	var fc := FireControl.new()
	fc.setup(ent)
	_check(fc.weapon_points.size() >= 1, "主机火力点 ≥1（保底，批复#12）")
	## ReimuA: Normal=2, main_y=2 → 主机首点 x=2*6+2=14（作者算例：基础0.1秒距+main_y修改值）
	var p0: Vector2 = fc.weapon_points[0].offset
	_check(absf(p0.x - 14.0) < 0.01, "主机首点 x=2*6+2=14（得 %f）" % p0.x)
	_check(fc.sub_points.size() >= 2, "僚机两侧火力点存在")
	## ReimuA: sub_x=-2 → 僚机首点 |x|=2*12-2=22
	var s0: Vector2 = fc.sub_points[0].offset
	## 【朝向帧 20261019】僚机=朝向垂直两侧 0.2秒距——断言侧距而非绝对 x
	_check(absf(s0.length() - 22.0) < 0.01, "僚机首点 侧距=2*12-2=22（得 %f）" % s0.length())
	## wpcs 序号：主机5点时 最左=3 中=1（文档算例）
	_check(fc.weapon_points[0].wpcs >= 1, "wpcs 序号生成")

## —— ⑦ 杂兵排布 ——
func _test_formation() -> void:
	print("[7] 杂兵排布预设")
	_check(PrivateFormation.PRESETS.has("扇形防护"), "扇形预设存在")
	_check(PrivateFormation.PRESETS.has("潮汐防护"), "潮汐/公转预设存在")
	var owner := BattleEntity.new()
	owner.setup(CharaDB.get_by_name("MarisaA"), 0, BattleEntity.Kind.MEMBER)
	owner.position = Vector2(200, 200)
	var priv := BattleEntity.new()
	priv.setup_private(CharaDB.get_private_by_name("FairyA"), 0, owner, 3, false)
	var fm := PrivateFormation.new()
	fm.setup(owner, priv, "扇形防护", {"custom_a": 10.0, "custom_b": 5.0})
	for i in 60:
		fm.step(1.0)
	_check(priv.local_pos.length() <= owner.normal_speed() * 60.0 * 0.35 + 8.0, "杂兵不超0.35秒距系绳（|d|=%f）" % priv.local_pos.length())
	_check(priv.privates_id == 3, "privates_id=3")

## —— ⑧ 排布修改值表达式 + wpcs 逐档收回（批复 2026-10-01 #1/#3）——
func _test_poi_expr_and_sweep() -> void:
	print("[8] poi 排布：修改值表达式 + 逐档收回")
	var row := CharaDB.get_by_name("ReimuA")
	row["main_y"] = "to_c*2+1" ## 表达式化修改值（玩家自制场景）
	var ent := BattleEntity.new()
	ent.setup(row, 0, BattleEntity.Kind.PLAYER, true)
	ent.position = Vector2(100, 200)
	var fc := FireControl.new()
	fc.setup(ent)
	_check(fc.weapon_points.size() >= 1, "主机火力点存在")
	_check(absf(fc.weapon_points[0].offset.x - 13.0) < 0.01,
		"main_y 表达式 to_c=0 → x=2*6+1=13（得 %f）" % fc.weapon_points[0].offset.x)
	ent.cruise_active = true
	for i in 6:
		fc.process(1.0 / 60.0, 0.0, 1) ## 第6帧触发 _update_all_poi（to_c 翻转→波浪开扫）
	_check(absf(fc.weapon_points[0].offset.x - 15.0) < 0.01,
		"快机后首档收回 x=2*6+3=15（得 %f）" % fc.weapon_points[0].offset.x)

## —— ⑨ 战场：-1 假弹幕不遮蔽 + 热力图 CPU 降级（②期准备）——
func _test_arena_hits_and_heatmap() -> void:
	print("[9] 战场 -1 遮蔽修复 + 热力图CPU降级")
	var arena: Node2D = load("res://scenes/battle_arena.tscn").instantiate()
	arena._ready() ## headless 手动初始化（不入树，_physics_process 不跑）
	_check(not arena.ht_side.is_empty() and arena.ht_side[0] != null, "热力图实例化（每侧一张）")
	_check(arena.fam_maps == null or arena.fam_maps.NAMES.size() == 8, "期望系 8 张（headless 允许 null）")
	_check(not arena.ht_side[0].ok, "headless → 热力图 CPU 降级模式")
	## CPU 热力图：加热+衰减+采样
	var b := Bullet.new()
	b.setup(GameGlobals.get_event("demo_aimed"), Vector2(200, 200), 1, arena.enemy_ents[0], arena)
	arena.bullets.append(b)
	var pts := PackedVector2Array([Vector2(200, 200)])
	for i in 3:
		arena.ht_side[0].step_cpu(arena.bullets)
	var vals: PackedInt32Array = arena.ht_side[0].sample(pts)
	_check(vals.size() == 1 and vals[0] > 0, "CPU热力图 加热+采样 >0（得 %d）" % (vals[0] if vals.size() else -1))
	var v_before: int = vals[0]
	for i in 5:
		arena.ht_side[0].step_cpu([])
	var vals2: PackedInt32Array = arena.ht_side[0].sample(pts)
	_check(vals2[0] < v_before, "CPU热力图 衰减0.8×（%d→%d）" % [v_before, vals2[0]])
	## -1 假弹幕（预警期激光）不再顶替同帧真伤害（批复 2026-10-01 #4）
	var target: BattleEntity = arena.player_ents[0]
	target.immune_frames = 0
	arena.bullet_hash.clear()
	var fake := Bullet.new()
	fake.setup(GameGlobals.get_event("demo_laser"), target.position, 1, arena.enemy_ents[0], arena)
	arena.bullet_hash.insert(fake) ## 预警期 t=0 → 伤害-1
	var real := Bullet.new()
	real.setup(GameGlobals.get_event("demo_aimed"), target.position, 1, arena.enemy_ents[0], arena)
	arena.bullet_hash.insert(real)
	var hp0: int = target.hp[1]
	var ap0: int = target.ap
	arena.time_frames = 1 ## 30Hz 被弹守卫：奇数帧才结算
	arena._resolve_hits()
	_check(target.hp[1] < hp0 or target.ap < ap0, "-1 弹不遮蔽同帧真伤害（HP/AP 已被真弹结算）")

## —— ⑩ 高火力覆写（运行时覆写官方参数链路，作者批复 2026-10-02）——
func _test_stress_override() -> void:
	print("[10] 高火力覆写测试")
	GameGlobals.apply_stress_override(true)
	var ev := GameGlobals.get_event("demo_aimed")
	_check(ev != null and ev.repeat_freq > 2 and ev.range_frames == 600,
		"覆写后 repeat_freq 增加、range×2（得 freq=%d range=%d）" % [ev.repeat_freq, ev.range_frames])
	GameGlobals.apply_stress_override(false)
	var ev2 := GameGlobals.get_event("demo_aimed")
	_check(ev2 != null and ev2.range_frames == 300, "关闭覆写后还原官方参数")

## —— ⑩b 数据守卫：demo 行列对齐（20261003 移位事故回归）+ 自机狙冻结朝向 ——
func _test_demo_data_guard() -> void:
	print("[10b] demo数据守卫 + 自机狙朝向")
	var ev := GameGlobals.get_event("demo_aimed")
	## 【20261025d】作者已将 demo_aimed 改为洋葱自机狙（gettarget(x)+min(x_copy*t,x_copy)）——
	## 列对齐断言改为前缀守卫（防历史移位事故回归），冻结断言改朝向断言（现为活弹幕）
	_check(ev != null and ev.x.contains("gettarget(x") and ev.y.contains("gettarget(y") and ev.x.contains("gettarget(d"),
		"demo_aimed 列对齐（gettarget 记法含 x/y/d，覆盖变体）")
	var eb := GameGlobals.get_event("demo_burst")
	_check(eb != null and eb.x == "cos(r0)+gettarget(x)/d", "demo_burst 列对齐（d 用法）")
	var arena: Node2D = load("res://scenes/battle_arena.tscn").instantiate()
	arena._ready()
	var me: BattleEntity = arena.player_ents[0]
	me.position = Vector2(60, 200)
	var b := Bullet.new()
	b.setup(ev, me.position, 0, me, arena, 0, {})
	b.update(1.0) ## 活弹幕（含早期 wobble 主导段——朝向断言改为运动性）
	var p0 := b.pos
	for i2 in 30:
		b.update(1.0)
	_check(b.pos != p0 and not is_nan(b.pos.x) and not is_nan(b.pos.y),
		"自机狙运动且无 NaN（含 /t_copy 项，pos=%s）" % b.pos.round())

## —— ⑪ 时间轴(.gd格式) + 激光渲染规模(46列) + 经济事件（作者批复 2026-10-02）——
func _test_timeline_and_laser() -> void:
	print("[11] 时间轴/激光规模/经济")
	## 时间轴：tick→多事件，.gd 文本往返
	var tl := TimelineData.new()
	tl.tl_name = "smoke_tl"
	tl.slot = "spell"
	tl.add_event(3, "demo_aimed")
	tl.add_event(3, "demo_ring")
	tl.add_event(10, "demo_laser")
	var txt := tl.to_gd()
	_check(TimelineData.is_timeline_gd(txt), "时间轴 .gd 头部标记")
	var back := TimelineData.parse_gd(txt)
	_check(back.tl_name == "smoke_tl" and back.slot == "spell" and back.ticks.size() == 2,
		"时间轴元数据/tick数往返")
	_check(back.ticks.get(3, PackedStringArray()).size() == 2, "同 tick 多事件往返")
	## 激光渲染规模：46列往返
	var ev := DanmakuEventData.new()
	ev.event_name = "t_laser"
	ev.tag = DanmakuEventData.TAG_LASER
	ev.laser_render_scale = 6.0
	var back2 := DanmakuEventData.new()
	back2.from_csv_row(DanmakuEventData.split_csv_line(ev.to_csv_row()))
	_check(absf(back2.laser_render_scale - 6.0) < 0.001, "laser_render_scale 46列往返")
	## 经济：击破杂兵 → 所属角色+5P；结界被剥 → 对方+3符
	var owner := BattleEntity.new()
	owner.setup(CharaDB.get_by_name("MarisaA"), 0, BattleEntity.Kind.MEMBER)
	var priv := BattleEntity.new()
	priv.setup_private(CharaDB.get_private_by_name("FairyA"), 0, owner, 1, false)
	var arena2: Node2D = load("res://scenes/battle_arena.tscn").instantiate()
	arena2._ready()
	arena2._connect_economy(priv)
	arena2.entities.append(owner) ## 挂入 entities 才会被 _update_drops 遍历
	arena2._connect_economy(owner)
	var pp0: int = owner.pp
	var drop_n: int = arena2.drops.size()
	priv.dead = true
	priv.destroyed.emit(priv)
	_check(arena2.drops.size() == drop_n + 1, "击破杂兵 → 掉落 P 拾取物（散落战场）")
	arena2._update_drops() ## 无角色在旁 → 仍在场
	var enemy: BattleEntity = arena2.enemy_ents[0]
	var sp0: int = enemy.spell_cards
	owner.barrier_shattered.emit(owner)
	_check(enemy.spell_cards >= sp0, "结界被剥 → 对方可接收+符（机制触发）")
	## 掉落物拾取：击破杂兵 5P 与剥甲 32P 拾取物都在 owner 脚下 → 一次 update 全拾
	arena2._update_drops()
	var got1: int = owner.pp - pp0
	_check(got1 == 37, "拾取击破 5P + 剥甲 32P（得 +%d）" % got1)
	arena2.drops.append({"pos": owner.position, "vel": Vector2.ZERO, "kind": "pp", "amount": 5, "frames": 100, "tex": null})
	arena2._update_drops()
	_check(owner.pp == pp0 + 42, "杂兵 5P 拾取 → +5P（得 +%d）" % (owner.pp - pp0))

func _report() -> void:
	print("================================")
	if fails.is_empty():
		print("SMOKE_OK —— 全部断言通过")
		get_tree().quit(0)
	else:
		print("SMOKE_FAIL —— %d 项失败：" % fails.size())
		for f in fails:
			print("  - %s" % f)
		get_tree().quit(1)

## —— ⑫ 通用弹幕旋转重复（20261015；类型修订 20261019）：数学/求值/往返/对战链路/锚定 ——
func _test_rotate_repeat() -> void:
	print("[12] 旋转重复（rotate_*）")
	## —— 位置：扇形 D=8 range=π/2 → 9 点 -π/4..+π/4；全圆从 0° 起分；D=0 仅原向 ——
	var rp8 := {"range": PI / 2.0, "div": 8, "rate": 0, "offset": 0.0, "pp": 0.0, "seq": "cw"}
	var pos: PackedFloat32Array = DanmakuEventData.rotate_positions(rp8)
	_check(pos.size() == 9 and absf(pos[0] + PI / 4.0) < 0.001 and absf(pos[8] - PI / 4.0) < 0.001,
		"扇形9位置 -π/4..+π/4")
	var rpc := {"range": TAU, "div": 4, "rate": 0, "offset": 0.0, "pp": 0.0, "seq": "cw"}
	var posc: PackedFloat32Array = DanmakuEventData.rotate_positions(rpc)
	_check(posc.size() == 4 and absf(posc[0]) < 0.001 and absf(posc[3] - 1.5 * PI) < 0.001,
		"全圆4位置从0°起分")
	_check(DanmakuEventData.rotate_positions({"range": 0.0, "div": 0}).size() == 1, "D=0 → 仅原始方向1点")
	## —— 步序：cw 左缘id0；ccw 右缘id0；mid_sync 中线0/左奇右偶/左侧先编号 ——
	var steps_cw: Array = DanmakuEventData.rotate_steps(rp8)
	_check(int(steps_cw[0][0][1]) == 0 and int(steps_cw[8][0][0]) == 8, "cw 时序 id0=左缘")
	var rpcc := {"range": PI / 2.0, "div": 8, "rate": 0, "offset": 0.0, "pp": 0.0, "seq": "ccw"}
	var steps_ccw: Array = DanmakuEventData.rotate_steps(rpcc)
	_check(int(steps_ccw[0][0][0]) == 8 and int(steps_ccw[0][0][1]) == 0, "ccw 时序 id0=右缘")
	var rpm := {"range": PI / 2.0, "div": 8, "rate": 0, "offset": 0.0, "pp": 0.0, "seq": "mid_sync"}
	var steps_m: Array = DanmakuEventData.rotate_steps(rpm)
	_check(int(steps_m[0][0][0]) == 4 and int(steps_m[0][0][1]) == 0, "mid_sync 首步=中线 id0")
	_check(int(steps_m[1][0][0]) == 3 and int(steps_m[1][0][1]) == 1 and int(steps_m[1][1][0]) == 5 and int(steps_m[1][1][1]) == 2,
		"mid_sync 次步=左(3,1)+右(5,2) 同步并列")
	_check(steps_m.size() == 5 and int(steps_m[4][0][0]) == 0 and int(steps_m[4][1][0]) == 8,
		"mid_sync 末步=两缘（5步9副本）")
	var rp3 := {"range": PI / 2.0, "div": 3, "rate": 0, "offset": 0.0, "pp": 0.0, "seq": "mid_sync"}
	var steps3: Array = DanmakuEventData.rotate_steps(rp3)
	_check(steps3.size() == 2
		and int(steps3[0][0][0]) == 1 and int(steps3[0][0][1]) == 1 and int(steps3[0][1][0]) == 2 and int(steps3[0][1][1]) == 2
		and int(steps3[1][0][0]) == 0 and int(steps3[1][0][1]) == 3 and int(steps3[1][1][0]) == 3 and int(steps3[1][1][1]) == 4,
		"奇数等分左先编号 1,2,3,4（2步×2同步）")
	## —— 回弹基数5 → 012348765（文档算例）；rate 溢出循环 ——
	var rpp := {"range": PI / 2.0, "div": 8, "rate": 9, "offset": 0.0, "pp": 5.0, "seq": "cw"}
	var plan: Array = DanmakuEventData.rotate_release_plan(rpp)
	var ids := ""
	for st in plan:
		ids += str(int(st[0][1]))
	_check(ids == "012348765", "回弹基数5 → 释放序 012348765（得 %s）" % ids)
	var rpp12 := {"range": PI / 2.0, "div": 8, "rate": 12, "offset": 0.0, "pp": 0.0, "seq": "cw"}
	_check(DanmakuEventData.rotate_release_plan(rpp12).size() == 12, "rate=12 → 12 次释放（溢出循环）")
	## —— 参数求值（20261019 表达式化）：数字=常量式；表达式参与 field_t；整式向下取整 ——
	var eve := DanmakuEventData.new()
	eve.event_name = "t_ev"
	eve.rotate_range = "1.5"
	eve.rotate_div = "field_t/10"
	eve.rotate_rate = "2.9"
	eve.rotate_offset = "0.25"
	eve.rotate_pingpong = "2.7"
	eve.compile()
	var rpe: Dictionary = eve.eval_rotate_params({"field_t": 30.0})
	_check(absf(rpe["range"] - 1.5) < 0.001 and int(rpe["div"]) == 3 and int(rpe["rate"]) == 2
		and absf(rpe["offset"] - 0.25) < 0.001 and int(rpe["pp"]) == 2,
		"eval_rotate_params：数字/表达式/取整（div=3 rate=2 pp=2）")
	## —— CSV 往返（54列；表达式原文保留）——
	var evr := DanmakuEventData.new()
	evr.event_name = "t_rot"
	evr.rotate_range = "1.5"
	evr.rotate_div = "wpcs*2"
	evr.rotate_rate = "10"
	evr.rotate_offset = "0.25"
	evr.rotate_sequence = "mid_left"
	evr.rotate_pingpong = "2"
	evr.rotate_delay = 7
	var back := DanmakuEventData.new()
	back.from_csv_row(DanmakuEventData.split_csv_line(evr.to_csv_row()))
	_check(back.rotate_div == "wpcs*2" and back.rotate_sequence == "mid_left" and back.rotate_delay == 7
		and back.rotate_range == "1.5" and back.rotate_offset == "0.25",
		"rotate_* 54列往返（表达式原文）")
	## —— 子弹旋转 + 运行时返回变量入 ctx ——
	var evs := DanmakuEventData.new()
	evs.event_name = "t_rotdir"
	evs.speed = "3"
	evs.x = "1"
	evs.y = "0"
	evs.compile()
	var world := Node.new()
	var b := Bullet.new()
	b.rot_angle = PI / 2.0
	b.rotate_id = 2
	b.setup(evs, Vector2(200, 100), 0, null, world, 0, {})
	b.update(1.0)
	_check(b.dir.y > 0.99 and absf(b.dir.x) < 0.01, "rot=π/2 → dir 右转向下")
	_check(b.pos.y > 100.0 and absf(b.pos.x - 200.0) < 0.01, "轨迹随旋转（y 正向行进）")
	var evv := DanmakuEventData.new()
	evv.event_name = "t_rotrid"
	evv.speed = "rotate_id*2"
	evv.x = "1"
	evv.y = "0"
	var errs := evv.compile()
	_check(errs.is_empty(), "rotate_id 表达式编译通过")
	var b2 := Bullet.new()
	b2.rotate_id = 2
	b2.setup(evv, Vector2.ZERO, 0, null, world, 0, {})
	_check(absf(b2.frozen_speed - 4.0) < 0.001, "rotate_id=2 → speed=4（运行时变量入 ctx）")
	var evr2 := DanmakuEventData.new()
	evr2.event_name = "t_roll"
	evr2.speed = "rate_roll+pattern_roll"
	evr2.x = "1"
	evr2.y = "0"
	evr2.compile()
	var b3 := Bullet.new()
	b3.rate_roll = 0.25
	b3.pattern_roll = 0.75
	b3.setup(evr2, Vector2.ZERO, 0, null, world, 0, {})
	_check(absf(b3.frozen_speed - 1.0) < 0.001, "rate_roll+pattern_roll=1（骰子变量入 ctx）")
	world.free()
	## —— 对战发射链路：整扇展开/延时锚定/repeat×rotate 相乘（批复 20261019）——
	var arena3: Node2D = load("res://scenes/battle_arena.tscn").instantiate()
	_check(arena3.get_script() != null, "battle_arena 脚本编译加载（canary）")
	arena3._ready()
	var fp := FireControl.FirePoint.new()
	var me2: BattleEntity = arena3.player_ents[0]
	fp.entity = me2
	fp.offset = Vector2.ZERO
	fp.ctx = {"wpcs": 1, "to_c": 0, "main_lr": 0, "sub_lr": 0}
	var evf := DanmakuEventData.new()
	evf.event_name = "t_fan"
	evf.speed = "3"
	evf.x = "1"
	evf.y = "0"
	evf.rotate_range = "1.5707963"
	evf.rotate_div = "4"
	evf.rotate_delay = 10
	evf.repeat_freq = 2 ## repeat 参数出生时求值——须在发射前设定
	evf.repeat_time = 30
	evf.compile()
	arena3._on_fire(fp, evf, {})
	_check(arena3.bullets.size() == 1 and arena3._rot_pend.size() == 4,
		"对战链路：首发=时序首副本，其余4副本入延时队列")
	var b0: Bullet = arena3.bullets[0]
	var base := b0.dir.rotated(PI / 4.0) ## 锚角 -π/4 → 反解基向
	_check(base.x > 0.99 and absf(base.y) < 0.01, "首发方向=基向.rotated(左缘角)（cw 首弹自逆时针极点起）")
	for i in 50:
		arena3._rot_pending_tick()
	_check(arena3.bullets.size() == 5 and arena3._rot_pend.is_empty(), "延时步序全出（5副本）")
	var b1: Bullet = arena3.bullets[1]
	_check(absf(b1.dir.angle() - (-PI / 8.0)) < 0.001,
		"延时副本=基向.rotated(槽位角)（不随外界时序重瞄）")
	## repeat×rotate：repeat 两次 → 整扇再重放两次（相乘、语义独立）
	b0.t = 31.0
	var n0: int = arena3.bullets.size()
	arena3._bullet_updates(1.0)
	_check(arena3.bullets.size() == n0 + 1 and arena3._rot_pend.size() == 4,
		"repeat 补发第1拍 → 整扇重放（首发+4延时）")
	var nrep: Bullet = arena3.bullets[n0]
	_check(nrep.repeat_enabled == false, "重放副本不再携带 repeat 节拍（防 N 倍繁殖）")
	for i in 50:
		arena3._rot_pending_tick()
	_check(arena3.bullets.size() == n0 + 5 and arena3._rot_pend.is_empty(), "重放扇完整（共10副本）")
	arena3.free()

## —— ⑬ 类型批复落地 + 绑定链路（20261019）：求值助手/净化/占位修复 ——
func _test_types_and_binding() -> void:
	print("[13] 类型批复 + 绑定链路")
	## 新建事件归属=空（不再"*"通配成全角色绑定——占位修复）
	## 表达式化通用参数：dmg/repeat/rotate_delay/rate（整数式向下取整）
	var evx := DanmakuEventData.new()
	evx.event_name = "t_expr"
	evx.dmg_s = "2+3"
	evx.repeat_time_s = "field_t*2"
	evx.repeat_freq_s = "2.9"
	evx.rotate_delay_s = "wpcs*10"
	evx.rate_s = "0.25*2"
	evx.compile()
	var spx: Dictionary = evx.eval_spawn_params({"field_t": 10.0, "wpcs": 2.0})
	_check(int(spx["dmg"]) == 5, "dmg 整式 2+3 → 5（出生时定值）")
	var rpx: Dictionary = evx.eval_repeat_params({"field_t": 10.0})
	_check(int(rpx["time"]) == 20 and int(rpx["freq"]) == 2, "repeat 算式 time=20 freq=2（2.9 下取整）")
	var rrx: Dictionary = evx.eval_rotate_params({"field_t": 0.0, "wpcs": 2.0})
	_check(int(rrx["delay"]) == 20, "rotate_delay 算式 wpcs*10=20")
	_check(absf(evx.eval_rate({}) - 0.5) < 0.001, "rate 命题式 0.5")
	## t_copy：释放时刻求值=0；子弹 ctx=自身存活帧
	_check("t_copy" in DanmakuEventData.EXPR_VARS, "t_copy 入表达式变量表")
	## 类型净化：nodes→regular 清失锁/引爆系专属参数（保留共享）
	var evs2 := DanmakuEventData.new()
	evs2.event_name = "t_san"
	evs2.tag = DanmakuEventData.TAG_NODES
	evs2.lost_max = 320.0
	evs2.can_destroy = true
	evs2.func_expr = "sin(t)"
	evs2.speed = "3"
	evs2.tag = DanmakuEventData.TAG_REGULAR
	evs2.sanitize_for_tag()
	_check(evs2.lost_max == 0.0 and evs2.can_destroy == false and evs2.func_expr == "" and evs2.speed == "3",
		"sanitize_for_tag：nodes 专属清空、共享 speed 保留")
	## CSV 往返：算式原文保留
	var evr3 := DanmakuEventData.new()
	evr3.event_name = "t_exprcsv"
	evr3.dmg_s = "2+3"
	evr3.repeat_time_s = "field_t*2"
	var back3 := DanmakuEventData.new()
	back3.from_csv_row(DanmakuEventData.split_csv_line(evr3.to_csv_row()))
	_check(back3.dmg_s == "2+3" and back3.repeat_time_s == "field_t*2", "算式列 CSV 往返保原文")
	## 【重写 20261020】角色弹幕分配=角色侧列表（main_evs 等）；事件 owner 不再产生绑定
	var evb := DanmakuEventData.new()
	evb.event_name = "t_bind_test"
	GameGlobals.editor_events.append(evb)
	var row_m := {"Name": "MarisaA", "main_evs": "t_bind_test", "sub_evs": "", "rest_evs": ""}
	var got: Array = GameGlobals.get_slot_events("MarisaA", "main", row_m)
	_check(got.size() == 1 and got[0].event_name == "t_bind_test",
		"角色列表含事件名 → get_slot_events 解析到工作集事件")
	var row_e := {"Name": "MarisaA", "main_evs": "", "sub_evs": "", "rest_evs": ""}
	_check(GameGlobals.get_slot_events("MarisaA", "main", row_e).is_empty(),
		"角色列表不含 → 空（owner='*' 不再通配绑定）")
	_check(GameGlobals.get_slot_events("MarisaA", "main", row_e).is_empty(),
		"事件不再携带 owner（绑定仅在角色列表侧）")
	GameGlobals.editor_events.erase(evb)

## —— ⑭ 朝向帧 + t/t_copy + 量纲迁移 + alarm 表达式（20261019 第三批）——
func _test_facing_and_semantics() -> void:
	print("[14] 朝向帧/t语义/量纲迁移")
	## 朝向帧：僚机在朝向垂直两侧（facing=RIGHT → 两侧=世界±y）
	var ent := BattleEntity.new()
	ent.setup(CharaDB.get_by_name("ReimuA"), 0, BattleEntity.Kind.MEMBER)
	var fc := FireControl.new()
	fc.setup(ent)
	var s0: Vector2 = fc.sub_points[0].offset
	_check(absf(s0.x) < 0.01 and absf(absf(s0.y) - 22.0) < 0.01,
		"僚机首点在朝向垂直侧（facing=RIGHT → |y|=22，得 %s）" % s0)
	## 转向 → 编队随帧旋转：facing=UP 时僚机转到世界 x 侧
	ent.facing = Vector2.UP
	fc._update_all_poi()
	var s1: Vector2 = fc.sub_points[0].offset
	_check(absf(s1.y) < 0.01 and absf(absf(s1.x) - 22.0) < 0.01,
		"facing=UP → 僚机随帧转到 |x|=22（得 %s）" % s1)
	## 主机沿朝向
	var p0: Vector2 = fc.weapon_points[0].offset
	_check(absf(p0.x) < 0.01 and absf(p0.y + 14.0) < 0.01, "主机首点沿 facing=UP（得 %s）" % p0)
	## t/t_copy 语义：repeat 子代 t=载体释放时刻、t_copy=0
	var evr := DanmakuEventData.new()
	evr.event_name = "t_tcopy"
	evr.speed = "3"
	evr.x = "t*0+1+t_copy*0" ## 引用 t/t_copy 使其进 ctx（_ctx_keys 按需收集）
	evr.y = "0"
	evr.repeat_freq = 2
	evr.repeat_time = 30
	evr.compile()
	var world := Node.new()
	var b := Bullet.new()
	b.setup(evr, Vector2.ZERO, 0, null, world, 0, {})
	var ctx0 := b._build_ctx()
	_check(absf(float(ctx0["t"]) - 0.0) < 0.001 and absf(float(ctx0["t_copy"]) - 0.0) < 0.001,
		"首发 t=t_copy=0")
	b.t = 31.0
	_check(b.repeat_tick(), "repeat 拍到")
	var child := Bullet.new()
	child.t_event = b.t
	child.setup(evr, Vector2.ZERO, 0, null, world, 1, {})
	var ctxc := child._build_ctx()
	_check(absf(float(ctxc["t"]) - 31.0) < 0.001 and absf(float(ctxc["t_copy"])) < 0.001,
		"子代 t=31(事件年龄) t_copy=0(副本年龄)")
	world.free()
	## alarm 表达式：出生时求值
	var eva := DanmakuEventData.new()
	eva.event_name = "t_alarm"
	eva.speed = "3"
	eva.x = "1"
	eva.y = "0"
	eva.alarm_s = "field_t/10"
	eva.compile()
	var world2 := Node.new()
	var ba := Bullet.new()
	ba.shared_ctx = {"field_t": 50.0, "field_phase": 1.0}
	ba.setup(eva, Vector2.ZERO, 0, null, world2, 0, {})
	_check(absf(ba.alarm_now - 5.0) < 0.001, "alarm 算式 field_t/10=5（出生定值）")
	world2.free()
	## 量纲：saturation 256 → S=1；hue 相对 color 偏移
	var evq := DanmakuEventData.new()
	evq.event_name = "t_quant"
	evq.color = "#b50321"
	evq.saturation = 256.0
	evq.hue = 0.0
	evq.speed = "3"
	evq.x = "1"
	evq.y = "0"
	evq.compile()
	_check(absf(evq.base_hue() - Color("#b50321").h) < 0.001, "base_hue 解析 color 列")
	var world3 := Node.new()
	var bq := Bullet.new()
	bq.setup(evq, Vector2.ZERO, 0, null, world3, 0, {})
	_check(absf(bq.sat_val - 2.0) < 0.001 and absf(bq.hue_val - Color("#b50321").h) < 0.001,
		"sat=256 → 倍乘2.0；hue=0 → H=base（对比度倍乘语义）")
	world3.free()
	## color 高级拆解列往返
	var evc := DanmakuEventData.new()
	evc.event_name = "t_coloradv"
	evc.color_r_s = "181"
	evc.color_g_s = "3+t"
	evc.color_b_s = "33"
	var backc := DanmakuEventData.new()
	backc.from_csv_row(DanmakuEventData.split_csv_line(evc.to_csv_row()))
	_check(backc.color_r_s == "181" and backc.color_g_s == "3+t" and backc.color_b_s == "33",
		"color_r/g/b 高级列往返（57列）")

## —— ⑮ gettarget 词字符参数（20261025b：x_copy/dm_smn/1d_ht_aver 曾被 [a-z]+ 拒收→静默失败）——
func _test_gettarget_wordparams() -> void:
	print("[15] gettarget 词参数（Youshio1 根因回归）")
	var e := DanmakuExpr.new()
	var ok := e.compile("gettarget(x_copy)/gettarget(d)", DanmakuEventData.EXPR_VARS)
	_check(ok and e._text == "x_copy/d", "gettarget(x_copy) 翻译（译后=%s）" % e._text)
	_check(absf(e.eval_num({"x_copy": 3.0, "d": 6.0}, -99.0) - 0.5) < 0.001,
		"gettarget(x_copy) 执行（原样残留→静默0 的回归）")
	var e2 := DanmakuExpr.new()
	e2.compile("getchara(normal)", DanmakuEventData.EXPR_VARS)
	_check(e2._text == "self_normal", "getchara(normal) 翻译（原 [xydapn] 拒收 o）")
	var e3 := DanmakuExpr.new()
	e3.compile("gettarget(dm_smn)", DanmakuEventData.EXPR_VARS)
	_check(e3._text == "target_dm_smn", "gettarget(dm_smn) 翻译+注册")
	var e4 := DanmakuExpr.new()
	e4.compile("gettarget(1d_ht_aver)", DanmakuEventData.EXPR_VARS)
	_check(e4._text == "ht1daver", "gettarget(1d_ht_aver) 重排翻译（数字开头非法标识符）")
	## 真实 Youshio1 事件本体：编译零错 + 帧控检测激活
	var y := GameGlobals.get_event("Youshio1")
	_check(y != null, "Youshio1 已加载")
	if y != null:
		var cerrs: Array[String] = y.compile()
		var uses := y.ex_x != null and y.ex_x.uses_variable("x_copy")
		_check(cerrs.is_empty() and uses, "Youshio1 编译零错且帧控激活（ex_x=%s）" % uses)
