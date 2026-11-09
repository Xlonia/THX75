extends Node2D
## =============================================================
## battle_arena —— 第①期重写（GPU DDM + 哈希被弹 + 队伍战 + MultiMesh）
## 【性能架构（批复#14 核心修正）】
##   0 期 CPU 逐弹像素印章/包围盒擦除/master重建 → 已全部移除。
##   现架构：
##     ① 弹幕 update（运动学，常量折叠表达式）
##     ② BulletHash 重建（每弹 O(1) 入格）→ 被弹解析（圆碰撞，矢量精确）
##     ③ DdmGpu.render（印章 → compute shader 弹幕图；AI/调试/预览用）
##     ④ MultiMesh 批量渲染弹幕（数千发 1 draw call/材质）
## 【队伍战（demo 目标）】每侧 5~6 角色 + 5×5 杂兵（privates.csv）
##   杂兵：相对角色坐标 + 目标点系绳 + 0.3/0.35秒距引力（PrivateFormation）
## 【被弹解析（哈希版，语义=DDM上升沿）】
##   每实体查 fields[side]（=可击中该方的弹幕）→ 与上一帧键集比对 →
##   上升沿键按伤害降序 → 最高伤害优先结算 → 0.5s 免疫
## =============================================================

const LOGICAL := 400
const HUD_RESERVE := 110
const MAX_BULLETS := 6000 ## 性能护栏（超出移除最旧）

var SCALE := 2.0
var time_frames := 0
var phase := 1
## 时间尺度地基（批复 2026-10-01#8）：月之怀表/须臾枝/时之魔珠类道具要求
## "被作用侧的速度、行进、AI、态势、已释放弹幕整体同步缩放"。
## ②期准备先统一挂在 敌方 移动+火控上；弹幕逐侧 dt 缩放随道具系统实装。
##   月之怀表=敌方×0并禁发；须臾枝=敌方×0.5；时之魔珠=双方×0.5（策划原文）。
var enemy_time_scale := 1.0:
	set(v):
		enemy_time_scale = 0.25 if GameGlobals.ai_slow_debug else v ## 【v0.0.8】慢速调试地基
var bullets: Array = []
var entities: Array = []
var fire_controls: Array = []
var formations: Array = []
## 【批复 2026-10-05】P点/符卡掉落拾取物（材质 pp.PNG/spell.PNG；30秒消失、我方12px拾取）
var drops: Array = []             ## {pos, kind:"pp"/"spell", amount, frames, tex}
var _drop_tex: Dictionary = {}    ## 材质缓存      ## Array[PrivateFormation]
var finished := false
var is_preview := false

## 弹幕图（GPU 可用则启用；双方各一份——键=可击中该方的弹幕集合）
## 【20261002】RD 用主渲染设备（Texture2DRD 零拷贝显示的前提；Forward+），
## 本地 RD 仅作无主设备时的回退；DdmGpu/HeatmapField 共享同一 RD。
var shared_rd: RenderingDevice = null
var ddm_gpu0: DdmGpu = null
var ddm_gpu1: DdmGpu = null
var gpu_ok := false
## 【每侧一张战场热力图（作者批复 2026-10-02）】ht_side[0] 加热 fields[0]
## （能击中我方的弹幕），ht_side[1] 加热 fields[1]；实体态势十六点采样本侧图。
## 我方法弹对本侧热力图天然为 0（"覆写为0"语义）；敌 AI 读对侧图（③期）。
var ht_side: Array = []
var hv_side: Array = []           ## ③期：Hv 速度热点图（每侧一张；升降沿彩虹）
var fam_maps: FamilyMaps = null   ## ③期收官：He/Hd/Hr/Hp 期望系（GPU 轨迹管线）
var bullet_hash := BulletHash.new()
var _stamp_buf0 := PackedFloat32Array()
var _stamp_buf1 := PackedFloat32Array()
var _sample_entities: Array = []  ## 本拍参与十六点采样的实体（与采样点顺序对应）
var _heat_print_acc := 0.0        ## 性能检测控制台周期打印
var _expired_count := 0          ## 航程到期消失计数（调试：区分"原地消失"来源）
var _cleared_count := 0          ## 释放消弹计数
var _heat_view := 0
var _hcs_horizon := 60.0 ## Hcs 查阅目标时间（帧；[ ] 键 10~60 步进）
func _refresh_hcs_view() -> void:
	var ent := picked_entity()
	if ent != null and ent.kind != BattleEntity.Kind.PRIVATE:
		_compute_hcs_hct(ent) ## 以当前视界即时重算选中角色               ## F1：0关 1=Ht 2=Hv（批复：按策划图族顺序切换）
var _show_sit16 := false          ## 十六点圆点调试层（F1 热力图模式叠加显示）
var _heat_focus: BattleEntity = null ## 【新三 20261028】热力图观察角色（F1 选取）
var _heat_view_side := 0          ## [：观察方（0我 1敌）
var _heat_frame := 0              ## ]：帧（多帧图预留）
var _show_pick := false           ## F2 角色选取高亮开关
## 【批复 2026-10-04】右上帧率显示：<59.8 标红；<20 自动暂停（继续后不再自动暂停）
var fps_label: Label = null
## 【批复 2026-10-05·完全接管（策划：Ctrl+Enter）】
var take_over := false            ## 接管状态（方向键射击操作）
var _takeover_pending := false    ## Ctrl+Enter 第一次：暂停+选框确认
var _perf_notice: Label = null
var _takeover_label: Label = null
var _fps_pause_dismissed := false
var _fps_accum := 0.0
var _fps_frames := 0
var _fps_measured := 60.0
var _lowfps_secs := 0           ## 连续低帧秒数（自动暂停去抖）
var _pick_idx := 0                ## 当前选中面板角色（两侧面板可选/可控·批复）
var _pick_side := 0

var player_side_chars: Array = []   ## Array[Dictionary] 我方角色行
var enemy_side_chars: Array = []    ## 敌方角色行（Enemy.csv 池或 Characters 池）
var player_ents: Array = []         ## Array[BattleEntity]
var enemy_ents: Array = []
var player_leader: BattleEntity = null
var enemy_leader: BattleEntity = null
var emitter_ent: BattleEntity = null
var _emitter_acc := 0.0

## 节点 ——
var world: Node2D
var entity_layer: Node2D
var bullet_layer: Node2D
var bullet_mm_layer: Node2D ## MultiMesh 粒子弹幕层（挂 HS 上色着色器）
var ddm_debug_layer: Node2D
var hud: CanvasLayer
var info_label: Label
var _heat_label: Label      ## 【20261026】左上：当前展示的热力图名
var _debug_hint_label: Label ## 【20261026】左下：调试键位说明（呼出后显示）
var _debug_used := false    ## 任意调试键按下后置位
var banner: Label
var pause_panel: PanelContainer
## 【20261003】两侧角色数据面板（作者批复：左友右敌，HP/P点/符卡）
var left_panel: VBoxContainer = null
var right_panel: VBoxContainer = null
const SIDE_PANEL_W := 200.0
## MultiMesh 批量渲染（每材质一个 MM；粒子弹幕全部 16px 材质高度共享）
var _mm: MultiMesh = null
var _mm_tex: Texture2D = null
var _mm_count := 0
## F3 调试持久 Sprite（批复 2026-10-01#6：玩家也得用，保留并扩展；
## 旧实现每10帧 queue_free+重建 Sprite——曾经存在过、为规避 Texture2DRD
## 引用刷新问题而重建，现改为持久 Sprite 换引用，重建逻辑保留在注释备查）
var _ddm_sprite: Sprite2D = null
var _ht_sprite: Sprite2D = null

func _ready() -> void:
	is_preview = (GameGlobals.arena_mode == "preview")
	var usable := float(DisplayServer.window_get_size().y) - float(HUD_RESERVE)
	SCALE = maxf(1.0, floor(usable / float(LOGICAL)))
	_init_gpu()
	_build_world()
	_build_hud()
	if is_preview:
		_setup_preview()
	else:
		_setup_versus()

func _init_gpu() -> void:
	## 【主设备路线实测放弃（2026-10-03）】Texture2DRD 零拷贝显示需要主 RD，
	## 但主 RD 上每帧 compute 提交与渲染线程互相等锁 → 实测帧率掉到个位数
	## （CPU 几乎空转=纯等锁）。按性能守则自动放弃，回退本地 RD（实测 60fps）。
	## DDM 的 compute 仍是每帧提交（60帧渲染，符合"取消0.1秒渲染DDM"批复）；
	## 差别只在 F3 调试显示走回读（10Hz，仅调试路径）。
	## 【内存泄漏修复 20261004】共享全局本地设备（旧版每次预览新建设备
	## 且从不释放 → 每次泄漏一个 Vulkan 设备的驱动堆提交，多次后 11G 死机）
	shared_rd = GameGlobals.arena_rendering_device()
	var is_main := false
	ddm_gpu0 = DdmGpu.new(shared_rd)
	ddm_gpu1 = DdmGpu.new(shared_rd)
	gpu_ok = ddm_gpu0.ok and ddm_gpu1.ok
	if gpu_ok:
		ddm_gpu0.main_device = is_main
		ddm_gpu1.main_device = is_main
		for side in 2:
			var ddm: DdmGpu = ddm_gpu0 if side == 0 else ddm_gpu1
			var ht := HeatmapField.new(shared_rd)
			ht.main_device = is_main
			ht.configure(ddm.image_rid())
			ht_side.append(ht)
			var hv := HvField.new(shared_rd, ddm.image_rid(), ddm.prev_image_rid())
			hv_side.append(hv)
			if fam_maps == null:
				fam_maps = FamilyMaps.new(shared_rd, ddm.image_rid())
	else:
		for side in 2:
			ht_side.append(HeatmapField.new(null)) ## CPU 降级
			hv_side.append(null)
	if not gpu_ok:
		push_warning("[Arena] GPU DDM 不可用（headless/兼容），弹幕图降级关闭；被弹走哈希（逻辑不受影响）")

## 会话 GPU 资源释放（场景更替时；设备本身常驻不释放）
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for h in ht_side:
			if h != null:
				h.shutdown()
		for h in hv_side:
			if h != null:
				h.shutdown()
		if fam_maps != null:
			fam_maps.shutdown()
		for d in [ddm_gpu0, ddm_gpu1]:
			if d != null:
				d.shutdown()

func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	_update_scale()
	add_child(world)
	## 窗口缩放 → 战场重适配（作者批复）；headless 手动初始化时无视口，跳过
	if is_inside_tree() and get_viewport() != null:
		get_viewport().size_changed.connect(_update_scale)
	entity_layer = _make_painter("EntityLayer", "entities")
	bullet_layer = _make_painter("BulletLayer", "bullets")
	## MultiMesh 粒子弹幕独立层，挂 HS 上色着色器（作者批复：目标色只定 H/S，
	## 亮度=纹理像素亮度，白部上色后仍白——line 绘制不能吃此材质故分层）
	bullet_mm_layer = _make_painter("BulletMM", "bulletmm")
	if OS.get_environment("TH75_NO_TINT") == "": ## [BISECT-E]
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/bullet_tint.gdshader")
		bullet_mm_layer.material = mat
	ddm_debug_layer = _make_painter("DDMDebug", "ddm")
	ddm_debug_layer.visible = false

## 战场缩放：SCALE=[[(窗口高-110)/400]]（策划渲染规格）；窗口缩放时重算并重适配
func _update_scale() -> void:
	## 【20261003】SCALE=[[(窗口高-110)/400]]（策划渲染规格），画布在
	## 顶部条带以下、两侧角色面板之间 居中（窗口可缩放，实时重适配）
	var win := Vector2(DisplayServer.window_get_size())
	var usable := win.y - float(HUD_RESERVE)
	SCALE = maxf(1.0, floor(usable / float(LOGICAL)))
	if world != null:
		world.scale = Vector2(SCALE, SCALE)
		var arena_px := float(LOGICAL) * SCALE
		var cx := SIDE_PANEL_W + (win.x - 2.0 * SIDE_PANEL_W - arena_px) * 0.5
		var cy := float(HUD_RESERVE) + (usable - arena_px) * 0.5
		world.position = Vector2(maxf(SIDE_PANEL_W, cx), maxf(0.0, cy))

func _make_painter(node_name: String, kind: String) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.set_script(load("res://scripts/versus/arena_painters.gd"))
	n.host = self
	n.draw_kind = kind
	world.add_child(n)
	return n

## 【批复】决斗场地 400×400 外全部裁剪：world 用 clip container 包装
## （Godot CanvasItem 无直接矩形裁剪 → 用 SubViewport 代价高；改由
##  各绘制函数出口钳制：实体/弹幕绘制前判断越界跳过；线段端点进界才画）

## =============================================================
## 队伍构建（demo：每侧 5 角色 + 5×5 杂兵）
## =============================================================
func _setup_versus() -> void:
	## 我方：配置的角色名列表（versus_menu 设置；默认队伍）
	var p_names: Array = GameGlobals.versus_player_team if not GameGlobals.versus_player_team.is_empty() else ["MarisaA", "ReimuA", "ReisenA", "Alice", "Nitori"]
	var e_names: Array = GameGlobals.versus_enemy_team if not GameGlobals.versus_enemy_team.is_empty() else ["Rumia", "Suika", "Aya", "Patchouli", "Yuka"]
	player_side_chars = _rows_for(p_names, false)
	enemy_side_chars = _rows_for(e_names, true)
	_spawn_side(player_side_chars, 0, true)
	_spawn_side(enemy_side_chars, 1, false)
	player_leader = player_ents[0] if not player_ents.is_empty() else null
	enemy_leader = enemy_ents[0] if not enemy_ents.is_empty() else null
	_assign_field_ids() ## 场地方位id（getChata 数字定位器用）

func _rows_for(names: Array, from_enemy_csv: bool) -> Array:
	var rows: Array = []
	for n in names:
		var row := {}
		if from_enemy_csv:
			row = CharaDB.get_enemy_by_name(n)
			if row.is_empty():
				row = CharaDB.get_by_name(n) ## 敌方池缺数据时回退角色表
		else:
			row = CharaDB.get_by_name(n)
		if not row.is_empty():
			rows.append(row)
	return rows

func _spawn_side(rows: Array, side: int, as_player_side: bool) -> void:
	var base_x := 60.0 if side == 0 else 340.0
	for i in rows.size():
		var ent := BattleEntity.new()
		var is_lead := i == 0
		ent.setup(rows[i], side, BattleEntity.Kind.MEMBER if not is_lead else BattleEntity.Kind.PLAYER, is_lead and as_player_side)
		## 【修复 20261005】开局 P 点/符卡：选人界面设置的 versus_start_pp 之前
		## 从未赋给实体（作者报告"无论设置多少开局都是 0"的根因）
		ent.pp = GameGlobals.versus_start_pp
		## 【批复 20261024/20261025d】自定义对战中每角色配置：逻辑列表（三步向导）/资源
		var ccfg: Dictionary = GameGlobals.versus_chara_cfg.get(ent.chara_name(), {})
		if not ccfg.is_empty():
			for lg in ccfg.get("logics", []):
				for f in ["stance", "stance_dist", "metric", "aim", "volley", "cruise", "appeal_boost"]:
					if lg.has(f):
						ent.ai_logic[f] = lg[f]
			if ccfg.has("stance"):
				ent.ai_logic["stance"] = ccfg["stance"] ## 旧单值配置兼容
			if ccfg.has("metric"):
				ent.ai_logic["metric"] = ccfg["metric"]
			if ccfg.has("pp"):
				ent.pp = int(ccfg["pp"])
			if ccfg.has("spell"):
				ent.spell_cards = int(ccfg["spell"])
		ent.position = Vector2(base_x, 60.0 + i * 70.0)
		world.add_child(ent)
		entities.append(ent)
		_connect_economy(ent)
		if side == 0:
			player_ents.append(ent)
		else:
			enemy_ents.append(ent)
		var fc := FireControl.new()
		fc.setup(ent)
		fc.fired.connect(_on_fire)
		if bool(ent.ai_logic.get("volley", false)):
			fc.set_mode("salvo") ## 【角色逻辑AI 20261024】齐射逻辑
		fire_controls.append(fc)
		## 每角色 5 杂兵（demo 5×5；私兵表循环取）
		var priv_rows := CharaDB.load_privates()
		if priv_rows.is_empty():
			priv_rows = [{"Name": "FairyA", "Normal": 2, "Determine": 3, "Defend": 1}] ## R4：空表防除零兜底
		for j in GameGlobals.versus_privates_per_char:
			var prow: Dictionary = priv_rows[(i * 5 + j) % priv_rows.size()]
			var priv := BattleEntity.new()
			priv.setup_private(prow, side, ent, j + 1, false)
			_register_priv_shooter(priv)
			priv.local_pos = Vector2((j - 2) * 6.0, 15.0)
			priv.sync_private_pos()
			world.add_child(priv)
			entities.append(priv)
			_connect_economy(priv)
			var fm := PrivateFormation.new()
			fm.setup(ent, priv, _chara_formation(ent), {"custom_a": 12.0, "custom_b": 6.0})
			formations.append(fm)

## =============================================================
## ②期经济（P点与符卡）事件接线（scheme《符卡与P点》照抄）
##   · 击破杂兵：+5P 归 其所归属角色；每少5杂兵 → 对方可接收角色随机+1符
##   · 结界被剥：对方可接收角色随机+3符；被剥者自身+32P（掉落接收顺序同杂兵）
##   · 满目疮痍：不奖励符卡；从其身上扣16P 掉落归同侧未满者
##   · 溢出：随机分配给本侧未满角色；全满→自机P容器未实装→就地销毁（策划）
##   · 主要符卡释放→最接近敌方+1符：释放系统实装时接线（已留 _on_main_spell）
## =============================================================
const PP_PER_PRIVATE := 5
const SPELLS_PER_5_PRIVATES := 1
const SPELLS_ON_BARRIER_BREAK := 3
const PP_ON_BARRIER_BREAK := 32
const PP_DROPPED_ON_DEATH := 16

