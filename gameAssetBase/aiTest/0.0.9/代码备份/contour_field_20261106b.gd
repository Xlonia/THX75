class_name ContourField
extends RefCounted
## =============================================================
## 等高线绘制（0.0.9·策划新三 1106 修订版）
##   Hd（总结期望云）/ Hr（快速弹幕警告云）=将 Ht/Hv 的热度按半径2像素
##   高斯模糊描绘等高线→抽象为多个多边形构成的分层设色图；
##   每层 16 热度共 16 层；采样帧率 10；记忆前 0.4 秒共五张；
##   每个多边形按五张的运动与形变数据，返回耦合的未来 5 秒内每秒的
##   设色图期望五张（外推=AI 批次）——两张图都是角色 AI 选择行为卡的
##   高权重热力图，设色图期望帧率 10。
## 【管线】fam front 纹理 → contour_down.glsl（8px 下采样）→ 2500B 回读 →
##   CPU 多层 marching squares（单遍 15 层：16..240 每 16 一层）→ 段→
##   折线链接（闭环标记）→ 等弧长重采样（8px）→ 动画环。
## 【Hr 源】0.0.9 起 Hr=Hv 半径2高斯派生（hv_derive.glsl，策划对齐）——
##   本类直采 fam Hr 纹理，不再做预模糊。
## 【20fps 与源 10Hz】tick 按调用方 60fps 节奏门控为 20fps；源图 10Hz
##   刷新，flip 序号未变则跳过提取（复用最新帧）——实际提取频率=源频率。
## =============================================================

const GRID := 50            ## 8px 块 × 50 = 400
const CELL := 8.0
## 【策划新三 1106 修订版】采样帧率 10、记忆 5 张（前 0.4 秒共五张）；
## 每 16 热度一层共 16 层；每个多边形按前 0.4 秒五张的运动与形变数据，
## 返回耦合的未来 5 秒内每秒的设色图期望五张（外推算法=AI 批次实现，
## query() 返回记忆帧，future() 接口预留）。
const HIST := 5             ## 前 0.4 秒共五张（10fps 采样）
const LEVEL_STEP := 16.0    ## 每 16 热度一层（策划）
const N_LEVELS := 15        ## 层值 16..240（R8 封顶 255，240-256 层并入）
## 提取对象（fam NAMES 序：He0 He1 Hd0 Hd1 Hr0 Hr1 Hp0 Hp1）
const MAPS := ["Hd0", "Hd1", "Hr0", "Hr1"]
## 【0.0.9·Hr 改 Hv 派生】Hr0/Hr1 由 hv_derive 半径2高斯产出——直采不再预模糊
const PRE_BLUR := [0.0, 0.0, 0.0, 0.0]
## 【0.0.9·作者裁定 20261105】等高线=AI 用抽象层（调试时不显示——切换 Hd 卡顿
## 根因=提取 spike）；AI 未接入前提取=纯成本。默认停用，AI 批次置 true 启用。
var enabled := false

## marching squares 案表（corner a=左上 b=右上 c=右下 d=左下；
## 边 0=顶 a-b 1=右 b-c 2=底 d-c 3=左 a-d；鞍点 5/10 取固定取向）
const MS_TAB := [
	[],           # 0
	[3, 0],       # 1  a
	[0, 1],       # 2  b
	[3, 1],       # 3  ab
	[1, 2],       # 4  c
	[3, 0, 1, 2], # 5  ac 鞍点
	[0, 2],       # 6  bc
	[3, 2],       # 7  abc
	[2, 3],       # 8  d
	[0, 2],       # 9  ad
	[0, 1, 2, 3], # 10 bd 鞍点
	[1, 2],       # 11 abd
	[1, 3],       # 12 cd
	[0, 1],       # 13 acd
	[3, 0],       # 14 bcd
	[],           # 15
]

