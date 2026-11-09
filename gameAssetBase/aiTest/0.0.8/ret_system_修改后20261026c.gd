class_name RetSystem
extends RefCounted
## =============================================================
## RET 快速探索树基底（v0.0.8 第一批）
## 【策划·新二 L223-229】RET16x3：48 次遍历（16 方向 × 1d/2d/5d 三环）。
##   RET-C（挑战探索树·默认）：从角色 s 热点图三环 48 个目标中，
##     选「低于当前热力」的方向 → 三环各自聚成 AI 倾向 → 总体倾向最大三点
##     作为 APF 引力点（时空路径规划交给 APF 平滑，本类只出引力点）。
##   RET-SP（最高权力运动路线·0.0.8 后续批）：两步 0.1s 可行性树，
##     Sl=第二步可行方向数（≤256），供符卡/能力申请与 e 态势。
## 【本批范围】共用基底：环几何（带转）、热力读取接口、倾向聚合、
##   引力点输出——RET-C 完整接入 AI；RET-SP 预留接口与 Sl 的
##   简化可行性判定（两点连线 Hcs 阈值），逐步树下一批。
## 【性能】纯 CPU 数值（sit16/Hcs 已是现成数组），48 点 O(1) 查表 +
##   10Hz 调度（战场侧调用），无新增 GPU 回读。
## =============================================================

const RING_RADII := ["1d", "2d", "5d"]   ## 0.1/0.2/0.5 秒距环
## 环基础半径（与态势十六点同口径：normal_speed×6/12/30）
const RING_DIST := [6.0, 12.0, 30.0]

var entity: BattleEntity
var spin := 0.0        ## 带转（偶帧0/奇帧1/32圈——调用方传入）
var cur_heat := 0.0    ## 当前所在点热力（中心 ht_at）
## 三环引力点输出（世界坐标；空=无可行方向）
var gravity_points: PackedVector2Array = PackedVector2Array()
## 三环各自倾向向量（AI 调试用；指向低热侧）
var ring_tendencies: PackedVector2Array = PackedVector2Array()
## RET-C 时空路径倾向（三环综合，指向总体最优）
var path_tendency := Vector2.ZERO
## 总体倾向最大的三个方向（世界向量，已带带转角度）
var best_dirs: PackedVector2Array = PackedVector2Array()

func _init(e: BattleEntity) -> void:
	entity = e

## =============================================================
## RET-C：48 目标遍历（每环 16 方向）
##   可行=该点热力 < 当前热力（"低于目前热力"——策划原文）；
##   环倾向=可行方向单位向量之和（低热差越大权重越高：Δh 归一）；
##   总体倾向=三环加权和（内环权重高：1d×3 / 2d×2 / 5d×1——近处优先）；
##   引力点=总体倾向最大三方向的环上点（世界坐标，供 APF 规划）。
## =============================================================
func compute_retc() -> void:
	gravity_points = PackedVector2Array()
	ring_tendencies = PackedVector2Array()
	best_dirs = PackedVector2Array()
	path_tendency = Vector2.ZERO
	if entity == null or entity.dead:
		return
	cur_heat = float(entity.get_meta("ht_at", 0))
	var weights := [3.0, 2.0, 1.0] ## 1d/2d/5d 环权重（近环优先）
	var n := entity.normal_speed()
	## 每环：可行方向收集（Δh 权重）
	var feas_per_ring: Array = []      ## [[dir, weight], ...] ×3
	var ri := 0
	for ring in RING_RADII:
		var arr: PackedInt32Array = entity.sit16_1d if ring == "1d" else (
			entity.sit16_2d if ring == "2d" else entity.sit16_5d)
		var feas: Array = []
		var tsum := Vector2.ZERO
		for k in 16:
			if k >= arr.size():
				continue
			var a := spin - PI / 2.0 + TAU * float(k) / 16.0
			var dv := Vector2(cos(a), sin(a))
			var h: float = float(arr[k])
			var dh: float = cur_heat - h ## >0 = 该方向更冷
			if dh > 0.0:
				var w: float = dh / 255.0 ## Δh 归一权重
				feas.append([dv, w])
				tsum += dv * w
		feas_per_ring.append(feas)
		ring_tendencies.append(tsum)
		path_tendency += tsum * weights[ri]
		ri += 1
	## 总体倾向最大三方向：跨环按与 path_tendency 的夹角一致性排序取前三
	if path_tendency != Vector2.ZERO:
		var all: Array = []
		for feas in feas_per_ring:
			for pair in feas:
				var dv2: Vector2 = pair[0]
				var w2: float = pair[1]
				var align: float = dv2.dot(path_tendency.normalized())
				all.append([dv2, align * w2]) ## 一致性×热力差综合
		all.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
		var nsp := spin
		var wall: Dictionary = entity.get_meta("apf_wall_dirs", {})
		for i in all.size():
			if best_dirs.size() >= 3:
				break
			var d3: Vector2 = all[i][0]
			## 【L227】RET-C 不穿 wall：方向落在墙集合（带转角反解 k）内的跳过
			if not wall.is_empty():
				var dk := wrapi(roundi((d3.angle() - (nsp - PI / 2.0)) / (TAU / 16.0)), 0, 16)
				if wall.has(dk):
					continue
			best_dirs.append(d3)
			## 引力点=方向所在环上的点（内环优先：先1d再2d再5d各取最近可行）
			var rr := 0.0
			for rj in 3:
				var arrj: PackedInt32Array = entity.sit16_1d if rj == 0 else (
					entity.sit16_2d if rj == 1 else entity.sit16_5d)
				## 该方向在环 rj 上的热度（带转角反解 k）
				var ak := d3.angle()
				var kk := wrapi(roundi((ak - (nsp - PI / 2.0)) / (TAU / 16.0)), 0, 16)
				if kk < arrj.size() and float(arrj[kk]) < cur_heat:
					rr = RING_DIST[rj] * n
					break
			if rr <= 0.0:
				rr = RING_DIST[0] * n
			gravity_points.append(entity.position + d3 * rr)

## =============================================================
## RET-SP 基底（下一批完整两步树）
##   可行方向：第一步=1d 环 Hcs 阈值（连线不穿白点近似为端点冷）；
##   第二步=假设到达该 1d 点后的 1d 环再判——现用同环数据近似，
##   完整版需"假设位置的重采样"（0.0.8 第二批接入 Hcs 平移采样）。
##   Sl=全部 16 方向的第二步可行数之和（0~256），0 时 e 态势。
## =============================================================
var sl := 256 ## RET-SP 可行方向数（默认满）

func compute_simplified_sl() -> void:
	## 简化可行性：1d 环 Hcs 冷点(<64)且该方向 1d Ht 冷(<96)为第一步可行；
	## 第二步可行=2d 环同角冷——Sl=Σ 每方向两步皆可
	sl = 0
	if entity == null or entity.dead:
		return
	var hcs: PackedFloat32Array = entity.hcs_pts
	for k in 16:
		if k >= entity.sit16_1d.size() or k >= entity.sit16_2d.size():
			continue
		var step1: bool = (hcs[k] < 64.0 if k < hcs.size() else true) and entity.sit16_1d[k] < 96
		if not step1:
			continue
		var step2: bool = (hcs[16 + k] < 64.0 if 16 + k < hcs.size() else true) and entity.sit16_2d[k] < 96
		if step2:
			sl += 16 ## 该方向的第二步 16 分支全可行（完整版逐分支）
	## 兜底：全部不可行时 Sl=0（e 态势由战场侧消费）