## 【Hcs/Hct 20261020】按游戏逻辑介绍：Hcs=角色 0.5秒距内弹幕未来 1s 时空分布
## （60 帧填充均值 sqrt×16）；Hct=20fps 10 帧均值+移动方向重合 +64。
## 分析式求值（点到轨迹段覆盖时长闭式解），49 点=三环48+中心。
func _compute_hcs_hct(ent: BattleEntity) -> void:
	var n_spd := ent.normal_speed()
	var arr48: Array = []
	var spin := TAU / 32.0 * float(time_frames % 2)
	for k in 48:
		var rr2 := n_spd * (6.0 if k < 16 else (12.0 if k < 32 else 30.0))
		var a2 := spin - PI / 2.0 + TAU * float(k % 16) / 16.0
		arr48.append(ent.position + Vector2(cos(a2), sin(a2)) * rr2)
	arr48.append(ent.position) ## 第49点=中心
	var R := n_spd * 30.0 ## 0.5秒距（Hcs 感知半径）
	## 【性能 20261020】候选弹一次预筛（范围=R+轨迹长；上限48），点循环只跑候选
	var cand_pos: Array[Vector2] = []
	var cand_dir: Array[Vector2] = []
	var cand_len: Array[float] = []
	var cand_rad: Array[float] = []
	var L_max := 0.0
	for b in bullets:
		var bl: Bullet = b
		if bl.hidden_now or bl.ev.tag == DanmakuEventData.TAG_LASER:
			continue
		if bl.source_side == ent.side and not bl.ev.is_phy:
			continue ## 威胁弹幕（本侧法弹天然不算）
		var spd := bl.track_speed
		if spd <= 0.05:
			continue
		var L := minf(spd * 60.0, 400.0) ## 未来 1s 轨迹长（钳场宽）
		if bl.pos.distance_to(ent.position) > R + L:
			continue
		cand_pos.append(bl.pos)
		cand_dir.append(bl.track_dir)
		cand_len.append(L)
		cand_rad.append(bl.draw_radius)
		L_max = maxf(L_max, L)
	var hcs_out := PackedFloat32Array()
	var hct_out := PackedFloat32Array()
	hcs_out.resize(49)
	hct_out.resize(49)
	if cand_pos.is_empty():
		ent.hcs_pts = hcs_out
		ent.hct_pts = hct_out
		ent.hcs_at = 0.0
		ent.hct_at = 0.0
		return
	for pi in 49:
		var p: Vector2 = arr48[pi]
		var fill := 0.0
		for ci in cand_pos.size():
			var w: Vector2 = p - cand_pos[ci]
			var tproj := clampf(w.dot(cand_dir[ci]), 0.0, cand_len[ci])
			var d := p.distance_to(cand_pos[ci] + cand_dir[ci] * tproj)
			var rad: float = cand_rad[ci]
			if d >= rad:
				continue
			var covered: float = minf(60.0, 2.0 * sqrt(maxf(0.0, rad * rad - d * d)) / maxf(cand_len[ci] / 60.0, 0.01))
			fill += 255.0 * covered / 60.0
		var h: float = floor(sqrt(minf(fill, 255.0)) * 16.0)
		hcs_out[pi] = h
		## 【勘误 20261020】Hct=任何方向与 Hcs 弹幕重合的采样点 +64（原"当前移动
		## 方向单侧"是错的——Hct 是快速避弹功能检测图，作者批复）
		var bonus := 256.0 if h > 0.0 else 0.0 ## 【新三 20261028】覆盖赋值 64→256（作者）
		hct_out[pi] = minf(255.0, h + bonus)
	ent.hcs_pts = hcs_out
	ent.hct_pts = hct_out
	ent.hcs_at = hcs_out[48]
	ent.hct_at = hct_out[48]

## 【场地方位id 20261020（批复）】每队 0~4，按战场建立时队伍内顺序分配
## （文档：最初排列从上到下 42013 为视觉序，id 依建队顺序）
func _assign_field_ids() -> void:
	var counters := [0, 0]
	for ent in entities:
		if ent is BattleEntity and ent.kind != BattleEntity.Kind.PRIVATE:
			ent.set_meta("field_id", counters[ent.side])
			counters[ent.side] += 1

## 【角色逻辑AI 20261024】目标选择器（决斗设定-新）：比较敌方角色选取量
func _refresh_ai_target(ent: BattleEntity) -> void:
	var best: BattleEntity = null
	var best_v := -INF
	var metric := String(ent.ai_logic.get("metric", "hp_max"))
	for o in entities:
		if not (o is BattleEntity) or o.dead or o.side == ent.side 				or o.kind == BattleEntity.Kind.PRIVATE or o == emitter_ent:
			continue
		var v := 0.0
		match metric:
			"hp_max": v = float(o.hp[0] + o.hp[1] + o.hp[2])
			"ap_max": v = float(o.ap)
			"hp_any_low": v = -float(o.hp[0] + o.hp[1] + o.hp[2]) ## 围剿近似=总HP低者优先
			"ap_ratio_low": v = -float(o.ap) ## 挫其锐气近似
			"dist_min": v = -ent.position.distance_squared_to(o.position)
			"dist_max": v = ent.position.distance_squared_to(o.position)
			_: v = float(o.hp[0] + o.hp[1] + o.hp[2])
		if v > best_v:
			best_v = v
			best = o
	ent.ai_target = best

func _show_hcs_view() -> bool:
	return _heat_view == 7 or _heat_view == 8

## 【get 系计数 20261020】各阵营累计击破的杂兵/角色数（下标=击方阵营）
var _camp_priv_collapse := [0, 0]
var _camp_chara_collapse := [0, 0]
var _priv_losses := [0, 0] ## 各侧累计杂兵损失

func arena_entities_n() -> int:
	return entities.size() + drops.size() + _rot_pend.size() + _cannons.size() + _priv_shooters.size()

func _connect_economy(ent: BattleEntity) -> void:
	ent.ret = RetSystem.new(ent) ## 【v0.0.8】RET 基底挂载
	ent.ret.world = self ## 分身八点弹幕碰撞查询用
	ent.destroyed.connect(_on_entity_destroyed)
	ent.barrier_shattered.connect(_on_barrier_shattered)
	ent.damaged.connect(_on_entity_hit_immune) ## 【方案A 20261020】被弹连坐免疫

## 【批复 20261020·方案A（存在感提升，性能优选）】杂兵被弹 → 同队其余杂兵
## 与所属角色 0.2s 免疫；角色被弹 → 本体+所属杂兵 0.5s 免疫（角色本体 30 帧
## 免疫 take_hit 已有）。选 A 弃 B 的理由：A 是命中事件 O(队友数) 的计时器
## 赋值，零遍历；B 每次被弹都要扫弹幕清单并批量销毁（渲染/DDM 批连带波动）。
func _on_entity_hit_immune(ent: BattleEntity) -> void:
	if ent.kind == BattleEntity.Kind.PRIVATE:
		var owner_ent: BattleEntity = ent.owner_ent
		for e in entities:
			if e is BattleEntity and not e.dead:
				if e == owner_ent:
					e.immune_frames = maxi(e.immune_frames, 12) ## 0.2s
				elif e.kind == BattleEntity.Kind.PRIVATE and e.owner_ent == owner_ent and e != ent:
					e.immune_frames = maxi(e.immune_frames, 12)
	else:
		for e in entities:
			if e is BattleEntity and not e.dead and e.kind == BattleEntity.Kind.PRIVATE 					and e.owner_ent == ent:
				e.immune_frames = maxi(e.immune_frames, 30) ## 0.5s

func _on_entity_destroyed(ent: BattleEntity) -> void:
	var side := ent.side
	## 【get 系计数 20261020】"该阵营累计击败"=击破对方实体数（击方=1-ent.side）
	if ent.kind == BattleEntity.Kind.PRIVATE:
		_camp_priv_collapse[1 - side] += 1
	else:
		_camp_chara_collapse[1 - side] += 1
	if ent.kind == BattleEntity.Kind.PRIVATE:
		_priv_losses[side] += 1
		## 【批复 2026-10-13·增援】队伍每减少 10 个杂兵 → 该队所有角色就地补充一次
		if _priv_losses[side] % 10 == 0:
			_reinforce_side(side)
		## 【批复 2026-10-05】P点散落战场：击破杂兵原地掉 5P 拾取物
		_spawn_drop(ent.position, "pp", PP_PER_PRIVATE)
		if _priv_losses[side] % 5 == 0:
			_spawn_drop(ent.position, "spell", 0) ## 每少5杂兵 → 掉符卡拾取物
	else:
		## 满目疮痍：16P 散落
		var drop: int = mini(PP_DROPPED_ON_DEATH, ent.pp)
		ent.pp -= drop
		if drop > 0:
			_spawn_drop(ent.position, "pp", drop)

## 生成掉落拾取物（材质 pp/spell）
## 【批复 2026-10-13】散落：随机方向 1px/帧 初速，模长每帧 -0.05，20 帧后静止
func _spawn_drop(pos: Vector2, kind: String, amount: int) -> void:
	if _drop_tex.is_empty():
		_drop_tex["pp"] = load("res://gameAssetBase/shooting/resource/pp.PNG")
		_drop_tex["spell"] = load("res://gameAssetBase/shooting/resource/spell.PNG")
	var dir := Vector2.RIGHT.rotated(randf() * TAU)
	drops.append({
		"pos": pos,
		"vel": dir * 1.0,           ## 初速 1px/帧
		"kind": kind, "amount": amount, "frames": 1800, ## 30秒消失
		"tex": _drop_tex.get(kind),
	})

## 【早苗技能（策划；批复：神由态势卡自动选）】
## 攻击态势→神奈子：御柱 10*50 以 8px/帧 冲向最近敌角色，每帧 -0.08，伤害 [[(v/v0)*8]]
## 防御/中性→诹访子：把早苗带到全局弹幕热力图最低点
func _sanae_skill() -> void:
	var sanae: BattleEntity = null
	for e in player_ents:
		if e is BattleEntity and e.chara_name() == "Sanae" and not e.dead:
			sanae = e
			break
	if sanae == null:
		return ## 场上无早苗
	if sanae.current_sit_card == "a" and enemy_leader != null:
		## 神奈子：御柱弹（用 demo_missile 类弹模拟；伤害按剩余速度比）
		var ev := GameGlobals.get_event("demo_missile")
		if ev != null:
			var b := Bullet.new()
			b.setup(ev, sanae.position, 0, sanae, self, 0, {})
			b.set_meta("onbashira", true)
			bullets.append(b)
	else:
		## 诹访子：移动到 Ht 最低点（48 采样点中最低者）
		var best := Vector2.ZERO
		var best_v := 99999
		var n := sanae.normal_speed()
		for k in 16:
			var a := -PI / 2.0 + TAU * float(k) / 16.0
			var p2 := sanae.position + Vector2(cos(a), sin(a)) * n * 30.0
			var v := int(_sample_ht_at(p2))
			if v < best_v:
				best_v = v
				best = p2
		sanae.position = best.clamp(Vector2.ZERO, Vector2(400, 400))

## 采样 Ht 单点（走 HeatmapField 的 GPU/CPU 路径）
func _sample_ht_at(pos: Vector2) -> int:
	if ht_side.is_empty() or ht_side[0] == null:
		return 0
	return ht_side[0].sample(PackedVector2Array([pos]))[0]

## 【批复 2026-10-13·投降结算】敌方同意 → 全员停攻+全改防御卡 1 秒后结算
func _surrender_accepted() -> void:
	surrender_phase = true
	surrender_frames = 60
## 【轮换（批复 2026-10-13）】角色在边界（画布边缘 20px 内）时长按 A 原地对换：
## 选中角色与队伍下一名存活角色互换“角色数据行+位置”——杂兵继承角色ID随 owner 走
func _swap_selected_character() -> void:
	var sel := picked_entity()
	if sel == null or sel.side != 0:
		return
	var near_edge := sel.position.x < 20.0 or sel.position.x > 380.0 		or sel.position.y < 20.0 or sel.position.y > 380.0
	if not near_edge:
		return
	var chars: Array = []
	for e in player_ents:
		if e is BattleEntity and e.kind != BattleEntity.Kind.PRIVATE and not e.dead and e != sel:
			chars.append(e)
	if chars.is_empty():
		return
	var other: BattleEntity = chars[_pick_idx % chars.size()]
	var tmp_db: Dictionary = sel.db
	var tmp_pos: Vector2 = sel.position
	sel.db = other.db
	sel.position = other.position
	other.db = tmp_db
	other.position = tmp_pos
	print("[轮换] ", sel.chara_name(), " ↔ ", other.chara_name())

## 就地增援单名杂兵（从角色位置出现；批复：就地从角色位置出现）
## 【杂兵弹幕 20261020（批复）】杂兵无火力点、弹幕从自身发射：
## privates.csv 的 shoot_evs 列表 + ShootCd（0.1秒）自身发射冷却。
## 每 0.1s 拍推进；事件级 cannon/旋转重复/repeat 语义全部复用 _spawn_event_copies。
var _priv_shooters: Dictionary = {} ## priv -> {events: Array, cd: float(帧), t: float}

func _register_priv_shooter(priv: BattleEntity) -> void:
	var evs: Array = []
	for nm in String(priv.db.get("shoot_evs", "")).split(";", false):
		var ev := _find_event(nm.strip_edges())
		if ev != null:
			ev.compile()
			evs.append(ev)
	if evs.is_empty():
		return
	_priv_shooters[priv] = {"events": evs,
		"cd": maxf(1.0, float(priv.db.get("ShootCd", 30))) * 6.0, "t": 0.0}

func _priv_shooters_tick() -> void:
	for priv in _priv_shooters.keys():
		if not is_instance_valid(priv) or priv.dead:
			_priv_shooters.erase(priv)
			continue
		var st: Dictionary = _priv_shooters[priv]
		st["t"] = float(st["t"]) + 1.0
		if float(st["t"]) >= float(st["cd"]):
			st["t"] = 0.0
			for ev: DanmakuEventData in st["events"]:
				_spawn_event_copies(ev, priv.position, priv, null, {}, 0)

## 【批复 20261024】角色排布预设（自定义对战配置；默认线列防护）
func _chara_formation(ent: BattleEntity) -> String:
	var f := str(GameGlobals.versus_chara_cfg.get(ent.chara_name(), {}).get("formation", "线列防护"))
	return f if PrivateFormation.PRESETS.has(f) else "线列防护"

func _spawn_private_for(ent: BattleEntity) -> void:
	var cnt := 0
	for e in entities:
		if e is BattleEntity and e.kind == BattleEntity.Kind.PRIVATE and e.owner_ent == ent and not e.dead:
			cnt += 1
	if cnt >= GameGlobals.versus_privates_per_char:
		return
	var priv_rows := CharaDB.load_privates()
	if priv_rows.is_empty():
		return
	var priv := BattleEntity.new()
	priv.setup_private(priv_rows[cnt % priv_rows.size()], ent.side, ent, cnt + 1, false)
	_register_priv_shooter(priv)
	priv.local_pos = Vector2.ZERO
	priv.sync_private_pos()
	world.add_child(priv)
	entities.append(priv)
	_connect_economy(priv)
	var fm := PrivateFormation.new()
	fm.setup(ent, priv, _chara_formation(ent), {"custom_a": 12.0, "custom_b": 6.0})
	formations.append(fm)

## 团队增援（R，批复：补充至上限）：每角色就地补满全部杂兵
func _reinforce_all() -> void:
	for ent: BattleEntity in player_ents:
		if not ent.dead:
			while _private_count(ent) < GameGlobals.versus_privates_per_char:
				_spawn_private_for(ent)

func _private_count(ent: BattleEntity) -> int:
	var cnt := 0
	for e in entities:
		if e is BattleEntity and e.kind == BattleEntity.Kind.PRIVATE and e.owner_ent == ent and not e.dead:
			cnt += 1
	return cnt

## 每 10 杂兵损失：全队就地增援一次（批复：补至上限）
func _reinforce_side(side: int) -> void:
	var ents: Array = player_ents if side == 0 else enemy_ents
	for ent: BattleEntity in ents:
		if not ent.dead:
			while _private_count(ent) < GameGlobals.versus_privates_per_char:
				_spawn_private_for(ent)

## 拾取结算（每帧）：最近我方角色 12px 内自动拾取
func _update_drops() -> void:
	var i := drops.size() - 1
	while i >= 0:
		var d: Dictionary = drops[i]
		d["frames"] -= 1
		## 散落物理：v 每帧 -0.05 直至 0（20 帧）
		var v: Vector2 = d["vel"]
		if v != Vector2.ZERO:
			var sp := maxf(v.length() - 0.05, 0.0)
			d["pos"] += v.normalized() * minf(v.length(), sp + 0.05) ## 先按当前速位移
			d["vel"] = v.normalized() * sp
		## 【批复 2026-10-14】双方可拾 + 吸附：40px 内吸向最近角色，<10px 收集
		var nearest: BattleEntity = null
		var nd := 1e9
		for e in entities:
			if e is BattleEntity and e.kind != BattleEntity.Kind.PRIVATE and not e.dead:
				var dist: float = e.position.distance_to(d["pos"])
				if dist < nd:
					nd = dist
					nearest = e
		var picked := false
		if nearest != null and nd < 40.0:
			var pull: Vector2 = (nearest.position - d["pos"]).normalized()
			d["pos"] += pull * maxf(2.0, 12.0 - nd * 0.2)
			if nd < 10.0:
				if d["kind"] == "pp":
					_redistribute_pp(nearest, d["amount"])
				else:
					if nearest.can_receive_spell():
						nearest.receive_spell()
					else:
						_grant_spell_ordered(nearest.side, 1)
				picked = true
		if picked or d["frames"] <= 0:
			drops.remove_at(i)
		i -= 1

## 按队伍顺序给最缺符卡的角色发符（位置序=策划"接收顺序"）
func _grant_spell_ordered(side: int, n_cards: int) -> void:
	var pool: Array = []
	var ents: Array = player_ents if side == 0 else enemy_ents
	for e in ents:
		if e is BattleEntity and e.kind != BattleEntity.Kind.PRIVATE and e.can_receive_spell():
			pool.append(e)
	for k in n_cards:
		if pool.is_empty():
			return
		pool.sort_custom(func(a, b): return a.spell_received < b.spell_received)
		(pool[0] as BattleEntity).receive_spell()

func _on_barrier_shattered(ent: BattleEntity) -> void:
	for i in SPELLS_ON_BARRIER_BREAK:
		_grant_spell_random(1 - ent.side) ## 对方可接收角色+3符
	if not ent.dead:
		_redistribute_pp(ent, PP_ON_BARRIER_BREAK) ## 被剥者+32P（同杂兵接收顺序）

## 加P（溢出随机再分配给同侧未满者；全满→就地销毁，策划原文）
func _redistribute_pp(target: BattleEntity, amount: int) -> void:
	var overflow := target.add_pp(amount)
	while overflow > 0:
		var pool := _side_pp_hungry(target.side)
		if pool.is_empty():
			return ## P点容器（物品）未实装——就地销毁
		var recv: BattleEntity = pool.pick_random()
		overflow = recv.add_pp(overflow)

func _side_pp_hungry(side: int) -> Array:
	var out: Array = []
	for e in entities:
		if e is BattleEntity and e.side == side and not e.dead and e.pp < BattleEntity.PP_CAP:
			out.append(e)
	return out

## 对方可接收符卡角色随机其一 +1符（全满则无事发生——"溢出部分作为物品存储"未实装）
func _grant_spell_random(side: int) -> void:
	var pool: Array = []
	for e in entities:
		if e is BattleEntity and e.side == side and e.can_receive_spell():
			pool.append(e)
	if not pool.is_empty():
		(pool.pick_random() as BattleEntity).receive_spell()

## 主要符卡释放钩子（符卡释放系统实装时调用）：最接近的敌方角色+1符
func _on_main_spell_released(caster: BattleEntity) -> void:
	var near := bullet_nearest_enemy_from(caster.side, caster.position)
	if near != null and near.can_receive_spell():
		near.receive_spell()

## 试炼场发射器：每 0.5s 从顶部随机 x 发射当前编辑事件
func _preview_emitter(delta: float) -> void:
	_emitter_acc += delta
	if _emitter_acc >= 0.5:
		_emitter_acc = 0.0
		var ev := _find_event(GameGlobals.preview_event_name)
		if ev != null and emitter_ent != null:
			emitter_ent.position = Vector2(40.0 + randf() * 320.0, 20.0)
			## 【修复 20261019】试炼场预览同样走旋转重复展开（原直接 _spawn_bullet
			## 绕过扇形——预览仅单弹的根因）；光标=假想目标
			_spawn_event_copies(ev, emitter_ent.position, emitter_ent, null, {}, 0)

