extends Control
## =============================================================
## danmaku_editor —— 第①期重构（对齐作者批复的编辑器设计案）
## 【布局（批复）】
##   顶栏：文件(新建/打开/导入材质/导出.thx/导出为官方数据(仅工程环境)/返回游戏标题)
##         编辑(撤销/重做/项目信息/查找)　帮助(游戏信息/文档链接)
##   左栏：事件列表（增/删/复制）
##   主区：标签页——①通用参数 ②弹幕表达（按 tag 互斥只显示核心参数）
##          ③使用者（该事件被哪些角色/火力槽引用）
##   底栏：状态栏（编译错误/操作反馈）+ 试炼场预览按钮
## 【功能】
##   运算/参数引入工具浮窗：全角注释插入（log(“底数”,“真数”)）+搜索+置顶
##   # 字符拦截（Godot 注释符会损毁文件）
##   可行性检查：全部表达式编译 → 状态栏报告
##   工程环境检测：res://gameAssetBase 可写时才显示“导出为官方数据”
## =============================================================

## 表单字段模式：[属性名, 标签, 控件类型, 选项?]
const SCHEMA_COMMON := [
	["event_name", "事件名(弹幕命名)", "str"],
	## 【批复 2026-10-03】归属角色/槽位由角色页"角色弹幕"绑定框管理，
	## 事件表单不再出现归属选栏（避免两处编辑打架）
	## 【批复 20261019】弹幕事件不设火力点参数——各类火力点自由分配弹幕，
	## 槽位完全由角色页绑定决定，事件侧空位即歧义，故彻底移除
	["timeline_frame", "时间轴帧(-1=火控循环)", "int"],
	["texture", "材质名", "opt_tex"],
	["color_adv", "颜色(#hex)·高级RGB", "color_adv"],
	["dmg", "伤害(整式,碎甲类=瘫痪秒)", "num_expr"],
	["dmg_mode", "攻击模式", "opt", ["N", "I", "S"]],
	["dmg_allow_moderate", "允许伤害调整", "check"],
	["repeat_time", "重复时间(整式,帧,副本间隔)", "num_expr"],
	["repeat_freq", "重复频率(整式,补发次数,0=禁用)", "num_expr"],
	["is_cannon", "选取：火炮(勾选)/无人机(不勾)", "check"],
	## ——通用弹幕旋转重复参数（弹幕编辑器-新 20261015；类型批复 20261019）——
	## range/offset=浮点式；div/rate=整式（浮点结果向下取整）；pingpong=式/命题
	["rotate_range", "旋转散布范围(浮点式,弧度,≥π=全圆)", "expr"],
	["rotate_div", "旋转等分(整式,0=不旋转重复)", "expr"],
	["rotate_rate", "旋转重复次数(整式,0=按等分一次)", "expr"],
	["rotate_offset", "旋转偏差(浮点式,弧度)", "expr"],
	["rotate_sequence", "旋转时序(cw/ccw/mid_sync/mid_left/mid_right)", "opt",
		["cw", "ccw", "mid_sync", "mid_left", "mid_right"]],
	["rotate_pingpong", "旋转回弹基数(式/命题,0=不回弹)", "expr"],
	["rotate_delay", "旋转重复延时(整式,帧,0=同帧)", "num_expr"],
	["range_frames", "航程/存活时间(整式,帧)", "num_expr"],
	["is_abs_coord", "坐标定值(绝对坐标)", "check"],
	["x_offset", "x偏差(整式,遮罩起点)", "num_expr"],
	["y_offset", "y偏差(整式,遮罩起点)", "num_expr"],
	["rate", "概率rate(空=无门)", "gate"],
	["pattern", "规律pattern(空=无门)", "gate"],
	["danmaku_size_muti", "规格参数(式/命题)", "num_expr"],
	["is_phy", "物弹(友伤)", "check"],
	["oob_mode", "出界处理", "opt", ["出界销毁", "出界后反射", "出界不处理"]],
	["alpha", "不透明度表达式(256=全)", "expr"],
	["pass_cond", "隐藏条件(命题)", "expr"],
]
## 弹幕表达（按 tag 互斥；tag 在通用区切换，此处只显示对应核心参数）
const SCHEMA_BY_TAG := {
	"IsDanmakuRegular": [
		["speed", "速度(像素/帧)", "expr", "", "danmaku"],
		["x", "x权重(方向向量)", "expr", "", "danmaku"],
		["y", "y权重(方向向量)", "expr", "", "danmaku"],
	],
	"IsDanmakuPhysical": [
		["speed", "速度乘数(常数)", "expr", "", "danmaku"],
		["x", "x速度表达式", "expr", "", "danmaku"],
		["y", "y速度表达式", "expr", "", "danmaku"],
	],
	"IsDanmakuFuncted": [
		["speed", "函数运行速度(x行进)", "expr", "", "danmaku"],
		["x", "坐标系x轴向x", "expr", "", "danmaku"],
		["y", "坐标系x轴向y", "expr", "", "danmaku"],
		["func_expr", "函数表达式(垂直偏移)", "expr", "", "danmaku"],
	],
	"IsDanmakuLaser": [
		["x", "x坐标表达式 n()遍历", "expr", "", "laser"],
		["y", "y坐标表达式 n()遍历", "expr", "", "laser"],
		["laser_n_step", "n()采样频率(像素)", "int"],
		["alarm", "预警时长(帧)", "int"],
		["alarm_shader_alpha", "预警期不透明度比值(可表达式)", "laser_param", "", "laser"],
		["laser_render_scale", "渲染规模(可表达式)", "laser_param", "", "laser"],
	],
	"Nodes": [
		["speed", "初速度", "expr", "", "danmaku"],
		["targe", "目标", "opt", ["", "enemy", "self"]],
		["targe_offsetx", "目标x偏移", "float"],
		["targe_offsety", "目标y偏移", "float"],
		["acc", "追踪加速度", "float"],
		["turn_arg", "最大转向角(弧度/帧)", "float"],
		["speed_max", "速度上限(0=无限)", "float"],
		["lost_max", "远失锁(0=永不)", "float"],
		["lost_min", "近失锁(0=永不)", "float"],
		["lost_if", "锁定条件(命题)", "expr"],
		## 【节点类扩充 20261020】对撞/激活/继承（新列）+ 旧列兼容
		["clash_s", "对撞(命题,真=参与DDM可被摧毁)", "expr"],
		["active_s", "激活(命题,接触即触发释放)", "expr"],
		["clash_ddm_s", "对撞弹幕图数列(占位)", "str"],
		["inherit_when_s", "引爆条件(命题)", "expr"],
		["inherit_s", "引爆事件列表(逗号分隔)", "str"],
		["release_when_s", "释放条件(命题,上升沿)", "expr"],
		["release", "释放事件列表(逗号分隔)", "str"],
		["can_destroy", "可摧毁(旧clash别名)", "check"],
	],
	"NodesB": [
		## 【新节点类 20261020】标准物理节点（弹幕推弹幕）
		["speed", "速度乘数(式)", "expr", "", "danmaku"],
		["x", "x速度表达式", "expr", "", "danmaku"],
		["y", "y速度表达式", "expr", "", "danmaku"],
		["func_expr", "函数表达式(填后转轨道式)", "expr", "", "danmaku"],
		["clash_s", "对撞(命题,真=互推+可被摧毁)", "expr"],
		["active_s", "激活(命题,接触即触发释放)", "expr"],
		["clash_ddm_s", "对撞弹幕图数列(占位)", "str"],
		["inherit_when_s", "引爆条件(命题)", "expr"],
		["inherit_s", "引爆事件列表(逗号分隔)", "str"],
		["release_when_s", "释放条件(命题,上升沿)", "expr"],
		["release", "释放事件列表(逗号分隔)", "str"],
	],
}
## HSL 颜色区
const SCHEMA_COLOR := [
	## 【量纲迁移 20261019】hue=-256~256（相对 color 的偏移）、saturation=0~256
	["hue", "色相(-256~256,相对color偏移)", "expr_num"],
	["saturation", "饱和度(0~256浮点,式)", "expr_num"],
]

## 运算引入工具目录（全角注释；插入格式：运算(“注释”,“注释”)）
## 【批复 2026-10-02：提供所有所属功能支持的运算】文档运算 + Godot 原生常用
## 域标签：danmaku=弹幕通用 / laser=瞬时类 / poi=火力点排布 / formation=杂兵排布 / all

var events: Array[DanmakuEventData] = []
var selected_idx := -1
var _widgets: Dictionary = {}
var _list: ItemList
var _tabs: TabContainer
var _assets: ItemList
var _asset_users: ItemList ## 材质引用反查列表（批复#6）
var _tool_pinned: Dictionary = {} ## 工具条目置顶（批复#9：name/sig -> true）
var _pages: Dictionary = {}
var _status: Label
var _file_dialog: FileDialog
var _pending_action := ""
var _expr_insert_target: LineEdit = null
var _tool_build: Dictionary = {} ## 工具浮窗当前组装（lambda 捕获共享）
var _tool_widgets: Array = [] ## 工具浮窗参数控件
var _tool_popup: PopupPanel = null

## =============================================================
## 事件数组唯一赋值入口：编辑器工作集与 GameGlobals.editor_events 恒为同一实例
## 【严重bug修复 20261019】旧版只有"试炼场预览"才同步——绑定弹幕后不经预览按钮
## 走自定义对战时 editor_events 为空，火力点读不到绑定（出不了弹）
## =============================================================
func _set_events(arr: Array[DanmakuEventData]) -> void:
	events = arr
	GameGlobals.editor_events = arr
	GameGlobals.sync_official_events(events, _deleted_names) ## 变更即落盘（合并-排除删除项）

var _deleted_names: PackedStringArray = [] ## 本会话真删除的事件名（同步时排除）

## =============================================================
## 杂兵页（批复 20261020）：privates.csv 元数据编辑 + shoot_evs 弹幕分配
## （杂兵无火力点——弹幕从自身发射，ShootCd=自身发射冷却，单位 0.1秒）
## =============================================================
func _build_privates_page() -> Control:
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	box.add_child(top)
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(220, 0)
	for prow in CharaDB.load_privates():
		pick.add_item("%s　%s" % [prow.get("Name", "?"), prow.get("NameZH", "")])
		pick.set_item_metadata(pick.item_count - 1, String(prow.get("Name", "")))
	top.add_child(pick)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(detail)
	var render := func():
		for c in detail.get_children():
			c.queue_free()
		var cname: String = pick.get_item_metadata(pick.selected) if pick.selected >= 0 else ""
		var prow: Dictionary = CharaDB.get_private_by_name(cname)
		if prow.is_empty():
			return
		var edit_row: Dictionary = {}
		for k in prow:
			edit_row[k] = str(prow[k])
		var meta := Label.new()
		meta.text = "【杂兵元数据】 %s" % cname
		detail.add_child(meta)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		detail.add_child(grid)
		for k in ["Normal", "Determine", "Defend", "ShootCd", "NameZH", "NameJP", "NameEN"]:
			var lb := Label.new()
			lb.text = k
			grid.add_child(lb)
			var e := LineEdit.new()
			e.text = str(edit_row.get(k, ""))
			e.text_changed.connect(func(t): edit_row[k] = t.replace("#", ""))
			grid.add_child(e)
		var dl := Label.new()
		dl.text = "【杂兵弹幕（自身发射；ShootCd 冷却；保存杂兵数据后生效）】"
		detail.add_child(dl)
		var col := "shoot_evs"
		var evs_list: PackedStringArray = String(edit_row.get(col, "")).split(";", false)
		var sl := Label.new()
		sl.text = "  发射列表（%d 项）" % evs_list.size()
		detail.add_child(sl)
		for ev_name in evs_list:
			var nm0 := ev_name.strip_edges()
			if nm0 == "":
				continue
			var row2 := HBoxContainer.new()
			detail.add_child(row2)
			var nm := Label.new()
			nm.text = "    ▸ " + nm0
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row2.add_child(nm)
			var rm := Button.new()
			rm.text = "移除"
			rm.pressed.connect(func():
				var cur: PackedStringArray = String(edit_row.get(col, "")).split(";", false)
				cur.erase(nm0)
				edit_row[col] = ";".join(cur)
				if CharaDB.save_private_row(cname, edit_row):
					_set_status("已移除并写入 privates.csv")
				_priv_render.call())
			row2.add_child(rm)
		var add := HBoxContainer.new()
		detail.add_child(add)
		var ev_o := OptionButton.new()
		for ev in events:
			ev_o.add_item(ev.event_name)
			ev_o.set_item_metadata(ev_o.item_count - 1, ev.event_name)
		if ev_o.item_count > 0:
			ev_o.select(0)
		add.add_child(ev_o)
		var addb := Button.new()
		addb.text = "挂载到自身发射"
		addb.pressed.connect(func():
			if ev_o.selected >= 0:
				var nm2: String = str(ev_o.get_item_metadata(ev_o.selected))
				var cur2: PackedStringArray = String(edit_row.get(col, "")).split(";", false)
				if nm2 != "" and not cur2.has(nm2):
					cur2.append(nm2)
					edit_row[col] = ";".join(cur2)
					if CharaDB.save_private_row(cname, edit_row):
						_set_status("已挂载 %s 并写入 privates.csv" % nm2)
					_priv_render.call())
		add.add_child(addb)
		var saverow := HBoxContainer.new()
		detail.add_child(saverow)
		var save := Button.new()
		save.text = "保存杂兵数据到 privates.csv"
		save.pressed.connect(func():
			if CharaDB.save_private_row(cname, edit_row):
				_set_status("已写回 %s（privates.csv）" % cname)
			else:
				_set_status("写回失败：%s" % cname))
		saverow.add_child(save)
	pick.item_selected.connect(func(_i): _priv_render.call())
	_priv_render = render ## lambda 无法自引用（同角色页方案）
	if pick.item_count > 0:
		pick.select(0)
		_priv_render.call()
	return box

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and not events.is_empty():
		GameGlobals.sync_official_events(events) ## 退出编辑器兜底落盘

