class_name Bullet
extends RefCounted
## =============================================================
## 弹幕运行时（第①期重写）
## 【性能架构】不再做 CPU 像素印章。每帧：
##   ① update(dt)：运动学 + 表达式（常量折叠）
##   ② 导出 印章数据(x,y,r) → DdmGpu（GPU 弹幕图，AI/调试/预览用）
##   ③ 导出 碰撞圆 → BulletHash（CPU 被弹解析，矢量精确）
## 【新参数（作者批复①期）】
##   x_offset/y_offset：弹幕相对火力点起始偏移；物弹遮罩起点
##   saturation/hue：HSL 渲染（替代 color_render；亮度=隐藏代码 lightness）
##   lost_if：命题为真时暂时失锁转直线（点向类）
##   repeat_time/repeat_freq：事件节拍（缓冲前多次发射，模拟双发/三发连射）
##   激光=几何图形：x/y 表达式 + n(k) 遍历换元采样 + range=xy渲染像素规模
##   激光材质：单像素线条（作者：制作弹幕使用的材质图应该是单像素的线条）
## 【外部变量】火力点上下文 wpcs/to_c/main_lr/sub_lr（poi 排布配套）
## =============================================================

const MAX_DEPTH := 3

var ev: DanmakuEventData
var side := 0
var source: BattleEntity
var source_side := 0
var origin := Vector2.ZERO   ## 发射原点（含 x/y_offset；物弹遮罩起点）
var pos := Vector2.ZERO
var t := 0.0
## 【t/t_copy 语义（作者批复 20261019）】t_copy=本副本已存续时间（即上面的 t，
## 内部运动/航程用它）；t=弹幕事件的已存续时间=出现时刻的事件年龄+自身存续。
## 表达式 ctx 中：t=t_event+t、t_copy=t。首发副本 t_event=0；repeat 重放
## 子代继承载体释放时刻的 t；rotate 延时副本=基时+步进延时。
var t_event := 0.0
var depth := 0
var alive := true
var hidden_now := false
var rate_roll := 1.0
var pattern_roll := 1.0
var rand_seed0 := 0.0
var rand_seed1 := 0.0

## —— 火力点上下文（事件表达式可见：wpcs/to_c/main_lr/sub_lr）——
var ctx_wpcs := 1
var ctx_to_c := 0
var ctx_main_lr := 0
var ctx_sub_lr := 0
var ctx_extra: Dictionary = {} ## poi 表达式求值缓存共享（fire point 计算）

## 运动状态
var velocity := Vector2.ZERO
var dir := Vector2.RIGHT
var forward := 0.0
var heading := 0.0
var speed_scalar := 0.0
var lost_lock := false
var release_armed := true
var _active_latched := false ## 激活触发沿（20261020：接触即释放，锁存防连发）
var target: BattleEntity = null
## 激光几何（第①期：几何图形替代粒子）
var laser_base := Vector2.ZERO   ## 激光原点（事件注册位置）
var laser_samples: PackedVector2Array = [] ## n() 采样的几何顶点
var laser_len := 0.0
## 【瞬时类性能修复 20261005】AABB 快速排除（哈希查询先盒后段，免 801 段遍历）
var laser_aabb_pos := Vector2.ZERO
var laser_aabb_size := Vector2.ZERO

## 渲染缓存
var tex: Texture2D
var tex_half := 8.0
var draw_radius := 8.0
var hue_val := 0.0
var sat_val := 1.0
var base_hue_now := 0.0 ## color 列基础色相（hue 相对偏移的基准——20261019）
## 【HS 渲染语义（作者批复 2026-10-02）】颜色只提供 H/S，亮度由纹理像素
## 亮度继承（乘色实现：白→全亮目标色，灰→按亮度衰减）——默认 1=不额外压暗。
## 隐藏代码（源码可改，不进 UI）。
var lightness_val := 1.0
var alpha_now := 256.0
## 法弹白色前向轨道（作者批复 2026-10-02：我方法弹不渲染材质，
## 只画一条纯白半透明、照向行进方向的粒子轨道；速度×0.2秒距为长度基准）
var track_speed := 0.0
## 【A4·线性闭包表】对 t 线性的表达式（a+b·t）setup 数值探测拟合，逐帧免 Expression。
## 非线性（sin(t) 等）自动回退。空数组=不可用。
var _cl_x: Array = []
var _cl_y: Array = []
var _cl_speed: Array = []
var _cl_func: Array = []
var track_dir := Vector2.RIGHT
## 激光参数现值（作者批复 20261003：透明度/渲染规模可变=表达式，分频求值）
var asa_now := 1.0
var lrs_now := 1.0

## repeat 节拍（批复#15：缓冲时间前多次发射，双发/三发连射）
## 【20261003】repeat_enabled=false 用于 repeat 补发的子弹（发射节拍属事件层，
## 子弹不再繁殖——修复 regularline_copy 类事件指数增殖导致的冻结）
var repeat_enabled := true
var _repeat_fired := 0
var _spawn_origin_point := Vector2.ZERO ## 首发位置（repeat 在发射点/特定位置再释放）
## 【类型批复 20261019】出生时刻求值的个体参数（式/命题在弹幕出现瞬间定值）
var repeat_time_now := 0
var repeat_freq_now := 0
var range_now := 300.0
var dmg_now := 1
var size_mul := 1.0
var alarm_now := 0.0 ## 预警时长（整式，出生时求值）

## 【旋转重复 20261015（弹幕编辑器-新）】本副本轨迹整体旋转角（弧度，含 rotate_offset）
## 与副本标号（时序方式排序，首副本=0；表达式可引用 rotate_id）
var rot_angle := 0.0
var rotate_id := 0
## 【整扇锚定 20261019（作者批复：首弹不得随外界时序偏转）】延时副本以
## 释放时刻的扇形基向出膛（仅一般类；ZERO=未锚定，走常规表达式/自机狙）
var pinned_dir := Vector2.ZERO

var _world: Object = null
## 【性能休整·嫌疑1】shared_ctx：战场每帧构建一次公共字段；
##   _ctx：弹幕首帧引用 shared_ctx（不复制），之后就地写自身变量——零复制零分配
var shared_ctx: Dictionary = {}
var _ctx: Dictionary = {}
## 【20261002】表达式实际引用外部位置变量时才逐帧回填（uses_variable 编译期判定）：
##   修复①期遗留——target_x/self_x 等从未被填过（自机狙实际退化成直线弹），
##   同时避免为 95% 不需要它们的弹幕做每帧最近敌查询。
var _needs_target_vars := false
var _needs_xy_copy := false ## 【20261024】x_copy/y_copy 触发目标快照
var _shared_target: BattleEntity = null ## 【20261025g】整扇共享目标（setup 传入 → _fill_position_vars 用）
var _shared_txy := Vector2.INF ## 【20261025g】入口快照的目标相对坐标（INF=无）
var _xy_in_motion := false   ## 【20261025】x/y 运动式引用 x_copy/y_copy → 不冻结、不闭包、不系统旋转
var _xy_t0 := Vector2.ZERO   ## 【20261025】发射时刻冻结的目标世界坐标（x_copy/y_copy 的基准）
var _needs_self_vars := false
var _needs_d := false          ## 表达式引用了 d（目标距离）
var _needs_snapshot := false
var _snapshot_done := false
var _target_cached: BattleEntity = null
var _target_refresh_cd := 0
## 【20261003】本事件表达式实际用到的 ctx 键（setup 一次性收集）：
## _build_ctx 只写这些键——典型弹幕仅 t（1次写入），替代固定 15 键全写
var _ctx_keys: Array = []
## 【20261003·定值语义（作者批复）】角色/战场可变量（target_*/self_*/field_*）
## 在弹幕出现（含 repeat 补发）瞬间取定值，此后不再实时读取——否则目标移动、
## 战态变化会让满屏弹幕横飞；需要持续跟踪的交给点向类（Nodes，目标实体保持实时）。
## 派生收益：普通弹幕的方向/速度若不依赖 t/t_r，在 setup 冻结，逐帧零表达式求值。
var frozen_dir := Vector2.ZERO
var frozen_speed := 0.0
var frozen_ok := false