## 【批复 20261024】试炼场预览控制：方向键移动玩家角色（测试重复/追弹稳定性）；
## P 键=玩家侧发射当前事件（瞄准 emitter——"让自己瞄准一个弹幕发射源"）；
## 敌方发射的弹幕本就以玩家为最近敌（"将自己作为弹幕目标"）
func _preview_controls() -> void:
	if player_leader == null or player_leader.dead:
		return
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_physical_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_physical_key_pressed(KEY_DOWN): dir.y += 1
	if dir != Vector2.ZERO:
		player_leader.position = (player_leader.position + dir.normalized() * player_leader.normal_speed()).clamp(Vector2.ZERO, Vector2(400, 400))
	if Input.is_physical_key_pressed(KEY_P) and time_frames % 12 == 0:
		var ev2 := _find_event(GameGlobals.preview_event_name)
		if ev2 != null and emitter_ent != null:
			## 玩家侧发射：瞄准 emitter（最近敌=emitter——"让自己瞄准弹幕发射源"）
			_spawn_event_copies(ev2, player_leader.position, player_leader, null, {}, 0)

func _setup_preview() -> void:
	var row := CharaDB.get_by_name("MarisaA")
	var ent := BattleEntity.new()
	ent.setup(row, 0, BattleEntity.Kind.PLAYER, true)
	ent.position = Vector2(200, 340)
	world.add_child(ent)
	entities.append(ent)
	player_leader = ent
	ent.pp = 100
	var erow := CharaDB.get_by_name("ReimuA")
	emitter_ent = BattleEntity.new()
	emitter_ent.setup(erow, 1, BattleEntity.Kind.ENEMY)
	emitter_ent.position = Vector2(200, 20)
	world.add_child(emitter_ent)
	entities.append(emitter_ent)

func _on_fire(point, ev: DanmakuEventData, rolls: Dictionary = {}) -> void:
	## 【类型批复 20261019】发射时刻统一求值：x/y_offset 算式、repeat 参数算式
	## （上下文与弹幕出现同语义；t=事件出现至今、t_copy=0）
	var src: BattleEntity = src_position_of(point)
	var rctx := _rot_eval_ctx(src, point)
	var sp: Dictionary = ev.eval_spawn_params(rctx)
	var origin := _fire_origin(point, ev, src, sp)
	if ev.is_cannon:
		## 【火炮（弹幕编辑器-新 20261015）】火炮类事件不自主发射——登记为炮节点，
		## 按 repeat_time 间隔×repeat_freq 次生成 repeat 禁用的弹幕粒子
		if _cannons.size() < 64:
			var rpt: Dictionary = ev.eval_repeat_params(rctx)
			_cannons.append({"ev": ev, "point": point, "src": src, "rolls": rolls.duplicate(),
				"rpt": rpt, "sp": sp, "timer": 0, "fired": 0})
		return
	_spawn_event_copies(ev, origin, src, point, rolls, 0, rctx, sp, 0.0)

## 火力点归属实体（null 安全）
func src_position_of(point) -> BattleEntity:
	if point != null and point.entity != null:
		return point.entity
	return point_source(point)

## 发射原点（含算式化的 x/y_offset；_on_fire 与火炮/延时/repeat 整扇副本共用；point 可空）
func _fire_origin(point, ev: DanmakuEventData, src: BattleEntity, sp: Dictionary = {}) -> Vector2:
	if ev.is_abs_coord:
		return Vector2(float(sp.get("xoff", ev.x_offset)), float(sp.get("yoff", ev.y_offset)))
	var base: Vector2 = src.position if src != null else Vector2.ZERO
	var poff: Vector2 = point.offset if point != null else Vector2.ZERO
	return base + poff + Vector2(float(sp.get("xoff", ev.x_offset)), float(sp.get("yoff", ev.y_offset)))

## =============================================================
## 【通用弹幕旋转重复】按事件旋转设定展开副本：
##   释放时刻求值 rotate 参数（20261019 表达式化）→ 步序（时序方式）展开；
##   rotate_delay>0 的后续步走 _rot_pend（从火力点实时位置出发），
##   并以首发副本反解"扇形基向"锚定——首弹不随外界时序偏转（作者批复 20261019）；
##   repeat 的重复=整扇再重放（与旋转重复相乘、语义独立）。gen>0 副本不再繁殖。
## =============================================================
var _rot_pend: Array = [] ## {ev, point, src, rolls, ang, rid, frames, gen, carrier, pinned}
var _cannons: Array = []  ## 火炮节点 {ev, point, src, rolls, timer, fired}

## 释放时刻的求值上下文（field/火力点/自身/目标快照——与弹幕出现同语义；
## t=事件出现至今（repeat 重放时非 0），t_copy=0（作者 20261019 语义））
func _rot_eval_ctx(src: BattleEntity, point, event_t: float = 0.0) -> Dictionary:
	var origin: Vector2 = src.position if src != null else Vector2.ZERO
	var c := {"field_t": float(time_frames), "field_phase": float(phase),
		"t": event_t, "t_copy": 0.0, "t_r": 0.0,
		"rate_roll": 0.0, "pattern_roll": 0.0, "rotate_id": 0.0,
		"r0": 0.0, "r1": 0.0, "n": 0.0,
		## 【get 系 20261020】阵营击破计数（实数）+ 态势变量占位（0；按角色回填）
		"friendly_privates_collapse": 0.0, "friendly_chara_collapes": 0.0,
		"enemy_privates_collapse": 0.0, "enemy_chara_collapes": 0.0,
		"field_privates_collapse": 0.0, "field_chara_collapes": 0.0,
		"self_x": origin.x, "self_y": origin.y}
	if point != null and point.ctx != null:
		for k in ["wpcs", "to_c", "main_lr", "sub_lr"]:
			c[k] = float(point.ctx.get(k, 0))
	for k2 in bullet_collapse_counts():
		c[k2] = float(bullet_collapse_counts()[k2])
	if src != null:
		c["self_ap"] = float(src.ap)
		c["self_pp"] = float(src.pp)
		c["self_normal"] = float(src.normal_speed())
		var tp := bullet_nearest_enemy_pos(src.side, origin)
		if tp != origin:
			c["target_x"] = tp.x - origin.x
			c["target_y"] = tp.y - origin.y
			c["d"] = tp.distance_to(origin)
	return c

func _spawn_event_copies(ev: DanmakuEventData, origin: Vector2, src: BattleEntity, point, rolls: Dictionary, gen: int,
		rctx: Dictionary = {}, sp: Dictionary = {}, event_t: float = 0.0, shared_target: BattleEntity = null,
		shared_txy: Vector2 = Vector2.INF) -> void:
	## 【整扇共享目标 20261025g】入口解算一次（副本发射后决定），全扇共用——
	## 否则各副本各自最近敌（选到敌方不同私兵）→ target_x/y 各异 → 整扇散架
	if shared_target == null and src != null:
		shared_target = bullet_nearest_enemy_from(src.side, origin)
	var _txy := Vector2.INF
	if shared_txy == Vector2.INF and shared_target != null:
		## 入口发射时刻的公共目标相对快照（整扇同一基准——作者批复语义）
		_txy = shared_target.position - origin if not ev.is_abs_coord else shared_target.position
		shared_txy = _txy
	if rctx.is_empty():
		rctx = _rot_eval_ctx(src, point, event_t)
	if sp.is_empty():
		sp = ev.eval_spawn_params(rctx)
	var rp: Dictionary = ev.eval_rotate_params(rctx)
	var plan: Array = DanmakuEventData.rotate_release_plan(rp)
	if plan.is_empty():
		return
	var positions: PackedFloat32Array = DanmakuEventData.rotate_positions(rp)
	var delay_step: int = int(rp.get("delay", 0))
	var carrier_left: bool = gen == 0 ## 同一代仅首副本携带 repeat 节拍（防 N 倍繁殖）
	var anchor_base := Vector2.ZERO ## 首发副本反解的扇形基向（延时副本锚定用）
	for si in plan.size():
		var step: Array = plan[si]
		for pair in step:
			var k: int = int(pair[0])
			var rid: int = int(pair[1])
			var ang: float = (positions[k] if k < positions.size() else 0.0) + float(rp.get("offset", 0.0))
			var pin: Vector2 = anchor_base if (ev.tag == DanmakuEventData.TAG_REGULAR and anchor_base != Vector2.ZERO) else Vector2.ZERO
			if delay_step <= 0 or si == 0:
				var b := _spawn_rotated_copy(ev, origin, src, point, ang, rid, rolls, gen, carrier_left, pin,
					event_t, shared_target, shared_txy)
				if si == 0 and b != null and ev.tag == DanmakuEventData.TAG_REGULAR and anchor_base == Vector2.ZERO:
					anchor_base = b.dir.rotated(-ang) ## 反解：副本实际方向 = 基向.rotated(本副本角)
				carrier_left = false
			elif _rot_pend.size() < 512:
				_rot_pend.append({"ev": ev, "point": point, "src": src,
					"rolls": rolls.duplicate(), "ang": ang, "rid": rid,
					"frames": si * delay_step, "gen": gen,
					"carrier": false, ## 【爆炸根因 20261027】原 carrier_left——mid_sync 首步
					## 多副本时第 2/3 pair 的 pend 仍带 true → 释放副本携带节拍 → 繁殖
					"pinned": pin, "sp": sp, "et": event_t + float(si * delay_step),
					"shared": shared_target, "stxy": shared_txy})
				carrier_left = false

func _spawn_rotated_copy(ev: DanmakuEventData, origin: Vector2, src: BattleEntity, point,
		ang: float, rid: int, rolls: Dictionary, gen: int, carrier: bool, pinned: Vector2 = Vector2.ZERO,
		event_t := 0.0, shared_target: BattleEntity = null, shared_txy: Vector2 = Vector2.INF) -> Bullet:
	var b := _spawn_bullet(ev, origin, gen, src, point, ang, rid, rolls, pinned, event_t, shared_target, shared_txy)
	if b == null:
		return null
	if not carrier:
		b.repeat_enabled = false
	return b

func _rot_pending_tick() -> void:
	for i in range(_rot_pend.size() - 1, -1, -1):
		var pr: Dictionary = _rot_pend[i]
		pr["frames"] = int(pr["frames"]) - 1
		if int(pr["frames"]) <= 0:
			var ev: DanmakuEventData = pr["ev"]
			_spawn_rotated_copy(ev, _fire_origin(pr["point"], ev, pr["src"], pr.get("sp", {})),
				pr["src"], pr["point"], pr["ang"], pr["rid"], pr["rolls"], pr["gen"], pr["carrier"],
				pr.get("pinned", Vector2.ZERO), float(pr.get("et", 0.0)), pr.get("shared", null),
				pr.get("stxy", Vector2.INF))
			_rot_pend.remove_at(i)

## 火炮节点：按 repeat_time 间隔生成 repeat 禁用的弹幕粒子（repeat_freq 拍后自毁）
## 【类型批复 20261019】repeat 参数允许算式——登记时求值
func _cannon_tick() -> void:
	for i in range(_cannons.size() - 1, -1, -1):
		var c: Dictionary = _cannons[i]
		var ev: DanmakuEventData = c["ev"]
		c["timer"] = int(c["timer"]) + 1
		var rpt: Dictionary = c.get("rpt", {})
		var beats: int = int(rpt.get("freq", 0)) if int(rpt.get("freq", 0)) > 0 else 1
		var interval: int = maxi(1, int(rpt.get("time", ev.repeat_time)))
		var guard := 0
		while int(c["fired"]) < beats and int(c["timer"]) >= int(c["fired"]) * interval and guard < 8:
			var origin := _fire_origin(c["point"], ev, c["src"], c.get("sp", {}))
			_spawn_event_copies(ev, origin, c["src"], c["point"], c["rolls"], 1)
			c["fired"] = int(c["fired"]) + 1
			guard += 1
		if int(c["fired"]) >= beats:
			_cannons.remove_at(i)

func point_source(point) -> BattleEntity:
	for fc in fire_controls:
		if fc.entity == null:
			continue
		for p in fc.weapon_points + fc.sub_points:
			if p == point:
				return fc.entity
	return player_leader

## =============================================================
## 主循环
## =============================================================
func _physics_process(delta: float) -> void:
	if pause_panel != null and pause_panel.visible:
		return
	var dt := delta * 60.0
	time_frames += 1
	if not finished:
		_player_input()
		_ai_sides()
		if is_preview:
			_preview_emitter(delta)
			_preview_controls() ## 【批复 20261024】预览可控：方向键移动玩家
	if surrender_phase:
		surrender_frames -= 1
		if surrender_frames <= 0:
			_finish("投降成立 —— 走决斗结果结算")
			return
	if cmd_frames > 0:
		cmd_frames -= 1
	_entity_ticks(dt)
	if not finished:
		_sit_tick(delta)
	if not surrender_phase:
		_fire_ticks(delta)
		_cannon_tick() ## 【20261015】火炮节点按 repeat 时序生成弹幕粒子
		_priv_shooters_tick() ## 【20261020】杂兵自身发射（ShootCd+shoot_evs）
		_rot_pending_tick() ## 【20261015】旋转重复延时副本释放
	else:
		for ent: BattleEntity in entities:
			if ent is BattleEntity and not ent.dead:
				ent.current_sit_card = "d"
	_bullet_updates(dt)
	## 【性能 2026-10-14】被弹判定与拾取结算降 30Hz（每 2 物理帧）——
	## 被弹已有 0.5s 免疫兜底、拾取无帧级敏感性；physics 33ms→~18ms 预期
	if time_frames % 2 == 1:
		_resolve_hits()
		_update_drops()
	_update_phase()
	_check_end()
	_refresh_hud()
	## 【性能休整·嫌疑3】GPU DDM 移至 _process（渲染线程），不阻塞物理线程
	## _render_ddm() 改在 _process 中调用

func _process(delta: float) -> void:
	## 【22b 20261028】上一拍 fam batch_read 提前到 _process 开头：
	## read 的 buffer_get_data 是 GPU-CPU fence 同步——在 physics 线程里
	## 调用会拖住物理（窗口化实测 110ms 的主源）。挪到渲染帧头=GPU 已
	## 提交完上一拍，fence≈0。数据本就是上一拍的（RET 用旧一拍无害）
	_consume_pending_samples()
	_render_ddm() ## GPU 弹幕图提交（渲染线程，异步不阻塞 physics）
	_heatmap_tick()
	## 真实帧率测量（每秒窗口；页面暂停时不更新）
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum >= 1.0:
		_fps_measured = float(_fps_frames) / _fps_accum
		_fps_accum = 0.0
		_fps_frames = 0 ## ②期准备：Ht 步进+态势十六点带转采样（10Hz，同拍）

## =============================================================
## ②期：热力图 Ht（每侧一张威胁图）+ 态势十六点（带转）采样（10Hz = 每6物理帧）
## 【DDM 与显示均 60帧（作者批复 2026-10-02）】_render_ddm 每帧提交，
##   F3 显示走主设备 Texture2DRD 零拷贝；10Hz 的只有 Ht 步进与采样（像素遍历图频率）。
## 【带转】偶数帧采样从最上端开始；奇数帧整体偏 1/32 圈（11.25°）。
## 【性能检测】HeatmapField 内置 μs 滑动平均；HUD(F3) 与控制台周期输出。
## =============================================================
func _heatmap_tick() -> void:
	var any_ok: bool = not ht_side.is_empty() and ht_side[0] != null and (ht_side[0].ok or not gpu_ok)
	if ht_side.is_empty() or ht_side[0] == null:
		return
	## 【22b 20261028e】热力全拍 10Hz→5Hz（%6→%12）：采样帧 GPU 提交簇
	## （ht.step×2+Hv×2+8 图 advance+48000 预测点上传）是驱动队列背压源——
	## 实测采样帧 proc 段 56ms vs 普通帧 3.9ms（6000 弹堆栈）。AI 读热力本就
	## 延迟一拍（0.1s 旧），改 0.2s 旧；DDM/显示仍 60 帧不变。
	if time_frames % 12 != 0:
		return
	for side in 2:
		var ht: HeatmapField = ht_side[side]
		if ht == null:
			continue
		if not ht.ok:
			ht.step_cpu(bullets) ## headless 降级
		else:
			ht.step() ## 读当帧本侧 DDM（同 RD 队列 FIFO，晚于 _render_ddm 提交）
		var hv = hv_side[side] if side < hv_side.size() else null
		if hv != null and hv.ok:
			hv.step() ## Ht 之后（cur 已渲染、prev 为上帧）

	## 【P1 修复 20261015】8 图 advance 合并为一次 GPU 提交（原 16 次/拍）
	if fam_maps != null and fam_maps.ok:
		var fam_pts := {} ## "He0".."Hp1" -> 点列（x,y 交错）
		for b in bullets:
			var bl: Bullet = b
			if bl.hidden_now or bl.ev.tag == DanmakuEventData.TAG_LASER:
				continue
			var spd := bl.track_speed
			var dirv := bl.track_dir
			if spd <= 0.1 or dirv == Vector2.ZERO:
				continue
			var horizon: float = minf(bl.range_now, 60.0) / 60.0 ## ≤1s
			var threat: int = 1 - bl.source_side ## 该弹威胁的侧
			var key_he := "He" + str(threat)
			var pts_he: PackedFloat32Array = fam_pts.get(key_he, PackedFloat32Array())
			var key_hr := "Hr" + str(threat)
			var pts_hr: PackedFloat32Array = fam_pts.get(key_hr, PackedFloat32Array())
			for k in 4: ## 【22b 20261028e】预测点 8→4（50×50 图上 8 点本就过密；GPU 提交量减半）
				var ft := (float(k) + 1.0) / 4.0 * horizon * 60.0
				var fp := bl.pos + dirv * spd * ft
				pts_he.append(fp.x); pts_he.append(fp.y)
				if spd >= 4.0:
					pts_hr.append(fp.x); pts_hr.append(fp.y)
			fam_pts[key_he] = pts_he
			fam_pts[key_hr] = pts_hr
			fam_pts["Hp" + str(threat)] = pts_he ## 规律图同步积累（同数据两图各自上传，免拷贝）
		var jobs := []
		for mp in ["He0", "He1", "Hr0", "Hr1", "Hp0", "Hp1", "Hd0", "Hd1"]:
			jobs.append([fam_maps.NAMES.find(mp), fam_pts.get(mp, PackedFloat32Array())])
		fam_maps.advance_batch(jobs)
	## —— 采样点收集：存活角色实体，各采"本侧威胁图"（1d/2d/5d 三圈16点 + 自身中心=49点/实体）——
	## 【P1 修复 20261015】第49点=实体位置：_sit_tick 的 Ht/Hd 位置值改从本批读出
	## 写入 ht_at/hd_at meta（原先 _sit_tick 每实体每帧做 1+8 次 GPU 同步回读）
	_sample_entities.clear()
	var pts := PackedVector2Array()
	## 带转偏移：偶数帧 0，奇数帧 1/32 圈
	var spin := TAU / 32.0 * float(time_frames % 2)
	for ent: BattleEntity in entities:
		if ent == emitter_ent or ent.dead:
			continue
		if ent.kind == BattleEntity.Kind.PRIVATE:
			continue ## 杂兵仅采样总结期望/所属角色图（③期）；现阶段跳过
		_sample_entities.append(ent)
		var n := ent.normal_speed()
		var r1 := n * 6.0   ## 0.1秒距
		var r2 := n * 12.0  ## 0.2秒距
		var r3 := n * 30.0  ## 0.5秒距（RET-C 第三圈；策划 48 采样=16×3）
		for k in 16:
			var a := spin - PI / 2.0 + TAU * float(k) / 16.0 ## 从最上端开始
			var dv := Vector2(cos(a), sin(a))
			pts.append(ent.position + dv * r1)
			pts.append(ent.position + dv * r2)
			pts.append(ent.position + dv * r3)
	if pts.is_empty():
		return
	## 【P1 修复 20261015·延迟一拍消费】先读上一拍已 dispatch 的采样结果——
	## 此时 GPU 队列已空闲，同步回读≈亚毫秒；原实现当拍回读，fence 要等完
	## 本拍全部提交（Ht/Hv 步进+族图印章+DDM）≈6ms。0.1s 旧数据符合策划态势语义。
	_consume_pending_samples()
	## 各侧实体分别采各自威胁图：Ht 逐侧 dispatch；fam 四图并批一次提交
	var fam_sides := []
	for side in 2:
		var side_pts := PackedVector2Array()
		var side_ents: Array = []
		for i in _sample_entities.size():
			var ent: BattleEntity = _sample_entities[i]
			if ent.side != side:
				continue
			side_ents.append(ent)
			for k in 48: ## 【N1 修复】追加点数=拷贝点数（1d/2d/5d 三圈）
				side_pts.append(pts[i * 48 + k])
			side_pts.append(ent.position) ## 第49点=自身中心
		if side_pts.is_empty():
			continue
		var ht: HeatmapField = ht_side[side]
		if ht.ok:
			if not skip_gpu_submit:
				ht.sample_dispatch(side_pts)
			_ht_pending[side] = side_ents
			## 【Hcs/Hct 20261020】逐实体 0.2s 交错计算（性能红线：同拍全量太重）
			for ei2 in side_ents.size():
				var e4: BattleEntity = side_ents[ei2]
				if (time_frames / 6 + ei2) % 2 == 0:
					_compute_hcs_hct(e4)
		else:
			_apply_ht_vals(ht.sample(side_pts), side_ents) ## CPU 降级立即生效
		fam_sides.append({
			"pts": side_pts,
			"maps": ["He%d" % side, "Hd%d" % side, "Hr%d" % side, "Hp%d" % side],
			"side": side, "ents": side_ents,
		})
	## 【③期收官·多图加权】【P2 修复】只采本侧 4 图并批一次提交（原 sample_multi 无条件回读 8 图）
	if fam_maps != null and fam_maps.ok and not fam_sides.is_empty():
		if not skip_gpu_submit:
			fam_maps.batch_dispatch(fam_sides)
		_fam_pending = fam_sides

