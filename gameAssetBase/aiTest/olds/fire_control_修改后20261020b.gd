class_name FireControl
extends RefCounted
## =============================================================
## 火控（第①期，对齐作者批复）
## 【规则修正（批复#10/#11/#12）】
##   撤离阶段：Pt=2（不论T），但 T 依然生效参与 min(T/60,4)
##   主机火力点保底 1；僚机（每侧个数）允许 0
##   火力点个数：主机=总共；僚机=左右侧每侧的个数（Spcs 为单侧值）
## 【概率/规律门（批复#11）】
##   rate：rate_roll=randf()，命题 rate_roll<=rate
##   pattern：pattern_roll+=pattern；命题为真时减一（pattern_roll>=1 → 减一并命题真）
##   两命题均为真时才释放（与运算；“或”由用户写否命题实现）
## 【火力点排布 poi（批复新增，Characters.csv 已提供7列表达式）】
##   基础坐标：主机首点=角色正前方0.1秒距；僚机首点=两侧0.2秒距
##   修改值：main_y/sub_x/sub_y（相对基础坐标；僚机以该僚机相对角色的方向为正）
##   步进向量：main_poi_x/y（主机）、sub_poi_x/y（每侧僚机，x正方向=该侧朝向）
##   poi 系列支持表达式（变量：wpcs 序号 / to_c 快机系数）
##   每 6 帧 按 wpcs 从小到大顺序 更新同 wpcs 火力点位置（与弹幕事件刷新同步，
##   表现“开快慢机时火力点慢慢收回来”）
##   奇数个点时中点无 x 正方向，相对 x 恒为 0
## 【wpcs 定义】该火力点在此侧面从里到外第几个（主机5点：最左3，中1；僚机每侧8点最右4）
## 【侧边系数】main_lr：火力点在角色左侧-1/右侧1/中0；sub_lr：相对所属僚机
## =============================================================

const TICK_RATE := 0.1
const POI_UPDATE_FRAMES := 6 ## 每6帧更新一档 wpcs（文档：与弹幕事件刷新同步）

class FirePoint:
	extends RefCounted
	var id: int = 0
	var part: int = 0            ## BattleEntity.PART_*
	var wpcs: int = 1            ## 侧面序号（从里到外）
	var lr: int = 0              ## -1左/1右/0中（main_lr 语义）
	var sub_lr: int = 0          ## 相对僚机的左右（sub_lr 语义）
	var offset: Vector2 = Vector2.ZERO ## 当前相对角色位置（poi 更新结果）
	var timer := 0.0
	var locked := true
	var events: Array = []
	var entity: BattleEntity
	var ctx: Dictionary = {}     ## 【20261003】火力点上下文直挂（发射零搜索）

var entity: BattleEntity
## 【批复 2026-10-04】事件绑定初始化定格：道具/状态覆盖在决斗开始生效，
## 此后角色事件绑定不变（重伤→部位停火由 part_ok 锁定实现）——
## rebuild_points 不再每次全池扫描
var _bound_main: Array = []
var _bound_rest: Array = []
var _bound_sub: Array = []
var mode := "rotate"
var weapon_points: Array = []
var sub_points: Array = []      ## 双侧僚机（offset 已含左右侧镜像）
var main_cd := 1.0
var sub_cd := 1.0
var _tick_acc := 0.0
var _salvo_timer := 0.0
var _pattern_rolls: Dictionary = {}
var _poi_exprs_cache: Dictionary = {} ## "main_y"/"main_poi_x"/… -> DanmakuExpr
var _poi_wpcs_cursor := 1       ## 逐档收回游标（to_c 变化时归1，每6帧+1；顶格=全量应用）
var _sweep_to_c := 0            ## 上次应用排布时的 to_c（变化检测）
var _frame_count := 0
var _engage_delay := 12 ## 【批复 2026-10-13】开火迟滞 0.2s（拟真；进场后首发射延迟）
var _engaged := false
var last_rolls := {"rate_roll": 1.0, "pattern_roll": 1.0} ## 【20261015】运行时返回变量随发射传出
signal fired(point: FirePoint, event: DanmakuEventData, rolls: Dictionary)