func _ready() -> void:
	_build_ui()
	if GameGlobals.editor_events.is_empty():
		_load_official_csv()
	else:
		_set_events(GameGlobals.editor_events)
	_refresh_list()
	if not events.is_empty():
		_select(0)

## =============================================================
## UI 构建：顶栏 / 左侧主页面签+素材栏 / 主区 / 底栏
## 【布局对齐 scheme/图片示意（作者批复 2026-10-02）】
##   左侧竖排主页面签：角色 / 弹幕 / 时间轴；其下为素材栏（媒体库式）
##   弹幕页 = 事件列表 + 三标签（通用参数[含颜色HSL]/弹幕表达/使用者）
##   角色页 = 元数据/表现/性格/角色弹幕 四节（BoardBasic）
##   弹幕显示浮窗：[Z] 或按钮唤出，2x 缩放，全屏=窗口最大化（BoardBasic/2）
##   表达式输入框旁挂"参/运"小按钮（BoardBasic2：变量用按钮点选代替键盘输入）
## =============================================================
func _build_ui() -> void:
	## 【布局 20261003b·三段锚定】顶栏锚顶 / 中段填满 / 底栏锚底——
	## 任意窗口尺寸下底栏按钮都可见可点（作者批复：下方按钮锚定底部）。
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var menubar := _build_menubar()
	menubar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(menubar)
	var body := HSplitContainer.new()
	body.anchor_left = 0.0
	body.anchor_right = 1.0
	body.anchor_top = 0.0
	body.anchor_bottom = 1.0
	body.offset_left = 4
	body.offset_right = -4
	body.offset_top = 34
	body.offset_bottom = -52
	add_child(body)
	## 左：主页面签 + 素材栏
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	body.add_child(left)
	var pagerow := HBoxContainer.new()
	left.add_child(pagerow)
	var group := ButtonGroup.new()
	for pg in [["danmaku", "弹幕"], ["chara", "角色"], ["privates", "杂兵"], ["timeline", "时间轴"], ["formation", "排布"]]:
		var b := Button.new()
		b.text = pg[1]
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_show_main_page.bind(pg[0]))
		if pg[0] == "danmaku":
			b.button_pressed = true
		pagerow.add_child(b)
	var asset_l := Label.new()
	asset_l.text = "素材（材质库）"
	left.add_child(asset_l)
	_assets = ItemList.new()
	_assets.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_assets.item_selected.connect(_on_asset_selected)
	_assets.item_activated.connect(_on_asset_double) ## 双击=材质详情+引用反查（批复#6）
	left.add_child(_assets)
	var _use_l := Label.new()
	_use_l.text = "引用反查（选中材质→哪些角色/事件在用）"
	left.add_child(_use_l)
	_asset_users = ItemList.new()
	_asset_users.custom_minimum_size = Vector2(0, 110)
	left.add_child(_asset_users)
	_refresh_assets()
	## 右：三个主页面
	_pages = { "danmaku": _build_danmaku_page(), "chara": ScrollContainer.new(), "privates": ScrollContainer.new(), "timeline": ScrollContainer.new(), "formation": _build_formation_page() }
	for k in _pages:
		_pages[k].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_pages[k].size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(_pages[k])
	_pages["chara"].name = "CharaPage"
	_pages["privates"].name = "PrivatesPage"
	_pages["timeline"].name = "TimelinePage"
	_pages["formation"].name = "FormationPage"
	_show_main_page("danmaku")
	## 底栏（锚定底部）
	var bottom := HBoxContainer.new()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 4
	bottom.offset_right = -4
	bottom.offset_top = -48
	bottom.offset_bottom = -4
	add_child(bottom)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 40)
	bottom.add_child(_status)
	var preview_b := Button.new()
	preview_b.text = "▶ 试炼场预览"
	preview_b.pressed.connect(_on_preview)
	bottom.add_child(preview_b)
	var show_b := Button.new()
	show_b.text = "弹幕显示浮窗(Z发射)"
	show_b.pressed.connect(_open_preview_window)
	bottom.add_child(show_b)
	var op_b := Button.new()
	op_b.text = "运算工具"
	op_b.pressed.connect(_show_tool_popup.bind(false, null)) ## 运算=算数/原生分类
	bottom.add_child(op_b)
	var var_b := Button.new()
	var_b.text = "参数工具"
	var_b.pressed.connect(_show_tool_popup.bind(true, null)) ## 参数=变量引用
	bottom.add_child(var_b)
	## 文件对话框（挂在编辑器节点下——独立窗口模式里随窗口走）
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.file_selected.connect(_on_file_selected)
	_dialog_reparent(_file_dialog, Vector2i(), false) ## 仅挂载，不弹出（修复：开屏弹保存窗）

## —— 主页面切换（懒建角色/时间轴页）——
func _show_main_page(key: String) -> void:
	for k in _pages:
		_pages[k].visible = (k == key)
	if key == "chara" and _pages["chara"].get_child_count() == 0:
		_pages["chara"].add_child(_build_chara_page())
	if key == "privates" and _pages["privates"].get_child_count() == 0:
		_pages["privates"].add_child(_build_privates_page())
	if key == "timeline" and _pages["timeline"].get_child_count() == 0:
		_pages["timeline"].add_child(_build_timeline_page())

## —— 弹幕页（原主体：事件列表 + 标签页）——
func _build_danmaku_page() -> HSplitContainer:
	var split := HSplitContainer.new()
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	split.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i): _select(i))
	left.add_child(_list)
	var lbtns := HBoxContainer.new()
	left.add_child(lbtns)
	for t in ["新增", "重命名", "复制", "删除", "检查"]:
		var b := Button.new()
		b.text = t
		b.pressed.connect(_on_list_btn.bind(t))
		lbtns.add_child(b)
	_tabs = TabContainer.new()
	split.add_child(_tabs)
	return split

## —— 素材栏（媒体库式：官方库 + 导入材质）——
func _refresh_assets() -> void:
	_assets.clear()
	var names: Array[String] = []
	var dir := DirAccess.open("res://gameAssetBase/shooting/danmaku16pxs")
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".png") or f.ends_with(".PNG"):
				names.append(f.get_basename())
			f = dir.get_next()
		dir.list_dir_end()
	for k in GameGlobals.editor_textures:
		if not names.has(k):
			names.append(k)
	names.sort()
	for n in names:
		_assets.add_item(n)

func _on_asset_selected(i: int) -> void:
	_refresh_asset_users()

func _on_asset_double(i: int) -> void:
	## 双击=详情浮窗（尺寸/规格）+ 引用反查刷新（批复#6）
	_refresh_asset_users()
	var tex := DanmakuTex.resolve(_assets.get_item_text(i))
	var sz := tex.get_size() if tex != null else Vector2.ZERO
	var users := _asset_users.item_count
	_set_status("材质 %s：%d×%d（粒子=2的次方、方向朝右；激光=单像素线）｜被 %d 处引用" % [
		_assets.get_item_text(i), sz.x, sz.y, users])

## 引用反查：该材质被哪些角色通过哪些事件使用
func _refresh_asset_users() -> void:
	if _asset_users == null:
		return
	_asset_users.clear()
	var sel := _assets.get_selected_items()
	if sel.is_empty():
		return
	var tex_name := _assets.get_item_text(sel[0])
	var all: Array = []
	all.append_array(events)
	for pool in [GameGlobals.mod_events, GameGlobals.official_events]:
		for e in pool.values():
			all.append(e)
	var seen := {}
	for e in all:
		var ev: DanmakuEventData = e
		if ev.texture.to_lower() != tex_name.to_lower():
			continue
		var line := "%s" % ev.event_name
		if not seen.has(line):
			seen[line] = true
			_asset_users.add_item(line)

## 独立窗口模式检测（标题画面唤出时编辑器挂在 Window 下）
func _in_window_mode() -> bool:
	return get_parent() is Window

## 顶栏菜单
func _build_menubar() -> MenuBar:
	var mb := MenuBar.new()
	var file_menu := PopupMenu.new()
	file_menu.name = "文件"
	var items: Array
	if _in_window_mode():
		## 窗口模式：无"返回游戏标题"（那会切走游戏主画面导致假死观感），
		## 关闭窗口即退出编辑器
		items = ["新建", "打开(.thx)", "导入材质", "保存(.thx)", "导出为官方数据", "关闭编辑器窗口"]
	else:
		items = ["新建", "打开(.thx)", "导入材质", "保存(.thx)", "导出为官方数据", "返回游戏标题", "退出游戏"]
	if not _is_project_env():
		var export_label := "打包并导出(.thx)"
		items[4] = export_label
	for i in items.size():
		file_menu.add_item(items[i], i)
	file_menu.id_pressed.connect(func(id): _on_menu_file(items[id]))
	mb.add_child(file_menu)
	var edit_menu := PopupMenu.new()
	edit_menu.name = "编辑"
	var edit_items := ["撤销", "重做", "项目信息", "查找"]
	for i in edit_items.size():
		edit_menu.add_item(edit_items[i], i)
	edit_menu.id_pressed.connect(_on_menu_edit.bind(edit_items))
	mb.add_child(edit_menu)
	var help_menu := PopupMenu.new()
	help_menu.name = "帮助"
	help_menu.add_item("游戏信息", 0)
	help_menu.add_item("Godot文档", 1)
	help_menu.id_pressed.connect(func(id):
		if id == 0:
			_set_status("THX075 东方无欲拾食纪 ~Starve Universia~ 弹幕编辑器 第①期")
		else:
			OS.shell_open("https://docs.godotengine.org/zh-cn/4.5/tutorials/scripting/evaluating_expressions.html"))
	mb.add_child(help_menu)
	return mb

## 编辑菜单回调（lambda内match的解析器歧义 → 命名函数）
func _on_menu_edit(_id: int, items: Array) -> void:
	match items[_id]:
		"撤销":
			_undo()
		"重做":
			_redo()
		"项目信息":
			_set_status("事件数 %d｜材质 %d" % [events.size(), GameGlobals.editor_textures.size()])
		"查找":
			_open_find()

