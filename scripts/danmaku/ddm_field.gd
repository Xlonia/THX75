class_name DdmField
extends RefCounted
## =============================================================
## 【批复 2026-10-01#7】本文件代码已整体注释保留——曾经存在过、为何存在过：
##
## DdmField 是【0期】的 CPU 伤害弹幕图（DDM）实现，0期的被弹结算核心：
##   每弹每帧做 CPU 像素印章（写入 πr² 个像素）+ 包围盒擦除 + master 合成图
##   懒重建，实体被弹时逐像素探测"白点上升沿"。
## 为何被废弃：作者实测百弹即严重卡顿（TECH_SPEC 0期记录），批复一#14 明示
##   "取消CPU像素印章！弹幕=渲染至弹幕图+屏幕的粒子"——①期性能改造后由
##   BulletHash（空间哈希被弹，矢量圆碰撞）+ DdmGpu（compute shader 弹幕图）
##   取代。运行时已无任何调用（battle_arena.bullet_field() 仅返回 null 兼容）。
## 为何注释保留而非删除：
##   ① 保留0期语义注释（DDM 键=伤害|模式、上升沿结算、部位优先级）——策划
##     文档的权威代码化翻译，③期热力图族的 CPU 参考实现可从这里找思路；
##   ② 批复要求"注释掉这段旧代码，旁边注释存在过、为何存在过"。
##   解除注释即可恢复（API 与 0 期一致；注意 stamp/erase 为每弹 O(πr²) 高开销）。
## =============================================================

#const W := 400
#const H := 400
#const N := W * H
#
### 一方的全部 DDM：键 "dmg|mode" -> PackedByteArray(0/1)
#var maps: Dictionary = {}
### 合成弹幕图（所有 DDM 求或；调试显示/AI 用），每次 rebuild_master 懒更新
#var master := PackedByteArray()
#var master_dirty := true
#
#func _init() -> void:
#	master.resize(N)
#	master.fill(0)
#
### 取（或按需创建）某伤害/模式的 DDM
#func get_map(dmg: int, mode: String) -> PackedByteArray:
#	var key := "%d|%s" % [dmg, mode]
#	if not maps.has(key):
#		var a := PackedByteArray()
#		a.resize(N)
#		a.fill(0)
#		maps[key] = a
#	return maps[key]
#
#func has_map(dmg: int, mode: String) -> bool:
#	return maps.has("%d|%s" % [dmg, mode])
#
### —— 印章式注册：写圆（val=1 盖白 / val=0 擦除）——
### 返回被写入的包围盒 [x0,y0,x1,y1]（供下一帧增量擦除）
#func stamp_circle(buf: PackedByteArray, cx: float, cy: float, r: float, val: int) -> Array:
#	var x0 := maxi(0, int(floor(cx - r)))
#	var y0 := maxi(0, int(floor(cy - r)))
#	var x1 := mini(W - 1, int(ceil(cx + r)))
#	var y1 := mini(H - 1, int(ceil(cy + r)))
#	var r2 := r * r
#	for y in range(y0, y1 + 1):
#		var dy := float(y) + 0.5 - cy
#		var row := y * W
#		for x in range(x0, x1 + 1):
#			var dx := float(x) + 0.5 - cx
#			if dx * dx + dy * dy <= r2:
#				buf[row + x] = val
#	if val != 0:
#		master_dirty = true
#	return [x0, y0, x1, y1]
#
### 增量擦除上一帧包围盒（矩形清除即可——重叠白点由其他子弹的重盖保证）
#func erase_bbox(buf: PackedByteArray, bbox: Array) -> void:
#	if bbox.is_empty():
#		return
#	for y in range(bbox[1], bbox[3] + 1):
#		var row := y * W
#		for x in range(bbox[0], bbox[2] + 1):
#			buf[row + x] = 0
#	master_dirty = true
#
### —— 判定区域接触检测 ——
### 实体判定圆(cx,cy,r) 内是否有白点；返回 [是否接触, 命中白点的角度集合]
### 角度用于部位判定（上120°武器 / 下120°机动 / 左右60°僚机）
#func probe_disc(buf: PackedByteArray, cx: float, cy: float, r: float) -> Array:
#	var touched := false
#	var angles: Array[float] = []
#	var x0 := maxi(0, int(floor(cx - r)))
#	var y0 := maxi(0, int(floor(cy - r)))
#	var x1 := mini(W - 1, int(ceil(cx + r)))
#	var y1 := mini(H - 1, int(ceil(cy + r)))
#	var r2 := r * r
#	for y in range(y0, y1 + 1):
#		var dy := float(y) + 0.5 - cy
#		var row := y * W
#		for x in range(x0, x1 + 1):
#			var dx := float(x) + 0.5 - cx
#			if dx * dx + dy * dy <= r2 and buf[row + x] != 0:
#				touched = true
#				## 命中白点相对实体中心的角度（atan2：x右 y下；正上方=-90°）
#				angles.append(atan2(dy, dx))
#	return [touched, angles]
#
### 点接触检测（点向类 can_destroy 用：被物弹和敌方弹幕摧毁）
#func probe_disc_any(cx: float, cy: float, r: float) -> bool:
#	for key in maps:
#		var buf: PackedByteArray = maps[key]
#		if probe_disc(buf, cx, cy, r)[0]:
#			return true
#	return false
#
### 合成弹幕图（所有 DDM 求或；懒重建）
#func rebuild_master() -> void:
#	if not master_dirty:
#		return
#	master.fill(0)
#	for key in maps:
#		var buf: PackedByteArray = maps[key]
#		for i in N:
#			if buf[i] != 0:
#				master[i] = 1
#	master_dirty = false
#
### 调试渲染：弹幕图 -> Image(L8)
#func master_image() -> Image:
#	rebuild_master()
#	var img := Image.create(W, H, false, Image.FORMAT_L8)
#	img.set_data(W, H, false, Image.FORMAT_L8, master)
#	return img
#
### 全部图按伤害降序的键列表（被弹检测"优先检验最高伤害"用）
#func sorted_damage_keys() -> Array:
#	var keys := maps.keys()
#	## 排除非法伤害（≤0：假弹幕/预警期，它们不参与被弹结算）
#	var valid: Array = []
#	for k in keys:
#		if int(String(k).split("|")[0]) > 0:
#			valid.append(k)
#	valid.sort_custom(func(a, b):
#		return int(String(a).split("|")[0]) > int(String(b).split("|")[0]))
#	return valid
#
#func clear_all() -> void:
#	maps.clear()
#	master.fill(0)
#	master_dirty = false