func setup(ent: BattleEntity) -> void:
	entity = ent
	main_cd = float(ent.db.get("Main_Cd", 4))
	sub_cd = float(ent.db.get("Sub_Cd", 2))
	mode = GameGlobals.versus_volley
	_compile_poi_exprs()
	## 【初始化定格】事件绑定只在决斗开始读一次（含 editor 预览工作集）
	var name := String(ent.db.get("Name", ""))
	_bound_main = GameGlobals.get_slot_events(name, DanmakuEventData.SLOT_MAIN)
	_bound_rest = GameGlobals.get_slot_events(name, DanmakuEventData.SLOT_REST)
	_bound_sub = GameGlobals.get_slot_events(name, DanmakuEventData.SLOT_SUB)
	rebuild_points()

## poi 表达式编译（Characters.csv 7列；建议仅加减乘除——常量折叠处理静态值）
## 【批复 2026-10-01#1】main_y/sub_x/sub_y 也按表达式求值（作者多给纯数字，
##   常量折叠后零运行时开销；玩家自制含 wpcs/to_c 变量时生效）。
func _compile_poi_exprs() -> void:
	var vars := PackedStringArray(["wpcs", "to_c"])
	for col in ["main_y", "sub_x", "sub_y", "main_poi_x", "main_poi_y", "sub_poi_x", "sub_poi_y"]:
		var raw := str(entity.db.get(col, "0"))
		if raw.strip_edges().is_empty():
			raw = "0"
		var e := DanmakuExpr.new()
		if not e.compile(raw, vars):
			push_warning("[FireControl] %s 的 %s 表达式非法：%s" % [entity.db.get("Name", "?"), col, raw])
			e = null
		_poi_exprs_cache[col] = e

func _poi_eval(col: String, wpcs: int, to_c: int) -> float:
	var e: DanmakuExpr = _poi_exprs_cache.get(col)
	if e == null:
		return 0.0
	return e.execute_dict({"wpcs": float(wpcs), "to_c": float(to_c)}, 0.0)

## 排布修改值列（main_y/sub_x/sub_y）：表达式求值，编译失败回退字面数值
func _val_db(col: String, wpcs: int, to_c: int) -> float:
	var e: DanmakuExpr = _poi_exprs_cache.get(col)
	if e != null:
		return e.execute_dict({"wpcs": float(wpcs), "to_c": float(to_c)}, 0.0)
	var raw := String(entity.db.get(col, "0")).strip_edges()
	if raw.is_empty():
		return 0.0
	return raw.to_float()

