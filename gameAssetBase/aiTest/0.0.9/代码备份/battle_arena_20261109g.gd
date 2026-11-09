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
const MAX_BULLETS := 8000 ## 性能护栏（超出批量驱逐最旧；0.0.9 C++ 化后性能余量提升）

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
var _sample_n := 1 ## 【采样平滑】1=关（逐帧）；2-5=每 N 帧采样+插值
## —— 【0.0.9·审计 Top2 20261108】bullet_hash C++ 接线（对照开关）——
## C++ 管 32px 格构建+粗查询（省 GD 格循环）；GD 端 per-hit 成员判定
## （skip_source/beyond_mask/dmg 组装——语义与纯 GD 完全一致）
var bullet_hash_cpp: Th75BulletHashCpp = null
var bullet_hash_cpp_enabled := true
var hcs_cpp_enabled := true ## 【审计 B2】Hcs/Hct C++ 快路径（对照开关）
var bc_enabled := true ## 【0.0.9·新三 BC】基础规避层（对照开关；false=回退旧移动）
## 【0.0.9·哈希映射修复 20261109】C++ 哈希 query 返回的是**插入序号**（ref_id 参数
## 从未被存储）——第三十五轮接线时 GD 侧误当 bullets 下标用（bullets[rid]）：
## 主循环倒序插入且跳过死/隐弹，插入序号≠数组下标→被弹/对撞全部判到
## 错误的弹上（所见即所判违背，1108k 起）。此表按插入序记录对象，
## 同时免疫帧内 swap-remove 搬移（对象引用不随下标变化）。
var _hash_objs: Array = []
var motion_hot: Th75MotionHot = null ## 【审计 Top2】slot 制 frozen 位置追踪
var _phys_acc := 0.0 ## 【渲染帧驱动】物理节流累加器（16.6ms 上限锁 60/s）
var _expired_count := 0
var _retired_count := 0 ## 【census 探针】累计回收入池          ## 航程到期消失计数（调试：区分"原地消失"来源）
var _cleared_count := 0          ## 释放消弹计数
var contour: ContourField = null ## 【0.0.9·等高线（策划新三 52-68）】Hd/Hr 矢量等高线+动画序列
## —— 【0.0.9·加载屏】开局预热分帧执行（作者批："开始前多花一些时间，
## 甚至若干秒来加载"——初始化/缓存全部挪进加载期，对局零冷启动）——
var _loading := true
var _load_tasks: Array = []      ## 每项 Callable（每物理帧执行一个）
var _loading_layer: ColorRect = null
var _loading_label: Label = null

func _build_loading_screen() -> void:
	_loading_layer = ColorRect.new()
	_loading_layer.color = Color(0.02, 0.03, 0.06, 0.92)
	_loading_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_loading_layer)
	_loading_label = Label.new()
	_loading_label.text = "少女祈祷中……" ## 作者指定文案（右下角）
	_loading_label.anchor_left = 1.0
	_loading_label.anchor_right = 1.0
	_loading_label.anchor_top = 1.0
	_loading_label.anchor_bottom = 1.0
	_loading_label.offset_left = -220
	_loading_label.offset_right = -12
	_loading_label.offset_top = -46
	_loading_label.offset_bottom = -12
	_loading_label.add_theme_font_size_override("font_size", 17)
	_loading_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.95, 0.9))
	hud.add_child(_loading_label)

func _build_load_tasks() -> void:
	_load_tasks.clear()
	_load_tasks.append(_warmup_textures)
	## setup 干跑按事件拆帧（单事件 ~2-8ms，加载屏期间逐事件预热）
	var world := self
	var done_ev := {}
	var ev_list: Array = []
	for fc in fire_controls:
		if fc.entity == null:
			continue
		for p in fc.weapon_points + fc.sub_points:
			for ev in p.events:
				if ev == null or done_ev.has(ev.event_name):
					continue
				done_ev[ev.event_name] = true
				ev_list.append([ev, fc.entity])
	for pr in _priv_shooters:
		for ev in pr.get("evs", []):
			if ev == null or done_ev.has(ev.event_name):
				continue
			done_ev[ev.event_name] = true
			ev_list.append([ev, null])
	for item in ev_list:
		var ev_i: DanmakuEventData = item[0]
		var ent_i = item[1]
		_load_tasks.append(func():
			var b := Bullet.new()
			b.tex_slot = 0
			b.setup(ev_i, Vector2(-999, -999), ent_i.side if ent_i != null else 0, ent_i, world, 0, {})
			b.tex_slot = _ddm_tex_slot(b.tex)
			if b.tex_slot > 0:
				_upload_ddm_tex(b.tex_slot, b.tex))
	_load_tasks.append(_warmup_hp)
	## GPU 管线首编译空跑（DDM/Ht/Hv/fam 全链一次提交——shader 编译挪进加载期）
	_load_tasks.append(func():
		if gpu_ok:
			ddm_gpu0.render(PackedFloat32Array())
			ddm_gpu1.render(PackedFloat32Array())
			for h in ht_side:
				if h != null and h.ok:
					h.step()
			for hv in hv_side:
				if hv != null and hv.ok:
					hv.step()
			if fam_maps != null and fam_maps.ok:
				fam_maps.advance_batch([[0, PackedFloat32Array()], [1, PackedFloat32Array()]]))
	_load_tasks.append(func():
		## 【采样平滑预热（作者要求：初始化完成）】N>1 时干跑一次平滑路径
		if _sample_n > 1 and not bullets.is_empty():
			var b0: Bullet = bullets[0]
			b0._pos_prev = b0.pos
			b0._pos_target = b0.pos
			b0.update_smooth(_sample_n)
		_finish_loading())

func _run_load_step() -> void:
	if _load_tasks.is_empty():
		_finish_loading()
		return
	var task: Callable = _load_tasks.pop_front()
	task.call()

func _finish_loading() -> void:
	_loading = false
	if _loading_layer != null:
		_loading_layer.queue_free()
		_loading_layer = null
	if _loading_label != null:
		_loading_label.queue_free()
		_loading_label = null

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
## 【尖峰放慢 20261031（作者批准）】fps<30 → Engine.time_scale=0.5（类时之魔珠
## 整体放慢；物理 tick 频率不变，不改刷新频率）。恢复：fps≥50 或 120 帧后；冷却 300 帧
var _slowmo_until_frame := 0
var _slow_lo := 0 ## 分段计数：<10fps 连续帧
var _slow_mid := 0 ## 分段计数：<30fps 连续帧
var _slowmo_cd := 0
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
var ddm_debug_layer: Node2D
var _ht_sprite: Sprite2D = null

func _ready() -> void:
	is_preview = (GameGlobals.arena_mode == "preview")
	var usable := float(DisplayServer.window_get_size().y) - float(HUD_RESERVE)
	SCALE = maxf(1.0, floor(usable / float(LOGICAL)))
	_init_gpu()
	_build_world()
	_build_hud()
	_sample_n = GameGlobals.bullet_sample_n ## 【采样平滑】进战前锁定（初始化完成）
	## 【0.0.9·物理驱动模式（作者批 20261108）】默认=渲染帧驱动（工作期调试同款：
	## set_physics_process(false)+每渲染帧手动调恰一次——引擎 catch-up 多 tick
	## 积压雪崩免疫）；旧弹幕模式（标题勾选·重启生效）=引擎调度原状
	if not GameGlobals.bullet_legacy_physics:
		set_physics_process(false)
	## 【0.0.9·加载屏预热（作者批 20261107）】原三段 warmup 在首帧内同步跑完
	## =默认决斗开局卡顿元凶；现改为分帧任务队列+加载屏（右下"少女祈祷中……"）
	_build_loading_screen()
	_build_load_tasks()
	if is_preview:
		_preview_probe_args() ## 【0.0.9·可变探针（作者批 20261105）】启动参数选中事件
		_setup_preview()
	else:
		_setup_versus()

## 【0.0.9·可变探针（作者批 20261105）】试炼场预览启动时按消息/测试要求
## 选中特定弹幕：命令行用户参数（godot ... -- event=事件名 [seed=N] [emit=秒]）
## 覆盖 preview_event_name——供 headless 探针与作者定向复现同一入口。
func _preview_probe_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("event="):
			GameGlobals.preview_event_name = a.substr(6).strip_edges()
			print("[可变探针] 事件=%s" % GameGlobals.preview_event_name)
		elif a.begins_with("seed="):
			seed(int(a.substr(5)))
			print("[可变探针] 随机种子=%s" % a.substr(5))
		elif a.begins_with("emit="):
			preview_emit_interval = float(a.substr(5))
			print("[可变探针] 发射间隔=%s 秒" % a.substr(5))

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
	if gpu_ok and fam_maps != null:
		contour = ContourField.new(shared_rd, fam_maps) ## 【0.0.9·等高线】循环外单建（side 循环内会建两次=泄漏）
	if ClassDB.class_exists("Th75BulletHashCpp"):
		bullet_hash_cpp = Th75BulletHashCpp.new() ## 【审计 Top2】C++ 空间哈希
	if ClassDB.class_exists("Th75MotionHot"):
		motion_hot = Th75MotionHot.new()
	if not gpu_ok:
		push_warning("[Arena] GPU DDM 不可用（headless/兼容），弹幕图降级关闭；被弹走哈希（逻辑不受影响）")

## 会话 GPU 资源释放（场景更替时；设备本身常驻不释放）
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if contour != null:
			contour.shutdown() ## 【0.0.9·等高线】
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
	ddm_debug_layer = _make_painter("DDMDebug", "ddm") ## 【22b 20261103·恢复】绘制热力图九图（原品红 DDM 叠层已删）
	if OS.get_environment("TH75_NO_TINT") == "": ## [BISECT-E]
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/bullet_tint.gdshader")
		bullet_mm_layer.material = mat

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
	## 【0.0.9·审计 B2】C++ 快路径：接管弹全量（GD 版>512 弹预筛抽样的精度上限
	## 之上）+每拍一次的非接管弹快照——口径逐条复刻；开关关=回退纯 GD 原路径
	if hcs_cpp_enabled and motion_hot != null and motion_hot_enabled:
		if _hcs_extra_frame != time_frames:
			_hcs_extra_frame = time_frames
			_hcs_pack_extra() ## 本帧首次：打包非接管弹（全帧共用，免逐实体扫全场）
		var spin := TAU / 32.0 * float(time_frames % 2)
		var o98: PackedFloat32Array = motion_hot.hcs_hct(
			ent.position.x, ent.position.y, n_spd, spin, ent.side)
		ent.hcs_pts = o98.slice(0, 49)
		ent.hct_pts = o98.slice(49, 98)
		ent.hcs_at = o98[48]
		ent.hct_at = o98[97]
		return
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
	## 【22b 20261028f】预筛扫描上限 512 弹（步进≈均匀采样全场）：原全弹扫描
	## ×每角色×采样拍 = 6000 弹病态堆栈下 37ms/拍的元凶（预筛无上限，"上限48"
	## 只作用于点循环）。均匀步进保留全场代表性。
	## 【22b 20261101·审计#41】cap 公式反了：原 maxi(512, size/12) 在
	## 984 弹时 scan_cap=512、step=984/512=1（整除）=全扫无 cap！
	## 改：目标扫描数=512，步进=ceil(size/512)
	var step_n: int = maxi(1, int(ceil(float(bullets.size()) / 512.0)))
	var bi := 0
	while bi < bullets.size():
		var bl: Bullet = bullets[bi]
		bi += step_n
		if bl.hidden_now or bl.ev.tag == DanmakuEventData.TAG_LASER:
			continue
		if bl.source_side == ent.side and not bl.ev.is_phy:
			continue ## 威胁弹幕（本侧法弹天然不算）
		var spd := bl.cur_speed()
		if spd <= 0.05:
			continue
		var L := minf(spd * 60.0, 400.0) ## 未来 1s 轨迹长（钳场宽）
		if bl.pos.distance_to(ent.position) > R + L:
			continue
		cand_pos.append(bl.pos)
		cand_dir.append(bl.cur_dir())
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

## 【0.0.9·审计 B2】非接管弹快照（每帧最多一次）：每行 x,y,dir_x,dir_y,spd,rad,
## side,phy——过滤口径同 GD 预筛（隐/激光/spd≤0.05 剔除；侧别与距离由 C++ 逐实体判）
var _hcs_extra_frame := -1
func _hcs_pack_extra() -> void:
	var rows := PackedFloat64Array()
	var bc_rows := PackedFloat64Array() ## 【0.0.9·BC】射线检测快照（非接管弹+激光采样点；不筛速度）
	for bl in bullets:
		var b: Bullet = bl
		if b.hidden_now:
			continue
		var is_laser: bool = b.ev.tag == DanmakuEventData.TAG_LASER
		if not b._mh_owned and not is_laser:
			var spd := b.cur_speed()
			if spd > 0.05:
				var dv := b.cur_dir()
				rows.append_array([b.pos.x, b.pos.y, dv.x, dv.y, spd, b.draw_radius,
					float(b.source_side), 1.0 if b.ev.is_phy else 0.0])
		if b._mh_owned:
			continue ## 接管弹已在 C++ slot（BC 直接读）
		if is_laser:
			## 激光按线宽跨步多枚圆参与射线检测（与 DDM 印章同口径=所见即所判）
			var lw := b.laser_width()
			var stride := maxi(1, int(lw * 4.0))
			for si in range(0, b.laser_samples.size(), stride):
				var lp: Vector2 = b.laser_samples[si]
				bc_rows.append_array([lp.x, lp.y, lw, float(b.source_side), 1.0 if b.ev.is_phy else 0.0])
		else:
			bc_rows.append_array([b.pos.x, b.pos.y, b.draw_radius, float(b.source_side), 1.0 if b.ev.is_phy else 0.0])
	motion_hot.hcs_set_extra(rows)
	motion_hot.bc_set_extra(bc_rows)

## 【0.0.9·BC】四弧阻断比例（上/下/左/右）：C++ 读接管 slot+非接管快照；扩展缺失回退 GD
func _bc_rays(ent: BattleEntity, blen: float) -> PackedFloat32Array:
	if motion_hot != null and motion_hot_enabled:
		if _hcs_extra_frame != time_frames:
			_hcs_extra_frame = time_frames
			_hcs_pack_extra() ## 与 Hcs 共享同帧快照
		return motion_hot.bc_rays(ent.position.x, ent.position.y, blen, ent.side)
	## —— GD 回退（口径同 C++ bc_rays）——
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var cand: Array = []
	for bl in bullets:
		var b: Bullet = bl
		if b.hidden_now or (b.source_side == ent.side and not b.ev.is_phy):
			continue
		if b.ev.tag == DanmakuEventData.TAG_LASER:
			var lw := b.laser_width()
			for si in range(0, b.laser_samples.size(), maxi(1, int(lw * 4.0))):
				var lp: Vector2 = b.laser_samples[si]
				if lp.distance_to(ent.position) <= blen + lw:
					cand.append([lp, lw])
		elif b.pos.distance_to(ent.position) <= blen + b.draw_radius:
			cand.append([b.pos, b.draw_radius])
	if cand.is_empty():
		return out
	var mids := [-PI / 2.0, PI / 2.0, PI, 0.0]
	var offs := [-PI / 6.0, -PI / 12.0, 0.0, PI / 12.0, PI / 6.0]
	for a in 4:
		var worst := 0.0
		for o in offs:
			var u := Vector2(cos(float(mids[a]) + float(o)), sin(float(mids[a]) + float(o)))
			var best_t := -1.0
			for c in cand:
				var w: Vector2 = (c[0] as Vector2) - ent.position
				var r: float = c[1]
				var th := -1.0
				if w.length_squared() <= r * r:
					th = 0.0
				else:
					var tca := w.dot(u)
					var d2 := w.length_squared() - tca * tca
					if tca >= 0.0 and d2 <= r * r:
						var t0 := tca - sqrt(r * r - d2)
						if t0 <= blen:
							th = maxf(t0, 0.0)
				if th >= 0.0 and (best_t < 0.0 or th < best_t):
					best_t = th
			if best_t >= 0.0:
				worst = maxf(worst, (blen - best_t) / blen)
		out[a] = worst
	return out

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

## 万岁冲锋挡弹：找该角色麾下 banzai 杂兵替死（一次一发）
func _take_banzai_hit(ent: BattleEntity) -> bool:
	for e2 in entities:
		if e2 is BattleEntity and (e2 as BattleEntity).kind == BattleEntity.Kind.PRIVATE 			and not (e2 as BattleEntity).dead and (e2 as BattleEntity).owner_ent == ent 			and int((e2 as BattleEntity).get_meta("banzai", 0)) > 0:
			var pb: BattleEntity = e2
			pb.set_meta("banzai", 0)
			pb.take_hit(9999, 0, 0.0) ## 替死（万岁冲锋被击败）
			print("[万岁冲锋] %s 替 %s 挡下一弹" % [pb.chara_name(), ent.chara_name()])
			return true
	return false