## 工程环境检测：res://gameAssetBase 可写（导出包内只读）
func _is_project_env() -> bool:
	var f := FileAccess.open("res://gameAssetBase/.write_test", FileAccess.WRITE)
	if f != null:
		f.close()
		DirAccess.remove_absolute("res://gameAssetBase/.write_test")
		return true
	return false

func _on_menu_file(item: String) -> void:
	_collect_form()
	match item:
		"新建":
			_set_events(DanmakuEventData.parse_csv_text(""))
			events.append(DanmakuEventData.new())
			_refresh_list()
			_select(0)
			_set_status("已新建")
		"打开(.thx)":
			_pending_action = "load_thx"
			_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			_file_dialog.filters = PackedStringArray(["*.thx ; THX弹幕包"])
			_file_dialog.popup_centered(Vector2i(900, 600))
		"导入材质":
			_pending_action = "import_tex"
			_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			_file_dialog.filters = PackedStringArray(["*.png ; PNG图片"])
			_file_dialog.popup_centered(Vector2i(900, 600))
		"保存(.thx)", "打包并导出(.thx)":
			_pending_action = "save_thx"
			_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			_file_dialog.filters = PackedStringArray(["*.thx ; THX弹幕包"])
			_file_dialog.popup_centered(Vector2i(900, 600))
		"导出为官方数据":
			_on_export_official()
		"关闭编辑器窗口":
			if _in_window_mode():
				_confirm_exit("close")
			else:
				_set_status("当前不是窗口模式")
		"返回游戏标题":
			_confirm_exit("title")
		"退出游戏":
			_confirm_exit("quit")

## =============================================================
## 标签页表单：通用参数 / 弹幕表达(tag互斥) / 使用者
## =============================================================
func _select(i: int) -> void:
	if i < 0 or i >= events.size():
		return
	_snapshot() ## R3：切换选择前留底（撤销/重做可回到切换前状态）
	selected_idx = i
	_build_tabs(events[i])

func _build_tabs(ev: DanmakuEventData) -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c) ## 【复发修复 20261020】queue_free 是帧末移除——
		c.queue_free() ## 同名新页当帧加入会被 Godot 改名 "@VBoxContainer@N"
	_widgets.clear()
	## Tab1 通用（含颜色HSL——设计图 BoardBasic2：三个标签）
	_tabs.add_child(_make_form_page("通用参数", SCHEMA_COMMON + SCHEMA_COLOR, ev))
	## Tab2 弹幕表达（互斥）
	var tag_schema: Array = SCHEMA_BY_TAG.get(ev.tag, [])
	## 【修复选框遮挡】弹幕表达页 = VBox[ 顶部tagrow(不滚动) + 表单ScrollContainer ]
	## 旧版把 tagrow 塞进 ScrollContainer 内，下拉框被滚动区裁剪遮挡
	var page_wrap := VBoxContainer.new()
	page_wrap.name = "弹幕表达"
	var tagrow := HBoxContainer.new()
	page_wrap.add_child(tagrow)
	var tl := Label.new()
	tl.text = "  行进类型："
	tagrow.add_child(tl)
	var tagpick := OptionButton.new()
	for t in DanmakuEventData.TAGS:
		tagpick.add_item(t)
	tagpick.select(DanmakuEventData.TAGS.find(ev.tag))
	## 【批复】切换运动方式先询问（不兼容参数将被清除；保存时按新类型归入对应 CSV）
	_tag_pick = tagpick
	tagpick.item_selected.connect(func(idx):
		_snapshot()
		_on_tag_switch(idx))

	var page2 := _make_form_page("弹幕表达", tag_schema, ev)
	page2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_wrap.add_child(page2)
	var add_row := HBoxContainer.new()
	page_wrap.add_child(add_row)
	var add_tag := Button.new()
	add_tag.text = "＋新增同类型弹幕"
	add_tag.pressed.connect(func():
		_collect_form()
		var ne := DanmakuEventData.new()
		ne.tag = ev.tag
		ne.event_name = "new_%s_%d" % [ev.tag, events.size() + 1]
		events.append(ne)
		_refresh_list()
		_select(events.size() - 1))
	add_row.add_child(add_tag)
	tagrow.add_child(tagpick)
	_tabs.add_child(page_wrap)
	## Tab3 使用者
	var page3 := ScrollContainer.new()
	page3.name = "使用者"
	var vbox3 := VBoxContainer.new()
	vbox3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page3.add_child(vbox3)
	var users := _find_users(ev.event_name)
	if users.is_empty():
		var l := Label.new()
		l.text = "好康，是新弹幕吔！未被任何角色/火力槽引用，去拿给少女们玩吧。"
		vbox3.add_child(l)
	else:
		for u in users:
			var l := Label.new()
			l.text = u
			vbox3.add_child(l)
	_tabs.add_child(page3)

func _make_form_page(tab_name: String, schema: Array, ev: DanmakuEventData) -> ScrollContainer:
	var page := ScrollContainer.new()
	## 【修复】TabContainer 标签取 name；未设名时显示 @ScrollContainer@N（作者报告）
	page.name = tab_name
	page.set_meta("tab_label", tab_name)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(grid)
	for row in schema:
		var key: String = row[0]
		var label := Label.new()
		label.text = row[1]
		grid.add_child(label)
		var w: Control = _make_widget(row, ev)
		## 表达式输入框旁挂"参/运"小按钮（BoardBasic2：工具紧邻输入框，
		## 变量用按钮点选代替键盘输入）
		if row[2] == "expr" or row[2] == "expr_num":
			var box := HBoxContainer.new()
			box.add_child(w)
			var vb := Button.new()
			vb.text = "参"
			vb.tooltip_text = "参数引入工具"
			vb.pressed.connect(_show_tool_popup.bind(true, w))
			box.add_child(vb)
			var ob := Button.new()
			ob.text = "运"
			ob.tooltip_text = "运算引入工具"
			ob.pressed.connect(_show_tool_popup.bind(false, w))
			box.add_child(ob)
			w = box
		_widgets[key] = w if not (row[2] == "expr" or row[2] == "expr_num") else w.get_child(0)
		grid.add_child(w)
	return page

func _find_users(event_name: String) -> Array:
	## 【重写 20261020】使用者=Characters 行 main_evs/sub_evs/rest_evs
	## 三列列表中含本事件名的角色（角色侧数据，不再扫事件 owner）
	var out: Array = []
	var all: Array = []
	all.append_array(CharaDB.load_all())
	for d in all:
		for slot in ["main", "sub", "rest"]:
			var col: String = {"main": "main_evs", "sub": "sub_evs", "rest": "rest_evs"}[slot]
			for nm in String(d.get(col, "")).split(";", false):
				if nm.strip_edges() == event_name:
					out.append("%s → %s 槽" % [d.get("NameZH", d.get("Name", "?")), slot])
	return out

## =============================================================
## 控件生成（含 # 拦截）
## =============================================================
## 【22b 20261102·修1】DanmakuEventData.get() 单参——null 显示 "<null>"
## （持续时间列等 0.0.7 出界销毁改造期引入的显示缺陷）——统一空串兜底
func _ev_get_or_empty(ev: DanmakuEventData, key: String) -> Variant:
	var v: Variant = ev.get(key)
	return v if v != null else ""

func _make_widget(row: Array, ev: DanmakuEventData) -> Control:
	var key: String = row[0]
	var t: String = row[2]
	match t:
		"str":
			return _line(str(_ev_get_or_empty(ev, key)), false)
		"expr":
			return _line(str(_ev_get_or_empty(ev, key)), true)
		"expr_num": ## 数值或表达式（hue/saturation）
			return _line(_num_or_expr(ev.get(key)), true)
		"num_expr": ## 数值+算式双字段（类型批复 20261019）：显示 _s 原文，否则数值
			var nv := str(_ev_get_or_empty(ev, key + "_s"))
			return _line(_num_or_expr(nv if nv != "" else ev.get(key)), true)
		"color_adv": ## 颜色 + 高级RGB拆解 + color_ab（作者批复 20261020）：
			## 开启高级→锁定 color 行（保留对照不可改）；再点隐藏四框但数据保留参与运算
			var cbox := VBoxContainer.new()
			var crow := HBoxContainer.new()
			cbox.add_child(crow)
			var clin := _line(str(ev.color), false)
			clin.set_meta("ckey", "color")
			clin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			crow.add_child(clin)
			var advb := Button.new()
			advb.text = "高级"
			crow.add_child(advb)
			var advbox := VBoxContainer.new()
			advbox.visible = false
			cbox.add_child(advbox)
			var adv_keys := [["color_r_s", "color.r(0~256整式)"], ["color_g_s", "color.g(0~256整式)"],
				["color_b_s", "color.b(0~256整式)"], ["color_ab_s", "color_ab(命题,A/B面切换,空=按高级开关)"]]
			for ck in adv_keys:
				var rrow := HBoxContainer.new()
				advbox.add_child(rrow)
				var rl := Label.new()
				rl.text = str(ck[1])
				rl.custom_minimum_size = Vector2(190, 0)
				rrow.add_child(rl)
				var rln := _line(str(ev.get(str(ck[0]))), true)
				rln.set_meta("ckey", str(ck[0]))
				rln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				rrow.add_child(rln)
			## 高级开启：显示四框并锁定 color 行；关闭：全隐（数据保留）
			advb.toggle_mode = true
			advb.button_pressed = ev.color_ab_def
			advbox.visible = ev.color_ab_def
			clin.editable = not ev.color_ab_def
			advb.toggled.connect(func(on):
				advbox.visible = on
				clin.editable = not on)
			var clines: Array = [clin]
			for rr in advbox.get_children():
				clines.append(rr.get_child(1))
			cbox.set_meta("clines", clines)
			cbox.set_meta("advbtn", advb)
			return cbox
		"event_list": ## 事件数列（点向类 explode/release；逗号分隔存储）
			var box2 := VBoxContainer.new()
			var chips := HBoxContainer.new()
			box2.add_child(chips)
			var names: PackedStringArray = str(_ev_get_or_empty(ev, key)).split(",", false)
			for nm in names:
				var nm_s := str(nm).strip_edges()
				if nm_s.is_empty():
					continue
				var chip := Label.new()
				chip.text = "▸ " + nm_s
				chips.add_child(chip)
			box2.set_meta("chips", chips)
			var w2 := Control.new()
			w2.set_meta("key", key)
			w2.set_meta("vbox", box2)
			return box2
		"laser_param": ## 激光参数：数值或表达式（alarm_shader_alpha/laser_render_scale）
			var ls: String = str(_ev_get_or_empty(ev, key + "_s"))
			return _line(ls if ls != "" else str(_ev_get_or_empty(ev, key)), true)
		"int":
			var s := SpinBox.new()
			s.min_value = -1
			s.max_value = 100000
			s.value = float(ev.get(key))
			return s
		"float":
			var s := SpinBox.new()
			s.min_value = -10000
			s.max_value = 10000
			s.step = 0.01
			s.value = float(ev.get(key))
			return s
		"check":
			var c := CheckBox.new()
			c.button_pressed = bool(ev.get(key))
			return c
		"gate":
			var spec: bool = ev.get(key + "_specified")
			return _line(str(_ev_get_or_empty(ev, key)) if spec else "", false)
		"opt":
			var o := OptionButton.new()
			for opt in row[3]:
				o.add_item(str(opt) if opt != "" else "（空）")
			if key == "oob_mode":
				o.select(clampi(int(ev.get(key)), 0, 2)) ## 三选栏按索引
				return o
			var cur: String = str(_ev_get_or_empty(ev, key))
			for i in o.item_count:
				if o.get_item_text(i) == (cur if cur != "" else "（空）"):
					o.select(i)
			return o
		"opt_chars":
			## 归属由角色页绑定框管理（作者批复 2026-10-03）
			var o := OptionButton.new()
			var cur_owner: String = str(_ev_get_or_empty(ev, key))
			o.add_item(cur_owner if cur_owner != "" and cur_owner != "*" else "（由角色页绑定）")
			o.select(0)
			o.disabled = true
			return o
		"opt_tex":
			var o := OptionButton.new()
			var names: Array[String] = []
			var dir := DirAccess.open("res://gameAssetBase/shooting/danmaku16pxs")
			if dir != null:
				dir.list_dir_begin()
				var f := dir.get_next()
				while f != "":
					if f.ends_with(".png") or f.ends_with(".PNG"):
						names.append(f.get_basename())
					f = dir.get_next()
				dir.list_dir_end()
			for k in GameGlobals.editor_textures:
				if not names.has(k):
					names.append(k)
			names.sort()
			for n in names:
				o.add_item(n)
			var cur_tex: String = str(_ev_get_or_empty(ev, key))
			var tfound := false
			for i in o.item_count:
				if o.get_item_text(i) == cur_tex:
					o.select(i)
					tfound = true
					break
			if not tfound and o.item_count > 0:
				o.select(0)
			return o
	return Label.new()