## =============================================================
## 【运算流程】火力点重建（P点/时间/阶段变化后调用）
## =============================================================
func rebuild_points() -> void:
	weapon_points.clear()
	sub_points.clear()
	if entity.dead:
		return
	var wm := float(entity.db.get("Weapon_Muti", 1))
	var t_sec := float(entity.get_meta("arena_time_sec", 0.0))
	var phase := int(entity.get_meta("arena_phase", 1))
	var pp := float(entity.pp)
	## 撤离：Pt=2（不论T）；T 仍参与 min(T/60,4)（批复#10）
	var pt_main := 2
	var pt_sub := 2
	if phase != 4:
		pt_main = 3 if t_sec < 60.0 else (4 if t_sec < 180.0 else 7)
		pt_sub = 1 if t_sec < 60.0 else (4 if t_sec < 180.0 else 7)
	## 主机 Mpcs=[[ [min(Pp/100,6,Pt)+min(T/60,4)]*0.5Wm ]]（总数；保底1）
	var base_main := minf(pp / 100.0, minf(6.0, float(pt_main)))
	var mpcs := int(floor((base_main + minf(t_sec / 60.0, 4.0)) * 0.5 * wm))
	mpcs = maxi(1, mpcs)
	## 单侧僚机 Spcs=[[ [min(Pp/100,6,Pt)+1]*0.5Wm ]]（每侧个数；可为0）
	var base_sub := minf(pp / 100.0, minf(6.0, float(pt_sub)))
	var spcs := int(floor((base_sub + 1.0) * 0.5 * wm))
	var main_events := _bound_main ## 定格绑定（不再全池扫描）
	var rest_events := _bound_rest
	var sub_events := _bound_sub
	## 【火力占比（作者 2026-10-03 数据列）】主机每侧点数侧=ceil/floor 拆分：
	## main_para_rat 进位=首要点数、main_seci_rat 去尾=次要点数、其余=其余武器点
	var para_rat := float(entity.db.get("main_para_rat", 0.3))
	var seco_rat := float(entity.db.get("main_seci_rat", 0.3))
	var per_side := int(ceil(mpcs / 2.0)) ## 每侧（奇数含中点）
	var para_cnt := mini(mpcs, int(ceil(per_side * para_rat)) * 2 if mpcs % 2 == 0 else int(ceil(per_side * para_rat)) * 2 - 1)
	var seco_cnt := mini(mpcs - para_cnt, int(floor(per_side * seco_rat)) * 2)
	## 主机火力点（总数 mpcs，绕中点分布，奇数含中点）
	var _rank := 0 ## 从中心向外的名次（0=首要区）
	for i in mpcs:
		var p := FirePoint.new()
		p.id = i
		p.part = BattleEntity.PART_WEAPON
		var rel := i - (mpcs - 1) / 2.0 ## -左…0…+右
		p.wpcs = _wpcs_of(rel, mpcs)
		p.lr = -1 if rel < -0.25 else (1 if rel > 0.25 else 0)
		p.events = _pool_for(main_events, rest_events)
		p.set_meta("rank", 0) ## 占比名次占位（首要/次要渲染与分配细化在后续批）
		weapon_points.append(p)
	## 僚机火力点（左右各 spcs 个；每侧内部从里到外 wpcs=1..spcs）
	for side_i in 2: ## 0=左 1=右
		for i in spcs:
			var p := FirePoint.new()
			p.id = side_i * 100 + i
			p.part = BattleEntity.PART_BODY
			p.wpcs = i + 1            ## 该侧从里到外
			p.sub_lr = -1 if side_i == 0 else 1
			p.lr = -1 if side_i == 0 else 1 ## 相对角色也是左/右
			p.events = sub_events.duplicate()
			sub_points.append(p)
	## 【B1·火力占比（策划：首要进位/次要去尾）】主机前 para_cnt 点标记"首要"，
	## 轮射解锁顺序：首要 → 次要 → 其余（get_index 越小越先解锁）
	var para_cnt2: int = 0
	for p in weapon_points:
		if para_cnt2 < maxi(0, weapon_points.size() - maxi(0, int(floor(weapon_points.size() * (1.0 - float(entity.db.get("main_para_rat", 0.3)) - float(entity.db.get("main_seci_rat", 0.3))))))):
			para_cnt2 += 1
		p.set_meta("rank", 0 if p.id < maxi(1, int(ceil(weapon_points.size() * float(entity.db.get("main_para_rat", 0.3))))) else 1)
	for p in sub_points:
		p.set_meta("rank", 2) ## 僚机点最后解锁
	for p in weapon_points + sub_points:
		p.locked = (mode == "rotate")
		p.timer = 0.0
		## 【R1 修复】火力点上下文直挂必须在建点之后（旧版在 clear() 后
		## 对空数组迭代——ctx 恒空、发射回退全表搜索）
		p.entity = entity
		p.ctx = {"wpcs": p.wpcs, "to_c": 1 if entity.cruise_active else 0, "main_lr": p.lr, "sub_lr": p.sub_lr}
	## 初始排布：全部档位立即应用（cursor 顶格），快慢机切换时才开逐档波浪
	_poi_wpcs_cursor = 1 << 20
	_sweep_to_c = 1 if entity.cruise_active else 0
	_update_all_poi()

## 侧面序号：主机 n 点（奇数含中点）——中点 wpcs=1，向外递增
## 例：5点 → 中1，左右各2/3（文档算例：最左3，中1）
func _wpcs_of(rel: float, total: int) -> int:
	if total <= 0:
		return 1
	if total % 2 == 1 and absf(rel) < 0.25:
		return 1 ## 中点
	var half := (total - 1) / 2.0
	var from_center := absf(rel) ## 0.5步进
	var w := int(round(from_center)) + 1
	return maxi(1, w)