var ok := false
var extract_us := 0.0 ## 提取耗时（μs 指数滑动；性能归因用）
var _rd: RenderingDevice = null
var _fam: FamilyMaps = null
var _shader_rid: RID = RID()
var _pipe: RID = RID()
var _dst_tex: Dictionary = {}   ## map -> RID（50×50 R8）
var _sets: Dictionary = {}      ## map -> [set(front0), set(front1)]（src 按 fam front 槽预建）
var _ubos: Dictionary = {}      ## map -> RID（Params pre_blur）
var _hist: Dictionary = {}      ## map -> Array[{frame:int, levels:Array[Array[{pts,closed}]]}]（levels 序=层 1..15）
var _last_flip: Dictionary = {} ## map -> 上次提取的 flip 序号
var _tick_acc := 0

func _init(rd: RenderingDevice, fam: FamilyMaps) -> void:
	_rd = rd
	_fam = fam
	if _rd == null or _fam == null or not _fam.ok:
		return
	var sh: RDShaderFile = load("res://shaders/contour_down.glsl")
	if sh == null:
		push_warning("[ContourField] 着色器加载失败")
		return
	_shader_rid = _rd.shader_create_from_spirv(sh.get_spirv(), "contour_down")
	if not _shader_rid.is_valid():
		push_warning("[ContourField] SPIRV 无效")
		return
	_pipe = _rd.compute_pipeline_create(_shader_rid)
	if not _pipe.is_valid():
		push_warning("[ContourField] 管线创建失败")
		return
	var fmt := RDTextureFormat.new()
	fmt.width = GRID
	fmt.height = GRID
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var zero := PackedByteArray()
	zero.resize(GRID * GRID)
	for mi in MAPS.size():
		var map: String = MAPS[mi]
		var tex := _rd.texture_create(fmt, RDTextureView.new(), [zero])
		if not tex.is_valid():
			push_warning("[ContourField] 纹理创建失败")
			return
		_dst_tex[map] = tex
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER ## GLSL uniform 块=UBO（StorageBuffer 类型不匹配=dispatch 静默丢弃）
		u.binding = 2
		var ubo := _rd.uniform_buffer_create(16)
		var parr := PackedFloat32Array([PRE_BLUR[mi], 0.0, 0.0, 0.0])
		_rd.buffer_update(ubo, 0, 16, parr.to_byte_array())
		u.add_id(ubo)
		_ubos[map] = ubo
		## src 绑定 fam 双槽各预建一套（front 翻面无需重建）
		var per_front: Array = []
		for fi in 2:
			var u_src := RDUniform.new()
			u_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			u_src.binding = 0
			u_src.add_id(_fam._tex[_fam.NAMES.find(map)][fi])
			var u_dst := RDUniform.new()
			u_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			u_dst.binding = 1
			u_dst.add_id(tex)
			per_front.append(_rd.uniform_set_create([u_src, u_dst, u], _shader_rid, 0))
		_sets[map] = per_front
		_hist[map] = []
		_last_flip[map] = -1
	ok = true

## 记忆环查询（新三 1106：前 0.4 秒共五张，back=0 最新）。
## 【AI 批次接口】在 5 张记忆之上做运动/形变耦合外推（未来 5 秒内每秒
## 一张设色图期望，共五张，帧率 10）——future() 届时实现。
func query(map: String, back: int = 0) -> Dictionary:
	var h: Array = _hist.get(map, [])
	if h.is_empty():
		return {}
	return h[maxi(0, h.size() - 1 - back)]

func hist_len(map: String) -> int:
	return (_hist.get(map, []) as Array).size()

## tick：调用方每帧调（观察图激活时）；内部 20fps 门控+flip 去重。
## 返回最新帧 {frame, levels}（无数据={}）
func tick(map: String, frame_no: int) -> Dictionary:
	if not ok or not enabled or not _hist.has(map): ## 【作者裁定】AI 接入前停提取
		return {}
	_tick_acc += 1
	if _tick_acc % 6 != 0: ## 10fps 门控（60/6——策划 1106 修订：采样帧率10）
		return _latest(map)
	var fl: int = _fam.flip_of(map)
	if _last_flip.get(map, -1) == fl: ## 源未翻面（10Hz 源）——不重复提取
		return _latest(map)
	_last_flip[map] = fl
	_extract_map(map, frame_no)
	return _latest(map)

func _latest(map: String) -> Dictionary:
	var h: Array = _hist.get(map, [])
	if not h.is_empty():
		return h[h.size() - 1]
	return {}

