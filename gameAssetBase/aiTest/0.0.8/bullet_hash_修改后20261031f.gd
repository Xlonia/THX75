class_name BulletHash
extends RefCounted
## =============================================================
## 弹幕空间哈希（第①期：被弹解析的 CPU 侧，替代 0 期像素遍历探测）
## 【语义等价于 DDM 上升沿探测】：
##   ① insert：发射/移动后的弹幕按包围盒入格（格子 32px）
##   ② query_keys(entity)：查询判定圆触及的候选弹幕 → 按 (伤害|模式)
##      分组返回 {键: [角度数组]}——等价于“检测该实体判定区域触及哪些伤害弹幕图”
##   ③ 调用方与上一帧键集比对得出上升沿 → 最高伤害优先结算（battle_arena）
## 【成本】每弹 O(1) 插入；每实体查询只遍历附近格子的少量候选。
##   数千弹幕 + 58 实体的队伍战实测达标（见 bench 场景）。
## 复用：每帧 clear() 后重建（弹幕位置全量已知，重建比增量维护更简单可靠）。
## =============================================================

const CELL := 32.0
const GRID := int(400 / CELL) + 1 ## 13×13 格（浮点除后取整，避免整数除法告警）

var _cells: Array = [] ## 每格 Array[Bullet]

func _init() -> void:
	_cells.resize(GRID * GRID)
	for i in _cells.size():
		_cells[i] = []

func clear() -> void:
	for c in _cells:
		c.clear()

## 弹幕入格：按弹幕圆(半径 r)覆盖的所有格子登记
func insert(b: Bullet) -> void:
	var r := b.hit_radius()
	var x0 := _ci(b.pos.x - r)
	var x1 := _ci(b.pos.x + r)
	var y0 := _ci(b.pos.y - r)
	var y1 := _ci(b.pos.y + r)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			if gx < 0 or gy < 0 or gx >= GRID or gy >= GRID:
				continue
			_cells[gy * GRID + gx].append(b)

## 查询：判定圆(cx,cy,r) 触及的弹幕 → 按伤害键分组
## 返回 { "dmg|mode": [命中角...] }（角=弹幕中心相对实体中心方向）
## skip_side：跳过该阵营发射的弹幕（法弹不伤友方；物弹由调用方单独处理）
func query_keys(cx: float, cy: float, r: float, skip_side: int, skip_source: BattleEntity) -> Dictionary:
	var out := {}
	var x0 := _ci(cx - r - 32.0)
	var x1 := _ci(cx + r + 32.0)
	var y0 := _ci(cy - r - 32.0)
	var y1 := _ci(cy + r + 32.0)
	for gy in range(maxi(0, y0), mini(GRID - 1, y1) + 1):
		for gx in range(maxi(0, x0), mini(GRID - 1, x1) + 1):
			for b: Bullet in _cells[gy * GRID + gx]:
				if b.hidden_now or b.source_side == skip_side and not b.ev.is_phy:
					continue ## 法弹不伤发射方；物弹双向（物弹遮罩在 Bullet 内判定）
				if b.source == skip_source and b.ev.is_phy and not b.beyond_mask():
					continue ## 物弹未超出友伤遮罩：不打发射者自己
				if b.overlaps_circle(cx, cy, r):
					## 【R8·20261004】整型复合键（dmg*4+模式序号）——替代逐命中字符串拼接
					var mode_i: int = 0 if b.ev.dmg_mode == "N" else (1 if b.ev.dmg_mode == "I" else 2)
					var key: int = b.hit_damage() * 4 + mode_i
					if not out.has(key):
						out[key] = []
					(out[key] as Array).append((b.pos - Vector2(cx, cy)).angle())
	return out

func _ci(v: float) -> int:
	return int(floor(v / CELL))