## =============================================================
## 【poi 排布更新运算流程】（每6帧一档，"带 wpcs 逐档收回"）
##   首点基础坐标：主机=正前方0.1秒距(6×Normal)；僚机=两侧0.2秒距(12×Normal)
##   修改值：main_y（主机y）/ sub_x sub_y（僚机，正方向=该僚机相对角色方向）
##   ——【批复 2026-10-01#1】三者均按表达式求值（常量折叠）
##   步进：第k点位置 = 首点 + Σ poi向量（按 wpcs 从小到大，每档 poi 向量
##   由 main_poi_x/y 或 sub_poi_x/y 表达式按当前 wpcs 求值）
##   【批复 2026-10-01#3】快慢机切换（to_c 变化）→ 游标归1，此后每6帧推进
##   一档 wpcs：已扫过的档位采用新目标位置，未扫过的保持旧位——
##   表现"开快慢机时火力点慢慢收回来"（文档：与弹幕事件刷新同步）。
##   poi x 正方向=该侧朝向；y 正方向=角色背向
## =============================================================
func _update_all_poi() -> void:
	if entity.dead:
		return
	var to_c := 1 if entity.cruise_active else 0
	## —— ① 全量计算各档目标位置（常量折叠后近乎零开销）——
	## 【朝向帧重建（批复 20261019）】局部帧：y 轴=角色朝向（fwd）、x 轴=右侧（right）、
	## 背向=back=-fwd。策划口径：主要火力点=正前方 0.1 秒距（fwd 方向）；
	## 僚机=两侧 0.2 秒距（±right）；poi 向量 x=该侧朝向（主点=lr*right、
	## 僚机点=sub_lr*right）、y=角色的背向（back）——旧实现用绝对 x/y 轴，
	## 三者错位（作者指出的玩法级缺陷）。
	var targets_main: Dictionary = {}  ## "side|wpcs" -> Vector2（side=-1左/1右/0中）
	var targets_sub: Dictionary = {}   ## "side|wpcs" -> Vector2
	var fwd := entity.frame_forward()
	var right_d := entity.frame_right()
	var back := entity.frame_back()
	var n_speed := entity.normal_speed()
	## main_y：主机排布修改值——修正"前方0.1秒距"（作者算例：2*6-2=10）
	var main_first := fwd * (n_speed * 6.0 + _val_db("main_y", 1, to_c))
	var max_tier := 1
	for p in weapon_points:
		max_tier = maxi(max_tier, p.wpcs)
		var key := "%d|%d" % [p.lr, p.wpcs]
		if not targets_main.has(key):
			## 累计 = 首点 + Σ_{k=1..wpcs-1} poi(k)；poi x 沿该侧朝向、y 沿背向
			var acc := main_first
			for k in range(1, p.wpcs):
				var pv := Vector2(_poi_eval("main_poi_x", k, to_c), _poi_eval("main_poi_y", k, to_c))
				acc += right_d * p.lr * pv.x
				acc += back * pv.y
			targets_main[key] = acc
	## 僚机（左右侧；poi x 正方向=该僚机的该侧朝向=sub_lr*right、y=背向）
	for side_i in 2:
		var side_sign := -1.0 if side_i == 0 else 1.0 ## 该僚机在角色的哪侧（远离中心为正）
		var away := right_d * side_sign
		## sub_x：侧向0.2秒距修改值（正=远离角色）；sub_y：沿背向
		var sub_first := away * (n_speed * 12.0 + _val_db("sub_x", 1, to_c)) \
			+ back * _val_db("sub_y", 1, to_c)
		for p in sub_points:
			if (p.sub_lr < 0) != (side_i == 0):
				continue
			max_tier = maxi(max_tier, p.wpcs)
			var key := "%d|%d" % [side_i, p.wpcs]
			if not targets_sub.has(key):
				var acc := sub_first
				for k in range(1, p.wpcs):
					var pv := Vector2(_poi_eval("sub_poi_x", k, to_c), _poi_eval("sub_poi_y", k, to_c))
					acc += right_d * float(p.sub_lr) * pv.x
					acc += back * pv.y
				targets_sub[key] = acc
	## —— ② to_c 变化 → 游标归1，重开逐档波浪 ——
	if to_c != _sweep_to_c:
		_sweep_to_c = to_c
		_poi_wpcs_cursor = 1
	_poi_wpcs_cursor = mini(_poi_wpcs_cursor + 1, max_tier + 1)
	## —— ③ 应用：已扫过的档位采用新目标，未扫过保持旧位（收回动画）——
	for p in weapon_points + sub_points:
		p.ctx["to_c"] = to_c
	for p in weapon_points:
		var mkey := "%d|%d" % [p.lr, p.wpcs]
		if _poi_wpcs_cursor >= p.wpcs and targets_main.has(mkey):
			p.offset = targets_main[mkey]
	for p in sub_points:
		var key := "%d|%d" % [(0 if p.sub_lr < 0 else 1), p.wpcs]
		if _poi_wpcs_cursor >= p.wpcs and targets_sub.has(key):
			p.offset = targets_sub[key]