## —— 召唤轮盘（新二 11-25 行；作者裁定 20261106：Shift+X **按住**显示、
##    松开按键确认选取，鼠标未接触=默认第一位；圆环加大）——
const SUMMON_EXCLUDE := ["晚汐", "风见幽香", "帕秋莉", "希洛妮娅", "叶妮雪尔米娜", "釉怜冠姬", "八云紫", "八云蓝", "宇佐见莲子", "梅莉", "清兰", "铃瑚"]
func _open_summon_wheel(sel: BattleEntity) -> void:
	_wheel_cands.clear()
	var used := {}
	for e in player_ents:
		if e is BattleEntity and (e as BattleEntity).kind != BattleEntity.Kind.PRIVATE:
			used[(e as BattleEntity).chara_name()] = true
	## 【作者裁定 20261106】候补列表=默认存档配置（自定义对战"召唤候补设置"）；
	## 未配置时 demo 兜底=角色池排除现役+特殊组
	var pool := CharaDB.load_all()
	if GameGlobals.summon_roster.is_empty():
		for row in pool:
			var nm: String = str(row.get("Name", ""))
			if nm == "" or used.has(nm):
				continue
			var excl := false
			for ex in SUMMON_EXCLUDE:
				if nm.contains(ex):
					excl = true
					break
			if not excl:
				_wheel_cands.append(row)
			if _wheel_cands.size() >= 8:
				break
	else:
		for nm0 in GameGlobals.summon_roster:
			var nm: String = str(nm0)
			if nm == "" or used.has(nm):
				continue
			for row in pool:
				if str(row.get("Name", "")) == nm:
					_wheel_cands.append(row)
					break
			if _wheel_cands.size() >= 8:
				break
	if _wheel_cands.is_empty():
		_toast("无可用候补——请在自定义对战设置召唤候补")
		return
	_wheel_open = true
	_wheel_sel = -1
	_wheel_target = sel
	_toast("%s 召唤轮盘（候补 %d 位）——松开 Shift+X 选取" % [sel.chara_name(), _wheel_cands.size()])

func _do_summon(sel: BattleEntity, row: Dictionary) -> void:
	## 策划：新角色 25 结界、破损自动离场（结界破损离场钩子=barrier_shattered 既有）、
	## 初始 P 点与符卡数量与原始角色共享；支援框外（中心350²内）召唤→下一帧强制发动能力
	var idx := -1
	for i in player_ents.size():
		if player_ents[i] == sel:
			idx = i
			break
	if idx < 0:
		return
	var ne := BattleEntity.new()
	ne.setup(row, 0, BattleEntity.Kind.PLAYER, true)
	ne.position = sel.position
	ne.pp = sel.pp          ## 与原始角色共享
	ne.spell_cards = sel.spell_cards
	ne.ap = 25              ## 召唤角色 25 结界
	ne.set_meta("summoned", true)
	player_ents[idx] = ne
	var eidx := entities.find(sel)
	if eidx >= 0:
		entities[eidx] = ne
	sel.dead = true ## 原角色离场（接替）
	if sel == player_leader:
		player_leader = ne
	if sel == _pick_side_target(0):
		pass
	## 支援框判定：中心 350×350 内召唤→强制下一帧发动能力（新二 8/21 行）
	if absf(ne.position.x - 200.0) <= 175.0 and absf(ne.position.y - 200.0) <= 175.0:
		if ne.pp >= 25:
			_apply_release(ne, "n")
			print("[召唤] 支援框外召唤→强制发动能力")
	print("[召唤] %s 接替 %s 上场（结界25 P=%d 符卡=%d）" % [
		ne.chara_name(), sel.chara_name(), ne.pp, ne.spell_cards])
	_toast("角色召唤：%s 接替 %s" % [ne.chara_name(), sel.chara_name()])

func _pick_side_target(_side: int):
	return null ## 占位（轮盘目标由 _wheel_target 持有）

## 右下面板（新二 87 行）：H 在"特定角色详细状态"与"决斗机控热键展示"间切换
func _br_cycle() -> void:
	_br_page = (_br_page + 1) % 3 ## 0 关 / 1 角色状态 / 2 热键
	_ensure_br_label()

func _ensure_br_label() -> void:
	if _br_label == null:
		_br_label = Label.new()
		_br_label.anchor_left = 1.0
		_br_label.anchor_right = 1.0
		_br_label.anchor_top = 1.0
		_br_label.anchor_bottom = 1.0
		_br_label.offset_left = -380
		_br_label.offset_right = -8
		_br_label.offset_top = -260
		_br_label.offset_bottom = -8
		_br_label.add_theme_font_size_override("font_size", 12)
		_br_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.92))
		hud.add_child(_br_label)
	_br_label.visible = _br_page != 0

## 杂兵面板当前选取的杂兵（滚轮序号→麾下列表）
func _priv_pick_entity():
	var sel := picked_entity()
	if sel == null:
		return null
	var list: Array = []
	for e2 in entities:
		if e2 is BattleEntity and (e2 as BattleEntity).kind == BattleEntity.Kind.PRIVATE 			and (e2 as BattleEntity).owner_ent == sel and not (e2 as BattleEntity).dead:
			list.append(e2)
	if list.is_empty():
		return null
	_priv_sel = clampi(_priv_sel, 0, list.size() - 1)
	return list[_priv_sel]

func _refresh_br_panel() -> void:
	if _br_label == null or _br_page == 0:
		return
	if _br_page == 2:
		var lines := "── 决斗机控热键 ──
"
		var last_cat := ""
		for b in KeyBindings.BINDINGS:
			if b["cat"] != last_cat:
				last_cat = b["cat"]
				lines += "【%s】
" % b["cat"]
			lines += "%s → %s
" % [b["keys"], b["name"]]
		_br_label.text = lines
		return
	## 页 1：特定角色详细状态（滚轮/F1 选中者）
	var ent := picked_entity()
	if ent == null or not is_instance_valid(ent):
		_br_label.text = "── 角色详细状态 ──
（滚轮或 F2 选取角色）"
		return
	var privs := 0
	for e2 in entities:
		if e2 is BattleEntity and (e2 as BattleEntity).kind == BattleEntity.Kind.PRIVATE 			and (e2 as BattleEntity).owner_ent == ent and not (e2 as BattleEntity).dead:
			privs += 1
	_br_label.text = "── %s 详细状态 ──
" % ent.chara_name() 		+ "HP %d/%d/%d　结界 %d　P %d　符卡 %d
" % [ent.hp[0], ent.hp[1], ent.hp[2], ent.ap, ent.pp, ent.spell_cards] 		+ "态势卡 %s　战术 %s
" % [ent.current_sit_card, ent.current_tactic] 		+ "杂兵 %d　装填 能力%.1fs/符卡%.1fs
" % [privs, ent.sit_cards.skill_load_t, ent.sit_cards.spell_load_t] 		+ ("团队指令 %s
" % team_stance if team_stance != "" else "") \
			+ ("点位指令 攻 (%d, %d) %.1fs\n" % [int(cmd_point.x), int(cmd_point.y), cmd_frames / 60.0] if cmd_frames > 0 and _cmd_ent == ent else "") \
			+ ("点位指令 防 (%d, %d) %.1fs\n" % [int(_cmd_point_b.x), int(_cmd_point_b.y), _cmd_frames_b / 60.0] if _cmd_frames_b > 0 and _cmd_ent_b == ent else "")

## 【0.0.9·点位指令统一下达】kind="g" 指定位置进攻 / "b" 指定位置防御（各 5 秒；
## 引力只作用于下达时选中的角色——新二 114/118 "选取对应角色"）
func _issue_point_cmd(kind: String, wp: Vector2) -> void:
	_pick_side = 0
	var psel := picked_entity()
	if kind == "b":
		_cmd_point_b = wp
		_cmd_frames_b = 300
		_cmd_ent_b = psel
		_toast("指定位置防御 → %s (%d,%d)" % [psel.chara_name() if psel != null else "?", int(wp.x), int(wp.y)])
	else:
		cmd_point = wp
		cmd_frames = 300
		_cmd_ent = psel
		_toast("指定位置进攻 → %s (%d,%d)" % [psel.chara_name() if psel != null else "?", int(wp.x), int(wp.y)])

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
var preview_emit_interval := 0.5 ## 【可变探针】试炼场自动发射间隔（秒；emit= 启动参数可改）

func _preview_emitter(delta: float) -> void:
	_emitter_acc += delta
	if _emitter_acc >= preview_emit_interval:
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
		## 【审计#42】登记门：死角色火力点不再建炮
		if _cannons.size() < 64 and src != null and not (src as BattleEntity).dead:
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
## 【0.0.9·弹幕构成探针（作者批）】按需查询弹幕构成（默认零开销，调用才统计）
## 返回：total 实际存在 / visible 可渲染 / hidden（pass 隐藏）/ offield（场外）/
##       laser（激光）/ pool（池待复用）/ rot_pend（延时副本）/ cannons（火炮）
##       expired（累计自然到期）/ retired（累计回收入池）
func bullet_census() -> Dictionary:
	var d := {"total": bullets.size(), "visible": 0, "hidden": 0, "offfield": 0,
		"laser": 0, "pool": _bullet_pool.size(), "rot_pend": _rot_pend.size(),
		"cannons": _cannons.size(), "expired": _expired_count, "retired": _retired_count}
	var by_ev := {} ## 【深挖】场外弹按事件分组（定位永生弹来源）
	var by_oob := {} ## oob_mode 分组（2=永不销毁）
	for b in bullets:
		var bl: Bullet = b
		if bl.ev.tag == DanmakuEventData.TAG_LASER:
			d["laser"] += 1
		elif bl.hidden_now:
			d["hidden"] += 1
		elif not _in_field(bl.pos):
			d["offfield"] += 1
			var k: String = bl.ev.event_name + "/oob" + str(bl.ev.oob_mode)
			by_ev[k] = int(by_ev.get(k, 0)) + 1
			by_oob[bl.ev.oob_mode] = int(by_oob.get(bl.ev.oob_mode, 0)) + 1
		else:
			d["visible"] += 1
	d["offfield_by_ev"] = by_ev
	d["offfield_by_oob"] = by_oob
	return d

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
		shared_txy: Vector2 = Vector2.INF, src_tag: String = "fire") -> void:
	## 【0.0.9·重写 20261104】旋转展开——干净重写：
	## ①共享目标整扇一次解算 ②参数整扇一次求值 ③plan 按时序步进
	## ④si==0 同帧发+其余入 pend ⑤gen==0 首载体带节拍（防指数繁殖）
	if ev == null:
		return
	if shared_target == null and src != null:
		shared_target = bullet_nearest_enemy_from(src.side, origin)
	if shared_txy == Vector2.INF and shared_target != null:
		shared_txy = shared_target.position - origin if not ev.is_abs_coord else shared_target.position
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
	var carrier_left: bool = gen == 0
	var anchor_base := Vector2.ZERO
	var fired_any: Bullet = null
	for si in plan.size():
		var step: Array = plan[si]
		for pair in step:
			var k: int = int(pair[0])
			var rid: int = int(pair[1])
			var ang: float = (positions[k] if k < positions.size() else 0.0) + float(rp.get("offset", 0.0))
			var pin: Vector2 = anchor_base if (ev.tag == DanmakuEventData.TAG_REGULAR and anchor_base != Vector2.ZERO) else Vector2.ZERO
			if delay_step <= 0 or si == 0:
				var b: Bullet = _spawn_rotated_copy(ev, origin, src, point, ang, rid, rolls, gen, carrier_left, pin,
					event_t, shared_target, shared_txy, sp, rp, src_tag)
				if si == 0 and b != null and ev.tag == DanmakuEventData.TAG_REGULAR and anchor_base == Vector2.ZERO:
					anchor_base = b.dir.rotated(-ang)
					fired_any = b
				carrier_left = false
			elif _rot_pend.size() < 2048:
				_rot_pend.append({"ev": ev, "point": point, "src": src,
					"rolls": rolls.duplicate(), "ang": ang, "rid": rid,
					"frames": si * delay_step, "gen": gen,
					"carrier": false,
					"pinned": pin, "sp": sp, "et": event_t + float(si * delay_step),
					"shared": shared_target, "stxy": shared_txy,
					"tag": src_tag,
					## 【0.0.9·基准错位修复（重复丢失/闪烁真因）20261105】延时副本
					## 从释放时刻火力点出发，但 stxy 是发射时刻原点的相对快照——
					## 发射源移动（试炼场发射器瞬移/对战实体走位）期间释放的副本
					## 落点整体偏移出界→出生即死。存绝对共享点，释放时按新原点重算。
					"stxy_abs": (origin + shared_txy) if (shared_txy != Vector2.INF and not ev.is_abs_coord) else shared_txy})
				carrier_left = false
	if fired_any == null and not plan.is_empty() and delay_step <= 0:
		pass


func _spawn_rotated_copy(ev: DanmakuEventData, origin: Vector2, src: BattleEntity, point,
		ang: float, rid: int, rolls: Dictionary, gen: int, carrier: bool, pinned: Vector2 = Vector2.ZERO,
		event_t := 0.0, shared_target: BattleEntity = null, shared_txy: Vector2 = Vector2.INF,
		setup_sp: Dictionary = {}, setup_rp: Dictionary = {}, src_tag: String = "fire") -> Bullet:
	var b := _spawn_bullet(ev, origin, gen, src, point, ang, rid, rolls, pinned, event_t, shared_target, shared_txy, setup_sp, setup_rp, src_tag)
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
			var pr_src = pr["src"]
			## 【审计#42】发射源死亡→丢弃延时副本
			if pr_src == null or not is_instance_valid(pr_src) or (pr_src as BattleEntity).dead:
				_rot_pend.remove_at(i)
				continue
			var rel_org := _fire_origin(pr["point"], ev, pr["src"], pr.get("sp", {}))
			var stxy_use: Vector2 = pr.get("stxy", Vector2.INF)
			var stxy_abs: Vector2 = pr.get("stxy_abs", Vector2.INF)
			if stxy_abs != Vector2.INF and not ev.is_abs_coord:
				stxy_use = stxy_abs - rel_org ## 【基准错位修复】按释放时刻原点重算相对共享点
			_spawn_rotated_copy(ev, rel_org,
				pr["src"], pr["point"], pr["ang"], pr["rid"], pr["rolls"], pr["gen"], pr["carrier"],
				pr.get("pinned", Vector2.ZERO), float(pr.get("et", 0.0)), pr.get("shared", null),
				stxy_use, {}, {}, str(pr.get("tag", "pend")))
			_rot_pend.remove_at(i)

## 火炮节点：按 repeat_time 间隔生成 repeat 禁用的弹幕粒子（repeat_freq 拍后自毁）
## 【类型批复 20261019】repeat 参数允许算式——登记时求值
func _cannon_tick() -> void:
	for i in range(_cannons.size() - 1, -1, -1):
		var c: Dictionary = _cannons[i]
		var ev: DanmakuEventData = c["ev"]
		## 【审计#42】src 死亡/失效→炮节点立即销毁（0 弹卡顿元凶）
		var src_c = c["src"]
		if src_c == null or not is_instance_valid(src_c) or (src_c as BattleEntity).dead:
			_cannons.remove_at(i)
			continue
		c["timer"] = int(c["timer"]) + 1
		var rpt: Dictionary = c.get("rpt", {})
		var beats: int = int(rpt.get("freq", 0)) if int(rpt.get("freq", 0)) > 0 else 1
		var interval: int = maxi(1, int(rpt.get("time", ev.repeat_time)))
		var guard := 0
		while int(c["fired"]) < beats and int(c["timer"]) >= int(c["fired"]) * interval and guard < 8:
			var origin: Vector2 = c.get("origin0", _fire_origin(c["point"], ev, c["src"], c.get("sp", {})))
			_spawn_event_copies(ev, origin, c["src"], c["point"], c["rolls"], 1, {}, {}, 0.0, null, Vector2.INF, "cannon")
			c["fired"] = int(c["fired"]) + 1
			guard += 1
			if _cannons.size() > 256:
				break
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
## 【0.0.9·物理分块计时（live 探针 split 用）】块序：AI/实体+态势/火控/弹幕更新/被弹
var _dbg_split := false
var _dbg_acc := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _dbg_ph0 := 0