static var skip_gpu_submit := false ## 【A/B 临时】采样帧 GPU 提交开关

## —— 采样延迟一拍（P1 修复 20261015）：本拍 dispatch，下一拍开头回读消费 ——
var _ht_pending := {}  ## side -> side_ents
var _fam_pending := [] ## fam_sides
## 【新三 20261028·边界虚拟热】采样点距边<25px:+96 / <10px:+160 / 出界:+256
## （外框弹幕进来的"墙角热"——防钻角落；叠加在 GPU 采样值之上，钳 255）
func _edge_heat(pos: Vector2) -> int:
	var m := minf(minf(pos.x, 400.0 - pos.x), minf(pos.y, 400.0 - pos.y))
	if m < 0.0:
		return 256
	if m < 10.0:
		return 160
	if m < 25.0:
		return 96
	return 0

func _apply_ht_vals(vals: PackedInt32Array, side_ents: Array) -> void:
	var vi := 0
	for ent in side_ents:
		if not is_instance_valid(ent):
			vi += 49
			continue
		var arr := PackedInt32Array()
		arr.resize(48)
		for k in 48:
			arr[k] = vals[vi] if vi < vals.size() else 0
			vi += 1
		## 边界虚拟热叠加（新三：外框弹幕进界热——三环逐点按位置加成）
		for k2 in 48:
			var ring_n: float = ent.normal_speed() * (6.0 if k2 < 16 else (12.0 if k2 < 32 else 30.0))
			var ang2 := -PI / 2.0 + TAU * float(k2 % 16) / 16.0
			var sp2: Vector2 = ent.position + Vector2(cos(ang2), sin(ang2)) * ring_n
			var eh := _edge_heat(sp2)
			if eh > 0:
				arr[k2] = mini(arr[k2] + eh, 255)
		ent.sit16_1d = arr.slice(0, 16)
		ent.sit16_2d = arr.slice(16, 32)
		ent.sit16_5d = arr.slice(32, 48)
		ent.set_meta("ht_at", vals[vi] if vi < vals.size() else 0)
		vi += 1

func _consume_pending_samples() -> void:
	for side in _ht_pending:
		var ht: HeatmapField = ht_side[side]
		if ht != null and ht.ok:
			_apply_ht_vals(ht.sample_read(), _ht_pending[side])
	_ht_pending.clear()
	if _fam_pending.is_empty():
		return
	var spin2 := TAU / 32.0 * float(time_frames % 2)
	var multi: Dictionary = fam_maps.batch_read()
	for sd in _fam_pending:
		var sfx: String = str(sd["side"])
		var side_ents: Array = sd["ents"]
		## 图数组提到循环外（原每 k 每实体 4 次字符串拼接+字典查找）
		var a_he: PackedInt32Array = multi.get("He" + sfx, PackedInt32Array())
		var a_hd: PackedInt32Array = multi.get("Hd" + sfx, PackedInt32Array())
		var a_hr: PackedInt32Array = multi.get("Hr" + sfx, PackedInt32Array())
		var a_hp: PackedInt32Array = multi.get("Hp" + sfx, PackedInt32Array())
		for ei in side_ents.size():
			var e2: BattleEntity = side_ents[ei]
			if not is_instance_valid(e2):
				continue
			var f := Vector2.ZERO
			## 【权重表 20261021（新二）】dm_apfrepul：Ht1 Hd3 Hcs5 Hct10 He2 Hp3（分母24）；
			## 攻击态势(a/c) Hcs/Hct 权重 0；中性(r/n/s) Hct 0；Shs-1d 攻击时 0
			var card := e2.current_sit_card
			var w_hcs := 5.0 if card in ["d", "h", "e"] else 0.0
			var w_hct := 10.0 if card in ["d", "h", "e"] else 0.0
			for k in 48:
				var a2 := spin2 - PI / 2.0 + TAU * float(k % 16) / 16.0
				var dv2 := Vector2(cos(a2), sin(a2))
				var rr := 6.0 if k < 16 else (12.0 if k < 32 else 30.0)
				var idx := ei * 49 + k ## 步长49（48环点+1中心）
				var v_he: int = a_he[idx] if idx < a_he.size() else 0
				var v_hd: int = a_hd[idx] if idx < a_hd.size() else 0
				var v_hp: int = a_hp[idx] if idx < a_hp.size() else 0
				## Ht 权重=同向十六点；Shs 权重（新二）：攻击态势 Shs-1d=0、Shs-2d=1
				var ring_arr: PackedInt32Array = e2.sit16_1d if k < 16 else (e2.sit16_2d if k < 32 else e2.sit16_5d)
				var v_ht: int = ring_arr[k % 16] if (k % 16) < ring_arr.size() else 0
				var shs_w := 1.0
				if card == "a" or card == "c":
					shs_w = 0.0 if k < 16 else 1.0
				var v_hcs: float = e2.hcs_pts[idx] if idx < e2.hcs_pts.size() else 0.0
				var v_hct: float = e2.hct_pts[idx] if idx < e2.hct_pts.size() else 0.0
				var hot := (float(v_ht) / 255.0) * 1.0 * shs_w + (float(v_hd) / 255.0) * 3.0 					+ (v_hcs / 255.0) * w_hcs + (v_hct / 255.0) * w_hct 					+ (float(v_he) / 255.0) * 2.0 + (float(v_hp) / 255.0) * 3.0
				f -= dv2 * (hot / 24.0) * (rr / maxf(e2.normal_speed() * 30.0, 1.0))
			e2.set_meta("map_force", f.limit_length(1.0))
			var ci := ei * 49 + 48
			e2.set_meta("hd_at", a_hd[ci] if ci < a_hd.size() else 0)
	_fam_pending = []
	## —— 态势十六点性能检测：控制台周期输出（作者批复要求）——
	_heat_print_acc += 0.1
	if _heat_print_acc >= 10.0:
		_heat_print_acc = 0.0
		var avg_txt := "无采样"
		if player_leader != null and player_leader.sit16_1d.size() == 16:
			var s := 0
			for v in player_leader.sit16_1d:
				s += v
			avg_txt = "领队1d均值=%d" % (s / 16)
		var ht0: HeatmapField = ht_side[0]
		var fam_txt := ""
		if fam_maps != null and fam_maps.ok:
			fam_txt = " | 族图adv=%.2fms 批采样=%.2fms" % [fam_maps.adv_us / 1000.0, fam_maps.samp_batch_us / 1000.0]
		print("[Heatmap] %s | 弹幕=%d | %s%s" % [ht0.stats_line(), bullets.size(), avg_txt, fam_txt])

## 【批复 2026-10-05·键位修正】WASD 不再移动任何角色——它们是团队姿态键
## （双击W=进攻姿态 / 双击S=保守 / 双击A或D=侧面，各持续5秒，策划原文）。
## 移动只在"完全接管"（Ctrl+Enter 进入，东方正作射击操作）下用方向键。
func _player_input() -> void:
	_update_double_tap()
	## ——完全接管（东方正作射击操作；策划）——
	if take_over and player_leader != null and not player_leader.dead:
		var dir := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_LEFT): dir.x -= 1
		if Input.is_physical_key_pressed(KEY_RIGHT): dir.x += 1
		if Input.is_physical_key_pressed(KEY_UP): dir.y -= 1
		if Input.is_physical_key_pressed(KEY_DOWN): dir.y += 1
		player_leader.cruise_active = not Input.is_physical_key_pressed(KEY_SHIFT) ## 默认快机 Shift慢机
		if dir != Vector2.ZERO:
			player_leader.position += dir.normalized() * (player_leader.cruise_speed() if player_leader.cruise_active else player_leader.normal_speed())
			player_leader.position = player_leader.position.clamp(Vector2.ZERO, Vector2(400, 400))
## ——双击检测（0.4s 窗口；策划）——
var _dt_last: Dictionary = {} ## key -> 上次按下 time_frames
var team_stance := ""         ## "" / "attack" / "defend" / "side"
var team_stance_frames := 0   ## 5秒到期自动解除
var _combo_frames := 0        ## Q+W / Q+S 组合按住计帧
var auto_reinforce := false   ## T 自动增援开关
var surrender_sent := false   ## Shift+S 投降请求（不会过期；Shift+W 撤销）
var surrender_phase := false  ## 投降同意：1 秒停攻倒计时
var surrender_frames := 0
func _update_double_tap() -> void:
	if team_stance != "":
		team_stance_frames -= 1
		if team_stance_frames <= 0:
			team_stance = ""
	## 组合指令：Q+W=冒进 Q+S=龟缩（按住半秒=30帧）
	var qw := Input.is_physical_key_pressed(KEY_Q) and Input.is_physical_key_pressed(KEY_W)
	var qs := Input.is_physical_key_pressed(KEY_Q) and Input.is_physical_key_pressed(KEY_S)
	if qw or qs:
		if _combo_frames < 30:
			_combo_frames += 1
			if _combo_frames == 30:
				team_stance = "rash" if qw else "turtle"
				team_stance_frames = 300
	else:
		_combo_frames = 0
	for key in [KEY_W, KEY_S, KEY_A, KEY_D]:
		if Input.is_physical_key_pressed(key):
			if not _dt_last.has(key):
				if _dt_last.get(str(key) + "armed", false) and time_frames - int(_dt_last.get(key, -999)) < 24:
					match key:
						KEY_W: team_stance = "attack"
						KEY_S: team_stance = "defend"
						KEY_A, KEY_D: team_stance = "side"
					team_stance_frames = 300
					_dt_last[str(key) + "armed"] = false
				else:
					_dt_last[key] = time_frames
					_dt_last[str(key) + "armed"] = true
		else:
			_dt_last[str(key) + "armed"] = false

func _ai_sides() -> void:
	## 【③期·双方同套 AI（作者批复：友方也加 AI，自走棋）】
	## 每个非自机角色（敌我两方）共用同一套：十六点 APF 斥力 + RET-C 冷点 +
	## 态势加权交战锚定 + RET 滞回。自机（领队）不进 AI——机控接管（策划）。
	var enemy_target: BattleEntity = player_leader
	var player_target: BattleEntity = enemy_leader
	for ent: BattleEntity in enemy_ents:
		if ent.dead or ent.kind == BattleEntity.Kind.PRIVATE or ent == emitter_ent:
			continue
		_ai_drive(ent, enemy_target, enemy_time_scale)
	## 【批复 2026-10-05】自机也是 AI 自动控制（自走棋）——接管时才由玩家操作
	if not take_over and player_target != null:
		if player_leader != null and not player_leader.dead:
			_ai_drive(player_leader, player_target, 1.0)
	for ent: BattleEntity in player_ents:
		if ent == player_leader or ent.dead or ent.kind == BattleEntity.Kind.PRIVATE or ent == emitter_ent:
			continue
		_ai_drive(ent, player_target, 1.0)