func _pool_for(main_events: Array, rest_events: Array) -> Array:
	var pool: Array = main_events.duplicate()
	pool.append_array(rest_events)
	return pool

## =============================================================
## 每帧推进
## =============================================================
func process(delta: float, arena_time_sec: float, arena_phase: int) -> void:
	if entity.dead:
		return

	entity.set_meta("arena_time_sec", arena_time_sec)
	entity.set_meta("arena_phase", arena_phase)
	_frame_count += 1
	if _frame_count % POI_UPDATE_FRAMES == 0:
		_update_all_poi() ## 内部推进逐档游标（批复#3：收回波浪）
	_tick_acc += delta
	while _tick_acc >= TICK_RATE:
		_tick_acc -= TICK_RATE
		_tick(arena_time_sec, arena_phase)

func _tick(_t: float, _phase: int) -> void:
	if not _engaged: ## 【开火迟滞 0.2s】只拦发射（poi 排布与计时不受影响）
		_frame_count += 1
		if _frame_count >= _engage_delay:
			_engaged = true
		return
	var all_points: Array = weapon_points + sub_points
	if mode == "rotate":
		for part in [BattleEntity.PART_WEAPON, BattleEntity.PART_BODY]:
			if not _part_alive(part):
				continue
			## 【B1】按 rank 升序解锁（0=首要 先解锁；僚机=2 最后）
			var pts := _points_of_part(part).duplicate()
			pts.sort_custom(func(a, b): return int(a.get_meta("rank", 1)) < int(b.get_meta("rank", 1)))
			for p in pts:
				if p.locked:
					p.locked = false
					break
		for p in all_points:
			if p.locked:
				continue
			if not _part_alive(p.part):
				p.locked = true
				continue
			p.timer += 1.0
			var buf := main_cd if p.part == BattleEntity.PART_WEAPON else sub_cd
			if p.timer >= buf:
				p.timer = 0.0
				_release_point(p)
	else:
		_salvo_timer += 1.0
		var buf := maxf(main_cd, sub_cd)
		if _salvo_timer >= buf:
			_salvo_timer = 0.0
			for p in all_points:
				if _part_alive(p.part):
					_release_point(p)

func _part_alive(part: int) -> bool:
	return entity.hp[part] > 0

func _points_of_part(part: int) -> Array:
	return weapon_points if part == BattleEntity.PART_WEAPON else sub_points

func _release_point(p: FirePoint) -> void:
	if p.events.is_empty():
		return
	for ev in p.events:
		if _gate(ev, p):
			fired.emit(p, ev, last_rolls.duplicate())