func _physics_process(delta: float) -> void:
	if _dbg_split:
		_dbg_ph0 = Time.get_ticks_usec()
	## 【加载屏】预热期每物理帧跑一个任务；画面被覆盖层遮住
	if _loading:
		_run_load_step()
		return
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
	if _cmd_frames_b > 0:
		_cmd_frames_b -= 1 ## 【0.0.9·B 空壳修复】原只写不减=永久显示"防"
	var _t0: int = Time.get_ticks_usec() if _dbg_split else 0
	_entity_ticks(dt)
	var _t1b: int = Time.get_ticks_usec() if _dbg_split else 0
	if not finished:
		_sit_tick(delta)
	var _t1: int = Time.get_ticks_usec() if _dbg_split else 0
	if not surrender_phase:
		_fire_ticks(delta)
		_cannon_tick() ## 【20261015】火炮节点按 repeat 时序生成弹幕粒子
		for e3 in entities:
			if e3 is BattleEntity and (e3 as BattleEntity).kind == BattleEntity.Kind.PRIVATE:
				var bm: int = int((e3 as BattleEntity).get_meta("banzai", 0))
				if bm > 0:
					(e3 as BattleEntity).set_meta("banzai", bm - 1) ## 万岁冲锋 30 秒时效
		_priv_shooters_tick() ## 【20261020】杂兵自身发射（ShootCd+shoot_evs）
		_rot_pending_tick() ## 【20261015】旋转重复延时副本释放
	else:
		for ent: BattleEntity in entities:
			if ent is BattleEntity and not ent.dead:
				ent.current_sit_card = "d"
	var _t2: int = Time.get_ticks_usec() if _dbg_split else 0
	_bullet_updates(dt)
	var _t3: int = Time.get_ticks_usec() if _dbg_split else 0
	## 【性能 2026-10-14】被弹判定与拾取结算降 30Hz（每 2 物理帧）——
	## 被弹已有 0.5s 免疫兜底、拾取无帧级敏感性；physics 33ms→~18ms 预期
	if time_frames % 2 == 1:
		_resolve_hits()
		_update_drops()
	var _t4: int = Time.get_ticks_usec() if _dbg_split else 0
	if _dbg_split:
		_dbg_acc[0] += float(_t0 - _dbg_ph0)
		_dbg_acc[1] += float(_t1b - _t0)
		_dbg_acc[2] += float(_t2 - _t1)
		_dbg_acc[3] += float(_t3 - _t2)
		_dbg_acc[4] += float(_t4 - _t3)
		_dbg_acc[5] += float(_t1 - _t1b) ## 实体 vs 态势拆分（态势=_dbg_acc[5]）
	_update_phase()
	_check_end()
	_refresh_hud()
	## 【性能休整·嫌疑3】GPU DDM 移至 _process（渲染线程），不阻塞物理线程
	## _render_ddm() 改在 _process 中调用

func _process(delta: float) -> void:
	## 【加载屏】预热任务在此执行（0.0.9·卡死修复：渲染帧驱动下
	## physics_process 被禁用——原加载分支永不开跑=卡死"少女祈祷中"）
	if _loading:
		_run_load_step()
		return
	## 【0.0.9·渲染帧驱动】物理调用移至 _process 末尾（GPU 提交先走、物理殿后
	## ——驱动背压对策：物理挤在提交簇前会让 proc 各提交点同步等待膨胀 3-4 倍）
	## 【22b 20261028】上一拍 fam batch_read 提前到 _process 开头：
	## read 的 buffer_get_data 是 GPU-CPU fence 同步——在 physics 线程里
	## 调用会拖住物理（窗口化实测 110ms 的主源）。挪到渲染帧头=GPU 已
	## 提交完上一拍，fence≈0。数据本就是上一拍的（RET 用旧一拍无害）
	## 【0.0.9·渲染帧驱动·顺序修正 20261109】物理移至 _render_ddm **之前**：
	## 原在 _process 末尾→消弹/出界销毁弹后 DDM 残留 1 帧幽灵 stamp→Ht "诈尸"
	## 现改为：物理先跑（创建/移动/销毁弹）→_render_ddm 立即反映当前状态
	if not GameGlobals.bullet_legacy_physics:
		_phys_acc += delta
		if _phys_acc >= 1.0 / 60.0:
			_phys_acc = minf(_phys_acc - 1.0 / 60.0, 1.0 / 60.0) ## 不追帧（掉帧=放慢）
			_physics_process(1.0 / 60.0)
	_consume_pending_samples()
	_render_ddm() ## GPU 弹幕图提交（渲染线程，异步不阻塞 physics）
	_heatmap_tick()
	## 【0.0.9·决斗操作批】轮盘超时/杂兵 meta 递减/右下面板刷新
	if _wheel_open:
		## 【按住模式（作者裁定）】Shift+X 松开→确认选取（鼠标未接触=默认第一位）
		if not (Input.is_physical_key_pressed(KEY_X) and Input.is_physical_key_pressed(KEY_SHIFT)):
			if _wheel_target != null and not _wheel_cands.is_empty():
				var pick: int = _wheel_sel if (_wheel_sel >= 0 and _wheel_sel < _wheel_cands.size()) else 0
				_do_summon(_wheel_target, _wheel_cands[pick])
			_wheel_open = false
	if not Input.is_physical_key_pressed(KEY_TAB):
		_priv_tab_lock = false ## 松开 Tab→解锁（下次按恢复）
	_priv_panel = Input.is_physical_key_pressed(KEY_TAB) and not _priv_tab_lock
	for ti in range(_toasts.size() - 1, -1, -1):
		_toasts[ti]["frames"] = int(_toasts[ti]["frames"]) - 1
		if int(_toasts[ti]["frames"]) <= 0:
			if _toasts[ti]["label"] != null:
				_toasts[ti]["label"].queue_free()
			_toasts.remove_at(ti)
		elif _toasts[ti]["label"] != null:
			(_toasts[ti]["label"] as Label).modulate.a = clampf(float(_toasts[ti]["frames"]) / 90.0, 0.0, 1.0) ## 后1.5秒渐隐
	if _br_page != 0:
		_refresh_br_panel()
	## 【0.0.9·等高线数据层（策划新三 52-68）】AI 抽象层提取挂点：
	## enabled=false（默认，作者裁定 AI 接入前停用）时 tick 内部直接返回零成本
	if contour != null and contour.ok and (_heat_view == 4 or _heat_view == 5):
		contour.tick(("Hd" if _heat_view == 4 else "Hr") + str(_heat_view_side), time_frames)
		## 【0.0.9·色图显示修复 20261108】ColorMap sprite 的 texture 喂养
		## （色图 sprite 化后无 painter 回调——在此同步刷新）
		if _contour_layer != null:
			var cspr: Sprite2D = _contour_layer.get_node_or_null("ColorMap") as Sprite2D
			if cspr != null:
				cspr.texture = contour.display(("Hd" if _heat_view == 4 else "Hr") + str(_heat_view_side))
	## 真实帧率测量（每秒窗口；页面暂停时不更新）
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum >= 1.0:
		_fps_measured = float(_fps_frames) / _fps_accum
		_fps_accum = 0.0
		_fps_frames = 0
		## 【尖峰放慢（作者批准+1031d 分段判定）】低帧率→全场放慢：
		## fps<30 连续 10 帧 → 0.5 倍；fps<10 连续 3 帧 → 0.25 倍；
		## 恢复 fps≥50 持续；冷却 300 帧。tick 频率 60 不变。
		if _slowmo_cd > 0:
			_slowmo_cd -= 1
		## 分段连续帧计数（每秒窗口改为即时判定，赶上瞬时跌落）
		if _fps_measured < 10.0:
			_slow_lo += 1
			_slow_mid = 0
		elif _fps_measured < 30.0:
			_slow_mid += 1
			_slow_lo = 0
		else:
			_slow_mid = 0
			_slow_lo = 0
		if time_frames > 300 and not finished:
			if Engine.time_scale < 0.25 and _slow_lo >= 3 and _slowmo_cd <= 0:
				Engine.time_scale = 0.25
				_slowmo_until_frame = time_frames + 180
				_slowmo_cd = 300
			elif Engine.time_scale < 0.5 and _slow_mid >= 10 and _slowmo_cd <= 0:
				Engine.time_scale = 0.5
				_slowmo_until_frame = time_frames + 120
				_slowmo_cd = 300
			elif Engine.time_scale < 1.0 and _fps_measured >= 50.0:
				Engine.time_scale = 1.0
			elif Engine.time_scale < 1.0 and time_frames > _slowmo_until_frame and _fps_measured >= 30.0:
				Engine.time_scale = 1.0 ## ②期准备：Ht 步进+态势十六点带转采样（10Hz，同拍）
	## 【0.0.9·渲染帧驱动】物理调用在 _process 末尾（GPU 提交先走、物理殿后——
	## 驱动背压对策：实测物理挤在提交簇前会让 proc 各提交点同步等待膨胀 3-4 倍）
	## 节流 16.6ms 锁 60/s（高刷屏弹幕 N 倍速防护）；掉帧不追帧=自然放慢
## =============================================================
## ②期：热力图 Ht（每侧一张威胁图）+ 态势十六点（带转）采样（10Hz = 每6物理帧）
## 【DDM 与显示均 60帧（作者批复 2026-10-02）】_render_ddm 每帧提交，
##   F3 显示走主设备 Texture2DRD 零拷贝；10Hz 的只有 Ht 步进与采样（像素遍历图频率）。
## 【带转】偶数帧采样从最上端开始；奇数帧整体偏 1/32 圈（11.25°）。
## 【性能检测】HeatmapField 内置 μs 滑动平均；HUD(F3) 与控制台周期输出。
## =============================================================
func _heatmap_tick() -> void:
	## 【0.0.9·修】暂停/结束时热力图全停（暂停时 Hp/He 仍衰减=低级错误）
	if pause_panel != null and pause_panel.visible:
		return
	if finished:
		return
	var any_ok: bool = not ht_side.is_empty() and ht_side[0] != null and (ht_side[0].ok or not gpu_ok)
	if ht_side.is_empty() or ht_side[0] == null:
		return
	if time_frames % 6 != 0:
		return
	for side in 2:
		var ht: HeatmapField = ht_side[side]
		if ht == null:
			continue
		if not ht.ok:
			ht.step_cpu(bullets) ## headless 降级
		else:
			ht.step() ## 读当帧本侧 DDM（同 RD 队列 FIFO，晚于 _render_ddm 提交）
		## 【20261028f 策划对齐】Hd=Ht 高斯模糊派生（原独立弹幕印章+decay 路径
		## 删除——策划明示"根据同一张图(Ht)抽象计算"；Ha 马赛克数据同着色器产出）
		if ht.ok and fam_maps != null and fam_maps.ok:
			fam_maps.derive_hd_from_ht(side, ht.front_texture_rid())
		var hv = hv_side[side] if side < hv_side.size() else null
		if hv != null and hv.ok:
			hv.step() ## Ht 之后（cur 已渲染、prev 为上帧）
			## 【0.0.9·Hv 时序修复】cur→prev 拷贝必须在 hv 读取**之后**
			## （原在 render() 尾=同帧先拷→diff 恒 0→Hv 恒空→Hr 派生恒空）
			var ddm_i = ddm_gpu0 if side == 0 else ddm_gpu1
			if ddm_i != null:
				ddm_i.copy_to_prev()
			## 【0.0.9·Hr 派生（策划新三对齐）】Hr=Hv 半径2高斯派生
			## （撤销快弹印章——测试弹速度不足 4 时 Hr 恒空=作者实测无热力）
			if fam_maps != null and fam_maps.ok:
				fam_maps.derive_hr_from_hv(side, hv.front_rid())
	## 【0.0.9·审计 B4】两侧 Hd/Ha/Hr 派生排队后一次提交（原 3×begin/end）
	if fam_maps != null and fam_maps.ok:
		fam_maps.derive_flush()

	## 【P1 修复 20261015】8 图 advance 合并为一次 GPU 提交（原 16 次/拍）
	if fam_maps != null and fam_maps.ok:
		var fam_pts := {} ## "He0".."Hp1" -> 点列（x,y 交错）
		## 【22b 20261028f】两遍式：先数点→预分配→下标写（原每弹 append 装箱
		## +逐弹 Dictionary 回写——6000 弹病态堆栈实测 23ms/拍，是"热力图注册"
		## 的 CPU 主体；正常千弹场景 ~4ms/拍）
		var cap_e := [0, 0]
		for b2 in bullets:
			var bl2: Bullet = b2
			if bl2.hidden_now or bl2.ev.tag == DanmakuEventData.TAG_LASER 					or bl2.cur_speed() <= 0.1 or bl2.cur_dir() == Vector2.ZERO:
				continue
			var th2: int = 1 - bl2.source_side
			## 【22b 20261104·幻影修复】低速弹预测点 8→1（未来≈原地，8 点叠加=幻影热点）
			if bl2.cur_speed() >= 1.0:
				cap_e[th2] += 16
			else:
				cap_e[th2] += 2
		for sd2 in 2:
			if cap_e[sd2] > 0:
				var pa := PackedFloat32Array()
				pa.resize(cap_e[sd2])
				fam_pts["He" + str(sd2)] = pa
		var wi := [0, 0]
		## 【22b 20261028f】数组引用循环外取（免每弹 2 次字符串拼接+字典哈希）
		## 【0.0.9】Hr 已改 Hv 派生——印章路径全撤（cap_r/wj/hr_by 删）
		var he_by: Array = [fam_pts.get("He0", PackedFloat32Array()), fam_pts.get("He1", PackedFloat32Array())]
		for b in bullets:
			var bl: Bullet = b
			if bl.hidden_now or bl.ev.tag == DanmakuEventData.TAG_LASER:
				continue
			var spd := bl.cur_speed()
			var dirv := bl.cur_dir()
			if spd <= 0.1 or dirv == Vector2.ZERO:
				continue
			var horizon: float = minf(bl.range_now, 60.0) / 60.0 ## ≤1s
			var threat: int = 1 - bl.source_side ## 该弹威胁的侧
			var pts_he: PackedFloat32Array = he_by[threat]
			var w0: int = wi[threat]
			## 【0.0.9·He 加速度（策划新三 61）】二阶外推：
			## a = 本帧速度 − 上帧速度（转向/加减速弹预测随曲率）
			var acc := Vector2.ZERO
			if bl._prev_pos != Vector2.INF:
				acc = (dirv * spd) - (bl.pos - bl._prev_pos)
			## 【20261104·幻影修复同步】写入与计数同判定：低速弹只写 1 预测点
			var kmax := 8 if spd >= 1.0 else 1
			for k in kmax:
				var ft := (float(k) + 1.0) / 8.0 * horizon * 60.0
				var fp := bl.pos + (dirv * spd + acc * 0.5 * ft) * ft
				pts_he[w0] = fp.x
				pts_he[w0 + 1] = fp.y
				w0 += 2
			wi[threat] = w0
		## 【20261028f】Hd0/Hd1 从 jobs 移除（Ht 派生）
		## 【20261104·作者裁定】Hp 恢复独立弹幕注册（慢记忆 0.98）——撤销派生
		var jobs := []
		for mp in ["He0", "He1"]: ## 【0.0.9】Hr 改 Hv 派生（ Hp 独立印章保留）
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
			ht.sample_dispatch(side_pts)
			_ht_pending[side] = side_ents
			## 【Hcs/Hct 20261020】逐实体 0.2s 交错计算（性能红线：同拍全量太重）
			for ei2 in side_ents.size():
				var e4: BattleEntity = side_ents[ei2]
				## 【新三】攻击态势不开启 Hcs/Hct 实时运算（省一拍算力；
				## 权重侧已为 0，不读旧值）
				if e4.current_sit_card in ["a", "c"]:
					continue
				if (time_frames / 6 + ei2) % 2 == 0:
					_compute_hcs_hct(e4)
		else:
			_apply_ht_vals(ht.sample(side_pts), side_ents) ## CPU 降级立即生效
		fam_sides.append({
			"pts": side_pts,
			"maps": ["He%d" % side, "Hd%d" % side, "Hr%d" % side, "Hp%d" % side, "Ha%d" % side],
			"side": side, "ents": side_ents,
		})
	## 【③期收官·多图加权】【P2 修复】只采本侧 4 图并批一次提交（原 sample_multi 无条件回读 8 图）
	if fam_maps != null and fam_maps.ok and not fam_sides.is_empty():
		fam_maps.batch_dispatch(fam_sides)
		_fam_pending = fam_sides

