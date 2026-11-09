extends RefCounted

const SUPPORTED_RESOURCE_TYPES := [
	"Animation",
	"CanvasItemMaterial",
	"Curve",
	"Environment",
	"Gradient",
	"PhysicsMaterial",
	"StandardMaterial3D",
	"Theme",
	"TileSet"
]

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"resource.create",
		"resource.edit",
		"resource.uid_repair",
		"resource.media_metadata"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"resource.create":
			_handle_resource_create(command)
			return true
		"resource.edit":
			_handle_resource_edit(command)
			return true
		"resource.uid_repair":
			_handle_resource_uid_repair(command)
			return true
		"resource.media_metadata":
			_handle_resource_media_metadata(command)
			return true
	return false


func _handle_resource_create(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var resource_path: String = str(args.get("path", "")).strip_edges()
	var resource_type: String = _normalize_resource_type(str(args.get("resource_type", "")).strip_edges())
	var overwrite: bool = _bool(args.get("overwrite", false), false)
	var properties: Dictionary = _dict(args.get("properties", {}))
	var details: Dictionary = _write_base_details("resource.create")
	_mark_native(details, ["Resource", "ResourceLoader", "ResourceSaver", "ClassDB", "EditorFileSystem"])
	details["path"] = resource_path
	details["resource_type"] = resource_type
	details["overwrite"] = overwrite
	details["property_count"] = properties.size()
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var path_result: Dictionary = _validate_resource_path(resource_path, false)
	if path_result.get("ok", false) != true:
		_ack(command, "error", str(path_result.get("message", "invalid resource path")), details)
		return
	resource_path = str(path_result.get("path", resource_path))
	details["path"] = resource_path
	details["absolute_path"] = str(path_result.get("absolute_path", ""))
	var exists_before: bool = _resource_exists(resource_path, str(path_result.get("absolute_path", "")))
	details["exists_before"] = exists_before
	if exists_before and not overwrite:
		_ack(command, "error", "resource file already exists; pass overwrite=true to replace it", details)
		return
	if not _is_supported_resource_type(resource_type):
		_ack(command, "error", "resource_type is not supported by the safe resource writer", details)
		return
	var resource: Resource = _instantiate_resource(resource_type)
	if resource == null:
		_ack(command, "error", "failed to instantiate resource_type", details)
		return
	var apply_result: Dictionary = _apply_properties(resource, resource_type, properties)
	details["property_changes"] = apply_result.get("changes", [])
	details["unsupported_properties"] = apply_result.get("unsupported", [])
	if apply_result.get("ok", false) != true:
		_ack(command, "error", str(apply_result.get("message", "resource property application failed")), details)
		return
	var save_result: Dictionary = _save_resource(resource, resource_path, details)
	if save_result.get("ok", false) != true:
		_ack(command, "error", str(save_result.get("message", "resource save failed")), details)
		return
	_scan_filesystem()
	details["saved"] = true
	details["changed"] = true
	details["affected_files"] = [resource_path]
	details["resource"] = _resource_snapshot(resource)
	_write_audit(details)
	_add_operation("Resource: create %s as %s" % [resource_path, resource_type])
	_ack(command, "ok", "resource created", details)


func _handle_resource_edit(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var resource_path: String = str(args.get("path", "")).strip_edges()
	var expected_type: String = _normalize_resource_type(str(args.get("expected_type", "")).strip_edges())
	var properties: Dictionary = _dict(args.get("properties", {}))
	var details: Dictionary = _write_base_details("resource.edit")
	_mark_native(details, ["Resource", "ResourceLoader", "ResourceSaver", "ClassDB", "EditorFileSystem"])
	details["path"] = resource_path
	details["expected_type"] = expected_type
	details["property_count"] = properties.size()
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if properties.is_empty():
		_ack(command, "error", "properties must contain at least one supported property", details)
		return
	var path_result: Dictionary = _validate_resource_path(resource_path, true)
	if path_result.get("ok", false) != true:
		_ack(command, "error", str(path_result.get("message", "invalid resource path")), details)
		return
	resource_path = str(path_result.get("path", resource_path))
	details["path"] = resource_path
	details["absolute_path"] = str(path_result.get("absolute_path", ""))
	var loaded: Variant = ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not (loaded is Resource):
		_ack(command, "error", "path did not load as a Resource", details)
		return
	var resource: Resource = loaded
	var resource_type: String = resource.get_class()
	details["resource_type"] = resource_type
	if not _is_supported_resource_type(resource_type):
		_ack(command, "error", "loaded resource type is not supported by the safe resource writer", details)
		return
	if expected_type != "" and not _resource_type_matches(resource_type, expected_type):
		_ack(command, "error", "loaded resource type does not match expected_type", details)
		return
	var apply_result: Dictionary = _apply_properties(resource, resource_type, properties)
	details["property_changes"] = apply_result.get("changes", [])
	details["unsupported_properties"] = apply_result.get("unsupported", [])
	if apply_result.get("ok", false) != true:
		_ack(command, "error", str(apply_result.get("message", "resource property application failed")), details)
		return
	var save_result: Dictionary = _save_resource(resource, resource_path, details)
	if save_result.get("ok", false) != true:
		_ack(command, "error", str(save_result.get("message", "resource save failed")), details)
		return
	_scan_filesystem()
	details["saved"] = true
	details["changed"] = int(apply_result.get("changed_count", 0)) > 0
	details["affected_files"] = [resource_path]
	details["resource"] = _resource_snapshot(resource)
	_write_audit(details)
	_add_operation("Resource: edit %s" % resource_path)
	_ack(command, "ok", "resource edited", details)


func _handle_resource_media_metadata(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var resource_path: String = str(args.get("path", "")).strip_edges()
	var max_scene_nodes: int = clampi(_int(args.get("max_scene_nodes", 256), 256), 1, 2000)
	var max_meshes: int = clampi(_int(args.get("max_meshes", 64), 64), 1, 512)
	var max_surfaces: int = clampi(_int(args.get("max_surfaces", 64), 64), 1, 512)
	var details: Dictionary = _read_base_details("resource.media_metadata")
	_mark_native(details, ["ResourceLoader", "Resource", "Texture2D", "AudioStream", "Mesh", "PackedScene"])
	details["path"] = resource_path
	details["max_scene_nodes"] = max_scene_nodes
	details["max_meshes"] = max_meshes
	details["max_surfaces"] = max_surfaces
	var path_result: Dictionary = _validate_read_resource_path(resource_path)
	if path_result.get("ok", false) != true:
		_ack(command, "error", str(path_result.get("message", "invalid resource path")), details)
		return
	resource_path = str(path_result.get("path", resource_path))
	details["path"] = resource_path
	details["absolute_path"] = str(path_result.get("absolute_path", ""))
	var loaded: Variant = ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not (loaded is Resource):
		_ack(command, "error", "path did not load as a Resource through Godot ResourceLoader", details)
		return
	var resource: Resource = loaded
	var metadata: Dictionary = _media_metadata_for_resource(resource, resource_path, max_scene_nodes, max_meshes, max_surfaces)
	for key: Variant in metadata.keys():
		details[str(key)] = metadata.get(key)
	_add_operation("Resource: media metadata %s" % resource_path)
	_ack(command, "ok", "resource media metadata inspected", details)


func _handle_resource_uid_repair(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var target_path: String = str(args.get("path", "")).strip_edges()
	var details: Dictionary = _write_base_details("resource.uid_repair")
	_mark_native(details, ["ResourceUID", "ResourceSaver", "EditorFileSystem"])
	details["path"] = target_path
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var path_result: Dictionary = _validate_uid_target_path(target_path)
	if path_result.get("ok", false) != true:
		_ack(command, "error", str(path_result.get("message", "invalid UID repair path")), details)
		return
	target_path = str(path_result.get("path", target_path))
	details["path"] = target_path
	details["absolute_path"] = str(path_result.get("absolute_path", ""))
	var resource_paths: Array[String] = _uid_target_resource_paths(target_path)
	details["resource_ref_count"] = resource_paths.size()
	var repairs: Array[Dictionary] = []
	var failures: Array[Dictionary] = []
	for resource_path: String in resource_paths:
		var repair: Dictionary = _ensure_resource_uid(resource_path)
		if repair.get("ok", false) == true:
			repairs.append(repair)
		else:
			failures.append(repair)
	details["repairs"] = repairs
	details["failures"] = failures
	details["failure_count"] = failures.size()
	details["changed"] = repairs.size() > 0
	details["affected_files"] = resource_paths
	_scan_filesystem()
	_write_audit(details)
	_add_operation("Resource: UID repair %s refs=%d failures=%d" % [target_path, repairs.size(), failures.size()])
	if failures.size() > 0:
		_ack(command, "error", "one or more resource UIDs could not be ensured", details)
		return
	_ack(command, "ok", "resource UIDs ensured", details)


func _normalize_resource_type(value: String) -> String:
	var key: String = value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	match key:
		"animation":
			return "Animation"
		"canvas_item_material", "canvasitemmaterial", "canvas":
			return "CanvasItemMaterial"
		"curve":
			return "Curve"
		"environment", "world_environment":
			return "Environment"
		"gradient":
			return "Gradient"
		"physics_material", "physicsmaterial":
			return "PhysicsMaterial"
		"standard_material_3d", "standardmaterial3d", "material3d", "standard3d":
			return "StandardMaterial3D"
		"theme":
			return "Theme"
		"tile_set", "tileset":
			return "TileSet"
	return value.strip_edges()


func _is_supported_resource_type(resource_type: String) -> bool:
	if not SUPPORTED_RESOURCE_TYPES.has(resource_type):
		return false
	if not ClassDB.class_exists(resource_type):
		return false
	return ClassDB.is_parent_class(resource_type, "Resource") or resource_type == "Resource"


func _resource_type_matches(actual: String, expected: String) -> bool:
	if actual == expected:
		return true
	if expected == "":
		return true
	if ClassDB.class_exists(actual) and ClassDB.class_exists(expected):
		return ClassDB.is_parent_class(actual, expected)
	return false


func _instantiate_resource(resource_type: String) -> Resource:
	var value: Variant = ClassDB.instantiate(resource_type)
	if value is Resource:
		return value
	if value is Object:
		value.free()
	return null


func _validate_resource_path(resource_path: String, must_exist: bool) -> Dictionary:
	var result: Dictionary = {"ok": false, "path": resource_path}
	resource_path = resource_path.strip_edges().replace("\\", "/")
	result["path"] = resource_path
	if resource_path == "":
		result["message"] = "path is required"
		return result
	if not resource_path.begins_with("res://"):
		result["message"] = "path must start with res://"
		return result
	var lower_path: String = resource_path.to_lower()
	if lower_path.contains(".."):
		result["message"] = "path traversal is not allowed"
		return result
	if lower_path.begins_with("res://addons/") or lower_path.begins_with("res://.godot/"):
		result["message"] = "addon and .godot paths are not writable through resource tools"
		return result
	if not (lower_path.ends_with(".tres") or lower_path.ends_with(".res")):
		result["message"] = "resource path must end with .tres or .res"
		return result
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	result["absolute_path"] = absolute_path
	if must_exist and not _resource_exists(resource_path, absolute_path):
		result["message"] = "resource file does not exist"
		return result
	result["ok"] = true
	return result


func _validate_read_resource_path(resource_path: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "path": resource_path}
	resource_path = resource_path.strip_edges().replace("\\", "/")
	result["path"] = resource_path
	if resource_path == "":
		result["message"] = "path is required"
		return result
	if not resource_path.begins_with("res://"):
		result["message"] = "path must start with res://"
		return result
	var lower_path: String = resource_path.to_lower()
	if lower_path.contains(".."):
		result["message"] = "path traversal is not allowed"
		return result
	if lower_path.begins_with("res://.godot/"):
		result["message"] = ".godot paths are not inspected through resource media metadata"
		return result
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	result["absolute_path"] = absolute_path
	if not ResourceLoader.exists(resource_path) and not FileAccess.file_exists(absolute_path):
		result["message"] = "resource file does not exist"
		return result
	result["ok"] = true
	return result


func _validate_uid_target_path(resource_path: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "path": resource_path}
	resource_path = resource_path.strip_edges().replace("\\", "/")
	result["path"] = resource_path
	if resource_path == "":
		result["message"] = "path is required"
		return result
	if not resource_path.begins_with("res://"):
		result["message"] = "path must start with res://"
		return result
	var lower_path: String = resource_path.to_lower()
	if lower_path.contains(".."):
		result["message"] = "path traversal is not allowed"
		return result
	if lower_path.begins_with("res://addons/") or lower_path.begins_with("res://.godot/"):
		result["message"] = "addon and .godot paths are not writable through UID repair"
		return result
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	result["absolute_path"] = absolute_path
	if not FileAccess.file_exists(absolute_path) and not ResourceLoader.exists(resource_path):
		result["message"] = "resource file does not exist"
		return result
	result["ok"] = true
	return result


func _uid_target_resource_paths(target_path: String) -> Array[String]:
	var paths: Array[String] = []
	var lower_path: String = target_path.to_lower()
	if lower_path.ends_with(".tscn") or lower_path.ends_with(".tres"):
		for resource_path: String in _serialized_ext_resource_paths(target_path):
			if not paths.has(resource_path):
				paths.append(resource_path)
	else:
		paths.append(target_path)
	return paths


func _serialized_ext_resource_paths(target_path: String) -> Array[String]:
	var paths: Array[String] = []
	var absolute_path: String = ProjectSettings.globalize_path(target_path)
	if not FileAccess.file_exists(absolute_path):
		return paths
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return paths
	while not file.eof_reached():
		var line: String = file.get_line()
		if not line.contains("[ext_resource") or not line.contains("path=\""):
			continue
		var resource_path: String = _quoted_attribute(line, "path")
		if resource_path.begins_with("res://") and not paths.has(resource_path):
			paths.append(resource_path)
	return paths


func _quoted_attribute(line: String, attribute: String) -> String:
	var needle := "%s=\"" % attribute
	var start := line.find(needle)
	if start < 0:
		return ""
	start += needle.length()
	var end := line.find("\"", start)
	if end < 0:
		return ""
	return line.substr(start, end - start)


func _ensure_resource_uid(resource_path: String) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"path": resource_path
	}
	var path_result: Dictionary = _validate_uid_target_path(resource_path)
	if path_result.get("ok", false) != true:
		result["message"] = str(path_result.get("message", "invalid resource path"))
		return result
	resource_path = str(path_result.get("path", resource_path))
	result["path"] = resource_path
	result["absolute_path"] = str(path_result.get("absolute_path", ""))
	var uid_id: int = ResourceSaver.get_resource_id_for_path(resource_path, true)
	result["uid_id"] = uid_id
	result["uid"] = ResourceUID.id_to_text(uid_id)
	if uid_id < 0:
		result["message"] = "ResourceSaver did not return a valid UID"
		return result
	var path_before := ""
	if ResourceUID.has_id(uid_id):
		path_before = ResourceUID.get_id_path(uid_id)
		ResourceUID.set_id(uid_id, resource_path)
	else:
		ResourceUID.add_id(uid_id, resource_path)
	result["path_before"] = path_before
	result["path_after"] = ResourceUID.get_id_path(uid_id) if ResourceUID.has_id(uid_id) else ""
	if _resource_saver_uid_supported(resource_path):
		var set_uid_error: int = ResourceSaver.set_uid(resource_path, uid_id)
		result["set_uid_error"] = set_uid_error
		if set_uid_error != OK:
			result["message"] = "ResourceSaver.set_uid failed: %s" % error_string(set_uid_error)
			return result
	else:
		result["set_uid_skipped"] = "ResourceSaver.set_uid is only used for serialized Godot resources"
	if _editor_interface != null and _editor_interface.has_method("get_resource_filesystem"):
		var resource_filesystem: Variant = _editor_interface.call("get_resource_filesystem")
		if resource_filesystem != null and resource_filesystem.has_method("update_file"):
			resource_filesystem.call("update_file", resource_path)
	result["ok"] = true
	result["message"] = "UID ensured"
	return result


func _resource_saver_uid_supported(resource_path: String) -> bool:
	var lower_path: String = resource_path.to_lower()
	return lower_path.ends_with(".tscn") or lower_path.ends_with(".tres") or lower_path.ends_with(".res")


func _resource_exists(resource_path: String, absolute_path: String) -> bool:
	if absolute_path != "" and FileAccess.file_exists(absolute_path):
		return true
	return ResourceLoader.exists(resource_path)


func _save_resource(resource: Resource, resource_path: String, details: Dictionary) -> Dictionary:
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	var dir_error: int = DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	details["make_dir_error"] = dir_error
	if dir_error != OK:
		return {"ok": false, "message": "failed to create resource directory", "error": error_string(dir_error)}
	if resource.has_method("take_over_path"):
		resource.call("take_over_path", resource_path)
	var save_error: int = ResourceSaver.save(resource, resource_path)
	details["save_error"] = save_error
	if save_error != OK:
		return {"ok": false, "message": "ResourceSaver.save failed", "error": error_string(save_error)}
	return {"ok": true, "message": "resource saved"}


func _media_metadata_for_resource(resource: Resource, resource_path: String, max_scene_nodes: int, max_meshes: int, max_surfaces: int) -> Dictionary:
	var result: Dictionary = {
		"schema_version": "gaw.resource_media_metadata.v0",
		"status": "ok",
		"path": resource_path,
		"resource": _resource_snapshot(resource),
		"resource_type": resource.get_class(),
		"metadata_source": "godot_resource_loader",
		"confidence": "medium",
		"supported": true
	}
	if resource is Texture2D:
		result["kind"] = "image"
		result["width"] = resource.get_width()
		result["height"] = resource.get_height()
		result["confidence"] = "high"
		return result
	if resource is AudioStream:
		result["kind"] = "audio"
		if resource.has_method("get_length"):
			var duration: float = float(resource.call("get_length"))
			result["duration_seconds"] = duration
			result["duration_available"] = duration >= 0.0
			result["confidence"] = "high" if duration >= 0.0 else "medium"
		else:
			result["duration_available"] = false
			result["notes"] = ["AudioStream does not expose get_length() on this Godot version/resource."]
		return result
	if resource is Mesh:
		result["kind"] = "mesh"
		result["mesh"] = _mesh_metadata(resource, max_surfaces)
		result["confidence"] = "high"
		return result
	if resource is PackedScene:
		result["kind"] = "scene"
		result["scene"] = _packed_scene_media_metadata(resource, max_scene_nodes, max_meshes, max_surfaces)
		result["confidence"] = "medium"
		return result
	result["kind"] = "resource"
	result["supported"] = false
	result["confidence"] = "low"
	result["notes"] = ["Resource type does not expose simple native media metadata."]
	return result


func _packed_scene_media_metadata(scene: PackedScene, max_scene_nodes: int, max_meshes: int, max_surfaces: int) -> Dictionary:
	var result: Dictionary = {
		"max_scene_nodes": max_scene_nodes,
		"max_meshes": max_meshes,
		"visited_nodes": 0,
		"mesh_instance_count": 0,
		"returned_mesh_count": 0,
		"surface_count": 0,
		"vertex_count": 0,
		"triangle_count": 0,
		"truncated_nodes": false,
		"truncated_meshes": false,
		"meshes": []
	}
	var root: Node = scene.instantiate()
	if root == null:
		result["status"] = "error"
		result["message"] = "PackedScene.instantiate() returned null"
		return result
	result["root_name"] = str(root.name)
	_collect_scene_meshes(root, root, result, max_scene_nodes, max_meshes, max_surfaces)
	root.free()
	return result


func _collect_scene_meshes(root: Node, node: Node, result: Dictionary, max_scene_nodes: int, max_meshes: int, max_surfaces: int) -> void:
	if node == null:
		return
	if int(result.get("visited_nodes", 0)) >= max_scene_nodes:
		result["truncated_nodes"] = true
		return
	result["visited_nodes"] = int(result.get("visited_nodes", 0)) + 1
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		var mesh: Mesh = mesh_instance.mesh
		if mesh != null:
			result["mesh_instance_count"] = int(result.get("mesh_instance_count", 0)) + 1
			var mesh_info: Dictionary = _mesh_metadata(mesh, max_surfaces)
			result["surface_count"] = int(result.get("surface_count", 0)) + int(mesh_info.get("surface_count", 0))
			result["vertex_count"] = int(result.get("vertex_count", 0)) + int(mesh_info.get("vertex_count", 0))
			result["triangle_count"] = int(result.get("triangle_count", 0)) + int(mesh_info.get("triangle_count", 0))
			var meshes: Array = result.get("meshes", [])
			if meshes.size() < max_meshes:
				mesh_info["node_name"] = str(node.name)
				mesh_info["node_path"] = _relative_node_path(root, node)
				meshes.append(mesh_info)
				result["meshes"] = meshes
				result["returned_mesh_count"] = meshes.size()
			else:
				result["truncated_meshes"] = true
	for child: Node in node.get_children():
		_collect_scene_meshes(root, child, result, max_scene_nodes, max_meshes, max_surfaces)
		if bool(result.get("truncated_nodes", false)):
			return


func _mesh_metadata(mesh: Mesh, max_surfaces: int) -> Dictionary:
	var surface_count: int = mesh.get_surface_count()
	var result: Dictionary = {
		"mesh_type": mesh.get_class(),
		"resource_path": mesh.resource_path,
		"surface_count": surface_count,
		"returned_surface_count": min(surface_count, max_surfaces),
		"surfaces_truncated": surface_count > max_surfaces,
		"vertex_count": 0,
		"index_count": 0,
		"triangle_count": 0,
		"surfaces": []
	}
	var surfaces: Array = []
	for surface_index: int in range(min(surface_count, max_surfaces)):
		var surface: Dictionary = {"index": surface_index}
		if mesh.has_method("surface_get_primitive_type"):
			surface["primitive_type"] = int(mesh.call("surface_get_primitive_type", surface_index))
		if mesh.has_method("surface_get_arrays"):
			var arrays: Variant = mesh.call("surface_get_arrays", surface_index)
			if typeof(arrays) == TYPE_ARRAY:
				var vertex_count: int = _variant_array_size(_array_item(arrays, Mesh.ARRAY_VERTEX))
				var index_count: int = _variant_array_size(_array_item(arrays, Mesh.ARRAY_INDEX))
				var triangle_count: int = _triangle_count(vertex_count, index_count, int(surface.get("primitive_type", Mesh.PRIMITIVE_TRIANGLES)))
				surface["vertex_count"] = vertex_count
				surface["index_count"] = index_count
				surface["triangle_count"] = triangle_count
				result["vertex_count"] = int(result.get("vertex_count", 0)) + vertex_count
				result["index_count"] = int(result.get("index_count", 0)) + index_count
				result["triangle_count"] = int(result.get("triangle_count", 0)) + triangle_count
		surfaces.append(surface)
	result["surfaces"] = surfaces
	return result


func _array_item(values: Array, index: int) -> Variant:
	if index < 0 or index >= values.size():
		return null
	return values[index]


func _variant_array_size(value: Variant) -> int:
	match typeof(value):
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			return value.size()
	return 0


func _triangle_count(vertex_count: int, index_count: int, primitive_type: int) -> int:
	if primitive_type != Mesh.PRIMITIVE_TRIANGLES:
		return 0
	if index_count > 0:
		return int(index_count / 3)
	return int(vertex_count / 3)


func _relative_node_path(root: Node, node: Node) -> String:
	if root == node:
		return str(root.name)
	var names: Array = []
	var current: Node = node
	while current != null and current != root:
		names.push_front(str(current.name))
		current = current.get_parent()
	names.push_front(str(root.name))
	return "/".join(names)


func _apply_properties(resource: Resource, resource_type: String, properties: Dictionary) -> Dictionary:
	var allowed: Dictionary = _allowed_property_set(resource_type)
	var changes: Array = []
	var unsupported: Array = []
	for key: Variant in properties.keys():
		var property_name: String = str(key)
		if not allowed.has(property_name):
			unsupported.append(property_name)
			continue
		if not _has_property(resource, property_name):
			unsupported.append(property_name)
			continue
		var property_type: int = _property_type(resource, property_name)
		var old_value: Variant = resource.get(property_name)
		var new_value: Variant = _coerce_value(properties.get(key), property_type)
		resource.set(property_name, new_value)
		var applied_value: Variant = resource.get(property_name)
		changes.append({
			"property": property_name,
			"old": _bounded_value(old_value),
			"new": _bounded_value(applied_value)
		})
	if not unsupported.is_empty():
		return {
			"ok": false,
			"message": "unsupported resource properties: %s" % ", ".join(unsupported),
			"changes": changes,
			"unsupported": unsupported,
			"changed_count": changes.size()
		}
	return {
		"ok": true,
		"changes": changes,
		"unsupported": unsupported,
		"changed_count": changes.size()
	}


func _allowed_property_set(resource_type: String) -> Dictionary:
	var names: Array = []
	match resource_type:
		"Animation":
			names = ["length", "loop_mode", "step"]
		"CanvasItemMaterial":
			names = ["blend_mode", "light_mode", "particles_animation"]
		"Curve":
			names = ["min_value", "max_value", "bake_resolution"]
		"Environment":
			names = ["background_mode", "background_color", "ambient_light_color", "ambient_light_energy", "glow_enabled", "fog_enabled", "fog_light_color", "fog_density"]
		"Gradient":
			names = ["colors", "offsets"]
		"PhysicsMaterial":
			names = ["friction", "bounce", "rough", "absorbent"]
		"StandardMaterial3D":
			names = ["albedo_color", "roughness", "metallic", "emission_enabled", "emission", "alpha_scissor_threshold"]
		"Theme":
			names = ["default_font_size"]
		"TileSet":
			names = ["tile_size"]
	var result: Dictionary = {}
	for property_name: String in names:
		result[property_name] = true
	return result


func _property_type(target: Object, property_name: String) -> int:
	for info: Dictionary in target.get_property_list():
		if str(info.get("name", "")) == property_name:
			return int(info.get("type", TYPE_NIL))
	return TYPE_NIL


func _coerce_value(value: Variant, property_type: int) -> Variant:
	match property_type:
		TYPE_BOOL:
			return _bool(value, false)
		TYPE_INT:
			return _int(value, 0)
		TYPE_FLOAT:
			return _float(value, 0.0)
		TYPE_STRING:
			return str(value)
		TYPE_VECTOR2:
			return _vector2(value)
		TYPE_VECTOR2I:
			var vec2: Vector2 = _vector2(value)
			return Vector2i(int(vec2.x), int(vec2.y))
		TYPE_VECTOR3:
			return _vector3(value)
		TYPE_VECTOR3I:
			var vec3: Vector3 = _vector3(value)
			return Vector3i(int(vec3.x), int(vec3.y), int(vec3.z))
		TYPE_COLOR:
			return _color(value)
		TYPE_PACKED_COLOR_ARRAY:
			var colors: PackedColorArray = PackedColorArray()
			if typeof(value) == TYPE_ARRAY:
				for item: Variant in value:
					colors.append(_color(item))
			return colors
		TYPE_PACKED_FLOAT32_ARRAY:
			var floats: PackedFloat32Array = PackedFloat32Array()
			if typeof(value) == TYPE_ARRAY:
				for item: Variant in value:
					floats.append(_float(item, 0.0))
			return floats
	return value


func _color(value: Variant) -> Color:
	match typeof(value):
		TYPE_COLOR:
			return value
		TYPE_STRING:
			return Color(str(value))
		TYPE_ARRAY:
			var array_value: Array = value
			if array_value.size() >= 3:
				var alpha: float = _float(array_value[3], 1.0) if array_value.size() >= 4 else 1.0
				return Color(_float(array_value[0], 0.0), _float(array_value[1], 0.0), _float(array_value[2], 0.0), alpha)
		TYPE_DICTIONARY:
			var dict_value: Dictionary = value
			return Color(
				_float(dict_value.get("r", 0.0), 0.0),
				_float(dict_value.get("g", 0.0), 0.0),
				_float(dict_value.get("b", 0.0), 0.0),
				_float(dict_value.get("a", 1.0), 1.0)
			)
	return Color.WHITE


func _vector2(value: Variant) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_ARRAY:
		var array_value: Array = value
		if array_value.size() >= 2:
			return Vector2(_float(array_value[0], 0.0), _float(array_value[1], 0.0))
	if typeof(value) == TYPE_DICTIONARY:
		var dict_value: Dictionary = value
		return Vector2(_float(dict_value.get("x", 0.0), 0.0), _float(dict_value.get("y", 0.0), 0.0))
	return Vector2.ZERO


func _vector3(value: Variant) -> Vector3:
	if typeof(value) == TYPE_VECTOR3:
		return value
	if typeof(value) == TYPE_ARRAY:
		var array_value: Array = value
		if array_value.size() >= 3:
			return Vector3(_float(array_value[0], 0.0), _float(array_value[1], 0.0), _float(array_value[2], 0.0))
	if typeof(value) == TYPE_DICTIONARY:
		var dict_value: Dictionary = value
		return Vector3(
			_float(dict_value.get("x", 0.0), 0.0),
			_float(dict_value.get("y", 0.0), 0.0),
			_float(dict_value.get("z", 0.0), 0.0)
		)
	return Vector3.ZERO


func _bounded_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR3I:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_COLOR:
			return value.to_html()
		TYPE_PACKED_COLOR_ARRAY:
			var colors: Array = []
			for color_value: Color in value:
				colors.append(color_value.to_html())
			return colors
		TYPE_PACKED_FLOAT32_ARRAY:
			var floats: Array = []
			for float_value: float in value:
				floats.append(float_value)
			return floats
		TYPE_ARRAY:
			var rows: Array = []
			for item: Variant in value:
				rows.append(_bounded_value(item))
			return rows
		TYPE_NODE_PATH:
			return str(value)
		TYPE_OBJECT:
			if value is Resource:
				return _resource_snapshot(value)
			if value is Object:
				return {"type": value.get_class()}
	return value


func _resource_snapshot(value: Variant) -> Dictionary:
	if value == null:
		return {"type": "null"}
	if value is Resource:
		return {
			"type": value.get_class(),
			"path": value.resource_path,
			"local_to_scene": value.resource_local_to_scene
		}
	return {"type": type_string(typeof(value)), "value": str(value)}


func _dict(value: Variant) -> Dictionary:
	var result: Variant = _host.call("workbench_dictionary", value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _bool(value: Variant, default_value: bool) -> bool:
	return bool(_host.call("workbench_bool", value, default_value))


func _int(value: Variant, default_value: int) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	var text: String = str(value).strip_edges()
	if text.is_valid_int():
		return int(text)
	return default_value


func _float(value: Variant, default_value: float) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	var text: String = str(value).strip_edges()
	if text.is_valid_float():
		return float(text)
	return default_value


func _write_gate_open() -> bool:
	return bool(_host.call("write_gate_open"))


func _write_base_details(action: String) -> Dictionary:
	var result: Variant = _host.call("write_base_details", action)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"action": action}


func _read_base_details(action: String) -> Dictionary:
	var result: Dictionary = {}
	if _host != null and _host.has_method("dev_details"):
		var details: Variant = _host.call("dev_details")
		if typeof(details) == TYPE_DICTIONARY:
			result = details
	result["action"] = action
	result["read_only"] = true
	return result


func _mark_native(details: Dictionary, native_api: Array) -> void:
	details["native_godot_api"] = true
	details["native_api"] = native_api
	details["dev_first"] = true
	details["stage"] = "15.16"


func _scan_filesystem() -> void:
	if _editor_interface == null or not _editor_interface.has_method("get_resource_filesystem"):
		return
	var resource_filesystem: Variant = _editor_interface.call("get_resource_filesystem")
	if resource_filesystem == null:
		return
	if resource_filesystem.has_method("scan_sources"):
		resource_filesystem.call("scan_sources")
	elif resource_filesystem.has_method("scan"):
		resource_filesystem.call("scan")


func _write_audit(details: Dictionary) -> void:
	_host.call("write_audit", details)


func _add_operation(text: String) -> void:
	_host.call("add_operation", text)


func _ack(command: Dictionary, status: String, message: String, details: Dictionary) -> void:
	_host.call("ack_dev_command", command, status, message, details)


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for info: Dictionary in target.get_property_list():
		if str(info.get("name", "")) == property_name:
			return true
	return false