## 单实体 AI 驱动（双方共用；target=本方的攻击目标领队）
func _ai_drive(ent: BattleEntity, target: BattleEntity, time_scale: float) -> void:
	if target == null or target.dead:
		return
	var push := Vector2.ZERO
	var spin := TAU / 32.0 * float(time_frames % 2)
	var n_speed := ent.normal_speed()
	for k in 16:
		var a := spin - PI / 2.0 + TAU * float(k) / 16.0
		var dv := Vector2(cos(a), sin(a))
		var h1: int = ent.sit16_1d[k] if k < ent.sit16_1d.size() else 0
		var h2: int = ent.sit16_2d[k] if k < ent.sit16_2d.size() else 0
		var hot := maxf((h1 - 96.0) / 160.0, 0.0) + maxf((h2 - 96.0) / 160.0, 0.0) * 0.5
		push -= dv * hot * 1.6 ## APF 热点斥力（Ht 权重 1）
		## 【修复：右下角停靠】冷点引力仅对"画布内"方向生效——
		## 采样点出界的方向 h2=0 恒冷，旧行为把角色持续推向界外角落
		var probe2: Vector2 = ent.position + dv * n_speed * 12.0
		var in_field2 := probe2.x > 8.0 and probe2.x < 392.0 and probe2.y > 8.0 and probe2.y < 392.0
		if in_field2:
			push += dv * maxf((160.0 - float(h2)) / 160.0, 0.0) * 0.5 ## RET-C 冷点引力
	## 【角色逻辑AI·第二级（决斗设定-新 20261024）】第一级合力之上的小力：
	## 方位逻辑按选择器目标施加（系数与理由见 BattleEntity.ai_logic 注释）
	if time_frames % 30 == 0:
		_refresh_ai_target(ent) ## 0.5s 刷新选择器
	var ai_t: BattleEntity = ent.ai_target
	if ai_t != null and not ai_t.dead:
		var to_t2: Vector2 = ai_t.position - ent.position
		var dd := to_t2.length()
		var dir_t := to_t2 / dd if dd > 0.01 else Vector2.ZERO
		match String(ent.ai_logic.get("stance", "standoff")):
			"approach":
				push += dir_t * 0.45
			"standoff":
				var want_d: float = float(ent.ai_logic.get("stance_dist", 180.0))
				if want_d <= 0.01:
					push -= dir_t * 0.80 ## 对峙距0=回避
				elif dd < want_d * 0.8:
					push -= dir_t * 0.60 ## 过近：斥（>引，防被反近身）
				elif dd > want_d * 1.2:
					push += dir_t * 0.35 ## 过远：引
			"none":
				push += (Vector2(200, 200) - ent.position).normalized() * 0.15
	## 【绝对躲避层（新二 20261021）】敌方角色 0.25秒距圆热度强制 255——
	## 最高优先级防撞；直接斥力不进权重平均
	for o2 in entities:
		if o2 is BattleEntity and o2 != ent and not o2.dead and o2.side != ent.side 				and o2.kind != BattleEntity.Kind.PRIVATE:
			var away2: Vector2 = ent.position - o2.position
			var dl2 := away2.length()
			var rr2 := ent.normal_speed() * 60.0 * 0.25
			if dl2 > 0.01 and dl2 < rr2:
				push += away2 / dl2 * (1.0 - dl2 / rr2 * 0.5)
	## 【边界斥力】距边 <24px 向内推（防止任何合力把角色钉在角落）
	var wall := 24.0
	if ent.position.x < wall: push.x += (wall - ent.position.x) / wall * 1.2
	if ent.position.x > 400.0 - wall: push.x -= (ent.position.x - (400.0 - wall)) / wall * 1.2
	if ent.position.y < wall: push.y += (wall - ent.position.y) / wall * 1.6
	if ent.position.y > 400.0 - wall: push.y -= (ent.position.y - (400.0 - wall)) / wall * 1.6
	## RET 滞回（策划）：>192 接管；<160 且超 5s 归还
	var mean := int(ent.get_meta("sit_mean_ht", 0))
	## 【免疫期 20261021】被弹免疫 0.5s 内 RET-SP 第一方向均不视为不可用
	if ent.immune_frames > 0:
		mean = 0
	if mean > 192:
		ent.set_meta("ret_mode", true)
		ent.set_meta("ret_since", time_frames)
	elif mean < 160 and ent.has_meta("ret_since") and time_frames - int(ent.get_meta("ret_since", 0)) > 300:
		ent.set_meta("ret_mode", false)
	## 【Hr 直线斥力（新二 20261021）】快弹（≥4px/f）1.5秒距内且朝向角色的
	## 直线分量>1秒距 → 垂直逃离中线斥力（速度×4）；>慢机速度→强制插 c 卡
	## 【批复 20261024④】强制 c 与申请顶替互斥；冲突时能力/符卡(n/s)优先
	var n_spd2 := ent.normal_speed()
	var hr_forced_c := false
	## 【22b 性能 20261028】Hr 扫描上限 128 弹/实体隔帧（原全弹每帧：
	## AI 段随弹量线性涨到 160ms 的主源）
	var hr_scan := 0
	for b2 in bullets:
		var bl2: Bullet = b2
		hr_scan += 1
		if hr_scan > 128:
			break
		if bl2.hidden_now or bl2.track_speed < 4.0 or bl2.source_side == ent.side:
			continue
		var to_ent: Vector2 = ent.position - bl2.pos
		if to_ent.length() > n_spd2 * 60.0 * 1.5:
			continue
		if to_ent.dot(bl2.track_dir) < n_spd2 * 60.0 * 1.0:
			continue
		var perp3 := Vector2(-bl2.track_dir.y, bl2.track_dir.x)
		if to_ent.dot(perp3) < 0.0:
			perp3 = -perp3
		var mag3 := bl2.track_speed * 4.0
		push += perp3 * minf(mag3 / 255.0, 1.0) * 1.2
		if mag3 > n_spd2:
			hr_forced_c = true
	if hr_forced_c and ent.sit_cards != null and not ent.sit_cards.ring.is_empty() 			and ent.sit_cards.ring[0] not in ["n", "s"]:
		ent.sit_cards.ring[0] = "c"
	## 【R-ETA（策划）】点向类追踪弹规避力（弹幕侧累积；读后清零）
	if ent.reta_force != Vector2.ZERO:
		push += ent.reta_force.limit_length(1.2)
		ent.reta_force = Vector2.ZERO
	## 【③期收官·多图期望斥力】（策划权重表 Ht1 Hd3 He2 Hp3）
	## 【v0.0.8】RET-C 引力并作第一级（参与采样侧合成；二级力不在此）
	var first_level: Vector2 = ent.get_meta("map_force", Vector2.ZERO) * 0.8 		+ ent.get_meta("ret_gravity", Vector2.ZERO)
	push += first_level
	## 【v0.0.8 RET-C·第一级（批复疑问3：二级力不进态势十六点采样）】
	## RET-C 倾向=第一级引力（参与热力图采样侧）→ 写 meta 供 map_force 合成；
	## 第二级（绝对躲避/角色逻辑）保持直接矢量和、不经采样
	if ent.ret != null and ent.ret.path_tendency != Vector2.ZERO:
		var ret_w := 1.6 if ent.get_meta("ret_mode", false) else 0.6
		ent.set_meta("ret_gravity", ent.ret.path_tendency.normalized() * ret_w)
		## 【v0.0.8 RET-SP·L228】防御态势（d/h/e）RET-SP 接管：倾向最高的第一步
		## 方向与 APF 合成（树主导向 1.2 / APF 0.4），无方向时回落 APF
		if ent.ret != null and ent.ret.sp_dirs.size() > 0 and ent.current_sit_card in ["d", "h", "e"]:
			push = push * 0.4 + ent.ret.sp_dirs[0] * 1.2

	## 【方案2·作者修订版 20261026c（新二 L41/227）】APF 接管墙检测：
	## ①环=2d 与 5d（巡航式三全开改为 2d+5d 双环，任一环命中即 wall）；
	## ②命中条件二选一：a) 连续 3 对（6 点环形连续=3 对相邻弧段全触弹）
	##   b) 不连续但位置相对的 3 对（6 点构成 3 组对径点，覆盖两侧）；
	## ③热段连续度检测保留（≥4 连续>96 也命中——密集栅格场景）；
	## ④RET 接管期移动不穿 wall（墙方向分量清零——L227）
	var wall_dirs := {} ## 方向 k -> true（命中墙的方向集合，跨 2d/5d 并集）
	var wall_hit := false ## 任一检测器命中（方向数与判定解耦——run4 只产 4 向）
	for ring_i in 2:
		var ring: PackedInt32Array = ent.sit16_2d if ring_i == 0 else ent.sit16_5d
		if ring.size() < 16:
			continue
		var hot := []
		for k2 in 16:
			hot.append(ring[k2] > 96)
		## a) 环形连续 6 点（3 对）
		var run6 := 0
		for k3 in 22: ## 16+6 环绕扫描
			if hot[k3 % 16]:
				run6 += 1
				if run6 >= 6:
					wall_hit = true
					for back in 6:
						wall_dirs[(k3 - back) % 16] = true
			else:
				run6 = 0
		## b) 相对 3 对：k 与 k+8 均热，收集对径对
		var opp_pairs := 0
		for k4 in 8:
			if hot[k4] and hot[(k4 + 8) % 16]:
				opp_pairs += 1
				wall_dirs[k4] = true
				wall_dirs[(k4 + 8) % 16] = true
		if opp_pairs >= 3:
			wall_hit = true ## 相对3对（方向已在收集时加入）
		## c) 热段连续度（保留）：≥4 连续
		var run4 := 0
		for k5 in 20:
			if hot[k5 % 16]:
				run4 += 1
				if run4 >= 4:
					wall_hit = true
					for back2 in 4:
						wall_dirs[(k5 - back2) % 16] = true
			else:
				run4 = 0
	if wall_hit:
		## wall 成立：取最早命中方向为墙参考起点（RET-C 开口查找用）
		var wk := 63
		for k6 in wall_dirs:
			wk = mini(wk, k6)
		ent.set_meta("apf_wall_k", wk)
		ent.set_meta("apf_wall_dirs", wall_dirs)
	else:
		ent.set_meta("apf_wall_dirs", {})
	## 【Hct 横移躲弹（策划：Hct=10 最高；躲狙=往左右走）】
	## 移动方向上 1d 热 → 向左右两侧中较冷的一侧垂直横移（而非单纯刹车）
	var mv_dir: Vector2 = ent.get_meta("ai_push", push)
	if mv_dir != Vector2.ZERO:
		var mv_a := mv_dir.angle()
		var mv_k := wrapi(roundi((mv_a + PI / 2.0) / (TAU / 16.0)), 0, 16)
		if mv_k < ent.sit16_1d.size():
			var hmv: int = ent.sit16_1d[mv_k]
			if hmv > 96:
				## 横移方向按实际两侧热度实测选择（防固定旋转方向的 y 偏置）
				## 【P1 修复 20261015】改读 2d 环（半径 n*12，与原探针同径）垂直两侧索引
				## ——环角 a_k = -90°+22.5°k，k_l ≈ mv_a/22.5°，k_r 为对面；去除每帧 2 次 GPU 同步回读
				var k_l := wrapi(roundi(mv_a / (TAU / 16.0)), 0, 16)
				var k_r := (k_l + 8) % 16
				var vl: int = ent.sit16_2d[k_l] if k_l < ent.sit16_2d.size() else 0
				var vr: int = ent.sit16_2d[k_r] if k_r < ent.sit16_2d.size() else 0
				var perp := Vector2(cos(mv_a - PI / 2.0), sin(mv_a - PI / 2.0)) if vl <= vr \
					else Vector2(cos(mv_a + PI / 2.0), sin(mv_a + PI / 2.0))
				push += perp * (float(hmv) / 255.0) * 2.0
	## 【机控指令圈（策划）】255 衰减引力圈（仅我方 AI 成员响应）
	if cmd_frames > 0 and ent.side == 0:
		var decay := float(cmd_frames) / 300.0
		push += (cmd_point - ent.position).normalized() * decay * 0.7
	## 【号召点（策划）】有战术号召时队友向号召点引力（降低规避）
	if rally_appeal > 0.0:
		## 【号召乘数（新二）】号召强度 × 剩余能力/普通符卡数
		var appeal2 := rally_appeal * maxf(1.0, float(ent.spell_cards))
		push += (rally_point - ent.position).normalized() * minf(appeal2 * 0.25, 1.0) * 0.4
		## 号召每帧自然衰减（约2秒耗尽——策划：号召持续至战术卡结束）
		rally_appeal = maxf(rally_appeal - 0.005, 0.0)
	## 【修复：实体重叠】同侧单位分离力（间距 < 24px 时互推）——
	## 决斗真实感；杂兵由排布系统管理不参与
	var sep := Vector2.ZERO
	for o in entities:
		if o is BattleEntity and o != ent and not o.dead 				and o.kind != BattleEntity.Kind.PRIVATE and o.side == ent.side:
			var d2: Vector2 = ent.position - o.position
			var dl := d2.length()
			if dl > 0.01 and dl < 24.0:
				sep += d2 / dl * (24.0 - dl) * 0.05
	push += sep
	## 【团队姿态（玩家双击W/S/A/D）】覆盖 AI 锚定权重（策划：姿态指令优先）
	## 【边缘内收】目标贴边时锚点向画布中心收拢（防边缘对峙）
	## 【角色逻辑AI 20261024】攻击目标：选择器命中者替换锚定目标（aim=true）；
	## 巡航目标：攻击时优先快机
	var anchor_src: BattleEntity = target
	if bool(ent.ai_logic.get("aim", true)) and ent.ai_target != null and not ent.ai_target.dead:
		anchor_src = ent.ai_target
	if bool(ent.ai_logic.get("cruise", false)) and ent.current_sit_card in ["a", "c"]:
		ent.cruise_active = true
	var tgt_pos: Vector2 = anchor_src.position
	## 【攻击夹角（新二 20261021）】攻击方向与朝向夹角<1 弧度不发起攻击
	var tgt_dir2 := anchor_src.position - ent.position
	var atk_ang := absf(ent.facing.angle_to(tgt_dir2.normalized())) if tgt_dir2.length() > 0.01 else 0.0
	var center_pull := (Vector2(200, 200) - tgt_pos) * 0.25
	var anchor_target: Vector2 = tgt_pos + center_pull
	var to_t: Vector2 = anchor_target - ent.position
	var radial := to_t.length() - 180.0
	var anchor := 0.5
	if atk_ang < 1.0 and (ent.current_sit_card == "a" or ent.current_sit_card == "c"):
		anchor = 0.0 ## 攻击夹角不足——不发起攻击

	## 【批复 20261024④】最小交战距离：贴锚定目标 <120px 锚定线性衰减归零，
	## 并施加 (1-d/120)×0.4 后退——与对峙逻辑同思路，杜绝"离得很近"贴脸
	var d_anchor := ent.position.distance_to(anchor_src.position)
	if d_anchor < 120.0:
		anchor *= d_anchor / 120.0
		push -= (anchor_src.position - ent.position).normalized() * (1.0 - d_anchor / 120.0) * 0.4
	match ent.current_sit_card:
		"a":
			anchor = 0.9
		"c":
			anchor = 0.2
		"r":
			anchor = -0.8
		"d", "h":
			anchor = 0.0
	if absf(radial) > 40.0:
		var anchor_w := anchor * (0.2 if ent.get_meta("ret_mode", false) else 1.0)
		var anch := to_t.normalized() * signf(radial) * anchor_w
		## 【修复：右下扎堆】锚定主导化：交战距离是 AI 的"家"——
		## 避压合力只允许在与锚定不冲突的方向上使用至多 0.7，锚定保底 0.35
		var limited := (push * 0.35 + anch).limit_length(1.0)
		push = limited
	else:
		push = push.limit_length(1.0)
	if ent.current_sit_card == "c":
		ent.cruise_active = true
	## 【AI 静默区（根因修复）】move() 对方向 normalized——任何 0.1 的小力
	## 都会全速移动；小力方向每帧乱变 → 原地打转/漂移/停靠角落。
	## |push|<0.15 视为静止（力平衡），不动。
	if push.length() < 0.15:
		ent.move(Vector2.ZERO, time_scale)
	else:
		var final_dir := push.limit_length(1.0)
		var dodge2: Vector2 = ent.get_meta("abs_dodge", Vector2.ZERO)
		if dodge2 != Vector2.ZERO:
			final_dir = (final_dir * 0.3 + dodge2 * 0.7).normalized() ## 防撞主导
			ent.set_meta("abs_dodge", Vector2.ZERO)
		## （沿墙滑行允许、穿墙禁止——红美铃道中防 miss）
		var wdirs: Dictionary = ent.get_meta("apf_wall_dirs", {})
		if not wdirs.is_empty() and ent.get_meta("ret_mode", false):
			var worst := Vector2.ZERO
			for wk2 in wdirs:
				var wa := spin - PI / 2.0 + TAU * float(int(wk2) % 16) / 16.0
				var wv := Vector2(cos(wa), sin(wa))
				if final_dir.dot(wv) > 0.0 and wdirs.has((int(wk2) + 8) % 16):
					worst += wv ## 双侧墙（对径均在）→ 该轴向禁行
			if worst != Vector2.ZERO:
				var wn := worst.normalized()
				final_dir = (final_dir - wn * final_dir.dot(wn))
				if final_dir.length() < 0.05:
					final_dir = wn.rotated(PI / 2.0) ## 全堵时沿墙切向逃生
		ent.move(final_dir, time_scale)

func _entity_ticks(dt: float) -> void:
	for ent in entities:
		ent.tick()
	## 【杂兵 APF（新二 20261021）】Hd×2 + 所属角色 Hcs×5（共用 owner 的 Hcs；
	## RET-SP 完全跳过）——每 0.2s 一次写入 meta（移动侧 formation 消费）
	if time_frames % 12 == 0:
		for fm in formations:
			var priv2: BattleEntity = fm.private_ent
			var owner2: BattleEntity = fm.owner
			if priv2 == null or owner2 == null or priv2.dead:
				continue
			var push3 := Vector2.ZERO
			var spin3 := TAU / 32.0 * float(time_frames % 2)
			for k3 in 32:
				var ring3: PackedInt32Array = owner2.sit16_1d if k3 < 16 else owner2.sit16_2d
				var v3: int = ring3[k3 % 16] if (k3 % 16) < ring3.size() else 0
				var a3 := spin3 - PI / 2.0 + TAU * float(k3 % 16) / 16.0
				var dv3 := Vector2(cos(a3), sin(a3))
				var v_hcs3: float = owner2.hcs_pts[k3] if k3 < owner2.hcs_pts.size() else 0.0
				var hot3 := (float(v3) / 255.0) * 2.0 + (v_hcs3 / 255.0) * 5.0
				push3 -= dv3 * (hot3 / 7.0) * (1.0 if k3 < 16 else 2.0)
			priv2.set_meta("apf_push", push3.limit_length(1.0) * priv2.normal_speed() * 0.5)
	## 【嫌疑4】杂兵排布每3帧一次（formation 步进+sync_private_pos 降频）
	if time_frames % 3 == 0:
		for fm in formations:
			fm.step(dt * 3.0) ## 补偿步长
		for ent in entities:
			if ent.kind == BattleEntity.Kind.PRIVATE:
				ent.sync_private_pos()
	## 【③期·杂兵 AI（批复：Hd+所属角色 Hcs；10Hz）】读所属角色十六点求斥力
	if time_frames % 6 == 0:
		for ent in entities:
			if ent.kind != BattleEntity.Kind.PRIVATE or ent.dead or ent.owner_ent == null:
				continue
			var own: BattleEntity = ent.owner_ent
			if own.sit16_2d.size() != 16:
				continue
			var push := Vector2.ZERO
			var spin := TAU / 32.0 * float(time_frames % 2)
			for k in 16:
				var a := spin - PI / 2.0 + TAU * float(k) / 16.0
				var dv := Vector2(cos(a), sin(a))
				var h2: int = own.sit16_2d[k] if k < own.sit16_2d.size() else 0
				push -= dv * maxf((h2 - 96.0) / 160.0, 0.0) * 0.8 ## 杂兵权重（Hd=2 近似 Ht）
			var cur: Vector2 = ent.get_meta("ai_push", Vector2.ZERO)
			ent.set_meta("ai_push", cur.lerp(push.limit_length(1.0), 0.5))
			ent.move(ent.get_meta("ai_push", Vector2.ZERO))

## =============================================================
## ③期·态势卡 tick（每 0.1s，与火控同拍）：全角色抽卡 →
##   A(a攻击)=追打目标 / c巡航=快机环绕 / D(d防御h躲避)=避弹优先 /
##   N(r撤退)=拉开距离；n/s（能力/符卡申请）暂记账；
##   战术卡检测（第16~25号卡）→ HUD 彩虹线 + 面板"攻击状态"
## 【性能】数组操作；每实体每0.1s 一次正态骰子（Box-Muller）
## =============================================================
var _sit_acc := 0.0
const SIT_COLORS := {"a": Color(0.8, 0.1, 0.1), "c": Color(1.0, 0.4, 0.6),
	"r": Color(0.9, 0.8, 0.2), "n": Color(0.9, 0.2, 0.9), "s": Color(0.5, 0.2, 0.9),
	"d": Color(0.2, 0.8, 0.3), "h": Color(0.2, 0.5, 0.9), "e": Color(1.0, 1.0, 1.0)}

func _sit_tick(delta: float) -> void:
	_ent_tick_sit(delta) ## 抽卡/战术逐拍累计（内部 0.1s 拍，须每帧吃 delta）
	## 【P1 修复 20261015】心情/Smn/Sms/SL 的输入（sit16 等）只以 10Hz 更新——
	## 本段同步降 10Hz（原 60Hz 重复计算 6 遍）；
	## Ht/Hd 位置值改读 _heatmap_tick 批量采样写入的 ht_at/hd_at meta
	## （原先此处每实体每物理帧 1 次 Ht 回读 + 1 次 8 图 sample_multi = 每帧约 90 次同步往返）
	if time_frames % 6 != 0:
		return
	## 每实体：回写十六点均值→心情→抽卡→战术检测
	for ent: BattleEntity in entities:
		if ent.dead or ent.kind == BattleEntity.Kind.PRIVATE or ent == emitter_ent:
			continue
		if ent.sit_cards == null:
			ent.sit_cards = SitCardSystem.new()
		## 【dm_situate 权重 20261021（新二）】Ht3 Hd2 He1 Hp2 加权（He/Hp 中心未实装暂 0）
		var sum := 0
		for v in ent.sit16_1d:
			sum += v
		var mean := sum / 16 if ent.sit16_1d.size() == 16 else 0
		var wsum := float(mean) * 3.0 + float(ent.get_meta("hd_at", 0)) * 2.0
		ent.set_meta("sit_mean", int(wsum / 5.0))
		ent.set_meta("sit_mean_ht", mean) ## 原始 Ht 均值（滞回阈值口径）
		var sp := ent.mood_sp()
		ent.sit_cards.mood_s = sp[0]
		ent.sit_cards.mood_p = sp[1]
		ent.sit_cards.sit_mean = mean
		## 【修复：态势UI全红】has_apf_field 恒 false → c→a / d→h 替换永远生效，
		## 卡组恒为红色 a。策划"引力场"来源现状：玩家姿态指令 / 战术号召 / 机控指令圈
		ent.sit_cards.has_apf_field = (team_stance != "") or (ent.current_tactic != "") or (cmd_frames > 0)
		## 【释放公式入参（批复 2026-10-13）】Kp/Dcs/Pcs/Smn/Sms 每拍回写；
		## Smn/Sms 用 Ht/Hd 位置采样近似权重表（Hcs/Hct 实装后替换）
		ent.sit_cards.Kp = clampf(float(ent.pp) / float(ent.PP_CAP), 0.0, 1.0)
		var dcount := 0
		for ci in mini(10, ent.sit_cards.ring.size()):
			var cc: String = ent.sit_cards.ring[ci]
			if cc == "d" or cc == "h":
				dcount += 1
		ent.sit_cards.Dcs = dcount
		var enemy_privs := 0
		for e3 in entities:
			if e3 is BattleEntity and e3.kind == BattleEntity.Kind.PRIVATE 					and e3.side != ent.side and not e3.dead:
				enemy_privs += 1
		ent.sit_cards.Pcs = enemy_privs
		var ht_at: int = ent.get_meta("ht_at", 0)
		var hd_at: int = ent.get_meta("hd_at", 0)
		## 【数值口径暂定】Smn/Sms = 权重×热度的加权和（0~255 口径，非归一）——
		## 策划公式 Dnr=512-Smn-… 与 Dsr=768+…-4Sms 的量纲暗示 Smn/Sms 为数十~数百级。
		## Hcs/Hct 实装后按完整权重表替换；当前 Ht/Hd 近似。
		## 【权重表 20261020（游戏逻辑介绍）】dm_smn=Ht3+Hd1+Hcs8；dm_sms=Ht2+Hd1+Hcs4
		## （0~3060 口径；Dnr=512-Smn 高倾向转负→65536 必成=危急必交符）
		var hcs_at := float(ent.hcs_at) if ent.hcs_pts.size() >= 49 else 0.0
		ent.sit_cards.Smn = clampf(float(ht_at) * 3.0 + float(hd_at) * 1.0 + hcs_at * 8.0, 0.0, 3060.0)
		ent.sit_cards.Sms = clampf(float(ht_at) * 2.0 + float(hd_at) * 1.0 + hcs_at * 4.0, 0.0, 2295.0)
		## 【RET-SP 两步（③期收官）】Sl=Σ 一段可行 × 二段可行(同角5d)
		## 一段可行=5d 圈该方向 <64（假设位移不穿热）；二段可行=1d 同角 <64
		var sl := 0.0
		for k in 16:
			var first_ok: bool = k < ent.sit16_5d.size() and ent.sit16_5d[k] < 64
			if first_ok:
				var second_ok: bool = k < ent.sit16_1d.size() and ent.sit16_1d[k] < 64
				sl += 16.0 if second_ok else 8.0 ## 二段可行=全16向，仅一段可行=半
		ent.sit_cards.SL = clampf(sl, 0.0, 256.0)
		ent.sit_cards.phase_p = [-50, -50, 50, 0, 50][mini(phase, 4)]
		## 【v0.0.8】RET-C 48 点遍历 + RET-SP 简化 Sl（10Hz）
		if ent.ret != null:
			ent.ret.spin = TAU / 32.0 * float(time_frames % 2)
			ent.ret.compute_retc()
			ent.ret.compute_sp()
			ent.sit_cards.SL = clampf(float(ent.ret.sl), 0.0, 256.0)