func setup(event: DanmakuEventData, spawn_origin: Vector2, bullet_side: int, src: BattleEntity, world: Object, spawn_depth: int = 0, fp_ctx: Dictionary = {}, shared_target: BattleEntity = null, shared_txy: Vector2 = Vector2.INF, setup_sp: Dictionary = {}, setup_rp: Dictionary = {}) -> void:
	ev = event
	_shared_target = shared_target
	_shared_txy = shared_txy
	side = bullet_side
	source = src
	source_side = src.side if src != null else bullet_side
	origin = spawn_origin
	pos = spawn_origin
	_spawn_origin_point = spawn_origin
	_world = world
	depth = spawn_depth
	ctx_wpcs = int(fp_ctx.get("wpcs", 1))
	ctx_to_c = int(fp_ctx.get("to_c", 0))
	ctx_main_lr = int(fp_ctx.get("main_lr", 0))
	ctx_sub_lr = int(fp_ctx.get("sub_lr", 0))
	ctx_extra = fp_ctx
	tex = DanmakuTex.resolve(ev.texture)
	tex_half = DanmakuTex.half_size(tex)
	draw_radius = tex_half * ev.danmaku_size_muti
	## 【量纲迁移 20261019】saturation/hue 为 0~256 整数量纲（类型一览.csv）；
	## hue 相对 color 基础色相偏移：H = fposmod(base_hue + hue/256, 1)
	base_hue_now = ev.base_hue()
	hue_val = fposmod(base_hue_now + ev.hue / 256.0, 1.0)
	## 【对比度倍乘 20261026（作者原文回退修正）】saturation=[0,256] 浮点=
	## 对比度倍乘（128=1.0 基准；>128 拉满对比度、<128 趋灰）——非"封顶比例"
	sat_val = maxf(0.0, ev.saturation / 128.0)
	rand_seed0 = randf() * TAU
	rand_seed1 = randf() * TAU
	if ev.tag == DanmakuEventData.TAG_NODES:
		target = _resolve_target()
		var tp := target_pos()
		heading = (tp - pos).angle()
		speed_scalar = _eval(ev.ex_speed, 3.0)
	elif ev.tag == DanmakuEventData.TAG_LASER:
		_build_laser_geometry()
	## 一般类 x/y 空缺时默认朝最近敌方（快速搭建便利，见规格书）
	if ev.tag == DanmakuEventData.TAG_REGULAR and ev.x.strip_edges().is_empty() and ev.y.strip_edges().is_empty():
		var tp: Vector2 = _world.bullet_nearest_enemy_pos(side, pos)
		dir = (tp - pos).normalized() if tp != pos else (Vector2.RIGHT if side == 0 else Vector2.LEFT)
	## 【整扇锚定 20261019】pinned 优先于自机狙/默认向——延时副本以释放时刻基向出膛
	if ev.tag == DanmakuEventData.TAG_REGULAR and pinned_dir != Vector2.ZERO:
		dir = pinned_dir
	## 外部变量需求（事件级编译期缓存，发射零扫描）
	for v in ev.ctx_keys_used:
		_ctx_keys.append(v)
		if v == "d":
			_needs_target_vars = true ## d 依赖 target 快照
			_needs_d = true
		elif String(v).begins_with("target_"):
			_needs_target_vars = true
		elif String(v).begins_with("self_"):
			_needs_self_vars = true
		elif v == "x_copy" or v == "y_copy" or v == "t_copy":
			## 【20261025g】copy 系同样依赖目标快照（基准=target_x/y）——
			## 此前只触发快照（_needs_xy_copy）但 target_x 键本身不在 _ctx_keys
			## 时 _fill_position_vars 不写 target_x → stamp 拿不到基准 → 静默跳过
			_needs_target_vars = true
	## 【20261025】x/y 运动式是否引用 x_copy/y_copy（帧控接管判定）
	_xy_in_motion = (ev.ex_x != null and (ev.ex_x.uses_variable("x_copy") or ev.ex_x.uses_variable("y_copy")))  	or (ev.ex_y != null and (ev.ex_y.uses_variable("x_copy") or ev.ex_y.uses_variable("y_copy")))

	## 激光参数现值（表达式→现值；无表达式=事件定值）
	asa_now = ev.alarm_shader_alpha ## 0~256 量纲（20261019 迁移；比值在使用处 /256）
	lrs_now = ev.laser_render_scale
	## 【定值语义】快照一次：出现瞬间的 target_*/self_*/field_t 全部定格进 ctx
	## 【修复 20261024】x_copy/y_copy 依赖目标快照——单独引用它们也要触发快照
	_needs_xy_copy = "x_copy" in _ctx_keys or "y_copy" in _ctx_keys
	_needs_snapshot = _needs_target_vars or _needs_self_vars or _needs_xy_copy
	if _needs_snapshot:
		_fill_position_vars()
		if shared_ctx.has("field_t"):
			_ctx["field_t"] = shared_ctx["field_t"]
			_ctx["field_phase"] = shared_ctx["field_phase"]
	## 【A4】t 依赖型表达式尝试线性闭包（数值探测：f(0)/f(1)/f(2)/f(3) 共线）
	var s_ctx0 := _build_ctx()
	## 【类型批复 20261019】出生时刻求值：伤害/规格/航程/repeat 参数（出现瞬间定值）
	var spnow: Dictionary = ev.eval_spawn_params(s_ctx0)
	dmg_now = int(spnow["dmg"])
	size_mul = float(spnow["size"])
	range_now = float(spnow["range"])
	alarm_now = float(spnow.get("alarm", ev.alarm))
	draw_radius = tex_half * size_mul
	var rpnow: Dictionary = ev.eval_repeat_params(s_ctx0)
	repeat_time_now = int(rpnow["time"])
	repeat_freq_now = int(rpnow["freq"])
	## 【20261025】x_copy/y_copy 依赖当前位置（每帧变化）→ 线性闭包不适用，跳过
	if _xy_in_motion:
		_cl_x = []
		_cl_y = []
	else:
		_cl_x = _fit_linear(ev.ex_x, s_ctx0)
		_cl_y = _fit_linear(ev.ex_y, s_ctx0)
	_cl_speed = _fit_linear(ev.ex_speed, s_ctx0)
	_cl_func = _fit_linear(ev.ex_func, s_ctx0)
	## 【22b 性能 20261028】快路径判定：_ctx_keys 全为廉价键（t 系/骰子/常量）
	_fast_ctx = true
	for _fk in _ctx_keys:
		if _fk not in ["t", "t_copy", "t_r", "field_t", "field_phase", "rate_roll",
				"pattern_roll", "rotate_id", "r0", "r1", "n"]:
			_fast_ctx = false
			break
	## 【22b 终修】静态键收集：快照/stamp 后不变的键（每帧无需重写）
	for _sk in _ctx_keys:
		if _sk.begins_with("target_") or _sk.begins_with("self_") 				or _sk == "x_copy" or _sk == "y_copy" or _sk == "d" or _sk == "n":
			_static_keys.append(_sk)
	## 【22b 20261028】w 冻结：x/y 引用的变量全为静态键（快照/stamp 常量）时
	## w 每帧恒定——setup 解算一次 dir，逐帧跳过双 eval+normalized+rotated
	## （demo_aimed 类：x/y 只用 target_*/x_copy/t_copy/d → 全静态）
	if _xy_in_motion and ev.tpl_is_regular:
		## 【22b 20261031d】w 冻结资格=事件级模板（原每发 27 变量×2 表达式扫描）
		var w_static: bool = ev.tpl_w_frozen_eligible
		if w_static:
			var w0 := Vector2(_eval(ev.ex_x, 0.0, s_ctx0), _eval(ev.ex_y, 0.0, s_ctx0))
			if w0 != Vector2.ZERO and is_finite(w0.x) and is_finite(w0.y):
				var d0 := w0.normalized()
				if rot_angle != 0.0:
					d0 = d0.rotated(rot_angle)
				_w_frozen_dir = d0
		elif ev.tpl_table_eligible:
			## 【22b 20261031d】建表资格=事件级模板
			## 【22b 20261030c→1031 摊帧】建表推迟到首次 update（_tbl_pending）：
			## setup×121点×2 eval 在整扇 70 副本时=发射帧 ~17ms 尖峰的构成；
			## 摊到各弹自己的第一帧。表内容与即时建完全一致（t_copy=0 起）。
			_tbl_pending = true
	var _qd := Time.get_ticks_usec()
	## 冻结判定：x/y/speed 均不依赖 t/t_r → 逐帧零求值（r0/r1 本就出生即定）
	if ev.tag == DanmakuEventData.TAG_REGULAR or ev.tag == DanmakuEventData.TAG_PHYSICAL:
		if not ev.motion_time_bound and not _xy_in_motion: ## 【20261025】x_copy 帧控弹幕不冻结
			## 定值弹幕：x/y/speed 均不依赖 t/t_r → 出现瞬间解算并冻结，逐帧零求值
			var s_ctx := _build_ctx()
			var w := Vector2(_eval(ev.ex_x, 0.0, s_ctx), _eval(ev.ex_y, 0.0, s_ctx))
			if pinned_dir != Vector2.ZERO:
				frozen_dir = pinned_dir ## 整扇锚定：覆盖 gettarget 快照（不随延时重瞄）
			elif w != Vector2.ZERO:
				frozen_dir = w.normalized()
			frozen_speed = _eval(ev.ex_speed, 3.0 if ev.tag == DanmakuEventData.TAG_REGULAR else 1.0, s_ctx)
			if frozen_dir != Vector2.ZERO and frozen_speed != 0.0:
				frozen_ok = true
				dir = frozen_dir
				velocity = frozen_dir * frozen_speed
	## 【语义终版 20261025g】副本常量盖章：t_copy/x_copy/y_copy 发射后决定
	if _needs_xy_copy and _ctx.has("target_x"):
		var crx := float(_ctx["target_x"])
		var cry := float(_ctx["target_y"])
		var cc := cos(-rot_angle)
		var csn := sin(-rot_angle)
		if _ctx_keys.has("t_copy"):
			_ctx["t_copy"] = 0.0 ## 发射时刻=0（update 后由 match 随帧递增）
		if _ctx_keys.has("x_copy"):
			_ctx["x_copy"] = crx * cc - cry * csn
		if _ctx_keys.has("y_copy"):
			_ctx["y_copy"] = crx * csn + cry * cc

	## 【旋转重复 20261015】初态旋转：冻结方向/速度向量/初始朝向/激光几何
	if rot_angle != 0.0:
		## 【语义修正 20261025i】x_copy 的 R(-a) 预补偿须与系统 R(+a) 相消（作者模型：
		## 表达式在未倾斜系书写，系统整体旋转轨迹）——跳过系统旋转会把 x_copy 变成
		## 镜像扇=与纯 x 同分布（"表现与 x 相同"的根因）
		if frozen_dir != Vector2.ZERO:
			frozen_dir = frozen_dir.rotated(rot_angle)
		if dir != Vector2.ZERO:
			dir = dir.rotated(rot_angle)
		if velocity != Vector2.ZERO:
			velocity = velocity.rotated(rot_angle)
		if ev.tag == DanmakuEventData.TAG_LASER:
			_rotate_laser()
		elif ev.tag == DanmakuEventData.TAG_NODES:
			heading += rot_angle