## LineEdit 工厂：拦截 #（Godot 注释符，会损毁导出的 .gd 文件）
func _line(text: String, is_expr: bool) -> LineEdit:
	var e := LineEdit.new()
	e.text = text.replace("#", "")
	e.custom_minimum_size = Vector2(320, 0)
	e.text_changed.connect(func(s: String):
		if s.contains("#"):
			e.text = s.replace("#", "")
			e.caret_column = e.text.length()
			_set_status("禁止输入 # —— 它是Godot注释符，会损毁文件！"))
	if is_expr:
		e.focus_entered.connect(func(): _expr_insert_target = e)
	return e

func _num_or_expr(v) -> String:
	var s := str(v)
	return s

## =============================================================
## 表单⇄数据
## =============================================================
func _collect_form() -> void:
	if selected_idx < 0 or selected_idx >= events.size():
		return
	var ev := events[selected_idx]
	## 【根治 20261020】收集完表单后静默落盘五分表——编辑内容跨场景/跨重启存活
	for row in SCHEMA_COMMON + SCHEMA_COLOR + (SCHEMA_BY_TAG.get(ev.tag, []) as Array):
		var key: String = row[0]
		if not _widgets.has(key):
			continue
		var w: Control = _widgets[key]
		match row[2]:
			"str", "expr":
				ev.set(key, str((w as LineEdit).text).strip_edges())
			"color_adv":
				## 颜色 + 高级RGB + color_ab（作者批复 20261020）：逐行按 ckey 回写；
				## color_ab 默认值=保存时高级开启且三通道有数据（制谱器保存数据决定）
				for cl in w.get_meta("clines"):
					var ck2: String = cl.get_meta("ckey")
					ev.set(ck2, str(cl.text).strip_edges().replace("#", ""))
				var adv_on: bool = (w.get_meta("advbtn") as Button).button_pressed
				ev.color_ab_def = adv_on and (ev.color_r_s != "" or ev.color_g_s != "" or ev.color_b_s != "")
			"num_expr":
				## 【类型批复 20261019】数值+算式双字段：纯数字存数值、算式存 _s 原文
				var nt := str((w as LineEdit).text).strip_edges().replace("#", "")
				if nt.is_valid_float():
					ev.set(key, nt.to_float())
					ev.set(key + "_s", "")
				else:
					ev.set(key + "_s", nt)
			"expr_num":
				var txt := str((w as LineEdit).text).strip_edges()
				ev.set(key, txt.to_float() if txt.is_valid_float() else txt)
			"laser_param":
				var lt := str((w as LineEdit).text).strip_edges().replace("#", "")
				if lt.is_valid_float():
					ev.set(key, lt.to_float())
					ev.set(key + "_s", "")
				else:
					ev.set(key, 1.0 if key != "laser_render_scale" else 1.0)
					ev.set(key + "_s", lt)
			"event_list":
				pass ## 数列由 +/- 按钮直接改事件字段（保存时随 CSV 转义）
			"int":
				ev.set(key, int((w as SpinBox).value))
			"float":
				ev.set(key, (w as SpinBox).value)
			"check":
				ev.set(key, (w as CheckBox).button_pressed)
			"gate":
				## 【类型批复 20261019】rate/pattern 允许算式/命题——纯数字存数值，否则存原文
				var text := str((w as LineEdit).text).strip_edges()
				if key == "rate":
					ev.rate_specified = text != ""
					ev.rate_s = ""
					if text != "":
						if text.is_valid_float():
							ev.rate = text.to_float()
						else:
							ev.rate = 0.0
							ev.rate_s = text
				else:
					ev.pattern_specified = text != ""
					ev.pattern_s = ""
					if text != "":
						if text.is_valid_float():
							ev.pattern = text.to_float()
						else:
							ev.pattern = 0.0
							ev.pattern_s = text
			"opt":
				var o := w as OptionButton
				if o.selected < 0:
					continue
				var v := o.get_item_text(o.selected)
				if key == "oob_mode":
					ev.set(key, o.selected) ## 三选栏存索引
				else:
					ev.set(key, "" if v == "（空）" else v)
			"opt_chars":
				pass ## 归属由角色页绑定框管理
			"opt_tex":
				var o := w as OptionButton
				if o.selected >= 0:
					ev.set(key, o.get_item_text(o.selected))

## =============================================================
## 列表操作
## =============================================================
	GameGlobals.sync_official_events(events)
func _refresh_list() -> void:
	_list.clear()
	for ev in events:
		_list.add_item(ev.display_label())

## 【重命名（作者批复 20261020）】改事件名并同步所有引用：
## Characters.csv 五个列表列 / 时间轴 tick / 各事件的 inherit/release 列表；
## 随后 _set_events 自动落盘分表
func _rename_event() -> void:
	_collect_form()
	if selected_idx < 0 or selected_idx >= events.size():
		return
	var old_name: String = events[selected_idx].event_name
	var dlg := AcceptDialog.new()
	dlg.title = "重命名弹幕事件"
	dlg.dialog_text = "新事件名（引用会自动同步：角色列表/时间轴/事件列表字段）"
	var le := LineEdit.new()
	le.text = old_name
	dlg.add_child(le)
	_dialog_reparent(dlg)
	dlg.confirmed.connect(func():
		var nn := le.text.strip_edges().replace("#", "").replace(",", "")
		if nn == "" or nn == old_name or nn.contains(";"):
			_set_status("重命名取消：名字为空/重复/含非法字符")
			return
		for e9 in events:
			if e9.event_name == nn:
				_set_status("重命名取消：已存在同名事件")
				return
		events[selected_idx].event_name = nn
		## —— 引用同步：Characters.csv 五列 ——
		var cols := ["main_evs", "sub_evs", "rest_evs", "skill_evs", "spell_evs"]
		for d in CharaDB.load_all():
			var changed := false
			for c in cols:
				var lst: PackedStringArray = String(d.get(c, "")).split(";", false)
				for i2 in lst.size():
					if lst[i2].strip_edges() == old_name:
						lst[i2] = nn
						changed = true
				if changed:
					d[c] = ";".join(lst)
			if changed:
				CharaDB.save_row(String(d.get("Name", "")), d)
		## —— 引用同步：时间轴 tick ——
		for tl in GameGlobals.editor_timelines:
			var touched := false
			for tick in tl.ticks:
				var arr: PackedStringArray = tl.ticks[tick]
				for i3 in arr.size():
					if arr[i3].strip_edges() == old_name:
						arr[i3] = nn
						touched = true
				tl.ticks[tick] = arr
			if touched:
				GameGlobals.save_timeline_gd(tl)
		## —— 引用同步：事件列表字段（inherit/release 等）——
		for e10 in events:
			for f in ["inherit_s", "release", "clash_ddm_s"]:
				var lst2: PackedStringArray = String(e10.get(f)).split(";", false)
				var ch2 := false
				for i4 in lst2.size():
					if lst2[i4].strip_edges() == old_name:
						lst2[i4] = nn
						ch2 = true
				if ch2:
					e10.set(f, ";".join(lst2))
		_refresh_list()
		_set_status("已重命名 %s → %s（引用已同步）" % [old_name, nn]))
	dlg.popup_centered()

func _on_list_btn(t: String) -> void:
	_collect_form()
	match t:
		"重命名":
			_rename_event()
		"新增":
			_snapshot()
			events.append(DanmakuEventData.new())
			_refresh_list()
			_select(events.size() - 1)
		"复制":
			_snapshot()
			if selected_idx >= 0:
				var ev := DanmakuEventData.new()
				ev.from_csv_row(DanmakuEventData.split_csv_line(events[selected_idx].to_csv_row()))
				ev.event_name = events[selected_idx].event_name + "_copy"
				events.append(ev)
				_refresh_list()
				_select(events.size() - 1)
		"删除":
			_snapshot()
			if selected_idx >= 0:
				_deleted_names.append(events[selected_idx].event_name) ## 同步时排除（真删除）
				events.remove_at(selected_idx)
				selected_idx = -1
				_refresh_list()
				if not events.is_empty():
					_select(0)
		"检查":
			_check_feasibility()

## 可行性检查：全部事件全部表达式编译报告
func _check_feasibility() -> void:
	_collect_form()
	var total := 0
	var bad: Array[String] = []
	for ev in events:
		var errs := ev.compile()
		total += 1
		for e in errs:
			bad.append(e)
	if bad.is_empty():
		_set_status("可行性检查通过：%d 个事件全部合法 ✓（试炼场可直接预览）" % total)
	else:
		_set_status("可行性检查发现 %d 处问题：\n%s" % [bad.size(), "\n".join(bad)])

## =============================================================
## 文件操作
## =============================================================
func _on_file_selected(path: String) -> void:
	match _pending_action:
		"save_thx":
			_save_thx(path)
		"load_thx":
			_load_thx(path)
		"import_tex":
			_import_texture(path)

## =============================================================
## 【draft.csv 20261025d·作者方案】暂存于 gameAssetBase/draft.csv：
##   ①导出为官方数据/保存.thx 点击前 → 暂存当前工作集（修改前内容）
##   ②不保存退出（退出前询问）→ 按 draft 还原工作集并回写分表（丢弃其后改动）
##   ③无 draft（从未保存过）时不保存退出=不还原
## =============================================================
const DRAFT_PATH := "res://gameAssetBase/draft.csv"

