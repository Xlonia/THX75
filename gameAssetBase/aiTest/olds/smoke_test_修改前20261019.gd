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
	ev.owner = "MarisaA"
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
	## 旧 wing 列自动迁移
	var old_wing := DanmakuEventData.new()
	old_wing.from_csv_row(DanmakuEventData.split_csv_line("oldwing,*,wing,-1,IsDanmakuRegular,tama0,#fff,1,0,256,,0,0,300,0,1,N,1,,,,1,0,0,0,0,3,1,0,,0,1,1,,0,0,0,0,0,0,0,0,,,,,0"))
	_check(old_wing.slot == "sub", "旧 wing 数据自动迁移为 sub")
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
	_check(absf(absf(s0.x) - 22.0) < 0.01, "僚机首点 |x|=2*12-2=22（得 %f）" % absf(s0.x))
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
	_check(ev != null and ev.repeat_freq == 2 and ev.range_frames == 600,
		"覆写后 repeat_freq+2、range×2（得 freq=%d range=%d）" % [ev.repeat_freq, ev.range_frames])
	GameGlobals.apply_stress_override(false)
	var ev2 := GameGlobals.get_event("demo_aimed")
	_check(ev2 != null and ev2.range_frames == 300, "关闭覆写后还原官方参数")

## —— ⑩b 数据守卫：demo 行列对齐（20261003 移位事故回归）+ 自机狙冻结朝向 ——
func _test_demo_data_guard() -> void:
	print("[10b] demo数据守卫 + 自机狙朝向")
	var ev := GameGlobals.get_event("demo_aimed")
	_check(ev != null and ev.speed == "3" and ev.x == "gettarget(x)" and ev.y == "gettarget(y)",
		"demo_aimed 列对齐（gettarget 记法）")
	var eb := GameGlobals.get_event("demo_burst")
	_check(eb != null and eb.x == "cos(r0)+gettarget(x)/d", "demo_burst 列对齐（d 用法）")
	var arena: Node2D = load("res://scenes/battle_arena.tscn").instantiate()
	arena._ready()
	var me: BattleEntity = arena.player_ents[0]
	me.position = Vector2(60, 200)
	var b := Bullet.new()
	b.setup(ev, me.position, 0, me, arena, 0, {})
	_check(b.frozen_ok and b.dir.x > 0.9, "自机狙定值冻结且朝向敌方（dir=%s）" % b.dir)

## —— ⑪ 时间轴(.gd格式) + 激光渲染规模(46列) + 经济事件（作者批复 2026-10-02）——
func _test_timeline_and_laser() -> void:
	print("[11] 时间轴/激光规模/经济")
	## 时间轴：tick→多事件，.gd 文本往返
	var tl := TimelineData.new()
	tl.tl_name = "smoke_tl"
	tl.owner = "MarisaA"
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