## —— 采样延迟一拍（P1 修复 20261015）：本拍 dispatch，下一拍开头回读消费 ——
var _ht_pending := {}  ## side -> side_ents
var _fam_pending := [] ## fam_sides
## 【22b 20261031·修复#2】回读延迟两拍（原一拍）：batch_read 的 fence 在
## GPU 深队列下实测 ~6ms/拍——隔两拍读=队列已排空，数据旧 0.2s（AI 态势
## 本就是 0.1s 旧近似，符策划"0.1 秒距采样"的时间容差）
var _ht_pending2 := {}
var _fam_pending2 := []
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
		## 【22b 20261103·三环采样错位修复（外部审计 Top1）】构造侧按
		## 方向交错（d0r1,d0r2,d0r3,d1r1,...），消费侧原按环连续切片
		## （sit16_1d=arr[0:16]）=三环语义全毁（RET/APF/边界热全读错排）。
		## 重排为按环连续：sorted[k]=arr[方向(k%16)*3+环(k/16)]
		var sorted48 := PackedInt32Array()
		sorted48.resize(48)
		for k2 in 48:
			sorted48[k2] = arr[(k2 % 16) * 3 + k2 / 16]
		## 边界虚拟热叠加（新三：外框弹幕进界热——三环逐点按位置加成）
		## 【审计#15】16 方向 cos/sin 预计算（原每拍 2880 次 trig→查表）
		if _dir16.size() != 16:
			_dir16.clear()
			for dk in 16:
				var da := -PI / 2.0 + TAU * float(dk) / 16.0
				_dir16.append(Vector2(cos(da), sin(da)))
		var n_spd_e: float = ent.normal_speed()
		for k2 in 48:
			var ring_n: float = n_spd_e * (6.0 if k2 < 16 else (12.0 if k2 < 32 else 30.0))
			var sp2: Vector2 = ent.position + _dir16[k2 % 16] * ring_n
			var eh := _edge_heat(sp2)
			if eh > 0:
				arr[k2] = mini(arr[k2] + eh, 255)
		ent.sit16_1d = sorted48.slice(0, 16)
		ent.sit16_2d = sorted48.slice(16, 32)
		ent.sit16_5d = sorted48.slice(32, 48)
		ent.set_meta("ht_at", vals[vi] if vi < vals.size() else 0)
		vi += 1

func _consume_pending_samples() -> void:
	## 消费两拍前的 pending（此时其 GPU 提交早已排空，fence≈0）
	for side in _ht_pending2:
		var ht: HeatmapField = ht_side[side]
		if ht != null and ht.ok:
			_apply_ht_vals(ht.sample_read(), _ht_pending2[side])
	_ht_pending2 = _ht_pending
	_ht_pending = {}
	if _fam_pending2.is_empty() and _fam_pending.is_empty():
		return
	var spin2 := TAU / 32.0 * float(time_frames % 2)
	var multi: Dictionary = {}
	if not _fam_pending2.is_empty():
		multi = fam_maps.batch_read()
	for sd in _fam_pending2:
		var sfx: String = str(sd["side"])
		var side_ents: Array = sd["ents"]
		## 图数组提到循环外（原每 k 每实体 4 次字符串拼接+字典查找）
		var a_he: PackedInt32Array = multi.get("He" + sfx, PackedInt32Array())
		var a_ha: PackedInt32Array = multi.get("Ha" + sfx, PackedInt32Array())
		var a_hd: PackedInt32Array = multi.get("Hd" + sfx, PackedInt32Array())
		var a_hr: PackedInt32Array = multi.get("Hr" + sfx, PackedInt32Array())
		var a_hp: PackedInt32Array = multi.get("Hp" + sfx, PackedInt32Array())
		for ei in side_ents.size():
			var e2: BattleEntity = side_ents[ei]
			if not is_instance_valid(e2):
				continue
			var f := Vector2.ZERO
			## 【权重表 20261030（新三 221 行作者更新）】dm_apfrepul：
			## Ht1 Hd3 Hcs5 Hct5 He2 Hp2 Ha5（分母28；Ha 采样本批接入）
			
			## 攻击态势(a/c)：Hcs/Hct 权重 0 且【不开启实时运算】（新三原文）；
			## 中性(r/n/s) Hct 0
			var card := e2.current_sit_card
			var w_hcs := 5.0 if card in ["d", "h", "e"] else 0.0
			var w_hct := 5.0 if card in ["d", "h", "e"] else 0.0
			if _dir16.size() != 16:
				_dir16.clear()
				for dk in 16:
					var da := -PI / 2.0 + TAU * float(dk) / 16.0
					_dir16.append(Vector2(cos(da), sin(da)))
			for k in 48:
				var dv2: Vector2 = _dir16[k % 16]
				if time_frames % 2 == 1:
					dv2 = dv2.rotated(TAU / 32.0) ## 带转偏移（原 spin2 口径）
				var rr := 6.0 if k < 16 else (12.0 if k < 32 else 30.0)
				var idx := ei * 49 + k ## 步长49（48环点+1中心）
				var v_he: int = a_he[idx] if idx < a_he.size() else 0
				var v_hd: int = a_hd[idx] if idx < a_hd.size() else 0
				var v_hp: int = a_hp[idx] if idx < a_hp.size() else 0
				var v_ha: int = a_ha[idx] if idx < a_ha.size() else 0
				## Ht 权重=同向十六点；Shs 权重（新二）：攻击态势 Shs-1d=0、Shs-2d=1
				var ring_arr: PackedInt32Array = e2.sit16_1d if k < 16 else (e2.sit16_2d if k < 32 else e2.sit16_5d)
				var v_ht: int = ring_arr[k % 16] if (k % 16) < ring_arr.size() else 0
				var shs_w := 1.0
				if card == "a" or card == "c":
					shs_w = 0.0 if k < 16 else 1.0
				var v_hcs: float = e2.hcs_pts[idx] if idx < e2.hcs_pts.size() else 0.0
				var v_hct: float = e2.hct_pts[idx] if idx < e2.hct_pts.size() else 0.0
				var hot := (float(v_ht) / 255.0) * 1.0 * shs_w + (float(v_hd) / 255.0) * 3.0 					+ (v_hcs / 255.0) * w_hcs + (v_hct / 255.0) * w_hct 					+ (float(v_he) / 255.0) * 2.0 + (float(v_hp) / 255.0) * 2.0 + (float(v_ha) / 255.0) * 5.0
				f -= dv2 * (hot / 28.0) * (rr / maxf(e2.normal_speed() * 30.0, 1.0))
			e2.set_meta("map_force", f.limit_length(1.0))
			var ci := ei * 49 + 48
			e2.set_meta("hd_at", a_hd[ci] if ci < a_hd.size() else 0)
			## 【新三 227 行为卡权重（1106）】dm_situate=Ht1 Hd3 Hr3 He1 Hp1
			## ——中心采样值（第49点）一并回写供 sit_mean 加权
			var a_hr2: PackedInt32Array = multi.get("Hr" + sfx, PackedInt32Array())
			var a_he2: PackedInt32Array = multi.get("He" + sfx, PackedInt32Array())
			var a_hp2: PackedInt32Array = multi.get("Hp" + sfx, PackedInt32Array())
			e2.set_meta("hr_at", a_hr2[ci] if ci < a_hr2.size() else 0)
			e2.set_meta("he_at", a_he2[ci] if ci < a_he2.size() else 0)
			e2.set_meta("hp_at", a_hp2[ci] if ci < a_hp2.size() else 0)
	_fam_pending2 = _fam_pending
	_fam_pending = []
	## —— 态势十六点性能检测：控制台周期输出（作者批复要求）——
	_heat_print_acc += 0.1
	if _heat_print_acc >= 10.0 and OS.get_environment("TH75_DEBUG_PRINT") == "1":
		## 【0.0.9·运行探针优化（作者批"实时检测影响运行"）】周期控制台 print
		## 在 Windows console 下是阻塞 IO（每 10 秒一次也可能 ms 级卡顿）——
		## 默认关闭；需采集时设 TH75_DEBUG_PRINT=1
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
var _dt_held: Dictionary = {} ## 【0.0.9·双击修复】key -> 上一帧是否按住（上升沿检测）
var _hold_a := 0              ## 【0.0.9·长按 A】按住帧数（=30 即半秒 触发轮换，每次按住一次）
## 【0.0.9·机控临时点（新二 82 行）】按住 E+左键宣布集结点→1/2/3（每场重置，循环覆盖）
var _temp_points: Array = [Vector2.INF, Vector2.INF, Vector2.INF]
var _temp_next := 0
var _cmd_ent: BattleEntity = null   ## G 指令对象（下达时的选中角色——引力只作用于它）
var _cmd_ent_b: BattleEntity = null ## B 指令对象
## —— 【0.0.9·决斗操作批 20261106】右下面板/召唤轮盘/杂兵面板 ——
## —— 【0.0.9·指令字幕（作者批 20261106）】左上角 3 秒渐隐，告知玩家刚触发的指令 ——
var _toasts: Array = []         ## [{text, frames}]（180 帧=3 秒线性淡出）
func _toast(txt: String) -> void:
	_toasts.append({"text": txt, "frames": 180, "label": _toast_label(txt)})
	if _toasts.size() > 5:
		var old = _toasts.pop_front()
		if old["label"] != null:
			old["label"].queue_free()
	_toasts[0]["label"].position = Vector2(8, 46) ## 左上角（热力图标签下方）

func _toast_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = Vector2(8, 46 + _toasts.size() * 20)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	hud.add_child(l)
	return l

var _br_page := 0               ## 右下面板页：0=关 1=角色详细状态 2=机控热键（H 切换）
var _br_label: Label = null
var _wheel_open := false        ## 召唤轮盘（Shift+S 选中角色时呼出）
var _wheel_sel := -1            ## 轮盘鼠标悬停槽位
var _wheel_frames := 0          ## 轮盘超时（300 帧=5 秒→自动第一位）
var _wheel_cands: Array = []    ## 轮盘候选（demo 角色池——候补数据源待作者裁定）
var _wheel_target: BattleEntity = null
var _priv_panel := false        ## 杂兵面板（Tab 按住呼出）
var _priv_tab_lock := false     ## 【锁 tab（作者释）】双击面板外区域→本次按住 Tab 失效；松开重按解锁
var _ml_last := 0               ## 左键双击检测
var _priv_sel := -1             ## 面板内滚轮选取序号
var _cmd_arm_b := false         ## B 点防待命（G 同款架构）
var _cmd_point_b := Vector2.ZERO
var _cmd_frames_b := 0
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
				_toast("团队指令：%s（5 秒）" % ("冒进" if qw else "龟缩防御"))
	else:
		_combo_frames = 0
	## 【0.0.9·双击修复 20261109】原判 `not _dt_last.has(key)` 首次写入后恒假=双击
	## W/S/A/D 永不触发（死代码）——改上升沿检测：0.4 秒内第二次按下=双击
	for key in [KEY_W, KEY_S, KEY_A, KEY_D]:
		var down := Input.is_physical_key_pressed(key)
		var was: bool = _dt_held.get(key, false)
		_dt_held[key] = down
		if down and not was:
			if time_frames - int(_dt_last.get(key, -999)) < 24:
				match key:
					KEY_W: team_stance = "attack"
					KEY_S: team_stance = "defend"
					KEY_A, KEY_D: team_stance = "side"
				team_stance_frames = 300
				_toast("团队姿态：%s（5 秒）" % {"attack": "进攻", "defend": "保守", "side": "侧面"}.get(team_stance, team_stance))
				_dt_last[key] = -999
			else:
				_dt_last[key] = time_frames
	## 【0.0.9·长按 A（新二 127 行）】按住半秒=轮换（原单击即触发，与双击 A 侧面姿态冲突）
	if Input.is_physical_key_pressed(KEY_A) and not Input.is_physical_key_pressed(KEY_SHIFT):
		_hold_a += 1
		if _hold_a == 30:
			_swap_selected_character()
	else:
		_hold_a = 0

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
	var hr_gate: bool = time_frames % 2 == 0 ## 【0.0.9·审计A7】Hr 扫描降 30Hz（原每实体每帧 128 弹）
	for b2 in bullets:
		if not hr_gate:
			break
		var bl2: Bullet = b2
		hr_scan += 1
		if hr_scan > 128:
			break
		if bl2.hidden_now or bl2.cur_speed() < 4.0 or bl2.source_side == ent.side:
			continue
		var to_ent: Vector2 = ent.position - bl2.pos
		if to_ent.length() > n_spd2 * 60.0 * 1.5:
			continue
		if to_ent.dot(bl2.cur_dir()) < n_spd2 * 60.0 * 1.0:
			continue
		var perp3 := Vector2(-bl2.cur_dir().y, bl2.cur_dir().x)
		if to_ent.dot(perp3) < 0.0:
			perp3 = -perp3
		var mag3 := bl2.cur_speed() * 4.0
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
	## 【0.0.9·机控引力圈（新三 227）】指令 5 秒；引力圈=下达后 2 秒内从 255 线性
	## 衰减（再次下达=重置=延长而非叠加）；只作用于下达时选中的角色（新二 114/118）
	if cmd_frames > 0 and ent == _cmd_ent:
		var ring := maxf(0.0, 1.0 - float(300 - cmd_frames) / 120.0)
		push += (cmd_point - ent.position).normalized() * ring * 0.7
	if _cmd_frames_b > 0 and ent == _cmd_ent_b:
		var ring_b := maxf(0.0, 1.0 - float(300 - _cmd_frames_b) / 120.0)
		var to_b: Vector2 = _cmd_point_b - ent.position
		## 指定位置防御：靠近该点（30px 内停住=就地防御）
		if to_b.length() > 30.0:
			push += to_b.normalized() * maxf(ring_b, 0.35) * 0.7
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
	if _cmd_frames_b > 0 and ent == _cmd_ent_b:
		anchor = 0.0 ## 【B 指令】防御中不追击（锚定归零；火力照常）
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
	## 【0.0.9·资源引力（新三 243）20261109】非防御态势（d/h 之外）：最近的 P 点/
	## 符卡掉落提供四分之一慢机速度的引力（push 量纲 1=慢机速度→0.25）；双方可拾。
	## 置于锚定/限幅之后=第二级直接力（不被锚定 ×0.35 缩放——新三 243 列于第二级）
	if ent.current_sit_card not in ["d", "h"] and not drops.is_empty():
		var best_d := 1e9
		var best_p := Vector2.INF
		for drp in drops:
			var dd2: float = (drp["pos"] as Vector2).distance_to(ent.position)
			if dd2 < best_d:
				best_d = dd2
				best_p = drp["pos"]
		if best_p != Vector2.INF and best_d > 0.5:
			push += (best_p - ent.position) / best_d * 0.25
	## 【0.0.9·基础规避 BC（新三 213-218）20261109】APF 后的最终一层（其输入=上面
	## 全部分级力的合力 push，量纲 1=慢机速度）：
	##   四弧（上/下/左/右）中线各一力：基力 256×(1-阻断比例)；push 分解到四向的
	##   分力 ÷慢机速度（×256 归入同量纲）为加成（同向=引力）/减成（反向=斥力）；
	##   合力=速度方向，标量×慢机速度/256=速度，超慢机速度取慢机速度（比例速度）。
	##   无弹时四基力互相抵消=退化为 push 本身；某向弧内贴弹→该向力被削→反向逃逸。
	## 阻断比例每 0.05 秒（3 帧，实体错相）检测并保持（"接下来的 0.05 秒"）。
	var bc_k := 1.0
	if bc_enabled:
		if (time_frames + (ent.get_instance_id() % 3)) % 3 == 0:
			ent.bc_block = _bc_rays(ent, n_speed * 6.0) ## 射线长=0.1 秒距
		var bc_axis := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
		var bc_net := Vector2.ZERO
		for bi in 4:
			var ax: Vector2 = bc_axis[bi]
			var f_k := 256.0 * (1.0 - float(ent.bc_block[bi])) + 256.0 * ax.dot(push)
			bc_net += ax * f_k
		## 合力标量×慢机速度/256 → 慢机速度比例（≤1）；方向替代 push
		bc_k = minf(bc_net.length() / 256.0, 1.0)
		push = bc_net / 256.0 if bc_net.length() > 0.001 else Vector2.ZERO
	if push.length() < (0.004 if bc_enabled else 0.15):
		ent.move(Vector2.ZERO, time_scale, bc_k)
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
		ent.move(final_dir, time_scale, bc_k) ## 【BC】比例速度（快机不受此比例）