func _draft_stash() -> void:
	var f := FileAccess.open(DRAFT_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[draft] 暂存失败（res:// 只读？）")
		return
	f.store_string(DanmakuEventData.build_csv(events))
	f.close()

func _draft_restore() -> bool:
	if not FileAccess.file_exists(DRAFT_PATH):
		return false
	var text := FileAccess.get_file_as_string(DRAFT_PATH)
	if text.strip_edges().is_empty():
		return false
	_set_events(DanmakuEventData.parse_csv_text(text)) ## _set_events 自动同步回分表=回滚
	_set_status("已按 draft.csv 还原（丢弃上次保存/导出后的改动）")
	return true

## 退出确认：保存并退出 / 不保存退出（按 draft 还原）/ 取消
func _confirm_exit(mode: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "退出编辑器"
	dlg.dialog_text = "是否保存后退出？\n· 确认=导出为官方数据后退出\n· 取消=不保存退出（按 draft.csv 还原上次保存点）\n· 关闭窗口=留在编辑器"
	dlg.ok_button_text = "保存并退出"
	dlg.cancel_button_text = "不保存退出"
	_dialog_reparent(dlg)
	dlg.confirmed.connect(func():
		_on_export_official()
		_after_exit(mode))
	dlg.canceled.connect(func():
		if not _draft_restore():
			_set_status("无 draft.csv（从未保存/导出）——直接退出，改动随自动同步保留")
		_after_exit(mode))
	dlg.popup_centered()

func _after_exit(mode: String) -> void:
	match mode:
		"close":
			if _in_window_mode():
				(get_parent() as Window).queue_free()
		"title":
			GameGlobals.goto_scene("res://scenes/title_menu.tscn")
		"quit":
			get_tree().quit()

func _save_thx(path: String) -> void:
	_draft_stash() ## 【draft 20261025d】保存前暂存修改前内容
	_collect_form()
	if not path.ends_with(".thx"):
		path += ".thx"
	var zp := ZIPPacker.new()
	if zp.open(path) != OK:
		_set_status("保存失败：%s" % path)
		return
	## .thx 内同样五路分表（读取兼容旧单文件）
	for tag: String in GameGlobals.OFFICIAL_EVENT_CSVS:
		var rows: Array[DanmakuEventData] = []
		for ev in events:
			if ev.tag == tag:
				ev.sanitize_for_tag() ## 分表前清除其它运动方式的专属参数（批复 20261019）
				rows.append(ev)
		zp.start_file("danmaku_event_%s.csv" % tag)
		zp.write_file(DanmakuEventData.build_csv(rows).to_utf8_buffer())
		zp.close_file()
	for ev in events:
		zp.start_file("danmaku/%s.gd" % ev.event_name)
		zp.write_file(_gen_event_gd(ev).to_utf8_buffer())
		zp.close_file()
	## 时间轴（作者批复：每0.1秒tick安排一个或多个事件，.gd 后缀文件）
	for tl in GameGlobals.editor_timelines:
		zp.start_file("danmaku/%s.gd" % tl.tl_name)
		zp.write_file(tl.to_gd().to_utf8_buffer())
		zp.close_file()
	for tex_name in GameGlobals.editor_textures:
		zp.start_file("texture/%s.png" % tex_name)
		zp.write_file(GameGlobals.editor_textures[tex_name])
		zp.close_file()
	zp.close()
	_set_status("已保存 .thx：%s（%d事件 %d材质）" % [path, events.size(), GameGlobals.editor_textures.size()])

func _load_thx(path: String) -> void:
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		_set_status("读取失败：%s" % path)
		return
	_set_events(DanmakuEventData.parse_csv_text(""))
	var imported := 0
	GameGlobals.editor_timelines = [] ## 打开新包 → 时间轴以包内容为准
	for f in zr.get_files():
		if f.begins_with("danmaku_event") and f.ends_with(".csv"):
			events.append_array(DanmakuEventData.parse_csv_text(zr.read_file(f).get_string_from_utf8()))
		elif f.begins_with("texture/"):
			var tex_name := f.get_file().get_basename()
			if DanmakuTex.load_from_bytes(tex_name, zr.read_file(f)):
				GameGlobals.editor_textures[tex_name] = zr.read_file(f)
				imported += 1
		elif f.begins_with("danmaku/") and f.ends_with(".gd"):
			var text := zr.read_file(f).get_string_from_utf8()
			if TimelineData.is_timeline_gd(text):
				GameGlobals.editor_timelines.append(TimelineData.parse_gd(text))
	zr.close()
	for ev in events:
		ev.compile()
	_refresh_list()
	if not events.is_empty():
		_select(0)
	_set_status("已读取：%d事件 %d材质" % [events.size(), imported])

func _import_texture(path: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		_set_status("材质导入失败")
		return
	var tex_name := path.get_file().get_basename()
	if DanmakuTex.load_from_bytes(tex_name, bytes):
		GameGlobals.editor_textures[tex_name] = bytes
		_set_status("已导入材质 %s（粒子=2的次方；激光=单像素线条）" % tex_name)
		if selected_idx >= 0:
			_build_tabs(events[selected_idx])
	else:
		_set_status("不是有效PNG")

## 【CSV 五路拆分（作者批复 2026-10-03）】加载：五份分表优先，旧单文件兼容
func _load_official_csv() -> void:
	_set_events(DanmakuEventData.parse_csv_text(""))
	var loaded := false
	for path in GameGlobals.OFFICIAL_EVENT_CSVS.values():
		if not FileAccess.file_exists(path):
			continue
		loaded = true
		events.append_array(DanmakuEventData.parse_csv_text(FileAccess.get_file_as_string(path)))
	if not loaded and FileAccess.file_exists(GameGlobals.OFFICIAL_EVENT_CSV):
		_set_events(DanmakuEventData.parse_csv_text(FileAccess.get_file_as_string(GameGlobals.OFFICIAL_EVENT_CSV)))
	for ev in events:
		ev.compile()

## 导出官方数据：按运行方式写五份分表（每表只含本类；旧单文件不再写）
func _on_export_official() -> void:
	_draft_stash() ## 【draft 20261025d】导出前暂存修改前内容
	_collect_form()
	var written := 0
	for tag: String in GameGlobals.OFFICIAL_EVENT_CSVS:
		var rows: Array[DanmakuEventData] = []
		for ev in events:
			if ev.tag == tag:
				ev.sanitize_for_tag() ## 分表前清除其它运动方式的专属参数（批复 20261019）
				rows.append(ev)
		var f := FileAccess.open(String(GameGlobals.OFFICIAL_EVENT_CSVS[tag]), FileAccess.WRITE)
		if f == null:
			_set_status("导出失败：当前环境 res:// 只读（仅工程源码环境可导出官方数据）")
			return
		f.store_string(DanmakuEventData.build_csv(rows))
		f.close()
		written += rows.size()
	var copied := 0
	for tex_name in GameGlobals.editor_textures:
		var src := _texture_cache_path(tex_name)
		var dst := "res://gameAssetBase/shooting/danmaku16pxs/%s.png" % tex_name
		if FileAccess.file_exists(src) and DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst)) == OK:
			copied += 1
	GameGlobals.reload_official()
	_set_status("已导出为官方数据：%d事件 + %d材质（运行时官方池已刷新）" % [events.size(), copied])

func _texture_cache_path(tex_name: String) -> String:
	var p := "user://editor_textures/%s.png" % tex_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://editor_textures"))
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_buffer(GameGlobals.editor_textures[tex_name])
		f.close()
	return p

## 生成 danmaku/(事件名).gd 描述文件
func _gen_event_gd(ev: DanmakuEventData) -> String:
	var lines: Array[String] = []
	lines.append("## %s —— 弹幕编辑器自动生成（THX075）" % ev.event_name)
	lines.append("## 数值数据源：danmaku_event.csv 同名行；本文件为参数描述。")
	lines.append("extends RefCounted")
	var all_keys := ["event_name","owner","tag","texture","dmg","dmg_mode","range_frames",
		"repeat_time","repeat_freq","is_cannon","rate","pattern","x_offset","y_offset","speed","x","y",
		"rotate_range","rotate_div","rotate_rate","rotate_offset","rotate_sequence",
		"rotate_pingpong","rotate_delay",
		"func_expr","alarm","laser_n_step","targe","acc","turn_arg","speed_max","lost_max","lost_min",
		"lost_if","explode_condit","release_condit","explode","release","can_destroy"]
	for k in all_keys:
		var v = ev.get(k)
		if k in ["rate", "pattern"]:
			v = v if ev.get(k + "_specified") else "(未启用)"
		lines.append("# %s = %s" % [k, str(v)])
	return "\n".join(lines) + "\n"

## =============================================================
## 试炼场 / 工具浮窗
## =============================================================
func _on_preview() -> void:
	_collect_form()
	var errs_all: Array[String] = []
	for ev in events:
		errs_all.append_array(ev.compile())
	GameGlobals.editor_events = events
	GameGlobals.preview_event_name = events[selected_idx].event_name if selected_idx >= 0 and selected_idx < events.size() else "demo_aimed"
	GameGlobals.arena_mode = "preview"
	## 【0.0.9·预览（作者 20261110 终裁=0.0.7-legacy/0.0.8 行为）】goto_scene
	## 替换**主窗口**为试炼场（编辑器子窗口=真 OS 窗口保持；gui_embed_subwindows
	## 已复位到 _ready）；退出试炼场=Esc 面板按钮回本场景（编辑器 _ready 重载工作集）
	GameGlobals.goto_scene("res://scenes/battle_arena.tscn")

## =============================================================
## 运算/参数引入工具浮窗（作者图示重做 2026-10-04）：
##   搜索栏下方一个**选栏**：变量引用 / 算数方法 / godot原生拓展运算
##   列表**单击** = 参数组件化构建（每个参数按类型给 输入框/选框，右侧提示参数名）
##   列表**双击** = 旧式整串插入（全角引号+注释，作者保留）
##   「变量引用」的参数是选框：gettarget(gettarget系变量下拉)、getchara(...)、getfield(...)
##   顶部另有 置顶 与 既有搜索；不再有"自引用勾选"（作者明示废除）
## =============================================================
const VAR_SYSTEMS := {
	"gettarget": {"desc": "目标角色参数（对发射点定值）",
		"params": ["x", "y", "d", "ap", "pp", "normal", "hpweapon", "hpbody", "hpmove"]},
	"getchara": {"desc": "发射者自身参数",
		"params": ["x", "y", "ap", "pp", "normal"]},
	"getfield": {"desc": "场地参数",
		"params": ["t", "phase"]},
}
## 【语义修订 20261015（弹幕编辑器-新）】弹幕在运行时返回的变量——
## 可在弹幕参数（运动表达式等）中引用；只读、不可手动设定。
## 原"弹幕自变量"表述有歧义，此处按新语义列出。
const RUNTIME_VARS := [
	{"name": "t", "desc": "时间：弹幕从开始到现在经过的帧数（只读）"},
	{"name": "t_r", "desc": "预警期时间比：t/alarm（瞬时类，只读）"},
	{"name": "rate_roll", "desc": "概率骰子结果：本次发射的概率骰（只读）"},
	{"name": "pattern_roll", "desc": "规律时序结果：规律累加值（只读）"},
	{"name": "rotate_id", "desc": "旋转副本标号：时序方式排序，首副本=0（只读）"},
	{"name": "r0", "desc": "出生随机数0（0~2π，只读）"},
	{"name": "r1", "desc": "出生随机数1（0~2π，只读）"},
	{"name": "n", "desc": "遍历换元（瞬时类 n(k) 采样，只读）"},
	{"name": "wpcs", "desc": "火力点侧面序号（从里到外，只读）"},
	{"name": "to_c", "desc": "快机系数：快机=1 否则=0（只读）"},
	{"name": "main_lr", "desc": "主机侧边系数：左-1/右1/中0（只读）"},
	{"name": "sub_lr", "desc": "僚机侧边系数：左-1/右1/中0（只读）"},
]
const OP_TOOLS := [
	{"name": "abs", "cat": "算数方法", "params": ["数值"], "desc": "绝对值"},
	{"name": "min", "cat": "算数方法", "params": ["数字1", "数字2"], "desc": "最小值（可连写）"},
	{"name": "max", "cat": "算数方法", "params": ["数字1", "数字2"], "desc": "最大值（可连写）"},
	{"name": "log", "cat": "算数方法", "params": ["底数", "真数"], "desc": "对数"},
	{"name": "sin", "cat": "算数方法", "params": ["弧度"], "desc": "正弦"},
	{"name": "cos", "cat": "算数方法", "params": ["弧度"], "desc": "余弦"},
	{"name": "atan2", "cat": "算数方法", "params": ["y", "x"], "desc": "反正切"},
	{"name": "sqrt", "cat": "算数方法", "params": ["数值"], "desc": "平方根"},
	{"name": "floor", "cat": "算数方法", "params": ["数值"], "desc": "去尾（[[x]]）"},
	{"name": "ceil", "cat": "算数方法", "params": ["数值"], "desc": "进位"},
	{"name": "ave", "cat": "算数方法", "params": ["数字1", "数字2", "数字3（若有）"], "desc": "平均值（翻译为 (a+b(+c))/n）"},
	{"name": "pow", "cat": "godot原生拓展运算", "params": ["底", "指数"], "desc": "次方"},
	{"name": "lerp", "cat": "godot原生拓展运算", "params": ["自", "到", "比例"], "desc": "线性插值"},
	{"name": "clampf", "cat": "godot原生拓展运算", "params": ["值", "最小", "最大"], "desc": "区间钳制"},
	{"name": "wrapf", "cat": "godot原生拓展运算", "params": ["值", "下界", "上界"], "desc": "区间回绕"},
	{"name": "posmod", "cat": "godot原生拓展运算", "params": ["被除", "除"], "desc": "正模"},
]
const TOOL_CATS := ["变量引用", "运行时返回变量", "算数方法", "godot原生拓展运算"]

func _show_tool_popup(is_vars: bool, target: LineEdit = null, domain: String = "") -> void:
	if target != null:
		_expr_insert_target = target
	if _tool_popup != null:
		_tool_popup.queue_free()
	_tool_popup = PopupPanel.new()
	_dialog_reparent(_tool_popup)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 420)
	_tool_popup.add_child(box)
	## 分类选栏（搜索栏下方——作者图示）
	var cat_o := OptionButton.new()
	for c in TOOL_CATS:
		cat_o.add_item(c)
	cat_o.select(1 if not is_vars else 0)
	box.add_child(cat_o)
	## 组件化构建区（单击列表条目时填充）
	var search := LineEdit.new()
	search.placeholder_text = "搜索…"
	box.add_child(search)
	var build_row := HBoxContainer.new()
	box.add_child(build_row)
	var build_hint := Label.new()
	build_hint.text = "单击条目 → 此处组装参数组件；双击条目 → 旧式整串插入"
	box.add_child(build_hint)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(list)
	var build_box2 := HBoxContainer.new()
	box.add_child(build_box2)
	var insert_btn := Button.new()
	insert_btn.text = "插入"
	box.add_child(insert_btn)
	var pin_btn := Button.new()
	pin_btn.text = "置顶选中"
	box.add_child(pin_btn)
	var close := Button.new()
	close.text = "关闭"
	box.add_child(close)
	close.pressed.connect(func(): _tool_popup.queue_free()) ## 【N14】关闭即释放

	## 【修复 20261025e】GDScript lambda 按值捕获局部变量——current_build 重绑定
	## 只改自身副本，插入按钮 lambda 永远见创建时空值（"请先单击"恒现根因）→成员共享
	_tool_build.clear()
	_tool_widgets.clear()
	var current_build := _tool_build
	var widgets := _tool_widgets

	var refresh := func(q: String):
		list.clear()
		var cat: String = TOOL_CATS[cat_o.selected]
		var items: Array = []
		if cat == "变量引用":
			for sys_name in VAR_SYSTEMS:
				items.append({"name": sys_name, "desc": VAR_SYSTEMS[sys_name]["desc"]})
		elif cat == "运行时返回变量":
			for item in RUNTIME_VARS:
				items.append(item)
		else:
			for item in OP_TOOLS:
				if item["cat"] == cat:
					items.append(item)
		var pinned: Array = []
		var normal: Array = []
		for item in items:
			if _tool_pinned.has(item["name"]):
				pinned.append(item)
			else:
				normal.append(item)
		for item in pinned + normal:
			var nm: String = item["name"]
			if q.is_empty() or nm.contains(q) or String(item["desc"]).contains(q):
				var idx := list.add_item("%s%s —— %s" % ["★" if _tool_pinned.has(nm) else "", nm, item["desc"]])
				list.set_item_metadata(idx, item)

	## 单击：组件化构建（每个参数按类型给 输入框/选框）
	var on_selected := func(i: int):
		for c in build_row.get_children():
			c.queue_free()
		for c in build_box2.get_children():
			c.queue_free()
		widgets.clear()
		var item: Dictionary = list.get_item_metadata(i)
		var nm: String = item["name"]
		current_build.clear()
		current_build.merge(item)
		if cat_o.selected == 0: ## 变量引用：gettarget( [选框] )
			var lbl := Label.new()
			lbl.text = nm + "( "
			build_row.add_child(lbl)
			var o := OptionButton.new()
			for p2 in VAR_SYSTEMS[nm]["params"]:
				o.add_item(p2)
			o.select(0) ## 【修复 20261025f】默认选中首项——原无默认值，未手点时 get_selected_item 恒空
			build_row.add_child(o)
			var lbl2 := Label.new()
			lbl2.text = " )"
			build_row.add_child(lbl2)
			widgets.append({"kind": "opt", "ctrl": o})
			var hint := Label.new()
			hint.text = "—— " + VAR_SYSTEMS[nm]["desc"]
			build_box2.add_child(hint)
		elif cat_o.selected == 1: ## 运行时返回变量：只读，插入裸变量名
			var lbl := Label.new()
			lbl.text = nm
			build_row.add_child(lbl)
			var hint := Label.new()
			hint.text = "—— 弹幕运行时返回变量：可直接引用，不可手动设定"
			build_box2.add_child(hint)
		else: ## 算数：每个参数一个输入框，右侧提示参数名
			var lbl := Label.new()
			lbl.text = nm + "( "
			build_row.add_child(lbl)
			var params: Array = item.get("params", [])
			for pi in params.size():
				var e := LineEdit.new()
				e.placeholder_text = str(params[pi])
				e.custom_minimum_size = Vector2(110, 0)
				build_row.add_child(e)
				widgets.append({"kind": "input", "ctrl": e})
				if pi < params.size() - 1:
					var cma := Label.new()
					cma.text = " , "
					build_row.add_child(cma)
			var lbl2 := Label.new()
			lbl2.text = " )"
			build_row.add_child(lbl2)
			var hint := Label.new()
			hint.text = "—— " + ", ".join(params)
			build_box2.add_child(hint)

	var do_insert := func(built: String):
		if _expr_insert_target != null:
			_expr_insert_target.text += built
			_expr_insert_target.text_changed.emit(_expr_insert_target.text)
			_set_status("已插入：%s" % built)
		else:
			_set_status("请先点击一个表达式输入框（或其旁的 参/运 按钮）")

	## 插入按钮：组件化内容替换全角注释（空=保留全角注释）
	## 【修复 20261025f】插入从实际 UI 控件现读（遍历构建行内的 OptionButton/
	## LineEdit），不再依赖任何被 lambda 捕获的数组/字典——捕获类问题根治
	insert_btn.pressed.connect(func():
		if current_build.is_empty():
			_set_status("请先单击一个条目组装参数")
			return
		var nm: String = current_build["name"]
		if cat_o.selected == 0:
			var ob: OptionButton = null
			for c in build_row.get_children():
				if c is OptionButton:
					ob = c
					break
			## 【真根因 20261025i】get_selected_item() 是 Godot3 API——4.7 不存在，
			## 点击即 Nonexistent function 静默中止（插入从未生效的真因）；改 get_item_text(selected)
			var argt: String = ob.get_item_text(ob.selected) if ob != null and ob.selected >= 0 else ""
			if argt == "":
				argt = VAR_SYSTEMS[nm]["params"][0]
			do_insert.call("%s(%s)" % [nm, argt])
		elif cat_o.selected == 1:
			do_insert.call(nm) ## 运行时返回变量：裸名插入
		else:
			var params2: Array = current_build.get("params", [])
			var parts: Array[String] = []
			var li := 0
			for c in build_row.get_children():
				if c is LineEdit:
					var txt: String = c.text.strip_edges()
					var fb: String = str(params2[li]) if li < params2.size() else ""
					parts.append(txt if txt != "" else fb)
					li += 1
			do_insert.call("%s(%s)" % [nm, ",".join(parts)])
)

	## 双击：旧式整串插入（全角引号+注释）
	list.item_activated.connect(func(i: int):
		var item: Dictionary = list.get_item_metadata(i)
		var nm: String = item["name"]
		if cat_o.selected == 0:
			do_insert.call("%s(“%s”)" % [nm, "参数"])
		elif cat_o.selected == 1:
			do_insert.call(nm) ## 运行时返回变量：裸名插入
		else:
			var ps: Array = item.get("params", [])
			var qs: Array[String] = []
			for p3 in ps:
				qs.append("“%s”" % p3)
			do_insert.call("%s(%s)" % [nm, ",".join(qs)])
)
	list.item_selected.connect(on_selected)
	cat_o.item_selected.connect(func(_i): refresh.call(search.text))
	pin_btn.pressed.connect(func():
		for i in list.get_selected_items():
			var item: Dictionary = list.get_item_metadata(i)
			var nm: String = item["name"]
			if _tool_pinned.has(nm):
				_tool_pinned.erase(nm)
			else:
				_tool_pinned[nm] = true
		refresh.call(search.text))
	search.text_changed.connect(func(q): refresh.call(q))
	refresh.call("")
	_tool_popup.popup_centered(Vector2i(580, 460))