## =============================================================
## 每帧推进（dt=帧数）。返回 false = 消亡
## =============================================================
## 【22b 性能 20261028】快路径判定：_ctx_keys 仅含廉价键（t/t_copy/field/
## rotate_id/骰子）时 update 内直接赋值，跳过 _build_ctx 的 match 全扫
var _fast_ctx := false ## setup 末尾判定
## 【22b 终修 20261028】动态/静态键二分：target_*/self_*/x_copy/y_copy/d/n
## 在快照或 stamp 后为常量——_build_ctx 每帧只更新动态键（t 系/field/骰子/
## rotate_id/rate_roll/pattern_roll），静态键跳过。实测 723 弹真实数据下
## bullets 段 49.65ms/帧 的主体就是每弹全键重扫+Expression。
var _static_keys: PackedStringArray = [] ## stamp 后不再变的键（_fill 一次）
var _w_frozen_dir := Vector2.ZERO ## 【22b 20261028】x/y 全静态键弹：w 一次解算冻结（逐帧跳过双 eval）
## 【22b 20261030c·表达式预采样表（作者"对战前缓存"落点）】
## t 依赖弹（_w_frozen 不适用）在 setup 时对 t 均匀采样存表，逐帧查表插值：
## Expression.execute 17µs → 查表 <1µs。静态键快照后不变=表只依赖 t。
## 采样步长 5 帧（≤121 点，弹寿命钳 600）；sin(0.1t) 类每周期 12+ 采样。
var _tbl_x := PackedFloat32Array()
var _tbl_y := PackedFloat32Array()
var _tbl_step := 5.0
var _tbl_t0 := 0.0
var _tbl_pending := false ## 【1031 摊帧】首次 update 时建表
var _lf_phase := 0 ## 【审计#39】low_freq 相位（setup 随机 0-5）
var _bulk_skip := false ## 【22b 20261101】批量运动学弹：本帧 _step_regular 跳过