## 逐拍抽卡（0.1s 一张）+ 行为应用（敌方）
var _card_acc := 0.0
var rally_point := Vector2.ZERO   ## 号召点（战术卡命中者位置）
## 【机控指令圈（策划：G键指定位置进攻；圈=255衰减的引力，持续2秒）】
var cmd_point := Vector2.ZERO
var cmd_frames := 0
var _cmd_arm_g := false           ## G 按住（等待战场点击）
## 多图采样圈半径辅助（k: 0-15=1d 16-31=2d 32-47=5d）
func n_ring(k: int) -> float:
	return 6.0 if k < 16 else (12.0 if k < 32 else 30.0)
var rally_appeal := 0.0           ## 号召强度（0=无）
func _ent_tick_sit(delta: float) -> void:
	_card_acc += delta
	while _card_acc >= 0.1:
		_card_acc -= 0.1
		for ent: BattleEntity in entities:
			if ent.dead or ent.kind == BattleEntity.Kind.PRIVATE or ent == emitter_ent or ent.sit_cards == null:
				continue
			var replaced: String = ent.sit_cards.release_tick(phase)
			if replaced != "":
				ent.sit_cards.ring[0] = replaced ## 替换下一张（策划：换掉下一张态势卡）
			ent.current_sit_card = ent.sit_cards.pop_card()
			## 释放判定（能力/符卡出卡即放；n=能力 s=次级符卡）
			if ent.current_sit_card == "n" or ent.current_sit_card == "s":
				_apply_release(ent, ent.current_sit_card)
			var tac: Dictionary = ent.sit_cards.check_tactic(ent.db)
			ent.current_tactic = tac.get("name", "")
			## 【号召点（③期）】命中战术的角色广播号召（队友 AI 向其引力靠拢）
			if tac.has("name"):
				var appeal: float = SitCardSystem.TACTIC_APPEAL.get(tac["name"], 0.0)
				if appeal > 0.0:
					rally_point = ent.position
					rally_appeal = appeal
			if ent.side == 1 and player_leader != null and not player_leader.dead:
				_apply_sit_behavior(ent)
			elif ent.side == 0 and ent != player_leader:
				_apply_sit_behavior(ent) ## 我方 AI 成员同样按卡行动

## 释放效果（策划：能力80px·0.5s / 次级符卡200px·1s / 主要符卡全屏·5s）
## 消耗：能力25P / 次级符卡1张 / 主要符卡1张+100P（本批 n=能力、s=次级；主要符卡随符卡设置实装）
func _apply_release(ent: BattleEntity, kind: String) -> void:
	## 【批复 2026-10-13】不论能力/符卡/主要符卡：释放即消除范围内弹幕
	## 能力 80px / 次级符卡 200px（主要符卡=全屏，随符卡数据实装）
	var radius := 80.0 if kind == "n" else 200.0
	var cleared := 0
	for b in bullets.duplicate():
		var bl: Bullet = b
		if bl.hidden_now or bl.source_side == ent.side:
			continue
		if bl.pos.distance_to(ent.position) <= radius:
			bullets.erase(bl)
			cleared += 1
	## 【批复 2026-10-13】消弹持续时长 = 剩余P点每100P点1秒，最低1秒
	var clear_sec: float = maxf(1.0, float(ent.pp) / 100.0)
	## 【批复 2026-10-13·火力瘫痪】释放开始 → 敌方全角色火力瘫痪；
	## 时长占位 1 秒（时间轴实装后 = 时间轴最后事件执行时刻）
	var paralyze_frames := 60
	match kind:
		"n":
			if ent.pp >= 25:
				ent.pp -= 25
				clear_sec = maxf(1.0, float(ent.pp) / 100.0) ## 扣费后剩余P定时长
				ent.apply_clear(80.0, clear_sec)
				ent.set_meta("release_flash", ent.chara_name())
				ent.set_meta("clear_count", cleared)
				_paralyze_fire(1 - ent.side, clear_sec)
		"s":
			if ent.spell_cards >= 1:
				ent.spell_cards -= 1
				clear_sec = maxf(1.0, float(ent.pp) / 100.0)
				ent.apply_clear(200.0, clear_sec)
				ent.set_meta("released_kind", "s")
				ent.set_meta("release_flash", ent.chara_name())
				ent.set_meta("clear_count", cleared)
				_paralyze_fire(1 - ent.side, clear_sec)
	ent.sit_cards.on_released(kind)

## 敌方火力瘫痪（时间轴实装前占位 1s/时长秒；实装后=至时间轴最后事件）
func _paralyze_fire(victim_side: int, seconds: float) -> void:
	var until := time_frames + int(seconds * 60.0)
	for e in entities:
		if e is BattleEntity and e.side == victim_side and not e.dead:
			e.set_meta("fire_paralyzed_until", until)

func _fire_is_paralyzed(ent: BattleEntity) -> bool:
	return ent.has_meta("fire_paralyzed_until") and time_frames < int(ent.get_meta("fire_paralyzed_until"))

## 持续消弹域（clear 期间每帧清范围内敌方弹幕）
func _clear_bullets_around(ent: BattleEntity) -> void:
	if ent.clear_radius <= 0.0:
		return
	for b in bullets.duplicate():
		var bl: Bullet = b
		if bl.hidden_now or bl.source_side == ent.side:
			continue
		if bl.pos.distance_to(ent.position) <= ent.clear_radius:
			bullets.erase(bl)
			_cleared_count += 1

## 态势→行为（③期映射：a=追击射击 c=快机 d/h=避弹 r=拉开）
func _apply_sit_behavior(ent: BattleEntity) -> void:
	match ent.current_sit_card:
		"a":
			ent.cruise_active = false
			ent.set_meta("sit_aggr", 1.0) ## 攻击倾向（火控门权重·后续批）
		"c":
			ent.cruise_active = true
		"d", "h":
			ent.cruise_active = false
		"r":
			ent.cruise_active = false
			ent.set_meta("sit_retreat", true) ## 撤退倾向（移动层·APF 反向）
		_:
			pass

func _fire_ticks(delta: float) -> void:
	var t_sec := float(time_frames) / 60.0
	for fc in fire_controls:
		if not fc.entity.dead and not _fire_is_paralyzed(fc.entity):
			## 敌侧火控接时间尺度（批复#8：AI/态势与弹幕节拍同步缩放）
			var d := delta * (enemy_time_scale if fc.entity.side == 1 else 1.0)
			fc.process(d, t_sec, phase)
	if time_frames % 300 == 0:
		for fc in fire_controls:
			if not fc.entity.dead:
				fc.rebuild_points()

func _bullet_updates(dt: float) -> void:
	## 【性能休整】共享上下文极简化：只含 field_t/field_phase（全局不变）
	## self_*/target_* 不进共享——绝大多数弹幕表达式不依赖它们
	## 【22b 20261028e】哈希 30Hz 重建（原每帧）：全部查询方（被弹/可摧毁/接触）
	## 均为 30Hz——奇数帧重建供本帧+下帧查询，弹位置 1 帧旧（16ms×弹速≈亚像素级
	## 误差；0.5s 免疫与 DDM 异步本就存在同级延迟）。千弹省 ~1.4ms/帧。
	if time_frames % 2 == 1:
		bullet_hash.clear()
	var gctx := {"field_t": float(time_frames), "field_phase": phase}
	## 【22b 20261028】collapse_counts 挪到循环外（原每弹 Dictionary 新建）
	gctx.merge(bullet_collapse_counts())
	for i in range(bullets.size() - 1, -1, -1):
		var b: Bullet = bullets[i]
		## 【20261028·作者规则】弹幕更新必须 60 帧——交错半帧实验撤销
		b.sync_shared(gctx)
		if not b.update(dt):
			bullets.remove_at(i)
			_expired_count += 1
			continue
		if time_frames % 2 == 1:
			bullet_hash.insert(b)
		if b.repeat_tick():
			## 【20261003】repeat 语义=“事件的发射节拍”，补发子弹本身不再携带
			## repeat——否则群体每周期翻倍（实测冻结元凶：regularline_copy）。
			## 【20261015·语义修订】repeat_time=副本重复间隔、repeat_freq=补发次数；
			## 旋转重复事件整扇重放（仅载体副本携带节拍）。
			## 【20261019】rotate_div 已表达式化——非"0"即按旋转事件处理；
			## t=事件出现至今（载体存活时长），t_copy=0（副本此刻刚释放）
			if b.ev.rotate_div.strip_edges() not in ["", "0"]:
				_spawn_event_copies(b.ev, b.repeat_origin(), b.source, null, {}, b.depth + 1,
					{}, {}, b.t, b._target_cached, Vector2(
						float(b._ctx.get("target_x", 0.0)), float(b._ctx.get("target_y", 0.0))))
			else:
				var child := _spawn_bullet(b.ev, b.repeat_origin(), b.depth + 1, b.source, null)
				if child != null:
					child.repeat_enabled = false
	while bullets.size() > MAX_BULLETS:
		bullets.pop_front()
	_resolve_nodesb_clash()

## 【NodesB 对撞互推（作者 20261020：弹幕推弹幕）】对撞命题为真的 NodesB
## 两两接触：位置分离到刚接触 + 法向速度对交换（弹性系数 0.5，近似推动）。
## 每帧两两检测上限 64 参与者（作者对节点类性能的既定警告），30Hz 足够。
func _resolve_nodesb_clash() -> void:
	var parts: Array = []
	if time_frames % 2 == 0:
		var ctx := {}
		for b in bullets:
			var bl: Bullet = b
			if bl.ev.tag != DanmakuEventData.TAG_NODES_B or bl.hidden_now:
				continue
			## 对撞命题为真（或旧 can_destroy）才参与互推
			var on := bl.ev.can_destroy or (bl.ev.ex_clash != null and bl.ev.ex_clash.eval_prop(ctx, 0.0) > 0.5)
			if on:
				parts.append(bl)
				if parts.size() >= 64:
					break
	if parts.size() < 2:
		return
	for i in parts.size():
		var a: Bullet = parts[i]
		for j in range(i + 1, parts.size()):
			var c: Bullet = parts[j]
			var d: Vector2 = c.pos - a.pos
			var dd := d.length()
			var rr := a.draw_radius + c.draw_radius
			if dd > 0.01 and dd < rr:
				var n := d / dd
				var overlap := (rr - dd) * 0.5
				a.pos -= n * overlap
				c.pos += n * overlap
				## 法向速度交换（推动感）：各取对方法向分量之半
				var va := a.velocity.dot(n)
				var vc := c.velocity.dot(n)
				if va > vc: ## 仅在相互接近时施力
					var exh := (va - vc) * 0.5
					a.velocity -= n * exh
					c.velocity += n * exh

## =============================================================
## ⑥ 被弹解析（性能休整·嫌疑2修复）
## 【作者指示】不要附加判定，不要跟踪路径，快速弹幕穿过不伤害可接受。
##   0.5秒减免=角色不参与所有DDM持续0.5秒（不只是被弹的那个弹幕）。
## 【极简化】不排序、不维护 touch_state 上升沿——直接首个命中即结算。
##   免疫期内角色完全跳过被弹（不查哈希）。
## =============================================================
func _resolve_hits() -> void:
	## 【20261003】被弹判定 30Hz（每2物理帧）：0.5s免疫不受影响；
	## 作者既定语义“快弹穿透不伤害可接受、不要附加判定”（批复二），
	## 高密度演练（661弹）下被弹占 physics ~6ms → 减半。
	if time_frames % 2 == 0:
		return
	for ent in entities:
		if ent.dead or ent == emitter_ent:
			continue
		if ent.immune_frames > 0:
			continue ## 0.5秒减免：角色不参与所有DDM（作者批复）
		if ent.clear_active():
			## 【批复 2026-10-13】屏蔽改消除：范围内敌方弹幕持续消除（消弹特效）
			_clear_bullets_around(ent)
		var r: float = ent.barrier_radius() if ent.ap > 0 else ent.judge_radius()
		## 【20261003修复·重大】skip_side=本侧（跳过本方法弹）——旧版传 1-ent.side
		## 把敌方法弹全跳过了（只有友方物弹能打中自己，方向反转的隐性大坑）
		var keys := bullet_hash.query_keys(ent.position.x, ent.position.y, r, ent.side, ent)
		if keys.is_empty():
			continue
		## 首个命中即结算——不排序（作者：能跳则跳）
		for key in keys:
			## 整型复合键（dmg*4+模式）——20261004 R8
			var dmg := int(key) >> 2
			var mi := int(key) & 3
			## 非法伤害（≤0：假弹幕/预警期）不参与被弹结算，继续找同帧真伤害键
			## （批复 2026-10-01#4 批准修改——原先 break 会把本帧额度让给 -1 弹）
			if dmg <= 0:
				continue
			var angles: Array = keys[key]
			var ang: float = angles[0] if not angles.is_empty() else 0.0
			ent.take_hit(dmg, mi, ang)
			break ## 只结算一次

func _choose_part(angles: Array) -> Array:
	var first_angle := {}
	for a in angles:
		var ang: float = a
		var p := _part_of_angle(ang)
		if not first_angle.has(p):
			first_angle[p] = ang
	for part in [BattleEntity.PART_BODY, BattleEntity.PART_WEAPON, BattleEntity.PART_MOVE]:
		if first_angle.has(part):
			return [part, first_angle[part]]
	return [BattleEntity.PART_BODY, angles[0] if not angles.is_empty() else 0.0]

func _part_of_angle(a: float) -> int:
	if absf(angle_difference(a, -PI / 2.0)) <= deg_to_rad(60.0):
		return BattleEntity.PART_WEAPON
	if absf(angle_difference(a, PI / 2.0)) <= deg_to_rad(60.0):
		return BattleEntity.PART_MOVE
	return BattleEntity.PART_BODY

## =============================================================
## 阶段与胜负（①期仍简化；四阶段完整判定属②期）
## =============================================================
func _update_phase() -> void:
	if is_preview:
		return
	## 【占位·④期替换】阶段推进最小版：远距(1) →20秒→ 短兵(2)
	## ——能力/符卡装填依赖短兵阶段（策划）；完整四阶段条件判定属④期
	if phase < 2 and time_frames >= 1200:
		phase = 2
	if phase < 4:
		var p_all_dead := _side_all_dead(player_ents)
		var e_all_dead := _side_all_dead(enemy_ents)
		if p_all_dead or e_all_dead:
			phase = 4

func _side_all_dead(ents: Array) -> bool:
	for e in ents:
		if not e.dead:
			return false
	return not ents.is_empty()

func _check_end() -> void:
	if is_preview or finished:
		return
	if _side_all_dead(enemy_ents) and not _side_all_dead(player_ents):
		_finish("胜  利 —— 敌方全灭")
	elif _side_all_dead(player_ents):
		_finish("败  北 —— 我方全灭")

func _finish(text: String) -> void:
	finished = true
	banner.text = text + "\nR 重试 / Esc 回标题"
	banner.visible = true

## =============================================================
## 事件发射（世界接口）
## =============================================================
func _find_event(event_name: String) -> DanmakuEventData:
	if event_name == "":
		event_name = "demo_aimed"
	for ev in GameGlobals.editor_events:
		if ev.event_name == event_name:
			return ev
	return GameGlobals.get_event(event_name)

func _spawn_bullet(ev: DanmakuEventData, origin: Vector2, depth: int, src: BattleEntity, point = null,
		rot := 0.0, rid := 0, rolls: Dictionary = {}, pinned := Vector2.ZERO, event_t := 0.0,
		shared_target: BattleEntity = null, shared_txy: Vector2 = Vector2.INF) -> Bullet:
	if ev == null or depth > Bullet.MAX_DEPTH:
		return null
	if bullets.size() >= MAX_BULLETS:
		return null
	var b := Bullet.new()
	var ctx: Dictionary = point.ctx if point != null else {}
	## 【旋转重复】rot/rid/rolls/pinned 必须在 setup 前写入——冻结表达式
	## 在 setup 内求值，rotate_id/rate_roll/锚定基向才可见；
	## t_event=事件已存续时间（t 语义，作者 20261019）：首发 0、
	## repeat 子代=载体释放时刻、rotate 延时=基时+步进延时
	b.rot_angle = rot
	b.rotate_id = rid
	b.rate_roll = float(rolls.get("rate_roll", 1.0))
	b.pattern_roll = float(rolls.get("pattern_roll", 1.0))
	b.pinned_dir = pinned
	b.t_event = event_t
	b.setup(ev, origin, src.side, src, self, depth, ctx, shared_target, shared_txy)
	bullets.append(b)
	return b

func spawn_event_by_name(event_name: String, at: Vector2, side: int, depth: int) -> void:
	var ev := _find_event(event_name)
	if ev == null:
		return
	var src := emitter_ent if is_preview else (player_leader if side == 0 else enemy_leader)
	if src == null:
		src = player_leader if side == 0 else enemy_leader
	if src == null:
		return
	var b := Bullet.new()
	b.setup(ev, at, side, src, self, depth)
	bullets.append(b)

## —— Bullet 依赖的世界接口 ——
func bullet_field(_side: int) -> DdmField:
	return null ## ①期哈希架构下无 CPU DDM；保留接口兼容

func bullet_hit_query(cx: float, cy: float, r: float, hit_side: int, _skip: BattleEntity) -> Dictionary:
	## 点向类 can_destroy 用：查询可击中 hit_side 的弹幕是否触及点
	## （同样修复 skip 方向：跳过 hit_side 本侧的法弹）
	return bullet_hash.query_keys(cx, cy, r, hit_side, null)

func bullet_nearest_enemy(side: int, from: Vector2) -> BattleEntity:
	return bullet_nearest_enemy_from(side, from)

func bullet_nearest_enemy_from(side: int, from: Vector2) -> BattleEntity:
	var best: BattleEntity = null
	var best_d := INF
	for ent in entities:
		if ent is not BattleEntity or ent.dead or ent.side == side or ent == emitter_ent:
			continue
		var d: float = ent.position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = ent
	return best

func bullet_nearest_enemy_pos(side: int, from: Vector2) -> Vector2:
	if is_preview:
		## 【批复 20261019】试炼场预览：光标位置=被瞄准的假想敌（自机狙可用）
		return _preview_cursor_pos()
	var e := bullet_nearest_enemy_from(side, from)
	if e != null:
		return e.position
	return from + (Vector2.RIGHT if side == 0 else Vector2.LEFT)

## 光标的战场逻辑坐标（与机控指令圈点击同一换算）
func _preview_cursor_pos() -> Vector2:
	var wp := get_global_mouse_position()
	if world != null and world.scale.x != 0.0:
		return (wp - world.position) / world.scale.x
	return wp