## 撤销/重做（①期简化：快照栈）
var _undo_stack: Array[String] = []
var _redo_stack: Array[String] = []
func _snapshot() -> void:
	_undo_stack.append(DanmakuEventData.build_csv(events))
	if _undo_stack.size() > 64:
		_undo_stack.pop_front()
	_redo_stack.clear()
func _undo() -> void:
	if _undo_stack.is_empty():
		_set_status("没有可撤销的操作")
		return
	_redo_stack.append(DanmakuEventData.build_csv(events))
	_set_events(DanmakuEventData.parse_csv_text(_undo_stack.pop_back()))
	_refresh_list()
	_set_status("已撤销")
func _redo() -> void:
	if _redo_stack.is_empty():
		_set_status("没有可重做的操作")
		return
	_undo_stack.append(DanmakuEventData.build_csv(events))
	_set_events(DanmakuEventData.parse_csv_text(_redo_stack.pop_back()))
	_refresh_list()
	_set_status("已重做")

var _tag_pick: OptionButton = null
var _pending_tag_idx := -1

## 切换运动方式：确认后清不兼容参数并按新类型重建表单（保存时自动归对应 CSV）
func _on_tag_switch(idx: int) -> void:
	if selected_idx < 0 or selected_idx >= events.size():
		return
	var new_tag: String = DanmakuEventData.TAGS[idx]
	var ev := events[selected_idx]
	if ev.tag == new_tag:
		return
	_pending_tag_idx = idx
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "切换运动方式为 %s？
不兼容的类型专属参数将被清除（保存时该弹幕将归入 danmaku_event_%s.csv）。" % [
		new_tag, new_tag.to_lower()]
	dlg.ok_button_text = "切换"
	dlg.cancel_button_text = "取消"
	_dialog_reparent(dlg) ## 同步挂载+popup_centered（修复：弹窗从不显示→无法切换）
	dlg.confirmed.connect(func():
		_collect_form()
		var ev2 := events[selected_idx]
		ev2.tag = new_tag
		## 【修复 20261019】清除不兼容参数改用数据级 sanitize_for_tag（旧实现按
		## 表单 schema 遍历：漏掉 alarm_shader_alpha_s 等派生字段、误清共享 speed）
		ev2.sanitize_for_tag()
		_build_tabs(ev2)
		_set_status("已切换为 %s（保存/导出时归入对应 CSV 分表）" % new_tag))
	dlg.canceled.connect(func():
		if _tag_pick != null:
			_tag_pick.select(DanmakuEventData.TAGS.find(events[selected_idx].tag)))


## 查找（编辑菜单）：弹小窗输入关键字过滤事件列表；点击结果跳转选中
func _open_find() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "查找弹幕事件"
	var box := VBoxContainer.new()
	dlg.add_child(box)
	var le := LineEdit.new()
	le.placeholder_text = "事件名 / 类型 / 表达式内容…"
	box.add_child(le)
	var res := ItemList.new()
	res.custom_minimum_size = Vector2(420, 260)
	box.add_child(res)
	le.text_changed.connect(func(q: String):
		res.clear()
		for i in events.size():
			var e := events[i]
			var hay := "%s %s %s %s %s %s" % [e.event_name, e.tag, e.x, e.y, e.speed, e.func_expr]
			if q.is_empty() or hay.contains(q):
				res.add_item(e.display_label())
				res.set_item_metadata(res.item_count - 1, i))
	res.item_activated.connect(func(i):
		_select(int(res.get_item_metadata(i)))
		dlg.queue_free())
	dlg.ok_button_text = "关闭"
	_dialog_reparent(dlg, Vector2i(460, 380))
	le.grab_focus()