func _extract_map(map: String, frame_no: int) -> void:
	var t0 := Time.get_ticks_usec()
	var mi: int = MAPS.find(map)
	var fi: int = _fam.NAMES.find(map)
	var set_rid: RID = _sets[map][_fam._front[fi]]
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipe)
	_rd.compute_list_bind_uniform_set(cl, set_rid, 0)
	_rd.compute_list_dispatch(cl, 7, 7, 1) ## 56×56 threads（guard ≥50）
	_rd.compute_list_end()
	var data := _rd.texture_get_data(_dst_tex[map], 0)
	if data.size() < GRID * GRID:
		return
	var corners := PackedFloat32Array()
	corners.resize(GRID * GRID)
	for i in GRID * GRID:
		corners[i] = float(data[i])
	var levels := _extract_polys(corners)
	var h: Array = _hist[map]
	h.append({"frame": frame_no, "levels": levels})
	if h.size() > HIST:
		h.pop_front() ## 策划 1106：记忆前 0.4 秒共五张
	extract_us = extract_us * 0.9 + float(Time.get_ticks_usec() - t0) * 0.1

## —— 多层 marching squares（纯逻辑，可单测）——
## 输入 50×50 角点（8px 块中心，场坐标 (x*8+4, y*8+4)）；
## 输出 Array[15]：每层 Array[{pts: PackedVector2Array, closed: bool}]
static func _extract_polys(c: PackedFloat32Array) -> Array:
	var seg_lists := []
	for l in N_LEVELS + 1:
		seg_lists.append([]) ## 0 号弃用（层值=序号×16）
	for y in GRID - 1:
		var row0: int = y * GRID
		var row1: int = (y + 1) * GRID
		for x in GRID - 1:
			var va: float = c[row0 + x]
			var vb: float = c[row0 + x + 1]
			var vd: float = c[row1 + x]
			var vc: float = c[row1 + x + 1]
			var mn: float = min(minf(va, vb), minf(vc, vd))
			if mn >= 240.0:
				continue ## 全格高于最高层——无等值线
			var mx: float = max(maxf(va, vb), maxf(vc, vd))
			if mx < LEVEL_STEP:
				continue ## 全格空——快路径
			var l0: int = maxi(1, int(ceil(mn / LEVEL_STEP)))
			var l1: int = mini(N_LEVELS, int(floor(mx / LEVEL_STEP)))
			var cx: float = x * CELL + 4.0
			var cy: float = y * CELL + 4.0
			for li in range(l0, l1 + 1):
				var lv: float = li * LEVEL_STEP
				var idx := 0
				if va >= lv: idx += 1
				if vb >= lv: idx += 2
				if vc >= lv: idx += 4
				if vd >= lv: idx += 8
				var tab: Array = MS_TAB[idx]
				if tab.is_empty():
					continue
				var sl: Array = seg_lists[li]
				var i2 := 0
				while i2 < tab.size():
					sl.append([_edge_pt(tab[i2], lv, va, vb, vc, vd, cx, cy),
						_edge_pt(tab[i2 + 1], lv, va, vb, vc, vd, cx, cy)])
					i2 += 2
	var out := []
	for li in range(1, N_LEVELS + 1):
		out.append(_chain(seg_lists[li]))
	return out

## 边插值点（e0 顶 a-b / e1 右 b-c / e2 底 d-c / e3 左 a-d）
static func _edge_pt(e: int, lv: float, va: float, vb: float, vc: float, vd: float,
		cx: float, cy: float) -> Vector2:
	var t := 0.5
	if e == 0:
		if vb != va: t = (lv - va) / (vb - va)
		return Vector2(cx + t * CELL, cy)
	elif e == 1:
		if vc != vb: t = (lv - vb) / (vc - vb)
		return Vector2(cx + CELL, cy + t * CELL)
	elif e == 2:
		if vc != vd: t = (lv - vd) / (vc - vd)
		return Vector2(cx + t * CELL, cy + CELL)
	else:
		if vd != va: t = (lv - va) / (vd - va)
		return Vector2(cx, cy + t * CELL)