func update(dt: float) -> bool:
	if not alive:
		return false
	t += dt
	if t > range_now:
		return false
	## 【A7·出界处理】0=销毁（超界 x=弹实际大小）；1=反射；2=不处理
	if ev.oob_mode == 0:
		var m := draw_radius
		if pos.x < -m or pos.x > 400.0 + m or pos.y < -m or pos.y > 400.0 + m:
			return false
	elif ev.oob_mode == 1:
		var m2 := draw_radius
		var bounced := false
		if pos.x < -m2:
			pos.x = -m2; velocity.x = absf(velocity.x); dir.x = absf(dir.x); bounced = true
		if pos.x > 400.0 + m2:
			pos.x = 400.0 + m2; velocity.x = -absf(velocity.x); dir.x = -absf(dir.x); bounced = true
		if pos.y < -m2:
			pos.y = -m2; velocity.y = absf(velocity.y); bounced = true
		if pos.y > 400.0 + m2:
			pos.y = 400.0 + m2; velocity.y = -absf(velocity.y); bounced = true
		if bounced:
			origin = pos ## 反射后以当前点为新原点（一般类公式）
	## 【撤销 20261025g】实时追踪与作者语义冲突（t_copy/x_copy/y_copy 均为
	## 副本发射后决定的定值，非实时值）——目标基准在发射时刻一次性决定
	## 【22b 终极 20261028】纯廉价键弹跳过 _build_ctx 调用（原地写 3 键）
	if _tbl_pending:
		_tbl_pending = false
		## 【1031 摊帧】首次 update 建表（快照键此时已就绪）
		var life2: float = clampf(range_now, 60.0, 600.0)
		var n_pts2: int = int(life2 / _tbl_step) + 1
		_tbl_x.resize(n_pts2)
		_tbl_y.resize(n_pts2)
		var tctx2 := _build_ctx()
		for pi3 in n_pts2:
			var tv2: float = float(pi3) * _tbl_step
			tctx2["t"] = t_event + tv2
			tctx2["t_copy"] = tv2
			_tbl_x[pi3] = _eval(ev.ex_x, 0.0, tctx2)
			_tbl_y[pi3] = _eval(ev.ex_y, 0.0, tctx2)
	var ctx: Dictionary
	if _fast_ctx:
		if _ctx_keys.has("t"):
			_ctx["t"] = t_event + t
		if _ctx_keys.has("t_copy"):
			_ctx["t_copy"] = t
		if shared_ctx.has("field_t"):
			_ctx["field_t"] = shared_ctx["field_t"]
			_ctx["field_phase"] = shared_ctx["field_phase"]
		ctx = _ctx
	else:
		ctx = _build_ctx()
	## 【性能休整·分频】pass/alpha/hue/sat 低频字段每6帧求值一次
	## （作者批复#4：不影响表现的前提下分频可行）
	## 【22b 20261031f·审计#39】low_freq 相位分散：原 int(t)%6 全场弹同步
	## 命中（同帧发射弹 t 相同）→ 每 6 帧一次 6 表达式求值尖峰；
	## 改按弹相位错开（_lf_phase=setup 时 randi 0-5）
	var do_low_freq := (int(t) + _lf_phase) % 6 == 0
	if do_low_freq:
		hidden_now = ev.ex_pass != null and ev.ex_pass.execute_dict(ctx, 0.0) > 0.5
		alpha_now = 256.0 if ev.ex_alpha == null else ev.ex_alpha.execute_dict(ctx, 256.0)
		alpha_now = clampf(alpha_now, 0.0, 256.0)
		if ev.ex_hue != null:
			hue_val = fposmod(base_hue_now + floorf(ev.ex_hue.execute_dict(ctx, ev.hue)) / 256.0, 1.0) ## 【整数语义 20261025d】
		if ev.ex_sat != null:
			sat_val = maxf(0.0, floorf(ev.ex_sat.execute_dict(ctx, ev.saturation)) / 128.0) ## 【倍乘 20261026】
		## 激光参数可变（作者批复 20261003）：透明度/渲染规模表达式，6帧一拍
		if ev.ex_asa != null:
			asa_now = clampf(ev.ex_asa.execute_dict(ctx, ev.alarm_shader_alpha), 0.0, 256.0)
		if ev.ex_lrs != null:
			lrs_now = maxf(0.5, ev.ex_lrs.execute_dict(ctx, ev.laser_render_scale))
	match ev.tag:
		DanmakuEventData.TAG_REGULAR: _step_regular(dt, ctx)
		DanmakuEventData.TAG_PHYSICAL: _step_physical(dt, ctx)
		DanmakuEventData.TAG_FUNCTED: _step_functed(dt, ctx)
		DanmakuEventData.TAG_LASER:
			## 【20261004】激光 x/y 支持可变变量（t）：仅 t 依赖型每 6 帧重采样
			## （静态激光一次成型；动态重采样上限 401 采样防高密度爆炸）
			if ev.laser_time_bound and int(t) % 6 == 0:
				_build_laser_geometry(ctx, 401)
				_rotate_laser() ## 旋转重复：重建后重新旋转（AABB 一并修正）
			## 【R-ETA·瞬时类 20261027（新二 L234）】预警期内向目标注册规避：
			## 最近线段的垂向逃离（s=5/x，x=到线段最近点距离）
			if target != null and int(t) % 6 == 0 and laser_samples.size() >= 2:
				var tnow := t
				if tnow <= alarm_now and alarm_now > 0.0:
					var best_d := INF
					var best_p := pos
					var stride := maxi(1, laser_samples.size() / 24)
					for si in range(0, laser_samples.size() - 1, stride):
						var sa: Vector2 = laser_samples[si]
						var sb: Vector2 = laser_samples[si + 1]
						var ab: Vector2 = sb - sa
						var tt: float = clampf((target.position - sa).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
						var cp: Vector2 = sa + ab * tt
						var dcp: float = cp.distance_to(target.position)
						if dcp < best_d:
							best_d = dcp
							best_p = cp
					var x6 := maxf(best_d, 4.0)
					var eta6 := x6 / maxf(speed_scalar, 1.0)
					if eta6 < 1.5:
						var away6 := (target.position - best_p).normalized()
						target.reta_force += away6 * (5.0 / x6) * (1.0 if eta6 < 0.5 else 0.5)
		DanmakuEventData.TAG_NODES:
			if not _step_nodes(dt, ctx):
				return false
	## 点向类可摧毁：被可击中本方的弹幕（哈希查询）命中即消亡
	## 【20261003】查询 30Hz（与被弹判定同拍）——作者"不要附加判定"语义内
	if ev.tag == DanmakuEventData.TAG_NODES or ev.tag == DanmakuEventData.TAG_NODES_B:
		## 【对撞（20261020）】命题真或旧 can_destroy：参与检测，可被物弹/敌弹摧毁；
		## clash_ddm 名单决定可摧毁来源侧别（_clash_sides）
		var clash_on := ev.can_destroy or (ev.ex_clash != null and ev.ex_clash.eval_prop(ctx, 0.0) > 0.5)
		if clash_on and _world != null and int(t) % 2 == 0:
			var destroyed := false
			for qside in _clash_sides():
				if not _world.bullet_hit_query(pos.x, pos.y, 2.0, qside, null).is_empty():
					destroyed = true
					break
			if destroyed:
				return false
		## 【激活（20261020）】命题真：任何弹幕接触即跳过释放条件触发释放事件
		if ev.ex_active != null and ev.ex_active.eval_prop(ctx, 0.0) > 0.5 and _world != null:
			if int(t) % 2 == 0:
				var touch_e: Dictionary = _world.bullet_hit_query(pos.x, pos.y, draw_radius, 1 - side, null)
				var touch_f: Dictionary = _world.bullet_hit_query(pos.x, pos.y, draw_radius, side, null)
				if (not touch_e.is_empty() or not touch_f.is_empty()) and not _active_latched:
					_active_latched = true
					_fire_event_list(ev.release)
	return true ## pass=真：弹幕继续运行，仅不注册弹幕图/不渲染（隐藏由 hidden_now 表达）

## 【clash_ddm 20261020】家族名单 → 可被摧毁来源侧别集合
## （ddms/ddmsma/ddmsmb/ddma=0方视角系、ddme/ddmema/ddmemb=1方视角系、ddmp=双方物弹）
func _clash_sides() -> Array:
	var list := ev.clash_ddm_s.to_lower().replace(" ", "")
	var sides: Array = []
	if list == "":
		return [1 - side] ## 空名单：旧默认（敌侧）
	var has_s := list.contains("ddms") or list.contains("ddma")
	var has_e := list.contains("ddme") or list.contains("ddma")
	var has_p := list.contains("ddmp")
	if has_e and side != 0:
		sides.append(0)
	if has_s and side != 1:
		sides.append(1)
	if has_p:
		for q in 2:
			if not sides.has(q):
				sides.append(q)
	if sides.is_empty():
		sides = [1 - side]
	return sides

## —— repeat 节拍：事件存活期内再发射副本 ——
## 【语义修订 20261015（弹幕编辑器-新）】repeat_time=副本重复间隔（帧，原"持续时间"
## 歧义已改）、repeat_freq=重复发射次数（0=禁用）。第 n 次补发发生于 t≥n×repeat_time。
## 由战场主循环在事件粒度调用（非弹幕粒度）；返回 true=本帧应再发一枚
func repeat_tick() -> bool:
	if not repeat_enabled or repeat_freq_now <= 0 or repeat_time_now <= 0:
		return false
	if _repeat_fired >= repeat_freq_now:
		return false
	var interval := float(maxi(1, repeat_time_now))
	var want := int(t / interval)
	if want > _repeat_fired:
		_repeat_fired = want
		return true
	return false

func repeat_origin() -> Vector2:
	return _spawn_origin_point

func _step_regular(dt: float, ctx: Dictionary) -> void:
	if _bulk_skip:
		return ## 【22b 20261101】C++ 批量已处理（pos/dir 由战场回写）
	if frozen_ok:
		## 定值弹幕：方向/速度已在出现瞬间冻结，逐帧零求值（性能批复）
		track_speed = frozen_speed
		track_dir = dir
		pos = origin + dir * frozen_speed * t
		return
	if _w_frozen_dir != Vector2.ZERO:
		dir = _w_frozen_dir ## 【22b】x/y 全静态键：w 逐帧恒定（setup 已冻结）
	elif _tbl_x.size() >= 2:
		## 【22b 20261030c】预采样查表插值（t 相对表起点；越界钳末值）
		var tq: float = clampf(t - _tbl_t0, 0.0, _tbl_step * float(_tbl_x.size() - 1))
		var fi: float = tq / _tbl_step
		var i0: int = int(fi)
		var fr: float = fi - float(i0)
		var i1: int = mini(i0 + 1, _tbl_x.size() - 1)
		var wx: float = _tbl_x[i0] + (_tbl_x[i1] - _tbl_x[i0]) * fr
		var wy: float = _tbl_y[i0] + (_tbl_y[i1] - _tbl_y[i0]) * fr
		var w := Vector2(wx, wy)
		if w != Vector2.ZERO and is_finite(w.x) and is_finite(w.y):
			dir = w.normalized()
			if rot_angle != 0.0:
				dir = dir.rotated(rot_angle)
	else:
		var w := Vector2(_eval_lin(_cl_x, ev.ex_x, ctx, 0.0), _eval_lin(_cl_y, ev.ex_y, ctx, 0.0))
		if w != Vector2.ZERO and is_finite(w.x) and is_finite(w.y):
			## 【22b 防御 20261028】inf/NaN 的 normalized/rotated 在浮点异常值慢路径
			## 上 940 倍慢（0.083→78µs）——表达式除零等意外不得拖垮全场
			dir = w.normalized()
			if rot_angle != 0.0:
				dir = dir.rotated(rot_angle) ## 旋转重复：运算轨迹整体旋转（含 x_copy 消偿）
	var s := _eval_lin(_cl_speed, ev.ex_speed, ctx, 3.0)
	if not is_finite(s):
		s = 0.0
	track_speed = s
	track_dir = dir
	if _xy_in_motion:
		## 【修复 20261025d·作者B反馈】x_copy 帧控一般弹幕=积分位移——原射线式
		## pos=O+dir·s·t 在 dir 逐帧变化时模长恒=t、方向狂转（"以原点为心的圆上
		## 飞速旋转"的根因）；积分后为正常偏置追踪螺线
		velocity = dir * s ## 【修复 20261025g】帧控分支须同步 velocity（此前恒 0——
		pos += dir * s * dt ## 轨道/碰撞速度全失效=作者"目标点停滞并抽搐"的另一半）
	else:
		pos = origin + dir * s * t

func _step_physical(dt: float, ctx: Dictionary) -> void:
	if frozen_ok:
		## 定值弹幕：速度向量在出现瞬间冻结（速度=快照值，不再随场态变化）
		track_speed = velocity.length()
		if velocity != Vector2.ZERO:
			track_dir = velocity.normalized()
		pos += velocity * dt
		return
	var v := Vector2(_eval_lin(_cl_x, ev.ex_x, ctx, 0.0), _eval_lin(_cl_y, ev.ex_y, ctx, 0.0))
	var m := _eval_lin(_cl_speed, ev.ex_speed, ctx, 1.0)
	if not (is_finite(v.x) and is_finite(v.y) and is_finite(m)):
		v = Vector2.ZERO; m = 0.0 ## 【22b 防御】异常浮点慢路径防护
	velocity = v * m
	if rot_angle != 0.0:
		velocity = velocity.rotated(rot_angle) ## 系统 R(+a)（x_copy 的 R(-a) 在此消偿）
	track_speed = velocity.length()
	if velocity != Vector2.ZERO:
		track_dir = velocity.normalized()
	pos += velocity * dt

func _step_functed(dt: float, ctx: Dictionary) -> void:
	var w := Vector2(_eval_lin(_cl_x, ev.ex_x, ctx, 1.0), _eval_lin(_cl_y, ev.ex_y, ctx, 0.0))
	if w != Vector2.ZERO:
		dir = w.normalized()
		if rot_angle != 0.0:
			dir = dir.rotated(rot_angle) ## 旋转重复：坐标系x轴随副本旋转（y=逆时针90°随之）
	var s := _eval_lin(_cl_speed, ev.ex_speed, ctx, 3.0)
	forward += s * dt
	var lat := _eval_lin(_cl_func, ev.ex_func, ctx, 0.0)
	track_speed = s
	track_dir = dir
	pos = origin + dir * forward + Vector2(-dir.y, dir.x) * lat

## =============================================================
## 激光几何（第①期重做，作者批复）
##   x/y 为表达式；n(k) 为遍历换元——代替数轴变量，每 k 像素采样一点
##   （n() 仅瞬时类允许；例：圆 x=50*cos(n(1)), y=50*sin(n(1))）
##   range = xy 方向渲染的像素规模（正负像素数）
## =============================================================
func _build_laser_geometry(passed_ctx: Dictionary = {}, max_samples: int = 801) -> void:
	laser_base = origin
	laser_samples.clear()
	var n_step := maxi(1, ev.laser_n_step) ## n(数值) 的采样频率
	## 遍历换元：n 从 -range 到 +range，步长 n_step 像素
	## 【类型批复 20261019】航程允许算式——激光用出生时求值的个体航程
	var rng := range_now
	## 传入 ctx（动态重建时携带当前 t）；无则取当前快照
	var ctx := passed_ctx if not passed_ctx.is_empty() else _build_ctx()
	var samples_wanted: int = mini(max_samples, int(rng * 2.0 / float(n_step)) + 1) ## 采样上限护栏
	var last: Vector2 = Vector2(INF, INF)
	var amin := Vector2(INF, INF)
	var amax := Vector2(-INF, -INF)
	for i in samples_wanted:
		var n_val := -rng + float(i * n_step)
		ctx["n"] = n_val
		var px := _eval(ev.ex_x, n_val, ctx) + laser_base.x
		var py := _eval(ev.ex_y, n_val, ctx) + laser_base.y
		var p := Vector2(px, py)
		if p.distance_squared_to(last) > 0.01:
			laser_samples.append(p)
			amin = amin.min(p)
			amax = amax.max(p)
			last = p
	laser_len = rng
	if laser_samples.size() > 0:
		laser_aabb_pos = amin
		laser_aabb_size = amax - amin

## 激光渲染宽度（作者批复 20261002：渲染规模=1像素材质的缩放，独立参数
## laser_render_scale，由玩家和作者决定大小——实现绀珠传式粗激光等）
## 预警期仍按 alarm_shader 阶段变细（×0.3，由调用方处理）
func laser_width() -> float:
	return maxf(0.5, lrs_now if ev.ex_lrs != null else ev.laser_render_scale)

## 【旋转重复 20261015】激光几何整体绕原点旋转（含 AABB 修正）
func _rotate_laser() -> void:
	if rot_angle == 0.0 or laser_samples.is_empty():
		return
	var amin := Vector2(INF, INF)
	var amax := Vector2(-INF, -INF)
	for i in laser_samples.size():
		laser_samples[i] = laser_base + (laser_samples[i] - laser_base).rotated(rot_angle)
		amin = amin.min(laser_samples[i])
		amax = amax.max(laser_samples[i])
	laser_aabb_pos = amin
	laser_aabb_size = amax - amin

## =============================================================
## 点向类
## =============================================================
func _step_nodes(dt: float, ctx: Dictionary) -> bool:
	var tp := target_pos()
	var dist := pos.distance_to(tp)
	## lost_if 命题（作者批复新增）：真=暂时失锁转直线，直至命题为否
	if ev.ex_lost_if != null:
		var lif := ev.ex_lost_if.execute_dict(ctx, 0.0) > 0.5
		if lif:
			lost_lock = true
		elif not _has_hard_lock_loss(tp, dist):
			lost_lock = false
	elif not _has_hard_lock_loss(tp, dist):
		lost_lock = false
	if not lost_lock and target != null:
		var want := (tp - pos).angle()
		var diff := wrapf(want - heading, -PI, PI)
		heading += clampf(diff, -ev.turn_arg * dt, ev.turn_arg * dt)
	speed_scalar += ev.acc * dt
	if ev.speed_max > 0.0:
		speed_scalar = minf(speed_scalar, ev.speed_max)
	velocity = Vector2(cos(heading), sin(heading)) * speed_scalar
	track_speed = speed_scalar

	track_dir = velocity.normalized() if velocity != Vector2.ZERO else Vector2(cos(heading), sin(heading))
	pos += velocity * dt
	## 【R-ETA 20261027（新二 L232-234）】追踪弹 ETA 反应：
	## ETA<1s 注册垂向规避（s=5/x；<0.25s 全额）；**掠过判定**：速度矢量已
	## 远离目标（to_target·vel <0 =弹已越过最近点）→ 不再注册（冲撞不伤——
	## 速度矢量远离自机未移动时的方向，合力量<10px/s 不判撞）
	if target != null and not lost_lock and speed_scalar > 0.5:
		var to_t5 := target.position - pos
		var approaching := to_t5.dot(velocity) > 0.0 ## 仍在接近
		if approaching:
			var x5 := dist
			var eta5 := x5 / speed_scalar
			if eta5 < 1.0:
				var away5 := to_t5.normalized()
				var perp5 := Vector2(-away5.y, away5.x)
				var mag5 := 5.0 / maxf(x5, 4.0)
				target.reta_force += perp5 * mag5 * (1.0 if eta5 < 0.25 else 0.5) * signf(fposmod(rand_seed0, 1.0) - 0.5)
	## 【20261020 改名+上升沿】释放条件=release_when（旧 release_condit 兼容）：
	## 每次从假到真上升沿执行释放事件列表（不清除本体）
	## 【20261004】事件名升级为数列（逗号分隔；编辑器绑定框增删）——逐个生成
	var rw := ev.ex_release_when
	if rw != null:
		var r := rw.eval_prop(ctx, 0.0) > 0.5
		if r and release_armed and ev.release != "":
			_fire_event_list(ev.release)
			release_armed = false
		elif not r:
			release_armed = true
	## 引爆条件=inherit_when（旧 explode_condit 兼容）：命题为真 → 执行继承列表并消除
	var iw := ev.ex_inherit_when
	if iw != null and ev.inherit_s != "":
		if iw.eval_prop(ctx, 0.0) > 0.5:
			_fire_event_list(ev.inherit_s)
			return false
	return true

## 事件列表生成（逗号分隔的事件名；深度限界由 spawn 侧把关）
func _fire_event_list(list_text: String) -> void:
	if list_text == "" or _world == null:
		return
	for nm in list_text.split(",", false):
		_world.spawn_event_by_name(nm.strip_edges(), pos, side, depth + 1)

## =============================================================
## 【新节点类 NodesB（作者 20261020）】标准物理节点：
##   x/y/speed 速度表达式（func 非空→轨道式坐标轴）——复刻绀珠传式
##   "弹幕推弹幕"：对撞命题为真的 NodesB 之间接触互推（分离+法向速度交换）；
##   激活/继承/释放与点向类同语义。targe_x/y 为返回值（动态目标相对自身）。
## =============================================================
func _step_nodes_b(dt: float, ctx: Dictionary) -> void:
	if ev.func_expr.strip_edges() != "":
		## 轨道式：x/y=坐标轴向量、speed=行进、func=垂直偏移（同轨道类）
		var w := Vector2(_eval(ev.ex_x, 1.0), _eval(ev.ex_y, 0.0))
		if w != Vector2.ZERO:
			dir = w.normalized()
		forward += _eval(ev.ex_speed, 3.0) * dt
		var lat := _eval(ev.ex_func, 0.0)
		pos = origin + dir * forward + Vector2(-dir.y, dir.x) * lat
		velocity = dir * _eval(ev.ex_speed, 3.0)
	else:
		velocity = Vector2(_eval(ev.ex_x, 0.0), _eval(ev.ex_y, 0.0)) * _eval(ev.ex_speed, 1.0)
		pos += velocity * dt
	track_speed = velocity.length()
	track_dir = velocity.normalized() if velocity != Vector2.ZERO else track_dir
	## 返回值：动态目标相对自身（供表达式引用）
	var tp: Vector2 = _world.bullet_nearest_enemy_pos(side, pos) if _world != null else pos
	ctx["targe_x"] = tp.x - pos.x
	ctx["targe_y"] = tp.y - pos.y
	## 释放/继承（与点向类同语义；上升沿）
	var rw := ev.ex_release_when
	if rw != null:
		var r := rw.eval_prop(ctx, 0.0) > 0.5
		if r and release_armed and ev.release != "":
			_fire_event_list(ev.release)
			release_armed = false
		elif not r:
			release_armed = true
	var iw := ev.ex_inherit_when
	if iw != null and ev.inherit_s != "":
		if iw.eval_prop(ctx, 0.0) > 0.5:
			_fire_event_list(ev.inherit_s)
			alive = false

func _has_hard_lock_loss(_tp: Vector2, dist: float) -> bool:
	return (ev.lost_max > 0.0 and dist > ev.lost_max) or (ev.lost_min > 0.0 and dist < ev.lost_min)
## =============================================================
## 碰撞/渲染接口（BulletHash 与战场调用）
## =============================================================
## 当前有效伤害（激光随预警阶段 -1；其余=出生时求值的个体伤害——式/命题 20261019）
func hit_damage() -> int:
	if ev.tag == DanmakuEventData.TAG_LASER:
		if t <= alarm_now:
			return -1
		return mini(16, dmg_now)
	return dmg_now

## 碰撞半径（哈希圆判定用；激光=线宽）
func hit_radius() -> float:
	if ev.tag == DanmakuEventData.TAG_LASER:
		return laser_width()
	return draw_radius

## 圆碰撞（实体判定圆 vs 弹幕圆；激光走线段集合）
func overlaps_circle(cx: float, cy: float, r: float) -> bool:
	if ev.tag == DanmakuEventData.TAG_LASER:
		## 【瞬时类性能修复 20261005】AABB 快速排除后再走线段
		## （此前每查询线性扫最多 801 段——比 Nodes 单点判定贵百倍）
		if cx < laser_aabb_pos.x - r or cx > laser_aabb_pos.x + laser_aabb_size.x + r:
			return false
		if cy < laser_aabb_pos.y - r or cy > laser_aabb_pos.y + laser_aabb_size.y + r:
			return false
		var rr := r + laser_width()
		for i in laser_samples.size() - 1:
			if _seg_circle(laser_samples[i], laser_samples[i + 1], cx, cy, rr):
				return true
		return false
	var d := pos - Vector2(cx, cy)
	return d.length_squared() <= (draw_radius + r) * (draw_radius + r)

func _seg_circle(a: Vector2, b: Vector2, cx: float, cy: float, r: float) -> bool:
	var ab := b - a
	var t := clampf(((Vector2(cx, cy) - a).dot(ab)) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	var closest := a + ab * t
	return closest.distance_squared_to(Vector2(cx, cy)) <= r * r

## 物弹是否已超出发射源友伤遮罩（15×慢机速度，遮罩起点=x/y_offset 后的发射原点）
func beyond_mask() -> bool:
	if source == null:
		return true
	var mask_r := 15.0 * source.normal_speed()
	return pos.distance_to(origin) > mask_r

## 【热力扫过段 20261026（作者"满天星"根因修复）】上次 Ht 采样帧的位置——
## DDM 是逐帧瞬时快照而 Ht 每 0.1s 才读一次：速度 v 的弹幕两次采样间走 6v 像素，
## 扩散半径 1px 补不上 → 热力轨迹成间隔点列（"满天星"）。采样帧改为扫过段盖章。
var heat_prev := Vector2(INF, INF)

## GPU 印章数据导出（x,y,r；激光=顶点序列各一枚小圆）
## swept=true（Ht 采样帧）：非激光弹追加 heat_prev→pos 的沿线印章（步长=半径）
func export_stamps(arr: PackedFloat32Array, swept := false) -> void:
	if hidden_now:
		return
	if swept and heat_prev.x != INF:
		var seg: Vector2 = pos - heat_prev
		var seglen := seg.length()
		if seglen > draw_radius * 0.5:
			var steps: int = maxi(1, int(seglen / maxf(draw_radius * 0.5, 1.0)))
			for si in steps:
				var sp: Vector2 = heat_prev + seg * (float(si) / float(steps))
				arr.append(sp.x)
				arr.append(sp.y)
				arr.append(draw_radius)
				arr.append(0.0)
	if ev.tag == DanmakuEventData.TAG_LASER:
		## 【瞬时类性能修复 20261005】印章跨步：间距≈4×线宽（DDM 覆盖连续即可）
		## ——旧版每采样一枚（601 印章/帧/发，激光多时 SSBO 与上传爆量）
		var w := laser_width()
		var stride := maxi(1, int(w * 4.0))
		for i in range(0, laser_samples.size(), stride):
			var p: Vector2 = laser_samples[i]
			arr.append(p.x)
			arr.append(p.y)
			arr.append(w)
			arr.append(0.0)
	else:
		arr.append(pos.x)
		arr.append(pos.y)
		arr.append(draw_radius)
		arr.append(0.0)

## =============================================================
## 上下文与工具
## =============================================================
## =============================================================
## 上下文与工具
## =============================================================
## 【性能休整·嫌疑1修复】零复制上下文方案：
##   shared_ctx 只含 field_t/field_phase（全局不变，所有弹幕共享同一个引用）。
##   self_*/target_* 不进 shared_ctx——绝大多数弹幕表达式不依赖它们
##   （只有自机狙 demo_aimed 用 target_x/target_y，这类弹幕 <5%）。
##   需要时由 _build_ctx 每弹自行填（低频，且 source.position 是 O(1) 属性读取）。
func _build_ctx() -> Dictionary:
	## 【20261003修复】旧"首帧重建字典"会把 setup 阶段已填好的定值快照整个
	## 清空（自机狙朝右的元凶）——_ctx 生命周期改为声明即用、永不整体置换
	## 【20261003】只写表达式用到的键（_ctx_keys setup 收集；典型=仅 t）
	## 共享字段单独判断（几乎全部事件都用 field_t 或 t）
	## 【22b 性能 20261028】快路径：_ctx_keys 全为廉价键（t 系/骰子/常量已 stamp）
	## 时只写 t 系+共享字段，跳过 match 全扫与 copy stamp 重算——
	## 实测 build_ctx 占 update 48%（2000 弹 3.4ms/帧）
	if _fast_ctx:
		if _ctx_keys.has("t"):
			_ctx["t"] = t_event + t
		if _ctx_keys.has("t_copy"):
			_ctx["t_copy"] = t
		if shared_ctx.has("field_t"):
			_ctx["field_t"] = shared_ctx["field_t"]
			_ctx["field_phase"] = shared_ctx["field_phase"]
		if shared_ctx.has("collapse_counts"):
			var ccq: Dictionary = shared_ctx["collapse_counts"]
			for kq in ["friendly_privates_collapse", "friendly_chara_collapes",
					"enemy_privates_collapse", "enemy_chara_collapes",
					"field_privates_collapse", "field_chara_collapes"]:
				if kq in _ctx_keys:
					_ctx[kq] = float(ccq.get(kq, 0.0))
		_fill_position_vars()
		return _ctx

	if shared_ctx.has("field_t"):
		_ctx["field_t"] = shared_ctx["field_t"]
		_ctx["field_phase"] = shared_ctx["field_phase"]
	if shared_ctx.has("collapse_counts"):
		var cc: Dictionary = shared_ctx["collapse_counts"]
		for k in ["friendly_privates_collapse", "friendly_chara_collapes",
				"enemy_privates_collapse", "enemy_chara_collapes",
				"field_privates_collapse", "field_chara_collapes"]:
			if k in _ctx_keys:
				_ctx[k] = float(cc.get(k, 0.0))
	## 【22b 终修】静态键（快照/stamp 常量）跳过——只在首次/重置后写
	## （动态键走下方 match；静态键由 _fill_position_vars/stamp 一次写入）
	## 【语义终版 20261025g（作者明示）】t_copy/x_copy/y_copy 均为**副本发射后
	## 决定的定值**（非实时）：x_copy/y_copy=发射时刻目标相对位移按 -rot_angle
	## 倾斜（x/y 向量反向倾斜，|xc,yc|==|x,y|）；表达式内自行配 t/t_copy 做变化。
	## 常量在 _ctx_keys 收集时一次写入（见 setup 尾 _stamp_copy_consts）
		## 【回调 20261025d】d 维持冻结快照（gettarget 家族语义）——作者新数据在分母用
		## gettarget(d)（如 0.8*gettarget(x)/gettarget(d)），d 活值会在接近目标时令该项
		## 爆炸（"起始数据严重偏大"的来源）。洋葱的加速由 speed 表达式承载（+0.01t）
	for k in _ctx_keys:
		## 【22b 终修】静态键（快照/stamp 常量）每帧跳过——已由 _fill/stamp 写入
		if _static_keys.has(k):
			continue
		match k:
			"t":
				_ctx["t"] = t_event + t ## 弹幕事件已存续时间（作者 20261019 语义）
			"t_copy":
				_ctx["t_copy"] = t ## 副本自身存活帧（发射后从0增长；"决定"指基准非实时目标）
			"t_r":
				_ctx["t_r"] = clampf(t / maxf(alarm_now, 1.0), 0.0, 1.0)
			"rate_roll":
				_ctx["rate_roll"] = rate_roll ## 运行时返回变量（只读；发射骰结果）
			"pattern_roll":
				_ctx["pattern_roll"] = pattern_roll ## 运行时返回变量（只读；规律累加值）
			"rotate_id":
				_ctx["rotate_id"] = float(rotate_id) ## 运行时返回变量（只读；旋转副本标号）
			_:
				## 【getChata 20261020】_chq_f_N/_chq_e_N：按阵营角色求值定位器，
				## 多命中随机取一，返回所选角色的参数值（计数器参数直接阵营计数）
				if k.begins_with("_chq_"):
					_ctx[k] = _eval_chata_query(k)
					continue
				## 【get 系 20261020】态势变量 <map><ring><stat>（如 ht1daver/ht2dvectsum）：
				## 平均值=环值均值；矢量和=Σ值×单位方向/16。ht 实数；其它图占位 0
				## （逐图环采样待 Hcs/Hct 表现批）。命名偏离文档"1d_ht_aver"——
				## 表达式标识符不能以数字开头，已列报告。
				if k.ends_with("aver") or k.ends_with("vectsum"):
					var ring: String = "1d"
					var rest: String = k.substr(0, k.length() - 4)
					if rest.ends_with("2d"):
						ring = "2d"; rest = rest.substr(0, rest.length() - 2)
					elif rest.ends_with("5d"):
						ring = "5d"; rest = rest.substr(0, rest.length() - 2)
					elif rest.ends_with("1d"):
						ring = "1d"; rest = rest.substr(0, rest.length() - 2)
					var mv := 0.0
					if rest.begins_with("hcs"):
						mv = -1.0
					elif rest.begins_with("hct"):
						mv = -2.0
					_ctx[k] = _sit_var(mv, ring, k.ends_with("vectsum"))
			"r0":
				_ctx["r0"] = rand_seed0
			"r1":
				_ctx["r1"] = rand_seed1
			"wpcs":
				_ctx["wpcs"] = ctx_wpcs
			"to_c":
				_ctx["to_c"] = ctx_to_c
			"main_lr":
				_ctx["main_lr"] = ctx_main_lr
			"sub_lr":
				_ctx["sub_lr"] = ctx_sub_lr
			"target_x", "target_y", "self_x", "self_y", "d", "target_dm_apfrepul", "target_dm_situate", "target_dm_smn", "target_dm_sms":
				pass ## 由 _fill_position_vars 统一快照回填（d 随 target 同刻）
			"alarm_shader_alpha":
				_ctx["alarm_shader_alpha"] = asa_now
			"laser_render_scale":
				_ctx["laser_render_scale"] = lrs_now
			_:
				pass
	_fill_position_vars()
	return _ctx

## 【getChata 20261020】单条查询求值：定位器在阵营角色上逐个求值（以该角色为
## self 上下文；未定义变量/执行失败→该角色不命中），多命中随机取一。
## 参数：计数器=阵营计数；状态参数=所选角色的值；player/fieldid/random系=0（占位）。
func _eval_chata_query(key: String) -> float:
	var q = null
	for qq in ev.chata_queries:
		if qq["token"] == key:
			q = qq
			break
	if q == null or source == null or _world == null:
		return 0.0
	var camp_side: int = source.side if q["camp"] != "e" else 1 - source.side ## r=己方范围
	var par: String = q["param"]
	## 计数器参数：阵营击破数
	if par == "privates_collapse" or par == "chara_collapes":
		var cc: Dictionary = _world.bullet_collapse_counts()
		if q["camp"] == "f":
			return float(cc.get("friendly_privates_collapse" if par == "privates_collapse" else "friendly_chara_collapes", 0.0))
		return float(cc.get("enemy_privates_collapse" if par == "privates_collapse" else "enemy_chara_collapes", 0.0))
	## 定位器求值（懒编译，缓存于查询表）
	var ex_loc: DanmakuExpr = q.get("_ex_loc")
	if ex_loc == null and q["locator"] != "":
		ex_loc = DanmakuExpr.new()
		if not ex_loc.compile(q["locator"], ["ap", "pp", "normal", "x", "y",
				"hpweapon", "hpbody", "hpmove", "kp", "sp"]):
			ex_loc = null
		q["_ex_loc"] = ex_loc
	## 候选角色（阵营侧非杂兵存活角色；发射者所在方 f=己方）
	var candidates: Array = _world.bullet_camp_chars(camp_side)
	## 【批复 20261020】定位器=数字 → 场地方位id 选择（两队各自 0~4）
	var hits: Array = []
	var loc_is_num: bool = q["locator"].is_valid_int()
	for c in candidates:
		if c == null or c.dead:
			continue
		if loc_is_num:
			if int(c.get_meta("field_id", -1)) == int(q["locator"]):
				hits.append(c)
			continue
		if ex_loc == null:
			hits.append(c)
			continue
		var lctx := {
			"ap": float(c.ap), "pp": float(c.pp), "normal": float(c.normal_speed()),
			"x": c.position.x, "y": c.position.y,
			"hpweapon": float(c.hp[0]), "hpbody": float(c.hp[1]), "hpmove": float(c.hp[2]),
			"kp": float(c.pp) / float(c.PP_CAP), "sp": float(c.spell_cards),
		}
		if ex_loc.eval_prop(lctx, 0.0) > 0.5:
			hits.append(c)
	if hits.is_empty():
		return 0.0
	## 【批复 20261020】多命中"全部选取"→状态参数取平均值（数值域聚合，已列报告）
	if not loc_is_num:
		## 命题定位器：全部选取
		pass
	if par == "fieldid":
		## randomChara(定位器)：返回随机一个命中角色的场地方位id（实体引用）
		var sel2: BattleEntity = hits.pick_random()
		return float(sel2.get_meta("field_id", -1))
	var acc := 0.0
	var n := 0
	for sel in hits:
		acc += _char_param_value(sel, par)
		n += 1
	return acc / maxf(1.0, float(n))

## getChata 参数取值（所选角色状态）
func _char_param_value(sel: BattleEntity, par: String) -> float:
	match par:
		"ap": return float(sel.ap)
		"pp": return float(sel.pp)
		"normal": return float(sel.normal_speed())
		"x": return sel.position.x
		"y": return sel.position.y
		"hpweapon": return float(sel.hp[0])
		"hpbody": return float(sel.hp[1])
		"hpmove": return float(sel.hp[2])
		"kp": return float(sel.pp) / float(sel.PP_CAP)
		"sp": return float(sel.spell_cards)
	return 0.0 ## player/fieldid/randomChara——实体引用（方位id）经 getChataFriendly(数字,参数) 取

## 态势十六点变量：map∈{ht,hv,hd,hr,hcs,hct,he,hp}；ring∈{1d,2d,5d}
func _sit_var(map_v: float, ring: String, vect: bool) -> float:
	if source == null:
		return 0.0
	## 【Hcs/Hct 20261020】实数接入（49点=三环48+中心；环切片同 ht）
	if map_v != 0.0:
		var src_arr: PackedFloat32Array = source.hcs_pts if map_v < 0.0 else source.hct_pts
		if src_arr.size() < 49:
			return 0.0
		var off := 0 if ring == "1d" else (16 if ring == "2d" else 32)
		if not vect:
			var sm := 0.0
			for kk in 16:
				sm += src_arr[off + kk]
			return sm / 16.0
		var vx2 := 0.0
		var vy2 := 0.0
		for kk2 in 16:
			var a3 := -PI / 2.0 + TAU * float(kk2) / 16.0
			vx2 += src_arr[off + kk2] * cos(a3)
			vy2 += src_arr[off + kk2] * sin(a3)
		return Vector2(vx2, vy2).length() / 16.0
	var arr: PackedInt32Array = source.sit16_1d if ring == "1d" else (
		source.sit16_2d if ring == "2d" else source.sit16_5d)
	if arr.size() != 16:
		return 0.0
	if not vect:
		var sum := 0
		for v in arr:
			sum += v
		return sum / 16.0
	var vx := 0.0
	var vy := 0.0
	for kk in 16:
		var a := -PI / 2.0 + TAU * float(kk) / 16.0
		vx += float(arr[kk]) * cos(a)
		vy += float(arr[kk]) * sin(a)
	return Vector2(vx, vy).length() / 16.0

## 战场每帧调用：将全局公共字段写入 shared_ctx（所有弹幕共用同一引用）
func sync_shared(new_shared: Dictionary) -> void:
	shared_ctx = new_shared

## 全量上下文（无共享时的回退路径——bench/诊断用）
func _build_ctx_full() -> Dictionary:
	var ctx := {}
	if _world != null:
		ctx["field_t"] = _world.bullet_time_frames()
		ctx["field_phase"] = _world.bullet_phase()
	if source != null:
		ctx["self_x"] = source.position.x
		ctx["self_y"] = source.position.y
		ctx["self_ap"] = source.ap
		ctx["self_pp"] = source.pp
		ctx["self_normal"] = source.normal_speed()
	return ctx

## 外部位置变量（target_*/self_*）按需惰性回填：
## target_x/y=最近敌相对弹幕起点（is_abs_coord=绝对，照抄编辑器文档）；
## self_x/y=发射者坐标（绝对）。每帧由 update() 先 erase 再回填，保证随动。
func _fill_position_vars() -> void:
	## 【20261003·定值语义】出现瞬间快照一次；此后不再实时读取角色/战场。
	## （旧"每帧随动"写法是弹幕横飞与性能损耗的根源，作者批复取消。）
	if _snapshot_done:
		return
	_snapshot_done = true
	if _needs_target_vars or _needs_xy_copy:
		_target_refresh_cd -= 1
		if _target_cached == null or _target_cached.dead or _target_refresh_cd <= 0:
			## 【整扇共享目标 20261025g（作者实测 bug）】旋转展开时传入共享目标——
			## 否则各副本各自最近敌（选到不同私兵）→ tx/ty 各异 → 整扇不汇聚
			if _shared_target != null:
				_target_cached = _shared_target
				_target_refresh_cd = 30
			else:
				_target_cached = _world.bullet_nearest_enemy(side, origin) if _world != null else null
				_target_refresh_cd = 30
		if _target_cached == null:
			## 【NA 兜底（作者批复 2026-10-03）】无实体目标时走 _pos：
			## 试炼场/浮窗预览=光标假想敌（作者批复 20261019：光标模拟被瞄准的
			## 敌方角色）；对战无目标=发射点前方 100px（朝本侧正向直飞）
			var facing := Vector2.RIGHT if side == 0 else Vector2.LEFT
			var vp: Vector2 = origin + facing * 100.0
			if _world != null and _world.has_method("bullet_nearest_enemy_pos"):
				vp = _world.bullet_nearest_enemy_pos(side, origin)
			if ev.is_abs_coord:
				_ctx["target_x"] = vp.x
				_ctx["target_y"] = vp.y
			else:
				_ctx["target_x"] = vp.x - origin.x
				_ctx["target_y"] = vp.y - origin.y
			if _needs_d:
				_ctx["d"] = maxf(1.0, origin.distance_to(vp))
		if _shared_txy != Vector2.INF:
			## 【整扇共享快照 20261025g】target_x/y=入口发射时刻的公共基准——
			## 各副本不再各自相对自己的 origin（否则扇内目标点各异=散架）
			_ctx["target_x"] = _shared_txy.x
			_ctx["target_y"] = _shared_txy.y
			## 【22b 修复 20261028】此分支此前不写 d——旋转扇副本（20261025g 引入
			## 共享路径的全部副本）d 键缺失→表达式除0→w=inf→每帧 normalized/
			## rotated 走浮点异常慢路径（实测 78µs vs 0.083µs，940 倍）＝节律性
			## 卡顿元凶。与 elif 分支同口径补齐。
			if _needs_d:
				_ctx["d"] = maxf(1.0, sqrt(_shared_txy.x * _shared_txy.x + _shared_txy.y * _shared_txy.y))
		elif _target_cached != null:
			var tp: Vector2 = _target_cached.position
			if ev.is_abs_coord:
				_ctx["target_x"] = tp.x
				_ctx["target_y"] = tp.y
			else:
				_ctx["target_x"] = tp.x - origin.x
				_ctx["target_y"] = tp.y - origin.y
			## 【20261003】d = 目标对弹幕起点的距离（target_x/y 向量模长，取定值）
			if _needs_d:
				_ctx["d"] = sqrt(_ctx["target_x"] * _ctx["target_x"] + _ctx["target_y"] * _ctx["target_y"])
			## 【get 系补全 20261025b】target_dm_*（目标态势结果快照）
			if "target_dm_apfrepul" in _ctx_keys:
				_ctx["target_dm_apfrepul"] = float(_target_cached.get_meta("map_force", Vector2.ZERO).length() / 4096.0)
			if "target_dm_situate" in _ctx_keys:
				_ctx["target_dm_situate"] = float(_target_cached.get_meta("sit_mean", 0))
			if "target_dm_smn" in _ctx_keys and _target_cached.sit_cards != null:
				_ctx["target_dm_smn"] = float(_target_cached.sit_cards.Smn)
			if "target_dm_sms" in _ctx_keys and _target_cached.sit_cards != null:
				_ctx["target_dm_sms"] = float(_target_cached.sit_cards.Sms)
			## 【get 系补全 20261024】target_kp/sp（快照口径）
			if "target_kp" in _ctx_keys:
				_ctx["target_kp"] = clampf(float(_target_cached.pp) / float(_target_cached.PP_CAP), 0.0, 1.0)
			if "target_sp" in _ctx_keys:
				_ctx["target_sp"] = float(_target_cached.spell_cards)
		## 【语义终版 20261025g】x_copy/y_copy=发射时刻目标相对位移按 -rot_angle
		## 倾斜的副本常量；_xy_t0 仅留作调参/诊断记录
	if _needs_self_vars and source != null:
		_ctx["self_x"] = source.position.x
		_ctx["self_y"] = source.position.y

func _resolve_target() -> BattleEntity:
	if ev.targe == "enemy":
		return _world.bullet_nearest_enemy(side, origin)
	if ev.targe == "self":
		return source
	return null

func target_pos() -> Vector2:
	if target != null and not target.dead:
		return target.position + Vector2(ev.targe_offsetx, ev.targe_offsety)
	return Vector2(ev.targe_offsetx, ev.targe_offsety)

func _eval(e: DanmakuExpr, fallback: float, ctx: Dictionary = {}) -> float:
	if e == null:
		return fallback
	if ctx.is_empty():
		ctx = _build_ctx()
	return e.execute_dict(ctx, fallback)

## 【A4】线性拟合：f(t)=a+b·t；探测 4 点共线才启用（含常量与快照变量）
## 快照变量在 ctx 中恒定 → 对 t 求值即为整条弹幕生命周期内的真实值
func _fit_linear(e: DanmakuExpr, ctx: Dictionary) -> Array:
	if e == null or not (e.uses_variable("t") or e.uses_variable("t_r")):
		return []
	var vals: Array = []
	for tv in [0.0, 1.0, 2.0, 3.0]:
		ctx["t"] = tv
		ctx["t_r"] = clampf(tv / maxf(alarm_now, 1.0), 0.0, 1.0)
		vals.append(e.execute_dict(ctx, 0.0))
	var b0: float = vals[1] - vals[0]
	var b1: float = vals[2] - vals[1]
	var b2: float = vals[3] - vals[2]
	if absf(b0 - b1) < 0.0001 and absf(b1 - b2) < 0.0001:
		return [vals[0], b0]
	return []

## 闭包求值：可用则 a+b·t，否则走 Expression
func _eval_lin(cl: Array, e: DanmakuExpr, ctx: Dictionary, fallback: float) -> float:
	if cl.size() == 2:
		return cl[0] + cl[1] * t
	return _eval(e, fallback, ctx)

## 表达式组是否引用变量 v（setup 一次性判定用）
static func _exprs_use(exprs: Array, v: String) -> bool:
	for e in exprs:
		if e != null and (e as DanmakuExpr).uses_variable(v):
			return true
	return false

## 【N4 修复】颜色缓存：分频求值改变 hue/sat 时失效重算（每弹每帧 3 次 from_hsv → 最多 6 帧 1 次）
var _col_cache := Color(-1.0, 0.0, 0.0, 0.0) ## r<0 = 无效
var _col_cache_hue := 0.0
var _col_cache_sat := 0.0
func modulate_color() -> Color:
	if _col_cache.r >= 0.0 and is_equal_approx(_col_cache_hue, hue_val) and is_equal_approx(_col_cache_sat, sat_val):
		return _col_cache
	_col_cache = Color.from_hsv(fposmod(hue_val, 1.0), clampf(sat_val, 0.0, 1.0), lightness_val)
	_col_cache_hue = hue_val
	_col_cache_sat = sat_val
	return _col_cache

func current_alpha_01() -> float:
	var a := alpha_now / 256.0
	if ev.tag == DanmakuEventData.TAG_LASER and t <= alarm_now:
		a *= asa_now / 256.0 ## 预警期不透明度（0~256 整数量纲——20261019 迁移）
	return clampf(a, 0.0, 1.0)

func draw_rotation() -> float:
	match ev.tag:
		DanmakuEventData.TAG_NODES, DanmakuEventData.TAG_PHYSICAL:
			return velocity.angle() if velocity != Vector2.ZERO else heading
		DanmakuEventData.TAG_REGULAR, DanmakuEventData.TAG_FUNCTED:
			return dir.angle()
		_:
			return 0.0