## 杂兵排布页：四系统预设公式浏览（完整自定义编辑=③期后续批）
func _build_formation_page() -> Control:
	## 【批复 20261024】排布公式可编辑：文本框可复制/修改，保存写入
	## user://formation_override.cfg（PrivateFormation 每次编译读取覆盖）；
	## 「恢复默认」清该预设覆盖
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = "杂兵排布预设（公式可编辑；保存后写入 formation_override；custom_a/b 释义见下）"
	t.add_theme_font_size_override("font_size", 16)
	box.add_child(t)
	var ovr := PrivateFormation.load_override()
	for preset_name in PrivateFormation.PRESETS:
		var pr: Dictionary = PrivateFormation.PRESETS[preset_name]
		var l := Label.new()
		l.text = "【%s】" % preset_name
		box.add_child(l)
		var fields := ["termin_point_x", "termin_point_y", "termin_range", "tpp"]
		var edits := {}
		for f in fields:
			var row := HBoxContainer.new()
			box.add_child(row)
			var fl := Label.new()
			fl.text = "  %s =" % f
			fl.custom_minimum_size = Vector2(150, 0)
			row.add_child(fl)
			var le := LineEdit.new()
			le.text = str(ovr.get("%s.%s" % [preset_name, f], pr.get(f, "")))
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(func(_tx): pass)
			row.add_child(le)
			edits[f] = le
		for k in pr.get("dict_zh", {}):
			var dl := Label.new()
			dl.text = "    %s = %s" % [k, pr["dict_zh"][k]]
			box.add_child(dl)
		var brow := HBoxContainer.new()
		box.add_child(brow)
		var sb := Button.new()
		sb.text = "保存本预设修改"
		var pname: String = preset_name
		sb.pressed.connect(func():
			var o := PrivateFormation.load_override()
			for f2 in fields:
				var v := str(edits[f2].text).strip_edges().replace("#", "")
				if v == "":
					o.erase("%s.%s" % [pname, f2])
				else:
					o["%s.%s" % [pname, f2]] = v
			PrivateFormation.save_override(o)
			_set_status("排布 %s 修改已保存（formation_override）" % pname))
		brow.add_child(sb)
		var rb := Button.new()
		rb.text = "恢复默认"
		rb.pressed.connect(func():
			var o := PrivateFormation.load_override()
			for f3 in fields:
				o.erase("%s.%s" % [pname, f3])
			PrivateFormation.save_override(o)
			for f4 in fields:
				edits[f4].text = str(pr.get(f4, ""))
			_set_status("排布 %s 已恢复默认" % pname))
		brow.add_child(rb)
	return box

## 弹窗统一挂载：不进编辑器 Control 子树（否则被 TabContainer 当子页签，
## 切运行方式后出现 "@ScrollContainer@数字" 占位标签——作者 2026-10-04 报告复发）
## 弹窗统一挂窗口根并弹出。
## 【20261004 修复：运动方式切换弹窗不出现】Window 默认隐藏——只 add_child
## 不 popup 就永远看不见（也就永远无法确认切换）。统一在此 add+popup：
## 编辑器在树内=同步（用户交互时父不忙）；构建期=全部延迟排队（FIFO 保序）。
func _dialog_reparent(dlg: Window, center_size: Vector2i = Vector2i(), do_popup := true) -> void:
	## 统一走延迟队列（同帧 FIFO：add 先于 popup）——
	## 同步 add 在 _ready 构建期会撞 "Parent busy"；交互期延迟也在同一帧内生效
	var host_win := get_window()
	if host_win != null and host_win != self:
		host_win.add_child.call_deferred(dlg)
	else:
		add_child.call_deferred(dlg)
	if not do_popup:
		return ## 文件对话框等按需弹出的窗体只挂载
	if center_size != Vector2i():
		dlg.call_deferred("popup_centered", center_size)
	else:
		dlg.call_deferred("popup_centered")

func _set_status(t: String) -> void:
	_status.text = t

## =============================================================
## 角色页（设计 BoardBasic 四节；20261003 起支持**编辑并写回 Characters.csv**）
## 可编辑：元数据(判定/结界/魔弹/物弹/三语名) 表现(速度/冷却/乘数/poi)
##         性格(Char_*)；ID/Team 只读（队伍结构数据）。
## =============================================================
const CHARA_EDIT_META := ["Determine", "Defend", "Mag", "Phy", "NameZH", "NameJP", "NameEN"]
const CHARA_EDIT_PERF := ["Cruise", "Normal", "Main_Cd", "Sub_Cd", "Weapon_Muti",
	"main_y", "sub_x", "sub_y", "main_poi_x", "main_poi_y", "sub_poi_x", "sub_poi_y",
	"main_para_rat", "main_seco_rat", "sub_para_rat"]
const CHARA_EDIT_CHAR := ["Char_Raid", "Char_Allfire", "Char_Blitz", "Char_Cover",
	"Char_Elast", "Char_Delay", "Char_Feint"]

func _build_chara_page() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pick := OptionButton.new()
	var chars := CharaDB.load_all()
	for d in chars:
		pick.add_item("%s　%s" % [d["Name"], d["NameZH"]])
		pick.set_item_metadata(pick.item_count - 1, d["Name"])
	box.add_child(pick)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(detail)
	var render := func():
		for c in detail.get_children():
			c.queue_free()
		var cname: String = pick.get_item_metadata(pick.selected)
		var d := CharaDB.get_by_name(cname)
		if d.is_empty():
			return
		var edit_row: Dictionary = {} ## 工作副本（字符串）
		for k in d:
			edit_row[k] = str(d[k])
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		detail.add_child(grid)

		## 四节（设计 BoardBasic）——每节两列：标签+输入（GDScript 无内嵌函数，循环内联）
		var meta_l := Label.new()
		meta_l.text = "【角色元数据】 %s | ID=%s 队伍=%s（只读）" % [cname, edit_row.get("ID"), edit_row.get("Team")]
		detail.add_child(meta_l)
		for k in CHARA_EDIT_META:
			var l := Label.new()
			l.text = "元数据.%s" % k
			grid.add_child(l)
			var e := LineEdit.new()
			e.text = str(edit_row.get(k, ""))
			e.custom_minimum_size = Vector2(150, 0)
			e.text_changed.connect(func(t): edit_row[k] = t.replace("#", ""))
			grid.add_child(e)
		var perf_l := Label.new()
		perf_l.text = "【角色表现】快/慢机=像素每帧；冷却=0.1秒；poi 支持表达式(wpcs/to_c)；占比：首要进位/次要去尾"
		detail.add_child(perf_l)
		var poi_cols := ["main_y", "sub_x", "sub_y", "main_poi_x", "main_poi_y", "sub_poi_x", "sub_poi_y"]
		for k in CHARA_EDIT_PERF:
			var l2 := Label.new()
			l2.text = "表现.%s" % k
			grid.add_child(l2)
			var e2 := LineEdit.new()
			e2.text = str(edit_row.get(k, ""))
			e2.custom_minimum_size = Vector2(150, 0)
			e2.text_changed.connect(func(t): edit_row[k] = t.replace("#", ""))
			if k in poi_cols:
				## poi 系列支持 wpcs/to_c 表达式 → 参/运 按钮（域=poi，作者批复）
				var pbox := HBoxContainer.new()
				pbox.add_child(e2)
				var pv := Button.new()
				pv.text = "参"
				pv.pressed.connect(_show_tool_popup.bind(true, e2, "poi"))
				pbox.add_child(pv)
				var po := Button.new()
				po.text = "运"
				po.pressed.connect(_show_tool_popup.bind(false, e2, "poi"))
				pbox.add_child(po)
				grid.add_child(pbox)
			else:
				grid.add_child(e2)
		var char_l := Label.new()
		char_l.text = "【角色性格】战术卡偏好（非负；1内为宜）"
		detail.add_child(char_l)
		for k in CHARA_EDIT_CHAR:
			var l3 := Label.new()
			l3.text = "性格.%s" % k
			grid.add_child(l3)
			var e3 := LineEdit.new()
			e3.text = str(edit_row.get(k, ""))
			e3.custom_minimum_size = Vector2(150, 0)
			e3.text_changed.connect(func(t): edit_row[k] = t.replace("#", ""))
			grid.add_child(e3)
		## 【重写 20261020（作者批复）】角色弹幕配置=角色侧数据：
		## Characters.csv 的 main_evs/sub_evs/rest_evs（分号分隔事件名列表）。
		## "为弹幕分配角色"（事件 owner 标记）的旧逻辑已全部废除。
		var dl := Label.new()
		dl.text = "【角色弹幕配置（本角色各火力点挂载的弹幕列表；保存角色数据后生效）】"
		detail.add_child(dl)
		for slot in ["main", "sub", "rest"]:
			var col: String = {"main": "main_evs", "sub": "sub_evs", "rest": "rest_evs"}[slot]
			var evs_list: PackedStringArray = String(edit_row.get(col, "")).split(";", false)
			var sl := Label.new()
			sl.text = "  %s 槽（%d 项）" % [slot, evs_list.size()]
			detail.add_child(sl)
			for ev_name in evs_list:
				var nm0 := ev_name.strip_edges()
				if nm0 == "":
					continue
				var row := HBoxContainer.new()
				detail.add_child(row)
				var found_ev: DanmakuEventData = null
				for e5 in events:
					if e5.event_name == nm0:
						found_ev = e5
						break
				var nm := Label.new()
				nm.text = "    ▸ %s [%s]%s" % [nm0, found_ev.tag if found_ev != null else "?",
					"" if found_ev != null else "（未找到——名字拼错或未导入）"]
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(nm)
				var rm := Button.new()
				rm.text = "移除"
				rm.pressed.connect(func():
					var cur: PackedStringArray = String(edit_row.get(col, "")).split(";", false)
					cur.erase(nm0)
					edit_row[col] = ";".join(cur)
					if CharaDB.save_row(cname, edit_row): ## 【批复 20261020】变动即时落盘
						_set_status("已从 %s 槽移除 %s 并写入 Characters.csv" % [slot, nm0])
					else:
						_set_status("写盘失败：%s" % cname)
					_chara_render.call())
				row.add_child(rm)
			var add := HBoxContainer.new()
			detail.add_child(add)
			var ev_o := OptionButton.new()
			for ev in events:
				ev_o.add_item(ev.event_name)
				ev_o.set_item_metadata(ev_o.item_count - 1, ev.event_name)
			if ev_o.item_count > 0:
				ev_o.select(0)
			add.add_child(ev_o)
			var addb := Button.new()
			addb.text = "挂载到该槽"
			addb.pressed.connect(func():
				if ev_o.selected >= 0:
					var nm2: String = str(ev_o.get_item_metadata(ev_o.selected))
					var cur2: PackedStringArray = String(edit_row.get(col, "")).split(";", false)
					if nm2 != "" and not cur2.has(nm2):
						cur2.append(nm2)
						edit_row[col] = ";".join(cur2)
						if CharaDB.save_row(cname, edit_row): ## 【批复 20261020】变动即时落盘
							_set_status("已挂载 %s → %s 槽并写入 Characters.csv" % [nm2, slot])
						else:
							_set_status("写盘失败：%s" % cname)
						_chara_render.call())
			add.add_child(addb)
		## 【0.0.9·角色贴图（作者 20261110 补欠账）】Players/Battle/Chars/<名>.PNG
		## 导入（复制入工程）/清除（改名 .bak 可恢复）/预览（图集显首帧+帧数信息）
		var tex_l := Label.new()
		tex_l.text = "【角色贴图】res://Players/Battle/Chars/<名>.PNG（横/竖条带图集自动切帧，循环播放）"
		detail.add_child(tex_l)
		var trow := HBoxContainer.new()
		detail.add_child(trow)
		var prev_box := VBoxContainer.new()
		trow.add_child(prev_box)
		var prev := TextureRect.new()
		prev.custom_minimum_size = Vector2(128, 128)
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		prev.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		prev_box.add_child(prev)
		var tinfo := Label.new()
		tinfo.add_theme_font_size_override("font_size", 11)
		prev_box.add_child(tinfo)
		var tbtns := VBoxContainer.new()
		trow.add_child(tbtns)
		var imp_dlg := FileDialog.new()
		imp_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		imp_dlg.access = FileDialog.ACCESS_FILESYSTEM
		imp_dlg.filters = ["*.png ; PNG 贴图", "*.PNG ; PNG 贴图"]
		imp_dlg.title = "选择角色贴图 PNG（导入=复制进工程）"
		var _apply_tex := func():
			var ct: Dictionary = CharaTex.get_chara(cname, str(edit_row.get("NameZH", "")))
			if ct.is_empty():
				prev.texture = null
				tinfo.text = "未设置（对战内用前向刻线）"
			else:
				var tx: Texture2D = ct["tex"]
				if int(ct["frames"]) > 1:
					var at := AtlasTexture.new()
					at.atlas = tx
					at.region = CharaTex.frame_region(ct, 0)
					prev.texture = at
				else:
					prev.texture = tx
				tinfo.text = "%s　%d×%d（%d 帧）" % [tx.resource_path.get_file(),
					tx.get_width(), tx.get_height(), int(ct["frames"])]
		imp_dlg.file_selected.connect(func(fp: String):
			var dst := ProjectSettings.globalize_path("res://Players/Battle/Chars/%s.PNG" % cname)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Players/Battle/Chars"))
			var err := DirAccess.copy_absolute(fp, dst)
			if err == OK:
				CharaTex.invalidate(cname, str(edit_row.get("NameZH", "")))
				_set_status("贴图已导入：%s.PNG" % cname)
			else:
				_set_status("贴图导入失败 err=%d" % err)
			_apply_tex.call()
			_chara_render.call())
		tbtns.add_child(imp_dlg)
		var imp_b := Button.new()
		imp_b.text = "导入 PNG（复制到 Chars/<名>.PNG）"
		imp_b.pressed.connect(func(): imp_dlg.popup_centered(Vector2i(720, 480)))
		tbtns.add_child(imp_b)
		var clr_b := Button.new()
		clr_b.text = "清除贴图（改名 .bak 可恢复）"
		clr_b.pressed.connect(func():
			var dst := ProjectSettings.globalize_path("res://Players/Battle/Chars/%s.PNG" % cname)
			if FileAccess.file_exists(dst):
				DirAccess.rename_absolute(dst, dst + ".bak")
				CharaTex.invalidate(cname, str(edit_row.get("NameZH", "")))
				_set_status("贴图已清除（.bak 保留）")
			else:
				_set_status("该角色本无贴图")
			_apply_tex.call()
			_chara_render.call())
		tbtns.add_child(clr_b)
		_apply_tex.call()
	## 保存行
		var row := HBoxContainer.new()
		detail.add_child(row)
		var save := Button.new()
		save.text = "保存角色数据到 Characters.csv"
		save.pressed.connect(func():
			if CharaDB.save_row(cname, edit_row):
				_set_status("已写回 %s（角色页即时重读生效）" % cname)
			else:
				_set_status("写回失败：%s" % cname))
		row.add_child(save)
	pick.item_selected.connect(func(_i): render.call())
	_chara_render = render ## 供绑定框闭包间接重渲染（lambda 无法自引用）
	if pick.item_count > 0:
		pick.select(0)
		render.call()
	return box