## 概率/规律门（批复#11）：
##   rate 命题：randf()<=rate；pattern 命题：池累加>=1 时减一（命题真）
##   两命题均为真才释放
## 【20261015】rate_roll/pattern_roll 为"弹幕运行时返回的变量"（弹幕编辑器-新）：
##   骰子结果/规律累加值随发射传出，子弹表达式可只读引用（不可手动设定）。
##   pattern_roll 返回值=减一后的结果（作者 20261019 语义）——恰为存池值。
## 【类型批复 20261019】rate/pattern 允许算式/命题——门时刻按火力点上下文求值
func _gate(ev: DanmakuEventData, p: FirePoint = null) -> bool:
	var ctx := {"field_t": 0.0, "field_phase": 1.0, "t": 0.0, "t_copy": 0.0, "t_r": 0.0,
		"rate_roll": 0.0, "pattern_roll": 0.0, "rotate_id": 0.0, "r0": 0.0, "r1": 0.0, "n": 0.0}
	if p != null:
		if p.ctx != null:
			for k in ["wpcs", "to_c", "main_lr", "sub_lr"]:
				ctx[k] = float(p.ctx.get(k, 0))
		if p.entity != null:
			ctx["field_t"] = float(p.entity.get_meta("arena_time_sec", 0.0)) * 60.0
			ctx["field_phase"] = float(p.entity.get_meta("arena_phase", 1))
			ctx["self_x"] = p.entity.position.x
			ctx["self_y"] = p.entity.position.y
			ctx["self_ap"] = float(p.entity.ap)
			ctx["self_pp"] = float(p.entity.pp)
			ctx["self_normal"] = float(p.entity.normal_speed())
			## 【批复 20261019④】事件所有求值处经 get 系取状态——门上下文同样
			## 注入目标快照（gettarget(x)→target_x 翻译链可见）
			var arena := p.entity.get_parent()
			if arena != null and arena.has_method("bullet_collapse_counts"):
				for k3 in arena.bullet_collapse_counts():
					ctx[k3] = float(arena.bullet_collapse_counts()[k3])
			if arena != null and arena.has_method("bullet_nearest_enemy_pos"):
				var tp0: Vector2 = arena.bullet_nearest_enemy_pos(p.entity.side, p.entity.position)
				if tp0 != p.entity.position:
					ctx["target_x"] = tp0.x - p.entity.position.x
					ctx["target_y"] = tp0.y - p.entity.position.y
					ctx["d"] = tp0.distance_to(p.entity.position)
	var rr := randf()
	last_rolls["rate_roll"] = rr
	var rate_ok := true
	if ev.rate_specified:
		rate_ok = rr <= ev.eval_rate(ctx)
	var pat_ok := true
	if ev.pattern_specified:
		var roll := float(_pattern_rolls.get(ev.event_name, 0.0)) + ev.eval_pattern(ctx)
		if roll >= 1.0:
			roll -= 1.0 ## 命题为真时减一
			_pattern_rolls[ev.event_name] = roll
		else:
			_pattern_rolls[ev.event_name] = roll
			pat_ok = false
	last_rolls["pattern_roll"] = float(_pattern_rolls.get(ev.event_name, 0.0)) if ev.pattern_specified else 0.0
	return rate_ok and pat_ok

func set_mode(m: String) -> void:
	mode = m
	_salvo_timer = 0.0
	## 【B1·火力占比（策划：首要进位/次要去尾）】主机前 para_cnt 点标记"首要"，
	## 轮射解锁顺序：首要 → 次要 → 其余（get_index 越小越先解锁）
	var para_cnt2: int = 0
	for p in weapon_points:
		if para_cnt2 < maxi(0, weapon_points.size() - maxi(0, int(floor(weapon_points.size() * (1.0 - float(entity.db.get("main_para_rat", 0.3)) - float(entity.db.get("main_seci_rat", 0.3))))))):
			para_cnt2 += 1
		p.set_meta("rank", 0 if p.id < maxi(1, int(ceil(weapon_points.size() * float(entity.db.get("main_para_rat", 0.3))))) else 1)
	for p in sub_points:
		p.set_meta("rank", 2) ## 僚机点最后解锁
	for p in weapon_points + sub_points:
		p.locked = (mode == "rotate")
		p.timer = 0.0
		## 【R1 修复】火力点上下文直挂必须在建点之后（旧版在 clear() 后
		## 对空数组迭代——ctx 恒空、发射回退全表搜索）
		p.entity = entity
		p.ctx = {"wpcs": p.wpcs, "to_c": 1 if entity.cruise_active else 0, "main_lr": p.lr, "sub_lr": p.sub_lr}

## 火力点上下文（20261003：直读 p.ctx，rebuild/poi 更新时维护）
func point_ctx(p: FirePoint) -> Dictionary:
	return p.ctx