## 【get 系 20261020】阵营击破计数（弹幕快照/门上下文用）
## f=friendly(0方视角：0方击破) e=enemy(1方击破)
func bullet_collapse_counts() -> Dictionary:
	return {
		"friendly_privates_collapse": float(_camp_priv_collapse[0]),
		"friendly_chara_collapes": float(_camp_chara_collapse[0]),
		"enemy_privates_collapse": float(_camp_priv_collapse[1]),
		"enemy_chara_collapes": float(_camp_chara_collapse[1]),
		"field_privates_collapse": float(_camp_priv_collapse[0] + _camp_priv_collapse[1]),
		"field_chara_collapes": float(_camp_chara_collapse[0] + _camp_chara_collapse[1]),
	}

## 【getChata 20261020】某阵营的存活角色列表（定位器候选；杂兵与发射器除外）
func bullet_camp_chars(side: int) -> Array:
	var out: Array = []
	for ent in entities:
		if ent is BattleEntity and ent.side == side and not ent.dead 				and ent.kind != BattleEntity.Kind.PRIVATE and ent != emitter_ent:
			out.append(ent)
	return out

func bullet_time_frames() -> float:
	return float(time_frames)

func bullet_phase() -> int:
	return phase

## =============================================================
## GPU DDM 渲染（每帧：导出印章 → compute）
## =============================================================
func _render_ddm() -> void:
	if not gpu_ok:
		return
	## 【22b 20261028】DDM 提交 30Hz（视觉 R8 图 60Hz 与 30Hz 不可辨；
	## 印章上传 4400+/帧 的 GPU 提交减半——主设备 Texture2DRD 引用每帧仍换）
	if time_frames % 2 != 0:
		return
	## 【热力扫过段 20261026】Ht 采样帧（%6==0）DDM 印章含 0.1s 扫过段（补采样间隙）
	var heat_tick := time_frames % 6 == 0
	_stamp_buf0.clear()
	_stamp_buf1.clear()
	for b in bullets:
		var bl: Bullet = b
		if bl.hidden_now:
			continue
		## fields[side]语义：敌方法弹+物弹 → 击中对方；物弹超遮罩 → 也入己方图。
		## 【法弹可见度（作者批复 2026-10-02）】我方法弹照常进入敌方 fields——
		## 敌 AI 必须能读到；对本侧它天然为 0（"覆写为0"语义）。
		## 视觉上的隐形+白色前向轨道只在渲染层处理，与本图无关。
		if bl.source_side == 0:
			_stamp_buf1 = _export(bl, _stamp_buf1)
			if bl.ev.is_phy and bl.beyond_mask():
				_stamp_buf0 = _export(bl, _stamp_buf0)
		else:
			_stamp_buf0 = _export(bl, _stamp_buf0)
			if bl.ev.is_phy and bl.beyond_mask():
				_stamp_buf1 = _export(bl, _stamp_buf1)
	ddm_gpu0.render(_stamp_buf0)
	ddm_gpu1.render(_stamp_buf1)
	if heat_tick:
		for b in bullets:
			var bl: Bullet = b
			bl.heat_prev = bl.pos ## 采样帧后记录（下个采样帧的扫过段起点）

func _export(bl: Bullet, buf: PackedFloat32Array) -> PackedFloat32Array:
	bl.export_stamps(buf, time_frames % 6 == 0)
	return buf

## =============================================================
## HUD / 输入
## =============================================================
## 【20261026】左上热力图名 + 左下调试键位（呼出后显示）
func _update_hud_debug_labels() -> void:
	if _heat_label != null:
		var names := ["关", "Ht 全局热点", "Hv 速度热点", "He 期望热点", "Hd 总结期望云",
			"Hr 快弹警告", "Hp 敌方规律", "Hcs 角色1s图", "Hct 角色s20图"]
		var side_txt := "我方" if _heat_view_side == 0 else "敌方"
		var focus_name: String = _heat_focus.chara_name() if _heat_focus != null and is_instance_valid(_heat_focus) else "未选(F1)"
		var sit_txt := ""
		if _heat_focus != null and is_instance_valid(_heat_focus) and _heat_focus.sit16_1d.size() == 16:
			var s1 := 0
			for v in _heat_focus.sit16_1d:
				s1 += v
			sit_txt = " 1d均值=%d" % (s1 / 16)
		var ret_txt := " RET接管" if _heat_focus != null and is_instance_valid(_heat_focus) and _heat_focus.get_meta("ret_mode", false) else ""
		_heat_label.text = "%s|%s(%s)%s%s" % [names[_heat_view] if _heat_view > 0 else "图:关", focus_name, side_txt, sit_txt, ret_txt]
	if _debug_hint_label != null and _debug_used:
		_debug_hint_label.text = "调试：F3显示开关 [切图种 ]切帧序 F2十六点 F1选角色 滚轮换角色 F4慢速0.25 V轮射 G点攻 B点防 Esc菜单"
func _unhandled_input(event: InputEvent) -> void:
	## 【键位设置】配置键映射回默认键码（R/T/H/V/F1/F2/F3/G/B 可改）
	if event is InputEventKey and event.pressed:
		for action in ["增援", "自动增援", "早苗技能", "指定位置进攻", "指定位置防御",
				"轮射齐射切换", "热力图显示", "选取高亮", "弹幕图显示"]:
			if event.keycode == GameGlobals.get_key(action):
				var mapped: int = GameGlobals.KEY_DEFAULTS[action]
				if mapped != event.keycode:
					event = InputEventKey.new()
					event.keycode = mapped
					event.pressed = true
				break
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_pick_idx = maxi(0, _pick_idx - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_pick_idx = _pick_idx + 1
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			team_stance = "" ## 取消当前姿态指令
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _cmd_arm_g:
		## G 按住后左键点击战场 = 指定位置进攻指令（策划机控：指定位置进攻持续5秒）
		var wp: Vector2 = (get_global_mouse_position() - world.position) / world.scale.x
		if wp.x >= 0 and wp.x <= 400 and wp.y >= 0 and wp.y <= 400:
			cmd_point = wp
			cmd_frames = 300 ## 5秒
			_pick_side = 0
		_cmd_arm_g = false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if finished:
					GameGlobals.goto_scene("res://scenes/title_menu.tscn")
				else:
					_toggle_pause()
			KEY_V:
				GameGlobals.versus_volley = "salvo" if GameGlobals.versus_volley == "rotate" else "rotate"
				for fc in fire_controls:
					fc.set_mode(GameGlobals.versus_volley)
			KEY_F1: ## 【新三 20261028】选取当前观察角色（热力图/态势十六点观察对象）
				_heat_focus = picked_entity()
				_debug_used = true
				_update_hud_debug_labels()

			KEY_BRACKETLEFT: ## 【新三 20261028】[ 切换热力图种类（关→Ht→…→Hct→关）
				_heat_view = (_heat_view + 1) % 9
				_debug_used = true
				if ddm_debug_layer != null and _heat_view > 0:
					ddm_debug_layer.visible = true
				_update_hud_debug_labels()

			KEY_BRACKETRIGHT: ## 【新三 20261028】] 切动态热力图（Hd/Hcs）帧序
				_debug_used = true
				_update_hud_debug_labels()
				_heat_frame += 1

			KEY_F2: ## 【新三 20261028】显示角色的三串态势十六点（1d/2d/5d 环）
				_show_sit16 = not _show_sit16
				_debug_used = true
				_update_hud_debug_labels()

			KEY_F4: ## 【v0.0.8】AI 慢速调试（敌侧 AI+速度=0.25 倍——避弹 AI 测试用）
				GameGlobals.ai_slow_debug = not GameGlobals.ai_slow_debug
				_debug_used = true
				_update_hud_debug_labels()
				enemy_time_scale = 1.0
				print("【调试】AI 慢速（敌侧 0.25 倍）：%s" % ("开" if GameGlobals.ai_slow_debug else "关"))
			KEY_ENTER:
				if Input.is_physical_key_pressed(KEY_CTRL):
					## 【策划：完全接管】Ctrl+Enter 第一次=瞬间暂停+提示选框
					_takeover_pending = true
					pause_panel.visible = true
					_takeover_label.visible = true
				elif _takeover_pending:
					## 再按 Enter：解除暂停并进入接管
					_takeover_pending = false
					take_over = true
					pause_panel.visible = false
					_takeover_label.visible = false
				elif take_over:
					take_over = false ## 持续接管中按 Enter=解除
			KEY_ESCAPE:
				if _takeover_pending:
					_takeover_pending = false
					pause_panel.visible = false
					_takeover_label.visible = false
				elif take_over:
					take_over = false
			KEY_R:
				## 【N3 修复】结束后 R=重开（原第二分支不可达）；进行中才增援
				if finished:
					get_tree().reload_current_scene()
				elif Input.is_physical_key_pressed(KEY_SHIFT):
					pass ## Shift+R=选中角色立即补充杂兵（角色指令，走面板选中）
				else:
					_reinforce_all() ## 团队增援
			KEY_T:
				auto_reinforce = not auto_reinforce
			KEY_C:
				if Input.is_physical_key_pressed(KEY_CTRL):
					team_stance = "" ## Ctrl+C 取消全部指令
			KEY_A:
				## 【批复 2026-10-13·轮换】边界处长按 A = 原地对换角色（选中者↔队伍下一名）
				if Input.is_physical_key_pressed(KEY_A):
					_swap_selected_character()
			KEY_S:
				if Input.is_physical_key_pressed(KEY_SHIFT):
					if surrender_sent and surrender_phase:
						pass ## 已同意
					elif surrender_sent:
						_surrender_accepted() ## 对方AI立即同意（策划）
						print("[投降] 对方同意 → 1秒后结算")
					else:
						surrender_sent = true
						print("[投降] 请求已发送（Shift+W 撤销；对方AI将立即同意）")
			KEY_W:
				if Input.is_physical_key_pressed(KEY_SHIFT):
					if surrender_sent and not surrender_phase:
						surrender_sent = false
						print("[投降] 请求已撤销")
			KEY_H:
				if not finished:
					_sanae_skill() ## 早苗技能：按当前态势自动选神（批复：玩家不能选）
			KEY_G:
				## 【N7】G 指令仅在选人后生效，避免对局中被空按打断
				if not finished and picked_entity() != null:
					_cmd_arm_g = true
			KEY_F3: ## 测试开关：DDM/热力图叠层（开/关切换）
				ddm_debug_layer.visible = not ddm_debug_layer.visible
				if _ddm_sprite != null:
					_ddm_sprite.visible = ddm_debug_layer.visible
				if _ht_sprite != null:
					_ht_sprite.visible = ddm_debug_layer.visible
			KEY_Z:
				## 【弹幕显示浮窗的再定义（作者批复 2026-10-02）】试炼场中按 Z =
				## 让窗口中的角色释放当前验证的单个弹幕事件（非唤出浮窗）。
				if is_preview and not finished:
					var ev := _find_event(GameGlobals.preview_event_name)
					if ev != null and player_leader != null and not player_leader.dead:
						_spawn_bullet(ev, player_leader.position, 0, player_leader, null)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	_build_side_panels()
	## 右上角帧率（作者批复）
	fps_label = Label.new()
	fps_label.anchor_left = 1.0
	fps_label.anchor_right = 1.0
	fps_label.offset_left = -150
	fps_label.offset_right = -6
	fps_label.offset_top = 4
	fps_label.add_theme_font_size_override("font_size", 13)
	hud.add_child(fps_label)
	info_label = Label.new()
	info_label.position = Vector2(8, 4)
	_heat_label = Label.new()
	_heat_label.position = Vector2(8, 24)
	_heat_label.add_theme_font_size_override("font_size", 13)
	_heat_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	_heat_label.text = "热力图：关"
	_debug_hint_label = Label.new()
	_debug_hint_label.position = Vector2(8, 386)
	_debug_hint_label.add_theme_font_size_override("font_size", 11)
	_debug_hint_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_debug_hint_label.text = ""
	info_label.add_theme_font_size_override("font_size", 13)
	hud.add_child(info_label)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	center.add_child(stack)
	banner = Label.new()
	banner.visible = false
	banner.add_theme_font_size_override("font_size", 28)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(banner)
	pause_panel = _build_pause_panel()
	stack.add_child(pause_panel)

func _toggle_pause() -> void:
	pause_panel.visible = not pause_panel.visible

func _on_pause_btn(p: PanelContainer, txt: String) -> void:
	match txt:
		"继续":
			p.visible = false
			_fps_pause_dismissed = true ## 玩家选择继续 → 本场不再自动暂停（作者批复）
		"重新开始":
			get_tree().reload_current_scene()
		"返回标题":
			GameGlobals.goto_scene("res://scenes/title_menu.tscn")

func _build_pause_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	p.add_child(box)
	var title := Label.new()
	title.text = "暂停（界面暂停 = 双方冻结）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_takeover_label = Label.new()
	_takeover_label.text = "完全接管：再按 Enter 开始控制（方向键移动 z射击 x能力 c符卡 x+c主要符卡 Shift慢机）
Esc 取消"
	_takeover_label.visible = false
	_takeover_label.modulate = Color(0.7, 0.9, 1.0)
	box.add_child(_takeover_label)
	_perf_notice = Label.new()
	_perf_notice.text = "帧率低于 20，已因性能自动暂停
（选择继续后本场不再自动暂停）"
	_perf_notice.modulate = Color(1, 0.5, 0.4)
	_perf_notice.visible = false
	_perf_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_perf_notice)
	for txt in ["继续", "重新开始", "返回标题"]:
		var btn := Button.new()
		btn.text = txt
		btn.pressed.connect(_on_pause_btn.bind(p, txt))
		box.add_child(btn)
	var hint := Label.new()
	hint.text = "移动:WASD　Shift:快机(演示)　V:轮射↔齐射　F3:DDM图　Esc:暂停"
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	return p

func _refresh_hud() -> void:
	if time_frames % 6 != 0: ## 【20261003】HUD 10Hz（拼串+两轮实体扫描移出每帧）
		return
	var volley := "轮射" if GameGlobals.versus_volley == "rotate" else "齐射"
	var phase_name: String = {1: "远距压制", 2: "短兵", 3: "破阵", 4: "撤离"}.get(phase, "?")
	var p_alive := 0
	var p_priv := 0
	for e in player_ents:
		if not e.dead:
			p_alive += 1
	for e in entities:
		if e is BattleEntity and e.side == 0 and e.kind == BattleEntity.Kind.PRIVATE and not e.dead:
			p_priv += 1
	var e_alive := 0
	var e_priv := 0
	for e in enemy_ents:
		if not e.dead:
			e_alive += 1
	for e in entities:
		if e is BattleEntity and e.side == 1 and e.kind == BattleEntity.Kind.PRIVATE and not e.dead:
			e_priv += 1
	var gpu_txt := "GPU-DDM✓" if gpu_ok else "哈希降级"
	var mode_txt := ("试炼场:%s" % GameGlobals.preview_event_name) if is_preview else "自定义对战"
	info_label.text = "%s | %s | %s | t=%.1fs 弹幕=%d %s\n我方 角色%d+杂兵%d  敌方 角色%d+杂兵%d" % [
		mode_txt, volley, phase_name, float(time_frames) / 60.0, bullets.size(), gpu_txt,
		p_alive, p_priv, e_alive, e_priv]
	if player_leader != null:
		info_label.text += "\n领队 %s AP%d HP 武%d/僚%d/机%d P%d 符%d(+%d)" % [
			player_leader.chara_name(), player_leader.ap,
			player_leader.hp[0], player_leader.hp[1], player_leader.hp[2],
			player_leader.pp, player_leader.spell_cards, player_leader.spell_received]
	## ——右上帧率（自测：上一秒实际帧数；监控器 EMA 被启动尖峰污染不可用）——
	if fps_label != null:
		fps_label.text = "FPS %.1f
弹幕 %d" % [_fps_measured, bullets.size()]
		fps_label.modulate = Color(1, 0.35, 0.3) if _fps_measured < 59.8 else Color(0.8, 1, 0.8)
	## 【批复】<20 帧：自动暂停并解释；玩家继续后本场不再自动暂停
	## 【修复 2026-10-13】暖机豁免：启动期着色器编译的帧率骤降不触发自动暂停
	## ——此前开局即冻结（tf 卡在 66）正是该误触发：作者看到的"弹幕原地消失"
	## 实为游戏被自动暂停冻结。条件：运行 >10 秒 且 连续 2 秒 <20 帧才触发
	if _fps_measured < 20.0 and time_frames > 600 and not finished 			and not _fps_pause_dismissed and not pause_panel.visible:
		_lowfps_secs += 1
		if _lowfps_secs >= 2:
			pause_panel.visible = true
			if _perf_notice != null:
				_perf_notice.visible = true
	else:
		_lowfps_secs = 0
	## 【修复 20261004】状态卡片调用点在历次编辑中丢失（只剩定义）→ 面板永不填充
	## ——作者"角色卡没看见"的直接根因；两块面板每 HUD 拍（10Hz）增量刷新
	_refresh_side_panel(left_panel, player_ents, Color(0.75, 0.85, 1.0))
	_refresh_side_panel(right_panel, enemy_ents, Color(1.0, 0.8, 0.75))
	if ddm_debug_layer != null and ddm_debug_layer.visible and not ht_side.is_empty() and ht_side[0] != null:
		info_label.text += "\n[十六点性能检测] %s" % ht_side[0].stats_line()

