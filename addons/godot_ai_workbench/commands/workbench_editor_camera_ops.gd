extends RefCounted

const DEFAULT_VIEWPORT_INDEX := 0
const MIN_VIEWPORT_INDEX := 0
const MAX_VIEWPORT_INDEX := 3

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return ["editor.camera_get", "editor.camera_set"]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"editor.camera_get":
			_handle_camera_get(command)
			return true
		"editor.camera_set":
			_handle_camera_set(command)
			return true
	return false


func _handle_camera_get(command: Dictionary) -> void:
	var args: Dictionary = _dictionary(command.get("args", {}))
	var viewport_index: int = _viewport_index(args)
	var snapshot: Dictionary = _camera_snapshot(viewport_index)
	if snapshot.get("ok", false) == true:
		_host.call("add_operation", "Editor camera: get viewport=%d" % viewport_index)
		_host.call("ack_dev_command", command, "ok", "editor camera snapshot", snapshot)
	else:
		_host.call("ack_dev_command", command, "error", str(snapshot.get("message", "editor camera snapshot failed")), snapshot)


func _handle_camera_set(command: Dictionary) -> void:
	var args: Dictionary = _dictionary(command.get("args", {}))
	var viewport_index: int = _viewport_index(args)
	var details: Dictionary = {
		"action": "editor.camera_set",
		"viewport_index": viewport_index
	}
	var camera_result: Dictionary = _editor_camera(viewport_index)
	if camera_result.get("ok", false) != true:
		details.merge(camera_result, true)
		_host.call("ack_dev_command", command, "error", str(camera_result.get("message", "editor camera is not available")), details)
		return
	var camera: Camera3D = camera_result.get("camera", null)
	if camera == null:
		details["message"] = "editor camera is not available"
		_host.call("ack_dev_command", command, "error", "editor camera is not available", details)
		return
	var before: Dictionary = _camera_snapshot(viewport_index)
	var changed := false
	if args.has("position"):
		var position_result: Dictionary = _vector3_from_value(args.get("position"))
		if position_result.get("ok", false) != true:
			details["validation"] = position_result
			_host.call("ack_dev_command", command, "error", str(position_result.get("message", "invalid position")), details)
			return
		camera.global_position = position_result.get("value", camera.global_position)
		changed = true
	if args.has("look_at"):
		var look_result: Dictionary = _vector3_from_value(args.get("look_at"))
		if look_result.get("ok", false) != true:
			details["validation"] = look_result
			_host.call("ack_dev_command", command, "error", str(look_result.get("message", "invalid look_at")), details)
			return
		var target: Vector3 = look_result.get("value", camera.global_position)
		if camera.global_position.distance_to(target) > 0.0001:
			camera.look_at(target, Vector3.UP)
			changed = true
	elif args.has("rotation_degrees"):
		var rotation_result: Dictionary = _vector3_from_value(args.get("rotation_degrees"))
		if rotation_result.get("ok", false) != true:
			details["validation"] = rotation_result
			_host.call("ack_dev_command", command, "error", str(rotation_result.get("message", "invalid rotation_degrees")), details)
			return
		var rotation_degrees: Vector3 = rotation_result.get("value", Vector3.ZERO)
		camera.global_rotation = Vector3(deg_to_rad(rotation_degrees.x), deg_to_rad(rotation_degrees.y), deg_to_rad(rotation_degrees.z))
		changed = true
	if args.has("fov"):
		camera.fov = clampf(float(args.get("fov", camera.fov)), 1.0, 179.0)
		changed = true
	if args.has("near"):
		camera.near = max(0.001, float(args.get("near", camera.near)))
		changed = true
	if args.has("far"):
		camera.far = max(camera.near + 0.001, float(args.get("far", camera.far)))
		changed = true
	var after: Dictionary = _camera_snapshot(viewport_index)
	details["ok"] = true
	details["changed"] = changed
	details["before"] = before
	details["after"] = after
	_host.call("add_operation", "Editor camera: set viewport=%d changed=%s" % [viewport_index, str(changed)])
	_host.call("ack_dev_command", command, "ok", "editor camera updated", details)


func _camera_snapshot(viewport_index: int) -> Dictionary:
	var camera_result: Dictionary = _editor_camera(viewport_index)
	if camera_result.get("ok", false) != true:
		return camera_result
	var camera: Camera3D = camera_result.get("camera", null)
	if camera == null:
		return _camera_error(viewport_index, "editor camera is not available")
	return {
		"ok": true,
		"schema_version": "gaw.editor_camera.v0",
		"action": "editor.camera_get",
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"viewport_index": viewport_index,
		"camera_path": str(camera.get_path()),
		"position": _vector3_value(camera.global_position),
		"rotation_degrees": _vector3_value(Vector3(rad_to_deg(camera.global_rotation.x), rad_to_deg(camera.global_rotation.y), rad_to_deg(camera.global_rotation.z))),
		"fov": camera.fov,
		"near": camera.near,
		"far": camera.far,
		"projection": camera.projection,
		"projection_name": "orthogonal" if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective"
	}


func _editor_camera(viewport_index: int) -> Dictionary:
	var editor_interface = _editor_interface_from_host()
	if editor_interface == null:
		return _camera_error(viewport_index, "editor interface is not available")
	if not editor_interface.has_method("get_editor_viewport_3d"):
		return _camera_error(viewport_index, "EditorInterface.get_editor_viewport_3d is not available in this Godot version")
	var viewport_value: Variant = editor_interface.call("get_editor_viewport_3d", viewport_index)
	var viewport: Viewport = viewport_value as Viewport
	if viewport == null:
		return _camera_error(viewport_index, "editor 3D viewport is not available")
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return _camera_error(viewport_index, "editor 3D camera is not available")
	return {
		"ok": true,
		"viewport_index": viewport_index,
		"camera": camera
	}


func _editor_interface_from_host() -> Variant:
	if _editor_interface != null:
		return _editor_interface
	if _host != null and _host.has_method("editor_interface"):
		return _host.call("editor_interface")
	return null


func _viewport_index(args: Dictionary) -> int:
	return clampi(int(args.get("viewport_index", DEFAULT_VIEWPORT_INDEX)), MIN_VIEWPORT_INDEX, MAX_VIEWPORT_INDEX)


func _vector3_from_value(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_VECTOR3:
		return {"ok": true, "value": value}
	if typeof(value) == TYPE_DICTIONARY:
		var source: Dictionary = value
		if not source.has("x") or not source.has("y") or not source.has("z"):
			return {"ok": false, "message": "Vector3 dictionary must contain x, y and z"}
		return {"ok": true, "value": Vector3(float(source.get("x", 0.0)), float(source.get("y", 0.0)), float(source.get("z", 0.0)))}
	if typeof(value) == TYPE_ARRAY:
		var array_value: Array = value
		if array_value.size() < 3:
			return {"ok": false, "message": "Vector3 array must contain at least 3 values"}
		return {"ok": true, "value": Vector3(float(array_value[0]), float(array_value[1]), float(array_value[2]))}
	return {"ok": false, "message": "Vector3 value must be a dictionary {x,y,z} or array [x,y,z]"}


func _vector3_value(value: Vector3) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z
	}


func _camera_error(viewport_index: int, message: String) -> Dictionary:
	return {
		"ok": false,
		"schema_version": "gaw.editor_camera.v0",
		"action": "editor.camera",
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"viewport_index": viewport_index,
		"message": message
	}


func _dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var result: Dictionary = value
		return result
	return {}