func _entity_ticks(dt: float) -> void:
	_live_ent_pos_dirty = true
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
				## 【22b 20261102d·新三 219 权重细化】杂兵 APF=Hd2+所属角色 Hcs5
				## （原用 sit16=Ht 代理——Hd 位置采样值已在 hd_at meta）
				var v_hd3: float = float(owner2.get_meta("hd_at", 0))
				var hot3 := (v_hd3 / 255.0) * 2.0 + (v_hcs3 / 255.0) * 5.0
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
		## 【dm_situate 权重（新三 227·1106 作者修订）】Ht1 Hd3 Hr3 He1 Hp1（分母 9）
		## Hr 采样中心值本批接入（此前快弹印章时代恒空）
		var sum := 0
		for v in ent.sit16_1d:
			sum += v
		var mean := sum / 16 if ent.sit16_1d.size() == 16 else 0
		var wsum := float(mean) * 1.0 + float(ent.get_meta("hd_at", 0)) * 3.0 			+ float(ent.get_meta("hr_at", 0)) * 3.0 + float(ent.get_meta("he_at", 0)) * 1.0 			+ float(ent.get_meta("hp_at", 0)) * 1.0
		ent.set_meta("sit_mean", int(wsum / 9.0))
		ent.set_meta("sit_mean_ht", mean) ## 原始 Ht 均值（滞回阈值口径）
		var sp := ent.mood_sp()
		ent.sit_cards.mood_s = sp[0]
		ent.sit_cards.mood_p = sp[1]
		ent.sit_cards.sit_mean = mean
		## 【修复：态势UI全红】has_apf_field 恒 false → c→a / d→h 替换永远生效，
		## 卡组恒为红色 a。策划"引力场"来源现状：玩家姿态指令 / 战术号召 / 机控指令圈
		ent.sit_cards.has_apf_field = (team_stance != "") or (ent.current_tactic != "") or (cmd_frames > 0 and ent == _cmd_ent) or (_cmd_frames_b > 0 and ent == _cmd_ent_b)
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
		## 【0.0.9·RET 轮转（性能裁定量化：单帧 spike 21-24ms 元凶）】
		## RET 树搜索按实体序 6 组轮转——每实体 10Hz 保持、单帧只算 1/6
		if ent.ret != null and entities.find(ent) % 6 == time_frames % 6:
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
		## 【0.0.9·回退分帧 20261108（作者实测：部分角色彩虹条不动）】
		## 拍间隔恰为 6 帧——time_frames%6 组号恒定=同一组每拍被处理、
		## 其余 5/6 角色卡组停摆。恢复每拍全实体（抽卡语义 10Hz）；
		## spike 治理改走审计 C3（消弹 hash 化）+RET 轮转（已做，保持）
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
	## 【22b 20261030c 效能化】同 _clear_bullets_around：倒序+平方距
	var rr2: float = radius * radius
	var qx: float = ent.position.x
	var qy: float = ent.position.y
	for ci in range(bullets.size() - 1, -1, -1):
		var bl: Bullet = bullets[ci]
		if bl.hidden_now or bl.source_side == ent.side:
			continue
		var ddx: float = bl.pos.x - qx
		var ddy: float = bl.pos.y - qy
		if ddx * ddx + ddy * ddy <= rr2:
			## 【0.0.9·回收风暴修复 20261107】remove_at O(n) 搬迁——大规模消弹/
			## 到期潮时 O(n²)（几百弹同帧回收=数十万次数组移动/帧）。
			## 三处回收均倒序遍历→swap-remove O(1) 安全（换上来的尾段已处理）
			bullets[ci] = bullets[bullets.size() - 1]
			bullets.pop_back()
			cleared += 1
			## 【0.0.9·作者裁定 20261109】消弹弹**直接销毁、不入回收池**
			## （入池可能扰乱回收序列；残热/复用隐患一并消除）
			mh_release(bl) ## 【审计①-1】属主校验释放
			bl.ev = null
	## 【22b 20261104·消弹残影】释放消弹同样清 DDM 区域（衰减尾巴+Ht 加热
	## 源头一并消除——作者实测"滞留原位持续加热"）
	if cleared > 0 and gpu_ok:
		ddm_gpu0.clear_region(qx, qy, int(radius) + 8)
		ddm_gpu1.clear_region(qx, qy, int(radius) + 8)
		## 【0.0.9·消弹热清零（作者批）】Ht 同步清零（与 DDM 同拍——消弹区
		## 热立即归零；扩散语义保持）
		for hts in ht_side:
			if hts != null and hts.ok:
				hts.clear_region(qx, qy, int(radius) + 8)
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
	## 【22b 20261030c 效能化】原版 duplicate()+erase（每命中 O(n) 数组搬移
	## +每拍一次全表拷贝）→ 倒序 remove_at O(1)/命中 + 距离平方比较（免 sqrt）
	var r2: float = ent.clear_radius * ent.clear_radius
	var px: float = ent.position.x
	var py: float = ent.position.y
	for i in range(bullets.size() - 1, -1, -1):
		var bl: Bullet = bullets[i]
		if bl.hidden_now or bl.source_side == ent.side:
			continue
		var dx: float = bl.pos.x - px
		var dy: float = bl.pos.y - py
		if dx * dx + dy * dy <= r2:
			bullets[i] = bullets[bullets.size() - 1] ## 【回收风暴修复】swap-remove
			bullets.pop_back()
			_cleared_count += 1
			## 【0.0.9·作者裁定】消弹弹直接销毁、不入池（同上）
			mh_release(bl) ## 【审计①-1】属主校验释放
			bl.ev = null
	## 【22b 20261103·消弹残影】DDM+热力图族区域清 0（衰减尾巴+滞留消除）
	if _cleared_count > 0 and gpu_ok:
		ddm_gpu0.clear_region(ent.position.x, ent.position.y, int(ent.clear_radius) + 8)
		ddm_gpu1.clear_region(ent.position.x, ent.position.y, int(ent.clear_radius) + 8)
		for htc in ht_side:
			if htc != null and htc.ok:
				htc.clear_region(ent.position.x, ent.position.y, int(ent.clear_radius) + 8)
		for hvc in hv_side:
			if hvc != null and hvc.ok:
				hvc.clear_region(ent.position.x, ent.position.y, int(ent.clear_radius) + 8)

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
	bullet_hash.clear()
	if bullet_hash_cpp != null:
		bullet_hash_cpp.begin_frame() ## 【审计 Top2】C++ 空间哈希并行构建
		_hash_objs.clear() ## 【0.0.9·哈希映射修复 20261109】插入序→Bullet 对象表（与 C++ 插入序号一一对应）
	## 【0.0.9·审计①-1 完整状态 C++ 接管 20261109】纯定值弹的 t/存活帧/pos/
	## 航程死/出界死由 C++ 单一写者推进；此处单点回填（GD 只读不写），
	## 死亡弹置 alive=false 交主循环统一回收（与 GD 自然死亡同一出口）。
	if motion_hot != null and motion_hot_enabled:
		motion_hot.begin_frame(1.0)
		var mo: PackedFloat64Array = motion_hot.get_frozen_pos()
		var k := 0
		while k < mo.size():
			var ob: Bullet = _mh_slot_owner[int(mo[k])] if int(mo[k]) < _mh_slot_owner.size() else null
			if ob != null and ob._mh_owned:
				ob.t += 1.0
				ob._alive_frames += 1.0
				ob.pos = Vector2(mo[k + 1], mo[k + 2])
			k += 3
		for md in motion_hot.get_dead():
			var dbl: Bullet = _mh_slot_owner[md] if md < _mh_slot_owner.size() else null
			if dbl != null and dbl._mh_owned:
				dbl._mh_dead = true
	var gctx := {"field_t": float(time_frames), "field_phase": phase}
	## 【22b 20261028】collapse_counts 挪到循环外（原每弹 Dictionary 新建）
	gctx.merge(bullet_collapse_counts())
	var sn := _sample_n
	for i in range(bullets.size() - 1, -1, -1):
		var b: Bullet = bullets[i]
		var alive_now: bool
		if b._mh_owned:
			## 【审计①-1】C++ 接管弹：update() 整帧跳过（状态已由 C++ 回填）
			alive_now = not b._mh_dead
		elif not b._mh_checked and motion_hot != null and motion_hot_enabled and b.mh_eligible():
			## 【审计①-1·交接帧】首遇即接管：本帧走一次精确逐帧 update(dt)
			## （采样模式下也不走大步进/插值——交接态 t/pos 与解析式严格同步），
			## 下一帧起 C++ 单一写者推进
			b._mh_checked = true
			b.sync_shared(gctx)
			alive_now = b.update(dt)
			if alive_now:
				mh_own(b)
		else:
			b._mh_checked = true
			## 【20261028·作者规则】弹幕更新必须 60 帧——交错半帧实验撤销
			b.sync_shared(gctx)
			## 【0.0.9·采样平滑（作者设计）】采样帧=公式大步进（t 增量总和）；
			## 中间帧=向目标线性插值（判定/消弹/DDM 全用插值位置=所见即所判）
			## 【0.0.9·分型采样（作者红线终解）】仅 frozen_ok（定值解析）弹采样
			## ——大步进=解析精确（误差 0）；t 依赖表达式弹（sonic 类 log 速度
			## 剧变段大步进积分差实测 139px）退回逐帧原运算（完全正常）
			## 【0.0.9·作者实测"原地停留"修复 20261108】else 的 update(dt*sn) 把
			## 非 frozen 弹（FUNCTED/PHYSICAL/NODES/LASER/表达式——Enisuel/Nitori/
			## Xlonia/Youshio）也大步进+采样收尾 pos 回起点=原地冻结——改三分：
			## 非 frozen 恒逐帧原运算
			if sn > 1 and b.frozen_ok and (time_frames + b._sample_phase) % sn != 0:
				alive_now = b.update_smooth(sn)
			elif sn > 1 and b.frozen_ok:
				alive_now = b.update(dt * sn) ## 采样帧：大步进（t 增量总和·解析精确）
			else:
				alive_now = b.update(dt) ## 非 frozen：逐帧原运算（完全脱离采样）
		if not alive_now:
			bullets[i] = bullets[bullets.size() - 1] ## 【回收风暴修复】swap-remove
			bullets.pop_back()
			_expired_count += 1
			_pool_retire(b)
			## 【0.0.9·审计#47 修订】载体死亡：剩余补发转 cannon 节点接管
			## （补发不再随载体死亡中断=零星发射修复；freq 用尽自毁）
			if b.repeat_enabled and b._repeat_fired < b.repeat_freq_now and b.source != null and not b.source.dead:
				var rp_dead: Dictionary = {"time": b.repeat_time_now, "freq": b.repeat_freq_now - b._repeat_fired}
				if _cannons.size() < 256:
					_cannons.append({"ev": b.ev, "point": null, "src": b.source,
						"rolls": {}, "rpt": rp_dead, "sp": {}, "timer": 0,
						"fired": b._repeat_fired, "origin0": b.repeat_origin()})
			continue
		b._prev_pos = b.pos
		if not b.hidden_now: ## 【高危修复】hidden 弹不入哈希（不参与判定）
			bullet_hash.insert(b)
			if bullet_hash_cpp != null:
				## 【审计 Top2】ref_id=bullets 当帧下标（swap-remove 仅帧尾回收——当帧稳定）
				bullet_hash_cpp.insert(b.pos.x, b.pos.y, b.hit_radius(), i, b.source_side, b.ev.is_phy)
				_hash_objs.append(b) ## 【哈希映射修复】C++ 返回插入序号——按序号取对象（非 bullets 下标）
		if b._mh_owned:
			continue ## 【审计①-1】接管弹非 repeat 载体（资格已排除）——免 repeat_tick 调用
		## 【0.0.9·采样平滑配套】repeat_tick 每调补一发——while 消费（cap 8 防爆）
		var rguard := 0
		while b.repeat_tick() and rguard < 8:
			rguard += 1
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
				## 【22b 20261031c·审计#34】repeat 补发子弹：复用载体的 spawn/repeat
				## 参数（同事件同系——原 setup 内重跑 9 次 eval）
				var child := _spawn_bullet(b.ev, b.repeat_origin(), b.depth + 1, b.source, null,
					0.0, 0, {}, Vector2.ZERO, b.t, null, Vector2.INF,
					{"dmg": b.dmg_now, "size": b.size_mul, "range": b.range_now,
					"alarm": b.alarm_now}, {}, "rp_child") ## 【审计#47】rp 不复用——补发子弹 rotate 参数从自身事件重求
				if child != null:
					child.repeat_enabled = false
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
		## 【0.0.9·恢复 20261109】被弹结算主体——第五十二轮回退语义改动时 Edit
		## 旧串匹配误删（约 55 行，角色完全不受伤）；从 battle_arena_20261109i
		## 原样恢复（去掉已随抑制方案撤除的 clear_zone_reset 段）
		var r: float = ent.barrier_radius() if ent.ap > 0 else ent.judge_radius()
		## 【20261003修复·重大】skip_side=本侧（跳过本方法弹）——旧版传 1-ent.side
		## 把敌方法弹全跳过了（只有友方物弹能打中自己，方向反转的隐性大坑）
		var keys: Dictionary
		if bullet_hash_cpp_enabled and bullet_hash_cpp != null and bullet_hash_cpp.count() > 0:
			## 【防御】count()==0（begin_frame 未跑——smoke 手动直调 _resolve_hits）→跳过 C++（空格查询会越界）
			## 【审计 Top2】C++ 粗查询（ref_ids）→GD 端 per-hit 成员判定/组装
			var ids: PackedInt32Array = bullet_hash_cpp.query(ent.position.x, ent.position.y, r, ent.side)
			keys = {}
			for rid in ids:
				var hb: Bullet = _hash_objs[rid] if rid < _hash_objs.size() else null ## 【哈希映射修复】
				if hb != null and hb.ev == null:
					continue ## 已被消弹销毁（同帧插入后）
				if hb == null or hb.hidden_now:
					continue
				if hb.source_side == ent.side and not hb.ev.is_phy:
					continue ## 法弹不伤发射方（与 GD 版同语义）
				if hb.source == ent and hb.ev.is_phy and not hb.beyond_mask():
					continue ## 物弹未出友伤遮罩：不打发射者自己
				if not hb.overlaps_circle(ent.position.x, ent.position.y, r):
					continue
				var mode_i: int = 0 if hb.ev.dmg_mode == "N" else (1 if hb.ev.dmg_mode == "I" else 2)
				var key: int = hb.hit_damage() * 4 + mode_i
				if not keys.has(key):
					keys[key] = []
				(keys[key] as Array).append((hb.pos - ent.position).angle())
		else:
			keys = bullet_hash.query_keys(ent.position.x, ent.position.y, r, ent.side, ent)
		if keys.is_empty():
			continue
		## 首个命中即结算——不排序（作者：能跳则跳）
		## 【22b 20261103·审计#44】被弹=同帧最高伤害优先（策划"最高伤害"规则；
		## 原首个命中即结算=低伤弹抢额）——取 dmg 最大的键
		var best_dmg := 0
		var best_mi := 0
		var best_ang := 0.0
		for key in keys:
			## 整型复合键（dmg*4+模式）——20261004 R8
			var dmg := int(key) >> 2
			var mi := int(key) & 3
			if dmg <= 0:
				continue
			if dmg > best_dmg:
				best_dmg = dmg
				best_mi = mi
				var angles: Array = keys[key]
				best_ang = angles[0] if not angles.is_empty() else 0.0
		if best_dmg > 0:
			## 【0.0.9·万岁冲锋（新二 141 行）】角色即将被弹→万岁杂兵替死挡弹
			## （持续 30 秒或至其被击败；一次抵挡一次替死）
			if _take_banzai_hit(ent):
				continue
			ent.take_hit(best_dmg, best_mi, best_ang)

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

## 【22b 20261031d·架构改造②】Bullet 对象池：RefCounted 每发 new/free 的
## 分配+GC 压力（发射风暴 44 发/帧×120µs setup 的构成之一）→ 池化复用。
const BULLET_POOL_SIZE := 4096
var _bullet_pool: Array = []
var _bullet_live: Array = [] ## 池中在用标记（弹 dead 时归还）

func _pool_get() -> Bullet:
	var b: Bullet
	if not _bullet_pool.is_empty():
		b = _bullet_pool.pop_back()
	else:
		b = Bullet.new()
	return b

func _pool_retire(b: Bullet) -> void:
	mh_release(b) ## 【审计①-1】slot 释放（属主校验——防同帧复用 slot 被误释放）
	_retired_count += 1
	if _bullet_pool.size() < BULLET_POOL_SIZE:
		_bullet_pool.append(b)

## =============================================================
## 【0.0.9·审计①-1 完整状态 C++ 接管 20261109】
## slot 属主表：slot → Bullet（注册时写、释放时清）。帧首回填 O(1) 定位，
## 免去每帧重建 slot→下标字典。
## 释放必须校验属主：C++ 判死的 slot 在 begin_frame 内已回收，同帧主循环
## 里新补发的弹可能领走同一 slot——此时旧弹 retire 不得再释放它。
## =============================================================
var motion_hot_enabled := true ## 【对照开关】false=全部弹走 GD 原路径
var _mh_slot_owner: Array = []