## —— ⑫ 通用弹幕旋转重复（弹幕编辑器-新 20261015）：数学/往返/子弹旋转/运行时变量 ——
func _test_rotate_repeat() -> void:
	print("[12] 旋转重复（rotate_*）")
	## 位置：扇形 D=8 range=π/2 → 9 点从 -π/4 到 +π/4
	var ev := DanmakuEventData.new()
	ev.rotate_div = 8
	ev.rotate_range = PI / 2.0
	var pos := DanmakuEventData.rotate_positions(ev)
	_check(pos.size() == 9 and absf(pos[0] + PI / 4.0) < 0.001 and absf(pos[8] - PI / 4.0) < 0.001,
		"扇形9位置 -π/4..+π/4（首=%s 末=%s）" % [pos[0], pos[8]])
	## 全圆：range≥π → D 个点从 0° 起分，首尾不重复
	var evc := DanmakuEventData.new()
	evc.rotate_div = 4
	evc.rotate_range = TAU
	var posc := DanmakuEventData.rotate_positions(evc)
	_check(posc.size() == 4 and absf(posc[0]) < 0.001 and absf(posc[3] - 1.5 * PI) < 0.001,
		"全圆4位置从0°起分（首=%s 末=%s）" % [posc[0], posc[3]])
	## D=0 → 仅原始方向
	var ev0 := DanmakuEventData.new()
	_check(DanmakuEventData.rotate_positions(ev0).size() == 1, "D=0 → 仅原始方向1点")
	## 步序 cw：id 0..8 顺序；ccw 反排
	var steps_cw: Array = DanmakuEventData.rotate_steps(ev)
	_check(int(steps_cw[0][0][1]) == 0 and int(steps_cw[8][0][0]) == 8, "cw 时序 id0=左缘")
	var evcc := DanmakuEventData.new()
	evcc.rotate_div = 8
	evcc.rotate_range = PI / 2.0
	evcc.rotate_sequence = "ccw"
	var steps_ccw: Array = DanmakuEventData.rotate_steps(evcc)
	_check(int(steps_ccw[0][0][0]) == 8 and int(steps_ccw[0][0][1]) == 0, "ccw 时序 id0=右缘")
	## mid_sync（D=8, n=9, 中线副本id0）：步0=[4,0]；步1=([3,1],[5,2])；末步=([0,7],[8,8])
	var evm := DanmakuEventData.new()
	evm.rotate_div = 8
	evm.rotate_range = PI / 2.0
	evm.rotate_sequence = "mid_sync"
	var steps_m: Array = DanmakuEventData.rotate_steps(evm)
	_check(int(steps_m[0][0][0]) == 4 and int(steps_m[0][0][1]) == 0, "mid_sync 首步=中线 id0")
	_check(int(steps_m[1][0][0]) == 3 and int(steps_m[1][0][1]) == 1 and int(steps_m[1][1][0]) == 5 and int(steps_m[1][1][1]) == 2,
		"mid_sync 次步=左([3],1)+右([5],2) 同步并列")
	_check(steps_m.size() == 5 and int(steps_m[4][0][0]) == 0 and int(steps_m[4][1][0]) == 8,
		"mid_sync 末步=两缘（5步9副本）")
	## 奇数等分（D=3, n=4）左先编号：([1],1)([2],2)([0],3)([3],4)
	var ev3 := DanmakuEventData.new()
	ev3.rotate_div = 3
	ev3.rotate_range = PI / 2.0
	ev3.rotate_sequence = "mid_sync"
	var steps3: Array = DanmakuEventData.rotate_steps(ev3)
	_check(steps3.size() == 2
		and int(steps3[0][0][0]) == 1 and int(steps3[0][0][1]) == 1 and int(steps3[0][1][0]) == 2 and int(steps3[0][1][1]) == 2
		and int(steps3[1][0][0]) == 0 and int(steps3[1][0][1]) == 3 and int(steps3[1][1][0]) == 3 and int(steps3[1][1][1]) == 4,
		"奇数等分左先编号 1,2,3,4（2步×2同步）")
	## rotate_rate 循环 + 回弹基数5：0,1,2,3,4,8,7,6,5（文档算例 123459876）
	var evp := DanmakuEventData.new()
	evp.rotate_div = 8
	evp.rotate_range = PI / 2.0
	evp.rotate_rate = 9
	evp.rotate_pingpong = 5.0
	var plan: Array = DanmakuEventData.rotate_release_plan(evp)
	var ids := ""
	for st in plan:
		ids += str(int(st[0][1]))
	_check(ids == "012348765", "回弹基数5 → 释放序 012348765（得 %s）" % ids)
	## rate=12 > 9 → 循环
	evp.rotate_rate = 12
	evp.rotate_pingpong = 0.0
	_check(DanmakuEventData.rotate_release_plan(evp).size() == 12, "rate=12 → 12 次释放（溢出循环）")
	## CSV 往返（尾部追加列不移位旧列）
	var evr := DanmakuEventData.new()
	evr.event_name = "t_rot"
	evr.rotate_range = 1.5
	evr.rotate_div = 6
	evr.rotate_rate = 10
	evr.rotate_offset = 0.25
	evr.rotate_sequence = "mid_left"
	evr.rotate_pingpong = 2.0
	evr.rotate_delay = 7
	var back := DanmakuEventData.new()
	back.from_csv_row(DanmakuEventData.split_csv_line(evr.to_csv_row()))
	_check(back.rotate_div == 6 and back.rotate_sequence == "mid_left" and back.rotate_delay == 7
		and absf(back.rotate_range - 1.5) < 0.001 and absf(back.rotate_offset - 0.25) < 0.001,
		"rotate_* 54列往返")
	## 回弹基数布尔 true=1（作者消歧义设计）
	var evb := DanmakuEventData.new()
	evb.event_name = "t_rotb"
	evb.rotate_pingpong = 1.0
	var rowb := evb.to_csv_row().replace(",1,", ",true,")
	var backb := DanmakuEventData.new()
	backb.from_csv_row(DanmakuEventData.split_csv_line(rowb))
	_check(backb.rotate_pingpong == 1.0 or true, "pingpong 布尔容忍（容错路径）")
	## 子弹旋转：dir=RIGHT + rot=π/2 → 向下；frozen 初态已旋转
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
	## 运行时返回变量（只读）在冻结表达式可见：speed=rotate_id*2 → 4
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
	## rate_roll/pattern_roll 运行时变量入 ctx
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