## =============================================================
## 时间轴编辑器（作者批复 2026-10-02）：每个 0.1秒 tick 安排一个或多个
## 弹幕事件；随 .thx 保存为 danmaku/<名>.gd（格式见 TimelineData）。
## 运行时释放（能力/符卡）属②期接线。
## =============================================================
var _tl_list: ItemList
var _tl_detail: VBoxContainer
var _tl_selected := -1

func _build_timeline_page() -> Control:
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## 左：时间轴列表
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	split.add_child(left)
	_tl_list = ItemList.new()
	_tl_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tl_list.item_selected.connect(func(i): _tl_selected = i; _refresh_tl_detail())
	left.add_child(_tl_list)
	var lbtns := HBoxContainer.new()
	left.add_child(lbtns)
	for t in ["新建", "删除"]:
		var b := Button.new()
		b.text = t
		b.pressed.connect(_on_tl_btn.bind(t))
		lbtns.add_child(b)
	## 右：详情
	_tl_detail = VBoxContainer.new()
	_tl_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_tl_detail)
	_refresh_tl_list()
	return split

func _refresh_tl_list() -> void:
	if GameGlobals.editor_timelines.is_empty():
		GameGlobals.editor_timelines.append(TimelineData.new()) ## 默认示例
	_tl_list.clear()
	for tl in GameGlobals.editor_timelines:
		_tl_list.add_item("%s [%s·%s] %d帧" % [tl.tl_name, tl.owner, tl.slot, tl.ticks.size()])
	if _tl_selected < 0 or _tl_selected >= GameGlobals.editor_timelines.size():
		_tl_selected = 0
	_tl_list.select(_tl_selected)
	_refresh_tl_detail()

func _on_tl_btn(t: String) -> void:
	match t:
		"新建":
			var tl := TimelineData.new()
			tl.tl_name = "timeline_%d" % (GameGlobals.editor_timelines.size() + 1)
			GameGlobals.editor_timelines.append(tl)
			_tl_selected = GameGlobals.editor_timelines.size() - 1
			_refresh_tl_list()
		"删除":
			if _tl_selected >= 0:
				GameGlobals.editor_timelines.remove_at(_tl_selected)
				_tl_selected = -1
				_refresh_tl_list()

var _tl_sel_tick := -1 ## 当前选中的帧格（Flash 式横向帧条）

func _refresh_tl_detail() -> void:
	for c in _tl_detail.get_children():
		c.queue_free()
	if _tl_selected < 0 or _tl_selected >= GameGlobals.editor_timelines.size():
		return
	var tl: TimelineData = GameGlobals.editor_timelines[_tl_selected]
	## 元数据行
	var meta := HBoxContainer.new()
	_tl_detail.add_child(meta)
	var name_e := LineEdit.new()
	name_e.text = tl.tl_name
	name_e.custom_minimum_size = Vector2(160, 0)
	name_e.text_changed.connect(func(t): tl.tl_name = t.replace("#", ""))
	meta.add_child(name_e)
	var owner_e := LineEdit.new()
	owner_e.text = tl.owner
	owner_e.custom_minimum_size = Vector2(110, 0)
	owner_e.text_changed.connect(func(t): tl.owner = t.replace("#", ""))
	meta.add_child(owner_e)
	var slot_o := OptionButton.new()
	for sl in ["skill", "spell"]:
		slot_o.add_item(sl)
	slot_o.select(0 if tl.slot == "skill" else 1)
	slot_o.item_selected.connect(func(i): tl.slot = "skill" if i == 0 else "spell")
	meta.add_child(slot_o)
	var len_s := SpinBox.new()
	len_s.min_value = 10
	len_s.max_value = 600
	len_s.value = tl.length_ticks
	len_s.prefix = "总帧(0.1s) "
	len_s.value_changed.connect(func(v):
		tl.length_ticks = int(v)
		_refresh_tl_detail())
	meta.add_child(len_s)
	## 【Flash 式帧格条】横向滚动；每格=0.1秒，格内数字=该帧安排的事件数
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.custom_minimum_size = Vector2(0, 84)
	_tl_detail.add_child(scroll)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	scroll.add_child(strip)
	var group := ButtonGroup.new()
	for tick in tl.length_ticks:
		var cell := Button.new()
		cell.toggle_mode = true
		cell.button_group = group
		cell.custom_minimum_size = Vector2(44, 64)
		var cnt: int = tl.ticks.get(tick, PackedStringArray()).size()
		cell.text = ("%d\n·%d" % [tick % 10, cnt]) if cnt > 0 else str(tick % 10)
		cell.tooltip_text = "第 %d tick（%.1f秒）：%s" % [tick, tick / 10.0,
			"、".join(tl.ticks.get(tick, PackedStringArray())) if cnt > 0 else "（空）"]
		cell.button_pressed = (tick == _tl_sel_tick)
		cell.pressed.connect(func():
			_tl_sel_tick = tick
			_refresh_tl_detail())
		strip.add_child(cell)
	## 选中帧编辑器
	var edit := VBoxContainer.new()
	_tl_detail.add_child(edit)
	if _tl_sel_tick < 0 or _tl_sel_tick >= tl.length_ticks:
		var tip := Label.new()
		tip.text = "点击上方帧格选中一个 0.1秒 帧，然后安排弹幕事件（可多个）。"
		edit.add_child(tip)
		return
	var sel_l := Label.new()
	sel_l.text = "第 %d 帧（%.1f秒）安排：" % [_tl_sel_tick, _tl_sel_tick / 10.0]
	edit.add_child(sel_l)
	for ev_name in tl.ticks.get(_tl_sel_tick, PackedStringArray()):
		var row := HBoxContainer.new()
		edit.add_child(row)
		var l := Label.new()
		l.text = "  ▸ " + ev_name
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var del := Button.new()
		del.text = "移除"
		del.pressed.connect(func():
			var arr: PackedStringArray = tl.ticks.get(_tl_sel_tick, PackedStringArray())
			arr.erase(ev_name)
			tl.set_events(_tl_sel_tick, arr)
			_refresh_tl_detail())
		row.add_child(del)
	var add := HBoxContainer.new()
	edit.add_child(add)
	var ev_o := OptionButton.new()
	for ev in events:
		ev_o.add_item(ev.event_name)
		ev_o.set_item_metadata(ev_o.item_count - 1, ev.event_name)
	add.add_child(ev_o)
	var addb := Button.new()
	addb.text = "安排到该帧"
	addb.pressed.connect(func():
		if ev_o.selected >= 0:
			tl.add_event(_tl_sel_tick, String(ev_o.get_item_metadata(ev_o.selected)))
			_refresh_tl_detail())
	add.add_child(addb)
	var clear_b := Button.new()
	clear_b.text = "清空该帧"
	clear_b.pressed.connect(func():
		tl.set_events(_tl_sel_tick, PackedStringArray())
		_refresh_tl_detail())
	add.add_child(clear_b)
	var tip2 := Label.new()
	tip2.text = "保存 .thx 时写入 danmaku/%s.gd（每0.1秒一帧→多事件；结构与弹幕事件行不同）。运行时释放属②期接线。" % tl.tl_name
	_tl_detail.add_child(tip2)

## =============================================================
## 弹幕显示浮窗（作者批复 2026-10-03 终版定义）：
##   独立浮窗（OS Window）里跑迷你舞台（与战场同款 HS 材质/轨道/激光渲染），
##   玩家在该浮窗内按 Z 让角色发射当前选中的单个弹幕事件，Esc 关闭浮窗。
## =============================================================
var _preview_window: Window = null
var _chara_render := Callable() ## 角色页重渲染（绑定框增删后调用；解决 lambda 自引用）
var _priv_render := Callable() ## 杂兵页重渲染（lambda 自引用方案）

func _open_preview_window() -> void:
	_collect_form()
	var ev := events[selected_idx] if selected_idx >= 0 and selected_idx < events.size() else null
	if ev == null:
		_set_status("弹幕显示浮窗：请先在左侧选择一个弹幕事件")
		return
	var errs := ev.compile()
	if not errs.is_empty():
		_set_status("弹幕显示浮窗：表达式有错，先做可行性检查——%s" % errs[0])
		return
	## 【作者批复 2026-10-03】浮窗不存在时呼出；已存在时只覆盖被显示的弹幕
	## （旧实现 queue_free+重建 → 二次点击崩溃）
	if _preview_window != null and is_instance_valid(_preview_window):
		var st := _preview_window.get_child(0) if _preview_window.get_child_count() > 0 else null
		if st != null and st.has_method("set_event"):
			st.set_event(ev)
			_preview_window.title = "弹幕显示 — %s（Z=发射  Esc=关闭）" % ev.event_name
			_set_status("浮窗已覆盖为 %s，按 Z 发射" % ev.event_name)
			return
	_preview_window = Window.new()
	_preview_window.title = "弹幕显示 — %s（Z=发射  Esc=关闭）" % ev.event_name
	_preview_window.size = Vector2i(460, 560)
	var stage: Node2D = (load("res://scripts/ui/danmaku_preview_stage.gd") as GDScript).new()
	stage.ev = ev
	_preview_window.add_child(stage)
	_preview_window.close_requested.connect(func(): _preview_window.queue_free())
	get_tree().root.add_child(_preview_window)
	_preview_window.show()
	_set_status("弹幕显示浮窗已打开：在浮窗内按 Z 发射 %s（可反复按，Esc 关闭）" % ev.event_name)
	## 【批复 2026-10-02】[Z] 的定义已改为"试炼场中让角色发射该弹幕"
	## （battle_arena 预览模式 KEY_Z），本浮窗只是参数速览，不再绑定 Z。