func mh_own(b: Bullet) -> void:
	if b._mh_owned or motion_hot == null or not motion_hot_enabled:
		return
	var s: int = motion_hot.register_frozen(b.origin.x, b.origin.y, b.dir.x, b.dir.y,
		b.frozen_speed, b.t, b._alive_frames, b.pos.x, b.pos.y, b.range_now, b.draw_radius, b.ev.oob_mode,
		b.source_side, b.ev.is_phy, b.hidden_now)
	if s >= _mh_slot_owner.size():
		_mh_slot_owner.resize(s + 1)
	_mh_slot_owner[s] = b
	b.mh_slot = s
	b._mh_owned = true
	b._mh_dead = false
	b._bulk_skip = true ## 防御：即便误入 update，frozen 分支也不写 pos

func mh_release(b: Bullet) -> void:
	var s: int = b.mh_slot
	if s >= 0 and s < _mh_slot_owner.size() and _mh_slot_owner[s] == b:
		_mh_slot_owner[s] = null
		if motion_hot != null:
			motion_hot.set_frozen_alive(s, false)
	b.mh_slot = -1
	b._mh_owned = false
	b._mh_dead = false
	b._bulk_skip = false

func _spawn_bullet(ev: DanmakuEventData, origin: Vector2, depth: int, src: BattleEntity, point = null,
		rot := 0.0, rid := 0, rolls: Dictionary = {}, pinned := Vector2.ZERO, event_t := 0.0,
		shared_target: BattleEntity = null, shared_txy: Vector2 = Vector2.INF,
		setup_sp: Dictionary = {}, setup_rp: Dictionary = {}, src_tag: String = "fire") -> Bullet:
	if ev == null or depth > Bullet.MAX_DEPTH:
		return null
	## 【0.0.9·池满策略】满仓时批量驱逐最旧弹（每次腾 64 位），避免
	## 逐发挤占导致活跃弹幕被系统性清空（作者实测 sonic 被清空）
	## 【0.0.9·池满策略 v2（作者实测 sonic 被清空）】优先驱逐将死弹
	## （存活>80% 航程），保护年轻弹幕——两遍扫描：
	## 第一遍驱逐将死弹；仍满则第二遍按最旧驱逐（兜底）
	if bullets.size() >= MAX_BULLETS:
		var dying: Array = []
		for di in bullets.size():
			var bd: Bullet = bullets[di]
			if bd._alive_frames > bd.range_now * 0.8:
				dying.append(di)
		var removed := 0
		for di in range(dying.size() - 1, -1, -1):
			var bi: int = dying[di]
			if bi < bullets.size():
				_pool_retire(bullets[bi])
				bullets.remove_at(bi)
				removed += 1
		var remain_evict: int = maxi(0, mini(64, bullets.size() - MAX_BULLETS + removed))
		for ei2 in remain_evict:
			if ei2 < bullets.size():
				_pool_retire(bullets[ei2])
		if remain_evict > 0:
			bullets = bullets.slice(remain_evict)
	var b := _pool_get()
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
	b.setup(ev, origin, src.side, src, self, depth, ctx, shared_target, shared_txy, setup_sp, setup_rp)
	b.spawn_src = src_tag ## 【谱系追踪】出生路径标签
	b.tex_slot = _ddm_tex_slot(b.tex)
	if b.tex_slot > 0:
		_upload_ddm_tex(b.tex_slot, b.tex)
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
	if bullet_hash_cpp_enabled and bullet_hash_cpp != null:
		## 【审计 Top2】C++ 粗查询 + GD 端 per-hit 成员判定（语义与纯 GD 一致）
		var ids: PackedInt32Array = bullet_hash_cpp.query(cx, cy, r, hit_side)
		var out := {}
		for rid in ids:
			var hb: Bullet = _hash_objs[rid] if rid < _hash_objs.size() else null ## 【哈希映射修复】
			if hb != null and hb.ev == null:
				continue ## 已被消弹销毁（同帧插入后）
			if hb == null or hb.hidden_now:
				continue
			if hb.source_side == hit_side and not hb.ev.is_phy:
				continue
			if not hb.overlaps_circle(cx, cy, r):
				continue
			var mode_i2: int = 0 if hb.ev.dmg_mode == "N" else (1 if hb.ev.dmg_mode == "I" else 2)
			var key: int = hb.hit_damage() * 4 + mode_i2
			if not out.has(key):
				out[key] = []
			(out[key] as Array).append((hb.pos - Vector2(cx, cy)).angle())
		return out
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
	## 【0.0.9·重写 20261104】DDM 注册——每 2 帧全清重画（30Hz）：
	## 图归属按策划（敌方法弹+物弹→对方图；物弹超遮罩→己方图）。
	## 唯一数据源=export_stamps（真实状态现算），本函数零状态。
	## 【0.0.9】暂停时 DDM 停更（弹不动图不变）
	if pause_panel != null and pause_panel.visible:
		return
	if finished:
		return
	if not gpu_ok:
		return
	if time_frames % 2 != 0:
		return
	_stamp_buf0.clear()
	_stamp_buf1.clear()
	## 【0.0.9·消弹区 stamp 跳过（作者实测"消弹区热力闪烁"修复）】
	## 清除期（clear_active）内的弹下一帧即被消——stamp 它们=DDM 白→Ht+64→
	## 下一帧消→DDM 黑→Ht 衰减→**闪烁循环**。跳过=消弹区 Ht 保持干净
	var _clear_zones: Array = []
	for e2 in entities:
		if e2 is BattleEntity and (e2 as BattleEntity).clear_active():
			_clear_zones.append([e2.position, e2.clear_radius])
	for b in bullets:
		var bl: Bullet = b
		if bl.hidden_now or not bl.alive:
			continue
		## 【0.0.9·所见即所判修复 20261109】stamp 原无场外检查——弹圆未与
		## 场地相交的弹（oob=2 环带游荡）也 stamp=DDM 白但屏幕无弹
		## （Ht"零星诈尸"实锤）。统一口径：弹圆与场地相交才 stamp（与 MM 同）
		if not _in_field(bl.pos, bl.draw_radius):
			continue
		var in_clear := false
		for cz in _clear_zones:
			if bl.pos.distance_to(cz[0]) < float(cz[1]):
				in_clear = true
				break
		if in_clear:
			continue
		var beyond := bl.ev.is_phy and bl.beyond_mask()
		if bl.source_side == 0:
			_stamp_buf1 = _export(bl, _stamp_buf1)
			if beyond:
				_stamp_buf0 = _export(bl, _stamp_buf0)
		else:
			_stamp_buf0 = _export(bl, _stamp_buf0)
			if beyond:
				_stamp_buf1 = _export(bl, _stamp_buf1)
	ddm_gpu0.render(_stamp_buf0)
	ddm_gpu1.render(_stamp_buf1)


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
			"Hr 快弹警告", "Hp 敌方规律", "Hcs 角色1s图", "Hct 角色s20图", "Ha 全局抽象"]
		var side_txt := "我方" if _heat_view_side == 0 else "敌方"
		var focus_name: String = _heat_focus.chara_name() if _heat_focus != null and is_instance_valid(_heat_focus) else "未选(F1)"
		var sit_txt := ""
		if _heat_focus != null and is_instance_valid(_heat_focus) and _heat_focus.sit16_1d.size() == 16:
			var s1 := 0
			for v in _heat_focus.sit16_1d:
				s1 += v
			sit_txt = " 1d均值=%d" % (s1 / 16)
		var ret_txt := " RET接管" if _heat_focus != null and is_instance_valid(_heat_focus) and _heat_focus.get_meta("ret_mode", false) else ""
		## 【22b 20261103·修D】标签描述扩展：Hcs/Hct 附带"态势十六点/回读"来源说明
		var desc_extra := ""
		if _heat_view == 7:
			desc_extra = " [态势十六点·Hcs 1s 时空分布]"
		elif _heat_view == 8:
			desc_extra = " [态势十六点·Hct 20帧避险]"
		elif _heat_view == 4:
			desc_extra = " [Ht 派生·半径2高斯·等高线8px]"
		elif _heat_view == 6:
			desc_extra = " [Hd 派生·慢记忆规律]"
		elif _heat_view == 5:
			desc_extra = " [Hr 快弹轨迹·半径2高斯·等高线8px]"
		elif _heat_view == 9:
			desc_extra = " [Ht 派生·25×25 马赛克]"
		_heat_label.text = "%s|%s(%s)%s%s%s" % [names[_heat_view] if _heat_view > 0 else "图:关", focus_name, side_txt, sit_txt, ret_txt, desc_extra]
	if _debug_hint_label != null and _debug_used:
		_debug_hint_label.text = "调试：F1/F3/[ 切热力图 ]切帧序 F2十六点 F1选角色 滚轮换角色 F4慢速0.25 V轮射 G点攻 B点防 Esc菜单"
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
		if _wheel_open:
			pass ## 轮盘期间滚轮让位（鼠标选槽）
		elif _priv_panel:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_priv_sel = maxi(0, _priv_sel - 1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_priv_sel += 1
		else:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_pick_idx = maxi(0, _pick_idx - 1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_pick_idx = _pick_idx + 1
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				## 取消当前指令（新二 101：姿态/冒进/防御类非瞬时指令）
				team_stance = ""
				cmd_frames = 0
				_cmd_frames_b = 0
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _priv_panel:
		## 【锁 tab（作者释）】面板显示中双击面板外区域→本次按住 Tab 失效
		var mr := Rect2(8, 300, 170, 24 + 6 * 18) ## 面板矩形（与 _draw_priv_panel 同域）
		var mouse_field: Vector2 = get_global_mouse_position()
		var in_panel := false
		for pi in 1:
			break ## 占位（面板挂 hud 屏幕域，鼠标屏坐标直接比对）
		if not (mouse_field.x >= 8 and mouse_field.x <= 178 and mouse_field.y >= 300 and mouse_field.y <= 432):
			if time_frames - _ml_last < 24:
				_priv_tab_lock = true
				_priv_panel = false
				_toast("杂兵面板锁定（松开 Tab 重按解锁）")
			_ml_last = time_frames
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and (_cmd_arm_b or _cmd_arm_g or Input.is_physical_key_pressed(KEY_E)):
		var wp: Vector2 = (get_global_mouse_position() - world.position) / world.scale.x
		var inside := wp.x >= 0 and wp.x <= 400 and wp.y >= 0 and wp.y <= 400
		if _cmd_arm_b or _cmd_arm_g:
			## G/B 待命中左键点击战场=对该点下达（战场外点击=取消待命）
			if inside:
				_issue_point_cmd("b" if _cmd_arm_b else "g", wp)
			_cmd_arm_b = false
			_cmd_arm_g = false
		elif inside:
			## 【0.0.9·临时点（新二 82 行）】按住 E+左键=宣布集结点→1/2/3 循环覆盖
			_temp_points[_temp_next] = wp
			_toast("临时点 %d → (%d, %d)" % [_temp_next + 1, int(wp.x), int(wp.y)])
			_temp_next = (_temp_next + 1) % 3
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		## 【0.0.9·取消指令（新二 133 行）】右键=取消角色点位指令（G/B）与待命
		if cmd_frames > 0 or _cmd_frames_b > 0 or _cmd_arm_g or _cmd_arm_b:
			cmd_frames = 0
			_cmd_frames_b = 0
			_cmd_arm_g = false
			_cmd_arm_b = false
			_toast("已取消点位指令")
	if event is InputEventKey and event.pressed and not event.echo:
		if _priv_panel:
			## 【杂兵指令】面板激活期间屏蔽其它热键（新二：Tab 不放时呼出屏蔽所有热键）
			match event.keycode:
				KEY_S:
					var pv = _priv_pick_entity()
					if pv != null:
						pv.dead = true ## 退下：就地消失（预备队复用待④期）
						print("[杂兵指令] %s 退下" % pv.chara_name())
						_toast("杂兵退下：%s" % pv.chara_name())
				KEY_D:
					var pd = _priv_pick_entity()
					if pd != null:
						pd.set_meta("banzai", 1800) ## 万岁冲锋 30 秒
						print("[杂兵指令] %s 万岁冲锋（30 秒挡弹）" % pd.chara_name())
						_toast("万岁冲锋：%s" % pd.chara_name())
			return
		if _wheel_open:
			return ## 轮盘期间屏蔽其它热键
		match event.keycode:
			KEY_ESCAPE:
				## 【0.0.9·同键合并】原第二个 KEY_ESCAPE 分支（取消接管）被本分支拦截=死代码
				if _takeover_pending:
					_takeover_pending = false
					pause_panel.visible = false
					_takeover_label.visible = false
				elif take_over:
					take_over = false
					_toast("已取消完全接管")
				elif _wheel_open:
					_wheel_open = false
					print("[召唤] 轮盘取消")
				elif finished:
					GameGlobals.goto_scene("res://scenes/title_menu.tscn")
				else:
					_toggle_pause()
			KEY_V:
				## 【0.0.9·同键合并】X+V=强制释放符卡（新二 122）优先；单 V=轮射↔齐射
				if Input.is_physical_key_pressed(KEY_X) and not finished:
					var vsel := picked_entity()
					if vsel != null and vsel.sit_cards != null:
						if vsel.sit_cards.spell_ready:
							_apply_release(vsel, "s")
							_toast("强制释放符卡 → %s" % vsel.chara_name())
						else:
							_toast("符卡装填中：%s" % vsel.chara_name())
				else:
					GameGlobals.versus_volley = "salvo" if GameGlobals.versus_volley == "rotate" else "rotate"
					for fc in fire_controls:
						fc.set_mode(GameGlobals.versus_volley)
			KEY_F1: ## 【22b 20261103·修3 正解】热力图显示=循环切图种
				## （键位表：F1=热力图显示；0.0.7 语义恢复——此前被改成选角色
				## 导致作者按 F1 永远停在 Ht）
				_heat_view = (_heat_view + 1) % 10
				_debug_used = true
				_heat_focus = picked_entity()
				_update_hud_debug_labels()

			KEY_BRACKETLEFT: ## 【新三 20261028】[ 切换热力图种类（关→Ht→…→Hct→关）
				_heat_view = (_heat_view + 1) % 10 ## 【20261030】9=Ha 接入
				_debug_used = true
				_update_hud_debug_labels()

			KEY_BRACKETRIGHT: ## 【新三 20261028】] 切动态热力图（Hd/Hcs）帧序
				_debug_used = true
				_update_hud_debug_labels()
				_heat_frame += 1

			KEY_F2: ## 【22b 20261103·键位表恢复】F2=选取高亮（滚动换角色不变）
				_show_pick = not _show_pick
				_debug_used = true
				_update_hud_debug_labels()

			KEY_F8: ## 【0.0.9·预设探针（作者批·消歧义 20261105）】我方萃香×5 敌方1号早苗2号希洛妮娅+3空（与自定义对战界面 F8/按钮同队伍；真实口径无火力覆写）
				GameGlobals.versus_player_team = ["Suika", "Suika", "Suika", "Suika", "Suika"]
				GameGlobals.versus_enemy_team = ["Sanae", "Xlonia", "", "", ""]
				GameGlobals.versus_player_name = "Suika"
				GameGlobals.versus_enemy_name = "Sanae"
				GameGlobals.goto_scene("res://scenes/battle_arena.tscn")
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
			KEY_R:
				## 【N3 修复】结束后 R=重开（原第二分支不可达）；进行中才增援
				if finished:
					get_tree().reload_current_scene()
				elif Input.is_physical_key_pressed(KEY_SHIFT):
					pass ## Shift+R=选中角色立即补充杂兵（角色指令，走面板选中）
				else:
					_reinforce_all() ## 团队增援
					_toast("团队增援：补充所有杂兵")
			KEY_T:
				auto_reinforce = not auto_reinforce
				_toast("自动增援：%s" % ("开" if auto_reinforce else "关"))
			KEY_C:
				## 【0.0.9·同键合并】原第二个 KEY_C 分支（请求/双击强制符卡）被本分支拦截=死代码
				if Input.is_physical_key_pressed(KEY_CTRL):
					## Ctrl+C 取消全部指令（姿态+点位指令+待命）
					team_stance = ""
					cmd_frames = 0
					_cmd_frames_b = 0
					_cmd_arm_g = false
					_cmd_arm_b = false
					_toast("已取消全部指令")
				elif not finished:
					## 【0.0.9·请求/强制释放符卡（新二 123/125 行）】
					var csel := picked_entity()
					if csel != null and csel.sit_cards != null:
						var now2 := time_frames
						var last2: int = int(_dt_last.get(KEY_C, -999))
						if now2 - last2 < 24: ## 双击 C=强制释放符卡
							_dt_last[KEY_C] = -999
							if csel.sit_cards.spell_ready:
								_apply_release(csel, "s")
								print("[角色指令] %s 强制释放符卡" % csel.chara_name())
								_toast("强制释放符卡 → %s" % csel.chara_name())
							else:
								print("[角色指令] %s 符卡装填中——到期前强制不执行（策划）" % csel.chara_name())
								_toast("符卡装填中：%s" % csel.chara_name())
						else:
							_dt_last[KEY_C] = now2
							csel.sit_cards.pending_kind = "s"
							csel.sit_cards.pending_tries = 10
							print("[角色指令] %s 请求释放符卡（2 秒内协同）" % csel.chara_name())
							_toast("请求释放符卡 → %s" % csel.chara_name())
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
						_toast("投降请求已发送")
			KEY_W:
				if Input.is_physical_key_pressed(KEY_SHIFT):
					if surrender_sent and not surrender_phase:
						surrender_sent = false
						print("[投降] 请求已撤销")
			KEY_H:
				if not finished:
					## 【0.0.9·键位裁定（作者 20261106）】早苗/铃仙能力改 Y 键——H 专职右下面板
					_br_cycle()
			KEY_Y:
				## 【0.0.9·能力键统一（作者裁定）】早苗-铃仙能力=Y 键
				if not finished:
					var ysel := picked_entity()
					if ysel != null:
						var yn: String = ysel.chara_name()
						if yn == "Sanae":
							_sanae_skill() ## 早苗：按态势自动选神
						elif yn.begins_with("Reisen"):
							_toast("铃仙能力（待实装）") ## 铃仙能力占位
						else:
							_toast("%s 无 Y 键能力" % yn)
			KEY_B:
				## 【0.0.9·指定位置防御（新二 128 行）】G 同款架构
				if not finished and picked_entity() != null:
					_cmd_arm_b = true
					_cmd_arm_g = false
					_toast("防御待命：左键点战场 或 按 1-3 临时点 / 4-6 预设点")
			KEY_X:
				## 【0.0.9·键位裁定（作者 20261106）】Shift+X=角色召唤（按住轮盘）；
				## X 单击=请求释放能力（无 Shift）
				if Input.is_physical_key_pressed(KEY_SHIFT):
					if not finished:
						var wsel := picked_entity()
						if wsel != null and wsel.side == 0 and not _wheel_open:
							_open_summon_wheel(wsel)
				elif not finished:
					var xsel := picked_entity()
					if xsel != null and xsel.sit_cards != null:
						var now := time_frames
						var last: int = int(_dt_last.get(KEY_X, -999))
						if now - last < 24: ## 双击 X=强制释放（0.4s 窗口）
							_dt_last[KEY_X] = -999
							if xsel.sit_cards.skill_ready:
								_apply_release(xsel, "n")
								print("[角色指令] %s 强制释放能力" % xsel.chara_name())
								_toast("强制释放能力 → %s" % xsel.chara_name())
							else:
								print("[角色指令] %s 能力装填中——到期前强制不执行（策划）" % xsel.chara_name())
								_toast("能力装填中：%s" % xsel.chara_name())
						else:
							_dt_last[KEY_X] = now
							## 请求释放：复用申请替换机制（2 秒内进能力协同）
							xsel.sit_cards.pending_kind = "n"
							xsel.sit_cards.pending_tries = 10
							print("[角色指令] %s 请求释放能力（2 秒内协同）" % xsel.chara_name())
							_toast("请求释放能力 → %s" % xsel.chara_name())
			KEY_TAB:
				## 【0.0.9·杂兵指令（新二 135-141 行）】Tab 呼出面板（按住显示）
				_priv_panel = Input.is_physical_key_pressed(KEY_TAB)
			KEY_SHIFT:
				pass
			KEY_G:
				## 【N7】G 指令仅在选人后生效，避免对局中被空按打断
				if not finished and picked_entity() != null:
					_cmd_arm_g = true
					_cmd_arm_b = false
					_toast("进攻待命：左键点战场 或 按 1-3 临时点 / 4-6 预设点")
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				## 【0.0.9·热键点（新二 81-82/114/118）】G/B 待命中按数字=对热键点下达
				if _cmd_arm_g or _cmd_arm_b:
					var ki: int = event.keycode - KEY_1
					var hp_pt: Vector2 = _temp_points[ki] if ki < 3 else GameGlobals.preset_points[ki - 3]
					if hp_pt == Vector2.INF:
						_toast("临时点 %d 未设置（按住 E+左键宣布）" % (ki + 1))
					else:
						_issue_point_cmd("b" if _cmd_arm_b else "g", hp_pt)
					_cmd_arm_g = false
					_cmd_arm_b = false
			KEY_F3: ## 【22b 20261103d·键位兼容】F3=循环切图种
				## （作者 0.0.7 习惯：F1/F3 都循环看图——三键兼容防键位配置差）
				_heat_view = (_heat_view + 1) % 10
				_debug_used = true
				_heat_focus = picked_entity()
				_update_hud_debug_labels()
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
	_update_hud_debug_labels() ## 【22b 20261102·修3】标签 10Hz 强制同步
	## （热力图名永远显示 Ht 的老毛病：按键刷新点遗漏/时序——兜底同步）
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
		## 【0.0.9·作者批 20261107】格式="显示弹幕量(实际弹幕量)"——括号=不可见
		## 但实际存在（回收不可见/移出/功能残缺）
		fps_label.text = "FPS %.1f
弹幕 %d(%d)" % [_fps_measured, _bullet_visible, bullets.size()]
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
	if _debug_used and not ht_side.is_empty() and ht_side[0] != null:
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
		## 【作者批 20261106】选中角色判定点金色（与侧面板选中名字高亮同款语义）
		if ent == picked_entity():
			col = Color(1.0, 0.85, 0.2)
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
		var gr := maxf(0.0, 1.0 - float(300 - cmd_frames) / 120.0) ## 引力圈 2 秒衰减（新三 227）
		onto.draw_arc(cmd_point, 40.0, 0, TAU, 32, Color(1, 1, 1, 0.15 + 0.45 * gr), 1.5)
		onto.draw_arc(cmd_point, 20.0, 0, TAU, 24, Color(1, 1, 1, 0.1 + 0.3 * gr), 1.0)
	if _cmd_frames_b > 0:
		var br := maxf(0.0, 1.0 - float(300 - _cmd_frames_b) / 120.0)
		onto.draw_arc(_cmd_point_b, 30.0, 0, TAU, 32, Color(0.45, 0.7, 1.0, 0.2 + 0.45 * br), 1.5)
		onto.draw_arc(_cmd_point_b, 12.0, 0, TAU, 20, Color(0.45, 0.7, 1.0, 0.15 + 0.3 * br), 1.0)
	## 【0.0.9·热键点显示】G/B 待命或按住 E 时标出 1-3 临时点 / 4-6 预设点
	if _cmd_arm_g or _cmd_arm_b or Input.is_physical_key_pressed(KEY_E):
		for hi in 6:
			var hpp: Vector2 = _temp_points[hi] if hi < 3 else GameGlobals.preset_points[hi - 3]
			if hpp == Vector2.INF:
				continue
			var hc := Color(1.0, 0.85, 0.3, 0.9) if hi < 3 else Color(0.6, 1.0, 0.7, 0.9)
			onto.draw_arc(hpp, 6.0, 0, TAU, 16, hc, 1.2)
			onto.draw_string(ThemeDB.fallback_font, hpp + Vector2(7, -5), str(hi + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, hc)
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
	## 【22b 20261102d·激光 MM 化（遗留清单）】逐段 draw_line（每激光
	## ~400 条×~1µs）→ 线段 MultiMesh（1 draw call）：单位白 quad 拉伸
	## 对齐每段（pos=段中点、旋转=段向、缩放=段长×宽）
	var laser_segs: Array = [] ## [mid, dir_angle, seglen, width, color]
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
			var pa: Vector2 = bl.laser_samples[i]
			var pb: Vector2 = bl.laser_samples[i + 1]
			var seg: Vector2 = pb - pa
			if seg.length_squared() < 0.01:
				continue
			laser_segs.append([(pa + pb) * 0.5, seg.angle(), seg.length(), w, c])
	if laser_segs.size() > 0:
		var lmm := _get_laser_mm()
		if laser_segs.size() > lmm.instance_count:
			lmm.instance_count = laser_segs.size()
		for li in laser_segs.size():
			var sd: Array = laser_segs[li]
			var xf := Transform2D(sd[1], sd[0])
			xf = xf.scaled_local(Vector2(sd[2], sd[3]))
			lmm.set_instance_transform_2d(li, xf)
			lmm.set_instance_color(li, sd[4])
		var last_l: int = int(_mm_last_cnt.get(_LASER_KEY, 0))
		if laser_segs.size() < last_l:
			for i2 in range(laser_segs.size(), last_l):
				lmm.set_instance_transform_2d(i2, Transform2D(0, Vector2(-9999, -9999)))
		_mm_last_cnt[_LASER_KEY] = laser_segs.size()
		onto.draw_multimesh(lmm, _laser_tex())
	## 我方法弹的白色前向粒子轨道（只有轨道、没有弹幕本体；敌方法弹同物弹正常显示）
	## 【22b 20261030】我方法弹白色前向轨道的逐弹 draw_line 已移除：
	## CanvasItem draw_line 每 command 实测 ~30µs（700 弹 49ms=process 中位
	## 17ms 元凶）——轨道并入 draw_bullet_mm 末尾的 MultiMesh 轨道层（1 draw call）

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
var _bullet_visible := 0 ## 【0.0.9】可渲染弹幕数（draw_bullet_mm 顺便统计→fps_label）
func draw_bullet_mm(onto: CanvasItem) -> void:
	_by_tex.clear()
	_bullet_visible = 0
	for b in bullets:
		var bl: Bullet = b
		if bl.hidden_now or bl.ev.tag == DanmakuEventData.TAG_LASER:
			continue
		if not _in_field(bl.pos, bl.draw_radius): ## 【所见即所判】弹圆压边即画（与 stamp 同口径）
			continue
		_bullet_visible += 1
		## 【方案一 20261030d→1031d 修正】我方法弹始终灰白高透明渲染
		## （新三第8行无范围限制——此前错用 beyond_mask 当渲染边界，
		## 法弹飞出 0.25 秒距即消失=作者反馈"超出范围不显示"）。
		## beyond_mask 只保留 DDM 归属语义（_render_ddm 的 is_phy 分支）。
		if false:
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
			var rc: Array = bl.render_color_alpha() ## 【定值预计算】static 弹零计算
			var mc: Color = rc[0]
			## 【近弹增显 20261026（作者 0.0.8 点子）】参与 DDM（pass 否）的弹幕
			## 靠近角色时 对比度/不透明度 += 2560/d（d=到最近角色距离，神灵庙式近弹提示）
			var alpha_extra := 0.0
			var sat_extra := 0.0
			## 【22b 20261031·审计#1】近弹增显：原每弹×60实体 distance_to
			## （2000弹=12万次/帧≈12ms，draw 侧每帧）→ 活实体位置预收集+
			## 平方距+命中即停（增显只看 40px 内，无需精确最近）
			if _live_ent_pos_dirty:
				_live_ent_pos.clear()
				for e2 in entities:
					if e2 is BattleEntity and not (e2 as BattleEntity).dead:
						_live_ent_pos.append((e2 as BattleEntity).position)
				_live_ent_pos_dirty = false
			var dmin := 99999.0
			var bx: float = bl.pos.x
			var by: float = bl.pos.y
			for ep in _live_ent_pos:
				var dx2: float = ep.x - bx
				var dy2: float = ep.y - by
				var d4: float = dx2 * dx2 + dy2 * dy2
				if d4 < dmin:
					dmin = d4
					if d4 < 1600.0:
						break
			if dmin < 1600.0:
				var boost: float = 2560.0 / maxf(sqrt(dmin), 4.0)
				sat_extra = boost
				alpha_extra = clampf(boost, 0.0, 1.0)
			var a_final: float = clampf(float(rc[1]) + alpha_extra, 0.0, 1.0)
			var mc2 := mc
			if sat_extra > 0.0:
				mc2.v = clampf(mc2.v + sat_extra / 256.0, 0.0, 1.0) ## 对比度亮度端增显
			## 【方案一 20261031f·灰白语义统一（作者反馈四类异常）】
			## 我方法弹：恒定灰白高透明（策划新三第8行，无范围/遮罩限制）；
			## 我方物弹：友伤遮罩内灰白（遮罩外可误伤=正常彩色显示）。
			## 旧实现把 beyond_mask 当渲染边界（弹消失）+ 物弹被排除（③类）。
			if bl.source_side == 0 and (not bl.ev.is_phy or not bl.beyond_mask()):
				mc2 = Color(0.75, 0.75, 0.78, 0.125)
				a_final = 0.125
			mm.set_instance_color(i, Color(mc2.r, mc2.g, mc2.b, a_final))
		## 缩容时只把"多出来的"实例挪到屏外一次（增量停靠）——
		## 旧版（注释备查）：每帧把 [cnt, instance_count) 全部重写，
		## 弹幕数波动时每帧多达成百上千次 set_instance_transform_2d。
		if cnt < _mm_last_cnt.get(tex, 0):
			for i in range(cnt, _mm_last_cnt[tex]):
				mm.set_instance_transform_2d(i, Transform2D(0, Vector2(-9999, -9999)))
		_mm_last_cnt[tex] = cnt
		onto.draw_multimesh(mm, tex)

	## 【方案一 20261030d】轨道层已删——灰白本形取代"白轨道"职责


## MultiMesh 缓存（材质 → MM 实例池）+ 每材质上一帧实例数（增量停靠用）
var _dir16: Array[Vector2] = [] ## 【审计#15】16 方向单位向量（cos/sin 预计算）
var _live_ent_pos: Array[Vector2] = [] ## 【审计#1】活实体位置缓存（draw 侧）
var _live_ent_bucket: Dictionary = {} ## 【审计A6】32px 分桶（增显近邻查询）
var _live_ent_pos_dirty := true
const _LASER_KEY := "__laser__" ## 【22b 20261102d】激光线段 MM 缓存键
var _laser_mm: MultiMesh = null
var _laser_texture: Texture2D = null

func _laser_tex() -> Texture2D:
	if _laser_texture == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_laser_texture = ImageTexture.create_from_image(img)
	return _laser_texture

func _get_laser_mm() -> MultiMesh:
	if _laser_mm == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.instance_count = 0
		mm.mesh = _quad_mesh(_laser_tex())
		_laser_mm = mm
	return _laser_mm

## 【22b 20261102·修4】DDM 形状贴合：弹幕纹理槽表（RID→槽 id，≤16）
var _ddm_tex_slots: Dictionary = {}
var _ddm_tex_arrays: Array = [] ## RID 列表（shader sampler2DArray 上传用）
const DDM_TEX_MAX := 255 ## 【20261103】0 保留圆盘兜底；1-255 纹理槽

var _ddm_tex_slots_uploaded: Dictionary = {}

func _upload_ddm_tex(slot: int, tex: Texture2D) -> void:
	## 【修4】纹理→256×256 r8 Image → ddm_gpu.update_tex_array
	if _ddm_tex_slots_uploaded.has(slot) or ddm_gpu0 == null:
		return
	_ddm_tex_slots_uploaded[slot] = true
	var img: Image = tex.get_image()
	img.resize(256, 256, Image.INTERPOLATE_BILINEAR)
	## 【修4 20261103】形状在 alpha 通道——L8 只留亮度会全白！
	## 手动把 alpha 写进灰度（R=G=B=A）
	for yy in img.get_height():
		for xx in img.get_width():
			var px: Color = img.get_pixel(xx, yy)
			var a8: float = px.a
			img.set_pixel(xx, yy, Color(a8, a8, a8, 1.0))
	img.convert(Image.FORMAT_L8)
	var images := {slot: img}
	ddm_gpu0.update_tex_array(images)
	if ddm_gpu1 != null:
		ddm_gpu1.update_tex_array(images)

func _ddm_tex_slot(tex: Texture2D) -> int:
	if tex == null:
		return 0
	var rid: RID = tex.get_rid()
	if _ddm_tex_slots.has(rid):
		return _ddm_tex_slots[rid]
	var slot := _ddm_tex_slots.size() + 1 ## 【20261103】槽从 1 起（0=圆盘兜底）
	if slot >= DDM_TEX_MAX:
		return 0
	_ddm_tex_slots[rid] = slot
	_ddm_tex_arrays.append(rid)
	return slot

var _mm_cache: Dictionary = {}
var _mm_last_cnt: Dictionary = {}
## 【22b 20261031f·管线预热】发射风暴帧的 114-162ms 尖峰=新弹幕纹理
## 首次渲染的 Vulkan 管线编译（主线程阻塞）。战场建立时把全事件纹理
## 各画一帧屏外实例 → 运行期零首次编译。
## 【22b 20261103·作者建议】决斗初始化阶段按角色弹幕样式预 setup：
## 对全事件各做一次 Bullet 干跑 setup（丢弃）——驱动 BulletHot C++ 编译
## 缓存/表达式首求值/纹理上传全部在初始化期完成，首次真实发射零冷启动
## 【0.0.9·Hp 重做（策划新三 66 行·作者令）】初始化时按弹幕表达式
## 模拟函数生成"假 DDM"：对每事件干跑弹幕轨迹（t 采样），弹位写入
## 400×400 L8 图；被重复/旋转复制复制后=该事件全部弹幕的规律期望。
## 不参与衰减扩散（静态规律图），每拍采样照读（10fps 语义）。
func _warmup_hp() -> void:
	if fam_maps == null or not fam_maps.ok:
		return
	var imgs := [Image.create(400, 400, false, Image.FORMAT_L8), Image.create(400, 400, false, Image.FORMAT_L8)]
	var done_ev := {}
	var world := self
	for fc in fire_controls:
		if fc.entity == null or fc.entity.dead:
			continue
		for pnt in fc.weapon_points + fc.sub_points:
			for ev in pnt.events:
				if ev == null or done_ev.has(ev.event_name):
					continue
				done_ev[ev.event_name] = true
				## 威胁侧：我方角色发的弹→威胁敌方（写 Hp1=敌方视角）
				var threat_side: int = 1 - fc.entity.side
				var rctx := _rot_eval_ctx(fc.entity, pnt, 0.0)
				var sp: Dictionary = ev.eval_spawn_params(rctx)
				var origin := _fire_origin(pnt, ev, fc.entity, sp)
				var b := Bullet.new()
				b.setup(ev, origin, fc.entity.side, fc.entity, world, 0, {})
				if not b.alive:
					continue
				## 干跑轨迹：t 步长 6 帧（10fps×~1s），采样 x/y/speed 表达式
				var gctx := {"field_t": 0.0, "field_phase": 1}
				b.sync_shared(gctx)
				var steps := int(minf(b.range_now, 600.0) / 6.0)
				for st in steps:
					b.t = float(st) * 6.0
					b._build_ctx()
					b._step_regular(6.0 / 60.0, b._ctx)
					var px := int(clampf(b.pos.x, 0.0, 399.0))
					var py := int(clampf(b.pos.y, 0.0, 399.0))
					var rr := int(clampf(b.draw_radius, 2.0, 24.0))
					for dy in range(-rr, rr + 1, 2):
						for dx in range(-rr, rr + 1, 2):
							if dx * dx + dy * dy <= rr * rr:
								var ix: int = px + dx
								var iy: int = py + dy
								if ix >= 0 and ix < 400 and iy >= 0 and iy < 400:
									imgs[threat_side].set_pixel(ix, iy, Color(1, 1, 1))
	## 上传到 fam Hp 纹理
	for side in 2:
		fam_maps.upload_hp_image(side, imgs[side])

func _warmup_setup() -> void:
	var world := self
	var done_ev := {}
	for fc in fire_controls:
		for p in fc.weapon_points + fc.sub_points:
			for ev in p.events:
				if done_ev.has(ev.event_name) or ev == null:
					continue
				done_ev[ev.event_name] = true
				var b := Bullet.new()
				b.tex_slot = 0
				b.setup(ev, Vector2(-999, -999), fc.entity.side, fc.entity, world, 0, {})
				## 干跑不进 bullets 数组（RefCounted 出域即弃）
				b.tex_slot = _ddm_tex_slot(b.tex)
				if b.tex_slot > 0:
					_upload_ddm_tex(b.tex_slot, b.tex)
	for pr in _priv_shooters:
		for ev in pr.get("evs", []):
			if done_ev.has(ev.event_name) or ev == null:
				continue
			done_ev[ev.event_name] = true
			var b2 := Bullet.new()
			b2.setup(ev, Vector2(-999, -999), 0, null, world, 0, {})
			b2.tex_slot = _ddm_tex_slot(b2.tex)
			if b2.tex_slot > 0:
				_upload_ddm_tex(b2.tex_slot, b2.tex)

func _warmup_textures() -> void:
	var seen := {}
	for b in bullets:
		var bl: Bullet = b
		if bl.tex != null and not seen.has(bl.tex):
			seen[bl.tex] = true
	var warm_mm := MultiMesh.new()
	warm_mm.transform_format = MultiMesh.TRANSFORM_2D
	warm_mm.use_colors = true
	warm_mm.instance_count = 1
	warm_mm.mesh = _quad_mesh(bullets[0].tex if bullets.size() > 0 else null)
	warm_mm.set_instance_transform_2d(0, Transform2D(0, Vector2(-9999, -9999)))
	for tex in seen:
		var mm := _get_mm(tex)
		if mm != null and mm.instance_count == 0:
			mm.instance_count = 1
			mm.set_instance_transform_2d(0, Transform2D(0, Vector2(-9999, -9999)))
			mm.set_instance_color(0, Color(1, 1, 1, 0))
	## 屏外画一帧触发管线编译
	if bullet_mm_layer != null:
		bullet_mm_layer.queue_redraw()

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
var _heat_watermark: Label = null ## 【22b 20261103】图种水印（与实际显示绑定）

## 【0.0.9·作者裁定 20261106 修订】调试显示=等高面投射的热力（分层设色
## 多边形填充，低层到高层叠画=阶梯设色）+青蓝色热力原图半透明覆盖其上。
## （矢量折线不画——作者不要"线"，要"面"；] 键回放记忆帧序）
## 【修复 20261106】R8 纹理 G/B=0 → 青蓝显示走 heat_tint.gdshader 重映射
var _heat_tint_mat_cache: ShaderMaterial = null
var _contour_layer: Node2D = null
var _contour_map := ""
func _ensure_contour_layer() -> void:
	if _contour_layer == null:
		_contour_layer = Node2D.new()
		_contour_layer.position = Vector2(200, 0) ## 与原图 sprite 对齐
		_contour_layer.z_index = -1 ## 等高面在青蓝原图之下
		var cs := Sprite2D.new()
		cs.name = "ColorMap"
		cs.centered = false
		cs.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST ## 阶梯色块
		## 【0.0.9·显示修复 20261108】50×50 值图必须放大到 400×400 场地
		## （未设 scale 时缩在左上角 50×50 像素=被原图完全盖住="只有原图"）
		var edge: float = float(GameGlobals.contour_edge_px)
		cs.scale = Vector2(edge, edge) ## GRIDX×CELL=400
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/contour_tint.gdshader")
		cs.material = mat
		_contour_layer.add_child(cs)
		hud.add_child(_contour_layer)

## 分层设色（策划：热力图红色系）——低层暗红→高层亮黄白；alpha 随层渐实
func _contour_level_color(li: int) -> Color:
	var t: float = float(li - 1) / 14.0
	return Color(1.0, 0.18 + 0.72 * t, 0.18 + 0.72 * t, 0.42 + 0.4 * t)

## 等高面投射：每层多边形从低到高填充（高层覆盖低层=阶梯设色热力）
func draw_contour_lines(onto: CanvasItem) -> void:
	pass ## 【0.0.9·色图光栅化】多边形绘制全撤（色图 sprite——texture 喂养在 _process 等高线分支）

## 鞋带面积（绝对值）
func _poly_shoelace(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % pts.size()]
		a += p0.x * p1.y - p1.x * p0.y
	return a * 0.5

## 自交快速检测（O(n²)；等高线折线通常 <60 点，调用频度=观察视图 10fps——可承受）
func _poly_self_intersects(pts: PackedVector2Array) -> bool:
	var n := pts.size()
	if n < 4:
		return false
	for i in n:
		var a1: Vector2 = pts[i]
		var a2: Vector2 = pts[(i + 1) % n]
		for j in range(i + 1, n):
			if j == i or (j + 1) % n == i or (i + 1) % n == j:
				continue ## 共享端点的相邻边不算
			var b1: Vector2 = pts[j]
			var b2: Vector2 = pts[(j + 1) % n]
			if Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != Vector2.INF:
				return true
	return false
func _heat_tint_mat() -> ShaderMaterial:
	if _heat_tint_mat_cache == null:
		var sh := load("res://shaders/heat_tint.gdshader")
		if sh != null:
			_heat_tint_mat_cache = ShaderMaterial.new()
			_heat_tint_mat_cache.shader = sh
	return _heat_tint_mat_cache

func draw_ddm_debug(onto: CanvasItem) -> void:
	if gpu_ok:
		## 【22b 20261103·水印】图种直接写在显示图上（与实际渲染绑定，
		## 不依赖标签刷新时序——作者环境的"恒 Ht"争议以此为准）
		if _heat_watermark == null:
			_heat_watermark = Label.new()
			_heat_watermark.position = Vector2(204, 4) ## 热力图旁
			_heat_watermark.add_theme_font_size_override("font_size", 18)
			_heat_watermark.add_theme_color_override("font_color", Color(1, 1, 0.4))
			world.add_child(_heat_watermark)
		if _contour_layer != null and not (_heat_view == 4 or _heat_view == 5):
			_contour_layer.visible = false ## 【等高面兜底】仅 Hd/Hr 视图显示
		var wname := ""
		match _heat_view:
			1: wname = "Ht"
			2: wname = "Hv"
			3: wname = "He"
			4: wname = "Hd"
			5: wname = "Hr"
			6: wname = "Hp"
			9: wname = "Ha"
		_heat_watermark.text = ("▶ " + wname + " (" + ("我方" if _heat_view_side == 0 else "敌方") + ")") if wname != "" else ""
		_heat_watermark.visible = _heat_view > 0 and _heat_view < 7 or _heat_view == 9
		## 【F1 热力图浏览器（作者批复）】_heat_view: 1=Ht 2=Hv；[切方 滚轮切角色 ]切帧
		var view_side: int = _heat_view_side
		if _heat_view == 1:
			if _ht_sprite == null:
				_ht_sprite = Sprite2D.new()
				_ht_sprite.centered = false
				_ht_sprite.position = Vector2(200, 0) ## 【22b 20261103·位置终版】场内右上象限（world 内随缩放；半透明不阻视野） ## 【22b 20261103h】hud 层（不受场裁剪）场右上角外
				_ht_sprite.modulate = Color(0.2, 1, 0.4, 0.35)
				hud.add_child(_ht_sprite)
			_ht_sprite.visible = true
			_ht_sprite.texture = ht_side[view_side].display_texture()
		elif _heat_view == 2:
			var hv = hv_side[view_side] if view_side < hv_side.size() else null
			if hv != null and hv.ok:
				if _ht_sprite == null:
					_ht_sprite = Sprite2D.new()
					_ht_sprite.centered = false
					_ht_sprite.position = Vector2(200, 0) ## 【22b 20261103·位置终版】场内右上象限（world 内随缩放；半透明不阻视野）
					hud.add_child(_ht_sprite)
				_ht_sprite.visible = true
				_ht_sprite.modulate = Color(1, 1, 1, 0.6) ## Hv 彩虹已烘焙（红升蓝降）
				_ht_sprite.texture = hv.display_texture()
		elif _heat_view == 9 and fam_maps != null and fam_maps.ok:
			## 【20261030·①Ha】全局抽象热点图（25×25 马赛克；derive 同拍产出）
			var ha_tex := fam_maps.display("Ha" + str(view_side))
			if ha_tex != null:
				if _ht_sprite == null:
					_ht_sprite = Sprite2D.new()
					_ht_sprite.centered = false
					_ht_sprite.position = Vector2(200, 0) ## 【22b 20261103·位置终版】场内右上象限（world 内随缩放；半透明不阻视野）
					hud.add_child(_ht_sprite)
				_ht_sprite.visible = true
				_ht_sprite.modulate = Color(1, 1, 1, 0.55)
				_ht_sprite.texture = ha_tex
		elif _heat_view >= 3 and fam_maps != null and fam_maps.ok:
			## 【③期收官】期望系：3=He 4=Hd 5=Hr 6=Hp（[ 键切方；每侧一张威胁图）
			var fam_name: String = ["He", "Hd", "Hr", "Hp"][mini(_heat_view - 3, 3)] + str(view_side)
			var fam_tex := fam_maps.display(fam_name)
			if fam_tex != null:
				if _ht_sprite == null:
					_ht_sprite = Sprite2D.new()
					_ht_sprite.centered = false
					_ht_sprite.position = Vector2(200, 0) ## 【22b 20261103·位置终版】场内右上象限（world 内随缩放；半透明不阻视野）
					hud.add_child(_ht_sprite)
				_ht_sprite.visible = true
				if _heat_view == 4 or _heat_view == 5:
					## 【0.0.9·作者裁定】Hd/Hr 调试=等高面热力（下）+青蓝原图半透明（上）。
					## 【修复 20261106】R8 单通道纹理 G/B=0，modulate 蓝青被乘成
					## 极暗红=作者实测"两张图都不能显示"——改 heat_tint shader
					## 把 R 灰度重映射到青蓝（GPU 零成本）。
					_ht_sprite.material = _heat_tint_mat()
					_ht_sprite.modulate = Color(1, 1, 1, 1)
					_ensure_contour_layer()
					_contour_layer.visible = true
					_contour_map = fam_name
				else:
					_ht_sprite.material = null
					_ht_sprite.modulate = Color(1, 1, 1, 0.55)
					if _contour_layer != null:
						_contour_layer.visible = false
				_ht_sprite.texture = fam_tex
		else:
			if _ht_sprite != null:
				_ht_sprite.visible = false
	else:
		for b in bullets:
			var bl: Bullet = b
			if bl.hidden_now:
				continue
			onto.draw_circle(bl.pos, bl.draw_radius, Color(1, 0, 1, 0.15))
	_draw_priv_panel(onto)
	_draw_summon_wheel(onto)

## 杂兵面板（Tab 按住）：选中角色麾下杂兵列表+滚轮高亮
func _draw_priv_panel(onto: CanvasItem) -> void:
	if not _priv_panel or not gpu_ok:
		return
	var sel := picked_entity()
	if sel == null:
		return
	var list: Array = []
	for e2 in entities:
		if e2 is BattleEntity and (e2 as BattleEntity).kind == BattleEntity.Kind.PRIVATE 			and (e2 as BattleEntity).owner_ent == sel and not (e2 as BattleEntity).dead:
			list.append(e2)
	if list.is_empty():
		return
	_priv_sel = clampi(_priv_sel, 0, list.size() - 1)
	onto.draw_rect(Rect2(8, 300, 170, 24 + list.size() * 18), Color(0.05, 0.07, 0.12, 0.85))
	onto.draw_string(ThemeDB.fallback_font, Vector2(14, 320), "── 杂兵(Tab) S退下 D万岁 ──",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.9, 1.0))
	for i in list.size():
		var pv: BattleEntity = list[i]
		var col := Color(1, 0.9, 0.4) if i == _priv_sel else Color(0.75, 0.8, 0.9)
		var tag: String = "▲万岁" if int(pv.get_meta("banzai", 0)) > 0 else ""
		onto.draw_string(ThemeDB.fallback_font, Vector2(14, 340 + i * 18),
			"%d. %s %s HP%d" % [i, pv.chara_name(), tag, pv.hp[0]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

## 召唤轮盘（Shift+S）：环形 8 槽+鼠标悬停高亮
func _draw_summon_wheel(onto: CanvasItem) -> void:
	if not _wheel_open or not gpu_ok:
		return
	var center := Vector2(200, 200)
	onto.draw_circle(center, 150, Color(0.05, 0.07, 0.12, 0.8)) ## 【作者裁定】圆环加大
	onto.draw_arc(center, 150, 0, TAU, 64, Color(0.6, 0.8, 1.0, 0.6), 1.5)
	var mp := (get_global_mouse_position() - world.position) / world.scale.x
	var mouse_in := false
	for i in _wheel_cands.size():
		var ang := -PI / 2.0 + TAU * float(i) / float(maxi(1, _wheel_cands.size()))
		var p := center + Vector2(cos(ang), sin(ang)) * 105.0
		if mp.distance_to(p) < 34.0:
			mouse_in = true
			_wheel_sel = i ## 鼠标悬停选取
		var col := Color(1, 0.9, 0.4, 0.95) if _wheel_sel == i and mouse_in else Color(0.7, 0.8, 0.95, 0.8)
		onto.draw_circle(p, 30.0, Color(0.1, 0.14, 0.22, 0.9) if _wheel_sel == i and mouse_in else Color(0.08, 0.1, 0.16, 0.7))
		onto.draw_string(ThemeDB.fallback_font, p + Vector2(-24, 4),
			str(_wheel_cands[i].get("NameZH", _wheel_cands[i].get("Name", "?"))),
			HORIZONTAL_ALIGNMENT_CENTER, 48, 11, col)
	if not mouse_in:
		_wheel_sel = -1 ## 鼠标未接触轮盘→默认第一位（策划）
		onto.draw_string(ThemeDB.fallback_font, center + Vector2(-40, 4),
			"默认第一位", HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color(0.6, 0.7, 0.85, 0.7))
