class_name HvField
extends RefCounted
## =============================================================
## Hv 全局速度热点图（③期热力图族第二张；每侧一张）
## 策划：弹幕图升降沿为热点的像素遍历图（10Hz；扩散/0.8衰减/升降沿+64）。
## GPU：shaders/hv_step.glsl——RGBA8 烘焙显示色（上升沿红相/下降沿蓝相），
##   AI 采样取 max(R,B)。headless 降级：跳过（F1 显示无碍战斗逻辑）。
## =============================================================

const W := 400
const H := 400

var ok := false
var _rd: RenderingDevice = null
var _hv: Array = [RID(), RID()]
var _front := 0
var _sets: Array = []
var _pipe: RID
var _cr_pipe: RID = RID()
var _cr_sets: Array = [] ## [front] → set
var _shader_rid: RID

func _init(rd: RenderingDevice, ddm_cur: RID, ddm_prev: RID) -> void:
	_rd = rd
	if _rd == null or not ddm_cur.is_valid() or not ddm_prev.is_valid():
		return
	var shader: RDShaderFile = load("res://shaders/hv_step.glsl")
	if shader == null:
		return
	_shader_rid = _rd.shader_create_from_spirv(shader.get_spirv(), "hv_step")
	if not _shader_rid.is_valid():
		return
	_pipe = _rd.compute_pipeline_create(_shader_rid)
	if not _pipe.is_valid():
		return
	var fmt := RDTextureFormat.new()
	fmt.width = W
	fmt.height = H
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var zero := PackedByteArray()
	zero.resize(W * H * 4)
	for i in 2:
		_hv[i] = _rd.texture_create(fmt, RDTextureView.new(), [zero])
		if not _hv[i].is_valid():
			return
	for front in 2:
		var u_prev := _img(_hv[front], 0)
		var u_next := _img(_hv[1 - front], 1)
		var u_c := _img(ddm_cur, 2)
		var u_p := _img(ddm_prev, 3)
		_sets.append(_rd.uniform_set_create([u_prev, u_next, u_c, u_p], _shader_rid, 0))
	ok = true

func _img(rid: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u

## 步进（10Hz；须在当帧 DDM 渲染之后）
func step() -> void:
	if _rd == null or not ok:
		return
	var front := _front
	var back := 1 - front
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipe)
	_rd.compute_list_bind_uniform_set(cl, _sets[front], 0)
	_rd.compute_list_dispatch(cl, 50, 50, 1)
	_rd.compute_list_end()
	_front = back

func clear_region(cx: float, cy: float, radius: float) -> void:
	if _rd == null or not ok or not _cr_pipe.is_valid():
		return
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _cr_pipe)
	_rd.compute_list_bind_uniform_set(cl, _cr_sets[_front], 0)
	_rd.compute_list_set_push_constant(cl,
		PackedInt32Array([int(cx), int(cy), int(radius), 0]).to_byte_array(), 16)
	_rd.compute_list_dispatch(cl, 50, 50, 1)
	_rd.compute_list_end()

func shutdown() -> void:
	if _rd == null:
		return
	for set_rid in _sets:
		if set_rid.is_valid():
			_rd.free_rid(set_rid)
	_sets.clear()
	for rid in [_hv[0], _hv[1], _pipe, _shader_rid]:
		if rid.is_valid():
			_rd.free_rid(rid)
	_hv = [RID(), RID()]
	_pipe = RID()
	_shader_rid = RID()
	ok = false

var _disp_cache: Texture2D = null
var _disp_front := -1
## F1 调试显示（彩虹已烘焙）；【N6】front 未翻面时复用缓存，免每帧新建
func display_texture() -> Texture2D:
	if not ok:
		return null
	if _disp_cache != null and _disp_front == _front:
		return _disp_cache
	_disp_cache = Texture2DRD.new()
	_disp_cache.texture_rd_rid = _hv[_front]
	_disp_front = _front
	return _disp_cache