## =============================================================
## 绘制（painters 回调）
## =============================================================
func draw_entities(onto: CanvasItem) -> void:
	for ent in entities:
		if ent is not BattleEntity or ent == emitter_ent:
			continue
		var col := Color(0.35, 0.65, 1.0) if ent.side == 0 else Color(1.0, 0.35, 0.3)
		if ent.kind == BattleEntity.Kind.PRIVATE:
			col = col.lerp(Color(0.7, 0.7, 0.7), 0.5) ## 杂兵淡化
			if ent.is_elite_private:
				col = Color(1.0, 0.85, 0.2) ## 较强杂兵金色
		if ent.dead:
			col = Color(0.4, 0.4, 0.4)
		var r: float = ent.judge_radius()
		onto.draw_arc(ent.position, r, 0, TAU, 16, col, 1.0)
		## 【朝向指示（批复 20261019）】局部帧 y 轴=角色朝向——贴图实装前以
		## 前向刻线可视（未来贴图旋转角 = facing.angle()+π/2，纹理上方对朝向）
		## 【批复 20261020】朝向仅角色：杂兵无朝向概念，不画刻线
		if ent.kind != BattleEntity.Kind.PRIVATE:
			onto.draw_line(ent.position, ent.position + ent.facing * (r + 7.0), col, 1.5)
		if ent.ap > 0 and ent.kind != BattleEntity.Kind.PRIVATE:
			onto.draw_arc(ent.position, ent.barrier_radius(), 0, TAU, 24, col.darkened(0.4), 1.0)
		if ent.is_player:
			onto.draw_arc(ent.position, 6.0, 0, TAU, 16, Color.WHITE, 0.5)
		if _show_pick and ent == picked_entity():
			onto.draw_arc(ent.position, r + 4.0, 0, TAU, 24, Color(1, 0.95, 0.4), 1.5)
		## 【批复】消弹范围圆形指示（透明度随剩余时间衰减）
		if ent.clear_active():
			var ca: float = clampf(float(ent.clear_frames) / 60.0, 0.15, 0.6)
			onto.draw_circle(ent.position, ent.clear_radius, Color(0.4, 0.8, 1.0, ca * 0.18))
			onto.draw_arc(ent.position, ent.clear_radius, 0, TAU, 48, Color(0.4, 0.8, 1.0, ca), 1.5)
	## P点/符卡掉落物绘制（材质 pp.PNG/spell.PNG；闪烁提示将消失）
	for d in drops:
		if d["tex"] == null:
			continue
		var blink := 1.0 if d["frames"] > 300 else (0.4 + 0.6 * absf(sin(float(d["frames"]) * 0.2)))
		var dtex: Texture2D = d["tex"]
		onto.draw_texture_rect(dtex, Rect2(d["pos"] - dtex.get_size() * 0.5, dtex.get_size()), false, Color(1, 1, 1, blink))
	## 【Hcs/Hct 可视化 20261020】F3 第8/9档：选中角色 49 点热度点阵；
	## Hcs 档 [ ] 键切换查阅目标时间后的帧（轨迹前瞻长度即时重算）；
	## Hct 档红叉标注热力施加点（与 Hcs 弹幕重合的采样点）
	if _show_hcs_view():
		var ent8 := picked_entity()
		if ent8 != null and (ent8.hcs_pts.size() >= 49 or ent8.hct_pts.size() >= 49):
			var n_spd := ent8.normal_speed()
			var spin8 := TAU / 32.0 * float(time_frames % 2)
			for k in 49:
				var rr8 := n_spd * (6.0 if k < 16 else (12.0 if k < 32 else 30.0))
				var p8: Vector2
				if k == 48:
					p8 = ent8.position
				else:
					var a8 := spin8 - PI / 2.0 + TAU * float(k % 16) / 16.0
					p8 = ent8.position + Vector2(cos(a8), sin(a8)) * rr8
				var v: float = ent8.hcs_pts[k] if _heat_view == 7 else ent8.hct_pts[k]
				if v <= 0.5:
					continue
				var c8 := Color(1, 1 - v / 255.0, 0, 0.5)
				onto.draw_circle(p8, 3.0, c8)
				if _heat_view == 8 and ent8.hcs_pts[k] > 0.5:
					## 红叉=热力施加点（与 Hcs 弹幕重合的采样点）
					var x8 := 4.0
					onto.draw_line(p8 - Vector2(x8, x8), p8 + Vector2(x8, x8), Color(1, 0, 0, 0.8), 1.2)
					onto.draw_line(p8 - Vector2(x8, -x8), p8 + Vector2(x8, -x8), Color(1, 0, 0, 0.8), 1.2)
	## 机控指令圈绘制（255 衰减白色引力圈）
	if cmd_frames > 0:
		onto.draw_arc(cmd_point, 40.0, 0, TAU, 32, Color(1, 1, 1, 0.5 * float(cmd_frames) / 300.0), 1.5)
		onto.draw_arc(cmd_point, 20.0, 0, TAU, 24, Color(1, 1, 1, 0.3 * float(cmd_frames) / 300.0), 1.0)
	## —— 态势十六点监视（F3 开启时；策划：0.1/0.2秒距圆也是给玩家的UI信息）——
	if _show_sit16:
		_draw_sit16(onto)

## 十六点采样监视：双圈 + 各采样点按热度着色（0黑→255红）+带转偏移可视化
func _draw_sit16(onto: CanvasItem) -> void:
	for ent in _sample_entities:
		var ent2: BattleEntity = ent
		if ent2.dead:
			continue
		var n := ent2.normal_speed()
		var r1 := n * 6.0
		var r2 := n * 12.0
		onto.draw_arc(ent2.position, r1, 0, TAU, 32, Color(1, 1, 1, 0.25), 1.0)
		onto.draw_arc(ent2.position, r2, 0, TAU, 32, Color(1, 1, 1, 0.15), 1.0)
		var spin := TAU / 32.0 * float(time_frames % 2)
		var r3 := n * 30.0
		onto.draw_arc(ent2.position, r3, 0, TAU, 40, Color(1, 1, 1, 0.08), 1.0)
		for k in 16:
			var a := spin - PI / 2.0 + TAU * float(k) / 16.0
			var dv := Vector2(cos(a), sin(a))
			var v1: int = ent2.sit16_1d[k] if k < ent2.sit16_1d.size() else 0
			var v2: int = ent2.sit16_2d[k] if k < ent2.sit16_2d.size() else 0
			var v3: int = ent2.sit16_5d[k] if k < ent2.sit16_5d.size() else 0
			onto.draw_circle(ent2.position + dv * r1, 1.6, Color(v1 / 255.0, 0.2, 0.2, 0.9))
			onto.draw_circle(ent2.position + dv * r2, 1.6, Color(v2 / 255.0, 0.4, 0.1, 0.7))
			onto.draw_circle(ent2.position + dv * r3, 1.6, Color(v3 / 255.0, 0.5, 0.1, 0.5))

## 弹幕绘制：MultiMesh 批量（1 draw call/材质组）+ 激光线段
## 【性能】MM 容量预分配为 MAX_BULLETS，每帧只设 instance_count，
##   不重建/重分配 mesh——避免每帧 ArrayMesh 创建开销
func draw_bullets(onto: CanvasItem) -> void:
	## 激光（线段集合，数量少直接 draw_line）
	## 【法弹隐形（作者批复 2026-10-02）】我方法弹（含激光）不渲染弹幕本体：
	##   激光只以纯白半透明细线显示（=其"轨道"），敌方激光正常彩色渲染。
	for b in bullets:
		var bl: Bullet = b
		if bl.hidden_now or bl.ev.tag != DanmakuEventData.TAG_LASER:
			continue
		if not _laser_in_field(bl):
			continue
		var own_side_invis: bool = bl.source_side == 0 and not bl.ev.is_phy
		var c := bl.modulate_color()
		c.a = bl.current_alpha_01()
		var w := bl.laser_width() * 2.0
		if bl.t <= bl.alarm_now:
			w *= 0.3
			c.a *= bl.ev.alarm_shader_alpha
		if own_side_invis:
			c = Color(1, 1, 1, 0.3) ## 纯白半透明轨道
			w = 1.5
		for i in bl.laser_samples.size() - 1:
			onto.draw_line(bl.laser_samples[i], bl.laser_samples[i + 1], c, w)
	## 我方法弹的白色前向粒子轨道（只有轨道、没有弹幕本体；敌方法弹同物弹正常显示）
	for b in bullets:
		var bl: Bullet = b
		if bl.hidden_now or bl.ev.tag == DanmakuEventData.TAG_LASER:
			continue
		if bl.source_side == 0 and not bl.ev.is_phy:
			if _in_field(bl.pos):
				var tlen := maxf(8.0, bl.track_speed * 12.0) ## 0.2秒距基准
				onto.draw_line(bl.pos, bl.pos + bl.track_dir * tlen, Color(1, 1, 1, 0.3), 2.0)

## 两侧角色数据面板（左友右敌：HP/P点/符卡/AP）
func _build_side_panels() -> void:
	left_panel = VBoxContainer.new()
	left_panel.anchor_left = 0.0
	left_panel.anchor_right = 0.0
	left_panel.anchor_top = 0.0
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 4
	left_panel.offset_right = SIDE_PANEL_W - 4
	left_panel.offset_top = HUD_RESERVE + 4
	left_panel.offset_bottom = -4
	left_panel.add_theme_constant_override("separation", 6)
	hud.add_child(left_panel)
	right_panel = VBoxContainer.new()
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_top = 0.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -(SIDE_PANEL_W - 4)
	right_panel.offset_right = -4
	right_panel.offset_top = HUD_RESERVE + 4
	right_panel.offset_bottom = -4
	right_panel.add_theme_constant_override("separation", 6)
	hud.add_child(right_panel)

## 角色状态卡片面板（左友右敌）：
##   【缓存版 20261004】旧实现每 0.1s 整树重建（3200 节点/秒 churn）→
##   现按角色名册签名缓存条目，刷新只改 文本/颜色/选中高亮。
##   条目 = 名字/HP/AP/P/符卡/攻击状态 按钮 + 态势卡彩虹线（30 色块）。
var _panel_cache: Dictionary = {} ## panel -> {key:String, entries:Array[{ent,btn,rects}]}

func _refresh_side_panel(panel: VBoxContainer, ents: Array, accent: Color) -> void:
	if panel == null:
		return
	var chars: Array = []
	for e in ents:
		if e is BattleEntity and e.kind != BattleEntity.Kind.PRIVATE:
			chars.append(e)
	var key := ""
	for e in chars:
		key += "%d," % e.get_instance_id()
	var cache: Dictionary = _panel_cache.get(panel, {})
	if cache.is_empty() or cache.get("key", "") != key:
		for c in panel.get_children():
			c.queue_free()
		cache = {"key": key, "entries": []}
		for ent in chars:
			var btn := Button.new()
			btn.flat = true
			btn.add_theme_font_size_override("font_size", 12)
			var side := 0 if panel == left_panel else 1
			btn.pressed.connect(func():
				_pick_side = side
				var idx := 0
				for e2 in chars:
					if e2 == ent:
						break
					idx += 1
				_pick_idx = idx
				_show_pick = true)
			panel.add_child(btn)
			var strip := HBoxContainer.new()
			panel.add_child(strip)
			var rects: Array = []
			for i in 30:
				var cr := ColorRect.new()
				cr.custom_minimum_size = Vector2(3, 8)
				strip.add_child(cr)
				rects.append(cr)
			cache["entries"].append({"ent": ent, "btn": btn, "rects": rects})
		_panel_cache[panel] = cache
	## 增量刷新（文本/颜色/高亮/彩虹）
	var stance_map: Dictionary = {"": "自动", "attack": "进攻姿态", "defend": "保守姿态", "side": "侧面姿态", "rash": "冒进", "turtle": "龟缩"}
	var volley: String = stance_map.get(team_stance, "自动")
	for e in cache["entries"]:
		var ent: BattleEntity = e["ent"]
		var btn: Button = e["btn"]
		if ent.dead:
			btn.text = "%s
满目疮痍" % ent.chara_name()
			btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.text = "%s
HP %d/%d/%d AP%d
P%d 符%d [%s]
心情:%s" % [
				ent.chara_name(), ent.hp[0], ent.hp[1], ent.hp[2],
				ent.ap, ent.pp, ent.spell_cards, volley, ent.mood()]
			btn.modulate = accent
			if ent == picked_entity():
				btn.modulate = Color(1.0, 0.95, 0.4)
		if ent.sit_cards != null:
			var rects: Array = e["rects"]
			for i in mini(30, rects.size()):
				if i < ent.sit_cards.ring.size():
					rects[i].color = SIT_COLORS.get(ent.sit_cards.ring[i], Color.WHITE)

## 当前选中实体（面板点击；未选=各侧领队）
func picked_entity() -> BattleEntity:
	var arr := player_ents if _pick_side == 0 else enemy_ents
	var chars: Array = []
	for e in arr:
		if e is BattleEntity and e.kind != BattleEntity.Kind.PRIVATE:
			chars.append(e)
	if chars.is_empty():
		return null
	return chars[mini(_pick_idx, chars.size() - 1)]

## 【批复】场地 400×400 外裁剪：越界弹幕不进渲染批（出界即隐，入界即现）
func _in_field(p: Vector2, margin: float = 24.0) -> bool:
	return p.x > -margin and p.x < 400.0 + margin and p.y > -margin and p.y < 400.0 + margin

## 激光：任一采样点入界即画（整条出界才裁）
func _laser_in_field(bl: Bullet) -> bool:
	for pt in bl.laser_samples:
		if _in_field(pt, 40.0):
			return true
	return false

## MultiMesh 粒子弹幕绘制（独立 painter，挂 bullet_tint.gdshader 做 HS 上色；
## 本函数内不画线——draw_line 不该吃上色材质）
## 【P5 修复 20261015】by_tex 改成员字典复用（原每帧新建大字典）；modulate_color
## 每弹每帧 3 次 → 1 次（bullet_runtime 颜色缓存命中间隔内已零成本）
var _by_tex: Dictionary = {}
func draw_bullet_mm(onto: CanvasItem) -> void:
	_by_tex.clear()
	for b in bullets:
		var bl: Bullet = b
		if bl.hidden_now or bl.ev.tag == DanmakuEventData.TAG_LASER:
			continue
		if not _in_field(bl.pos):
			continue
		## 我方法弹不渲染材质（作者批复：防止玩家对己方法弹过多反应）
		if bl.source_side == 0 and not bl.ev.is_phy:
			continue
		if not _by_tex.has(bl.tex):
			_by_tex[bl.tex] = []
		_by_tex[bl.tex].append(bl)
	for tex in _by_tex:
		var list: Array = _by_tex[tex]
		var mm := _get_mm(tex)
		if mm == null:
			continue
		var cnt := list.size()
		if cnt > mm.instance_count:
			mm.instance_count = cnt ## 仅在数量增长时扩容（会重置缓冲，随后全量写）
		for i in cnt:
			var bl: Bullet = list[i]
			var xf := Transform2D(bl.draw_rotation(), bl.pos)
			xf = xf.scaled_local(Vector2(bl.size_mul, bl.size_mul))
			mm.set_instance_transform_2d(i, xf)
			var mc: Color = bl.modulate_color()
			## 【近弹增显 20261026（作者 0.0.8 点子）】参与 DDM（pass 否）的弹幕
			## 靠近角色时 对比度/不透明度 += 2560/d（d=到最近角色距离，神灵庙式近弹提示）
			var alpha_extra := 0.0
			var sat_extra := 0.0
			if not bl.ev.pass_cond.is_empty() or true:
				## pass 为否=正常注册 DDM（pass 空即否）；距离取双侧最近角色
				var dmin := 99999.0
				for e2 in entities:
					if e2 is BattleEntity and not e2.dead:
						var d2: float = e2.position.distance_to(bl.pos)
						if d2 < dmin:
							dmin = d2
				if dmin < 40.0: ## 生效圈：40px 内渐显（d>40 无增显）
					var boost: float = 2560.0 / maxf(dmin, 4.0)
					sat_extra = boost
					alpha_extra = clampf(boost, 0.0, 1.0)
			var a_final: float = clampf(bl.current_alpha_01() + alpha_extra, 0.0, 1.0)
			var mc2 := mc
			if sat_extra > 0.0:
				mc2.v = clampf(mc2.v + sat_extra / 256.0, 0.0, 1.0) ## 对比度亮度端增显
			mm.set_instance_color(i, Color(mc2.r, mc2.g, mc2.b, a_final))
		## 缩容时只把"多出来的"实例挪到屏外一次（增量停靠）——
		## 旧版（注释备查）：每帧把 [cnt, instance_count) 全部重写，
		## 弹幕数波动时每帧多达成百上千次 set_instance_transform_2d。
		if cnt < _mm_last_cnt.get(tex, 0):
			for i in range(cnt, _mm_last_cnt[tex]):
				mm.set_instance_transform_2d(i, Transform2D(0, Vector2(-9999, -9999)))
		_mm_last_cnt[tex] = cnt
		onto.draw_multimesh(mm, tex)

## MultiMesh 缓存（材质 → MM 实例池）+ 每材质上一帧实例数（增量停靠用）
var _mm_cache: Dictionary = {}
var _mm_last_cnt: Dictionary = {}
func _get_mm(tex: Texture2D) -> MultiMesh:
	if _mm_cache.has(tex):
		return _mm_cache[tex]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.instance_count = 0
	mm.mesh = _quad_mesh(tex)
	_mm_cache[tex] = mm
	return mm

func _quad_mesh(tex: Texture2D) -> Mesh:
	## 单位四边形（中心原点；实例变换含尺寸/旋转/位置）
	## 【修复：弹幕被刷成纯色圆】旧实现用 SurfaceTool + Vector3 顶点提交，
	##   在 canvas draw_multimesh 路径下 UV 未被采到 → 整面平涂实例色；
	##   改为 2D 规范的 PackedVector2Array 顶点 + ARRAY_TEX_UV 显式建面。
	var sz: Vector2 = tex.get_size() if tex != null else Vector2(16, 16)
	var h := sz * 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## DDM 调试图（F3）+ Ht 热力图显示（扩展调试；作者批复#6：玩家也得用）
## 【DDM 60帧（作者批复 2026-10-02）】主设备 Texture2DRD 零拷贝 → 每帧换引用；
## 旧实现（注释备查）：每10帧 queue_free 重建 Sprite（Texture2DRD 不可用时代的
## 回读节流方案），以及随后一版 10Hz 回读——均已被零拷贝取代。
func draw_ddm_debug(onto: CanvasItem) -> void:
	if gpu_ok:
		if _ddm_sprite == null:
			_ddm_sprite = Sprite2D.new()
			_ddm_sprite.position = Vector2(200, 200)
			_ddm_sprite.modulate = Color(1, 0, 1, 0.3)
			world.add_child(_ddm_sprite)
		## 【F1 热力图浏览器（作者批复）】_heat_view: 1=Ht 2=Hv；[切方 滚轮切角色 ]切帧
		var view_side: int = _heat_view_side
		if _heat_view == 1:
			if _ddm_sprite == null:
				_ddm_sprite = Sprite2D.new()
				_ddm_sprite.position = Vector2(200, 200)
				world.add_child(_ddm_sprite)
			_ddm_sprite.visible = true
			_ddm_sprite.modulate = Color(1, 0, 1, 0.3)
			_ddm_sprite.texture = ddm_gpu1.get_display_texture()
			if _ht_sprite == null:
				_ht_sprite = Sprite2D.new()
				_ht_sprite.position = Vector2(200, 200)
				_ht_sprite.modulate = Color(0.2, 1, 0.4, 0.35)
				world.add_child(_ht_sprite)
			_ht_sprite.visible = true
			_ht_sprite.texture = ht_side[view_side].display_texture()
		elif _heat_view == 2:
			var hv = hv_side[view_side] if view_side < hv_side.size() else null
			if hv != null and hv.ok:
				if _ht_sprite == null:
					_ht_sprite = Sprite2D.new()
					_ht_sprite.position = Vector2(200, 200)
					world.add_child(_ht_sprite)
				_ht_sprite.visible = true
				_ht_sprite.modulate = Color(1, 1, 1, 0.6) ## Hv 彩虹已烘焙（红升蓝降）
				_ht_sprite.texture = hv.display_texture()
			if _ddm_sprite != null:
				_ddm_sprite.visible = false
		elif _heat_view >= 3 and fam_maps != null and fam_maps.ok:
			## 【③期收官】期望系：3=He 4=Hd 5=Hr 6=Hp（[ 键切方；每侧一张威胁图）
			var fam_name: String = ["He", "Hd", "Hr", "Hp"][mini(_heat_view - 3, 3)] + str(view_side)
			var fam_tex := fam_maps.display(fam_name)
			if fam_tex != null:
				if _ht_sprite == null:
					_ht_sprite = Sprite2D.new()
					_ht_sprite.position = Vector2(200, 200)
					world.add_child(_ht_sprite)
				_ht_sprite.visible = true
				_ht_sprite.modulate = Color(1, 1, 1, 0.55)
				_ht_sprite.texture = fam_tex
			if _ddm_sprite != null:
				_ddm_sprite.visible = false
		else:
			if _ddm_sprite != null:
				_ddm_sprite.visible = false
			if _ht_sprite != null:
				_ht_sprite.visible = false
	else:
		for b in bullets:
			var bl: Bullet = b
			if bl.hidden_now:
				continue
			onto.draw_circle(bl.pos, bl.draw_radius, Color(1, 0, 1, 0.15))