static func _pkey(p: Vector2) -> int:
	## 端点匹配键（量化 0.5px；400×2=800 < 16384）
	return int(roundf(p.x * 2.0)) * 16384 + int(roundf(p.y * 2.0))

## 段→折线链接（端点哈希双向延伸；闭环标记）
static func _chain(segs: Array) -> Array:
	var polys: Array = []
	if segs.is_empty():
		return polys
	var used := {}
	var end_map := {} ## key -> Array[[seg_i, end_j]]
	for si in segs.size():
		var s: Array = segs[si]
		for j in 2:
			var k: int = _pkey(s[j])
			if not end_map.has(k):
				end_map[k] = []
			end_map[k].append([si, j])
	for si in segs.size():
		if used.has(si):
			continue
		used[si] = true
		var s0: Array = segs[si]
		var pts := PackedVector2Array([s0[0], s0[1]])
		var head_k: int = _pkey(s0[0])
		var tail_k: int = _pkey(s0[1])
		var closed: bool = head_k == tail_k
		var guard := 0
		## 尾端延伸
		while not closed and guard < 4096:
			guard += 1
			var nxt: Array = end_map.get(tail_k, [])
			var found := false
			for cand in nxt:
				var ci: int = int(cand[0])
				if used.has(ci):
					continue
				var cs: Array = segs[ci]
				var other: Vector2
				if int(cand[1]) == 1:
					other = cs[0]
				else:
					other = cs[1]
				used[ci] = true
				pts.append(other)
				tail_k = _pkey(other)
				if tail_k == head_k:
					closed = true ## 闭环（回到起点）
				found = true
				break
			if not found:
				break
		## 首端延伸（非闭环时补链）
		if not closed:
			guard = 0
			while guard < 4096:
				guard += 1
				var prv: Array = end_map.get(head_k, [])
				var found2 := false
				for cand2 in prv:
					var ci2: int = int(cand2[0])
					if used.has(ci2):
						continue
					var cs2: Array = segs[ci2]
					var other2: Vector2
					if int(cand2[1]) == 0:
						other2 = cs2[1]
					else:
						other2 = cs2[0]
					used[ci2] = true
					pts.insert(0, other2)
					head_k = _pkey(other2)
					found2 = true
					break
				if not found2:
					break
			closed = head_k == tail_k ## 首尾延伸后可能相接
		if pts.size() >= 2:
			## 【每条边长8像素（策划字面）】链接后等弧长重采样 step=8px——
			## 输出绘制折线恒为 8px 步长（尾段=余量 ≤8px）
			polys.append({"pts": _resample(pts, closed, CELL), "closed": closed})
	return polys

## 等弧长重采样：沿折线每 step 像素取一点（尾段=余量 ≤step；闭环回起点）
static func _resample(pts: PackedVector2Array, closed: bool, step: float) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var seq := pts
	if closed:
		seq = pts.duplicate()
		seq.append(pts[0]) ## 闭合段：末点→首点补一段
	var out := PackedVector2Array([seq[0]])
	var acc := 0.0
	var next_mark := step
	for i in range(1, seq.size()):
		var a: Vector2 = seq[i - 1]
		var b: Vector2 = seq[i]
		var seg_len := a.distance_to(b)
		if seg_len <= 0.0001:
			continue
		while next_mark <= acc + seg_len + 0.0001:
			var t: float = (next_mark - acc) / seg_len
			out.append(a + (b - a) * t)
			next_mark += step
		acc += seg_len
	return out

## 会话资源释放（战场 PREDELETE）
func shutdown() -> void:
	if _rd == null:
		return
	for map in _sets:
		for set_rid in _sets[map]:
			if set_rid.is_valid():
				_rd.free_rid(set_rid)
	for map2 in _dst_tex:
		if _dst_tex[map2].is_valid():
			_rd.free_rid(_dst_tex[map2])
	for ubo in _ubos.values():
		if ubo.is_valid():
			_rd.free_rid(ubo)
	for rid in [_pipe, _shader_rid]:
		if rid.is_valid():
			_rd.free_rid(rid)
	_sets.clear()
	_dst_tex.clear()
	_ubos.clear()
	_hist.clear()
	ok = false
