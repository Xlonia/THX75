class_name DanmakuTex
extends RefCounted
## =============================================================
## 弹幕材质解析器 —— 事件参数 texture（材质名）→ Texture2D
## 材质名约定：不带扩展名的文件名（如 tama0、lasermidpx2）
## 解析优先级：
##   ① 编辑器/运行时从 .thx 的 texture/ 导入的材质（内存缓存，由编辑器注入）
##   ② 官方材质库 res://gameAssetBase/shooting/danmaku16pxs/（大小写不敏感扫描）
##   ③ 兜底程序化白圆（保证缺材质时游戏不崩、编辑器预览可见）
## 官方材质规范（照抄文档）：
##   尽量体现灰度、尺寸为 2 的次方数、弹幕（若有）方向朝右；
##   普通弹幕多为 16×16，特别弹幕 32×32 / 64×64，最大可至 128/256。
## =============================================================

## 运行时材质缓存：材质名 -> Texture2D（.thx 导入的优先放这里）
static var runtime_cache: Dictionary = {}

static var _official_index: Dictionary = {} ## 材质名(小写) -> res:// 绝对路径
static var _official_scanned := false
static var _warned_missing: Dictionary = {} ## 缺材质一次性告警（诊断"白圆弹幕"）

static func resolve(name: String) -> Texture2D:
	var key := name.strip_edges()
	if key.is_empty():
		return _fallback()
	if runtime_cache.has(key):
		return runtime_cache[key]
	_scan_official_once()
	if _official_index.has(key.to_lower()):
		var tex := load(_official_index[key.to_lower()])
		if tex is Texture2D:
			return tex
	## 走到兜底=材质缺失：一次性告警（作者批复 2026-10-01：测试中弹幕显示为
	## 纯色圆，需确认是否真的用上了材质——缺材质时白圆兜底会盖住真相）
	if not _warned_missing.has(key):
		_warned_missing[key] = true
		push_warning("[DanmakuTex] 材质「%s」未找到（官方库/mod 均无）→ 使用白圆兜底" % key)
	return _fallback()

## 官方库一次性扫描（大小写不敏感索引；.PNG/.png 均收）
static func _scan_official_once() -> void:
	if _official_scanned:
		return
	_official_scanned = true
	var dir := DirAccess.open("res://gameAssetBase/shooting/danmaku16pxs")
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var lower := f.to_lower()
		if lower.ends_with(".png") or lower.ends_with(".bmp") or lower.ends_with(".cur") or lower.ends_with(".ico"):
			_official_index[f.get_basename().to_lower()] = "res://gameAssetBase/shooting/danmaku16pxs/".path_join(f)
		f = dir.get_next()
	dir.list_dir_end()

## 兜底材质：8×8 白圆（缺材质时不至于看不见弹幕）
static func _fallback() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var c := img.get_size() / 2.0
	for y in 8:
		for x in 8:
			if Vector2(x, y).distance_to(c) <= 3.5:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## 从字节流装载材质（.thx 的 texture/ 文件夹用），失败返回 null
static func load_from_bytes(name: String, bytes: PackedByteArray) -> bool:
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return false
	runtime_cache[name] = ImageTexture.create_from_image(img)
	return true

## 材质原始尺寸的一半（弹幕判定半径估算用；无材质按 8px）
static func half_size(tex: Texture2D) -> float:
	if tex == null:
		return 4.0
	return maxf(tex.get_size().x, tex.get_size().y) / 2.0
