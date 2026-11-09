extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"domain.physics_layers",
		"domain.tileset_info"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"domain.physics_layers":
			_handle_physics_layers(command)
			return true
		"domain.tileset_info":
			_handle_tileset_info(command)
			return true
	return false


func _handle_physics_layers(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "inspect")))
	var space: String = _normalize_space(str(args.get("space", "both" if action == "inspect" else "2d")))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var details: Dictionary = _write_base_details("domain.physics_layers")
	_mark_native(details, ["ProjectSettings", "CollisionObject2D", "CollisionObject3D", "EditorUndoRedoManager"])
	details["action_mode"] = action
	details["space"] = space
	details["node_path"] = node_path
	if action == "inspect":
		details["project_layers"] = _project_layer_snapshot(space)
		_add_collision_node_snapshot(details, node_path)
		_add_operation("Domain: physics layers inspect")
		_ack(command, "ok", "physics layers inspected", details)
		return
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	match action:
		"set_project_layer":
			_handle_project_layer_write(command, details, args, space)
		"set_node_layers":
			_handle_node_layer_write(command, details, args, node_path)
		_:
			_ack(command, "error", "action must be inspect, set_project_layer or set_node_layers", details)


func _handle_project_layer_write(command: Dictionary, details: Dictionary, args: Dictionary, space: String) -> void:
	if space != "2d" and space != "3d":
		_ack(command, "error", "space must be 2d or 3d for set_project_layer", details)
		return
	var layer_index: int = int(clamp(_int(args.get("layer_index", 0), 0), 1, 32))
	if layer_index < 1 or layer_index > 32:
		_ack(command, "error", "layer_index must be between 1 and 32", details)
		return
	if not args.has("layer_name"):
		_ack(command, "error", "layer_name is required", details)
		return
	var layer_name: String = str(args.get("layer_name", "")).strip_edges()
	if layer_name.length() > 64:
		_ack(command, "error", "layer_name must be at most 64 characters", details)
		return
	var save_project: bool = _bool(args.get("save_project", true), true)
	var setting_name: String = _layer_setting_name(space, layer_index)
	var old_value: Variant = ProjectSettings.get_setting(setting_name, "")
	ProjectSettings.set_setting(setting_name, layer_name)
	details["setting_name"] = setting_name
	details["layer_index"] = layer_index
	details["old_value"] = old_value
	details["new_value"] = layer_name
	details["changed"] = str(old_value) != layer_name
	details["saved"] = false
	if save_project:
		var save_error: int = ProjectSettings.save()
		details["save_error"] = save_error
		details["saved"] = save_error == OK
		if save_error != OK:
			_write_audit(details)
			_ack(command, "error", "ProjectSettings.save failed", details)
			return
	details["project_layers"] = _project_layer_snapshot(space)
	details["status"] = "applied"
	_write_audit(details)
	_add_operation("Domain: physics layer %s %d = %s" % [space, layer_index, layer_name])
	_ack(command, "ok", "physics project layer updated", details)


func _handle_node_layer_write(command: Dictionary, details: Dictionary, args: Dictionary, node_path: String) -> void:
	if node_path == "":
		_ack(command, "error", "node_path is required for set_node_layers", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	var changes: Array = []
	if args.has("collision_layer") and _has_property(node, "collision_layer"):
		_add_property_change(changes, node, "collision_layer", max(0, _int(args.get("collision_layer", 0), 0)))
	if args.has("collision_mask") and _has_property(node, "collision_mask"):
		_add_property_change(changes, node, "collision_mask", max(0, _int(args.get("collision_mask", 0), 0)))
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["before"] = _collision_snapshot(node)
	if changes.is_empty():
		_ack(command, "error", "no supported collision_layer or collision_mask change requested", details)
		return
	var undo_redo: EditorUndoRedoManager = _resolve_undo_redo()
	if undo_redo == null:
		_ack(command, "error", "EditorUndoRedoManager is unavailable", details)
		return
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var save_context: Dictionary = {}
	if save_scene:
		save_context = _prepare_scene_save(details, root)
		if save_context.get("ok", false) != true:
			_ack(command, "error", str(save_context.get("message", "scene save preparation failed; write aborted")), details)
			return
	undo_redo.create_action("Godot AI Workbench: physics layers %s" % str(details.get("resolved_node_path", "")), 0, root)
	for change: Dictionary in changes:
		undo_redo.add_do_property(change.get("target"), str(change.get("property", "")), change.get("new"))
		undo_redo.add_undo_property(change.get("target"), str(change.get("property", "")), change.get("old"))
	undo_redo.commit_action()
	details["after"] = _collision_snapshot(node)
	details["changes"] = _change_summaries(changes)
	details["status"] = "applied"
	details["saved"] = false
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Domain: physics layers node %s" % str(details.get("resolved_node_path", "")))
	_ack(command, "ok", "physics node layers updated", details)


func _handle_tileset_info(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var resource_path: String = str(args.get("resource_path", "")).strip_edges()
	var max_sources: int = int(clamp(_int(args.get("max_sources", 16), 16), 1, 128))
	var max_tiles: int = int(clamp(_int(args.get("max_tiles", 32), 32), 0, 512))
	var details: Dictionary = _read_base_details("domain.tileset_info")
	_mark_native(details, ["TileSet", "TileSetSource", "ResourceLoader"])
	details["node_path"] = node_path
	details["resource_path"] = resource_path
	details["max_sources"] = max_sources
	details["max_tiles"] = max_tiles
	var tile_set: Variant = null
	if resource_path != "":
		tile_set = ResourceLoader.load(resource_path, "TileSet", ResourceLoader.CACHE_MODE_IGNORE)
		details["source"] = "resource_path"
	else:
		var root: Node = _edited_scene_root()
		if root == null:
			_ack(command, "error", "no edited scene root", details)
			return
		var node: Node = _resolve_target_node(root, node_path, details)
		if node == null:
			_ack(command, "error", str(details.get("target_error", "node not found")), details)
			return
		if not _has_property(node, "tile_set"):
			_ack(command, "error", "target node does not expose tile_set", details)
			return
		tile_set = node.get("tile_set")
		details["scene_path"] = root.scene_file_path
		details["resolved_node_path"] = _scene_node_path(root, node)
		details["source"] = "node"
	if not tile_set is TileSet:
		_ack(command, "error", "TileSet resource not found", details)
		return
	details["tileset"] = _tileset_snapshot(tile_set, max_sources, max_tiles)
	_add_operation("Domain: TileSet info")
	_ack(command, "ok", "TileSet inspected", details)


func _project_layer_snapshot(space: String) -> Dictionary:
	var result: Dictionary = {}
	if space == "both" or space == "2d":
		result["2d"] = _layer_rows("2d")
	if space == "both" or space == "3d":
		result["3d"] = _layer_rows("3d")
	return result


func _layer_rows(space: String) -> Array:
	var rows: Array = []
	for index: int in range(1, 33):
		var setting_name: String = _layer_setting_name(space, index)
		rows.append({
			"index": index,
			"name": str(ProjectSettings.get_setting(setting_name, "")),
			"setting": setting_name
		})
	return rows


func _layer_setting_name(space: String, index: int) -> String:
	return "layer_names/%s_physics/layer_%d" % [space, index]


func _add_collision_node_snapshot(details: Dictionary, node_path: String) -> void:
	if node_path == "":
		return
	var root: Node = _edited_scene_root()
	if root == null:
		details["node_error"] = "no edited scene root"
		return
	var node: Node = _resolve_target_node(root, node_path, details)
	if node == null:
		details["node_error"] = str(details.get("target_error", "node not found"))
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["collision"] = _collision_snapshot(node)


func _collision_snapshot(node: Node) -> Dictionary:
	var result: Dictionary = {
		"type": node.get_class()
	}
	if _has_property(node, "collision_layer"):
		result["collision_layer"] = int(node.get("collision_layer"))
	if _has_property(node, "collision_mask"):
		result["collision_mask"] = int(node.get("collision_mask"))
	if _has_property(node, "monitoring"):
		result["monitoring"] = bool(node.get("monitoring"))
	if _has_property(node, "monitorable"):
		result["monitorable"] = bool(node.get("monitorable"))
	return result


func _tileset_snapshot(tile_set: TileSet, max_sources: int, max_tiles: int) -> Dictionary:
	var result: Dictionary = {
		"type": tile_set.get_class(),
		"path": tile_set.resource_path,
		"source_count": tile_set.get_source_count(),
		"sources": []
	}
	var count: int = min(tile_set.get_source_count(), max_sources)
	for source_index: int in range(count):
		var source_id: int = tile_set.get_source_id(source_index)
		var source: Variant = tile_set.get_source(source_id)
		result["sources"].append(_tileset_source_snapshot(source_id, source, max_tiles))
	result["sources_truncated"] = tile_set.get_source_count() > max_sources
	return result


func _tileset_source_snapshot(source_id: int, source: Variant, max_tiles: int) -> Dictionary:
	var result: Dictionary = {
		"id": source_id,
		"type": source.get_class() if source is Object else type_string(typeof(source)),
		"path": source.resource_path if source is Resource else "",
		"tiles": []
	}
	if source == null or not source is Object:
		return result
	if source.has_method("get_tiles_count"):
		var tile_count: int = int(source.call("get_tiles_count"))
		result["tile_count"] = tile_count
		var count: int = min(tile_count, max_tiles)
		for tile_index: int in range(count):
			var tile_id: Variant = source.call("get_tile_id", tile_index) if source.has_method("get_tile_id") else tile_index
			result["tiles"].append(_tile_source_tile_snapshot(source, tile_id))
		result["tiles_truncated"] = tile_count > max_tiles
	if source.has_method("get_atlas_grid_size"):
		result["atlas_grid_size"] = _bounded_value(source.call("get_atlas_grid_size"))
	for property_name: String in ["texture", "texture_region_size", "margins", "separation", "use_texture_padding"]:
		if _has_property(source, property_name):
			result[property_name] = _bounded_value(source.get(property_name))
	return result


func _tile_source_tile_snapshot(source: Object, tile_id: Variant) -> Dictionary:
	var result: Dictionary = {
		"id": _bounded_value(tile_id)
	}
	if source.has_method("get_alternative_tiles_count"):
		var alternatives: int = int(source.call("get_alternative_tiles_count", tile_id))
		result["alternative_count"] = alternatives
		var alternative_ids: Array = []
		var count: int = min(alternatives, 16)
		for index: int in range(count):
			if source.has_method("get_alternative_tile_id"):
				alternative_ids.append(source.call("get_alternative_tile_id", tile_id, index))
		result["alternative_ids"] = _bounded_value(alternative_ids)
		result["alternatives_truncated"] = alternatives > 16
	return result


func _add_property_change(changes: Array, target: Object, property_name: String, new_value: Variant) -> void:
	if target == null or property_name == "" or not _has_property(target, property_name):
		return
	var old_value: Variant = target.get(property_name)
	if old_value == new_value:
		return
	changes.append({
		"target": target,
		"property": property_name,
		"old": old_value,
		"new": new_value
	})


func _change_summaries(changes: Array) -> Array:
	var result: Array = []
	for change: Dictionary in changes:
		var target: Object = change.get("target")
		result.append({
			"target_type": target.get_class() if target != null else "null",
			"property": str(change.get("property", "")),
			"old": _bounded_value(change.get("old")),
			"new": _bounded_value(change.get("new"))
		})
	return result


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


func _normalize_space(value: String) -> String:
	var key: String = _normalize_key(value)
	if key in ["", "both", "all"]:
		return "both"
	if key in ["2", "2d", "physics_2d"]:
		return "2d"
	if key in ["3", "3d", "physics_3d"]:
		return "3d"
	return key


func _normalize_key(value: String) -> String:
	return value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")


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


func _write_gate_open() -> bool:
	return bool(_host.call("write_gate_open"))


func _write_base_details(action: String) -> Dictionary:
	var result: Variant = _host.call("write_base_details", action)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"action": action}


func _read_base_details(action: String) -> Dictionary:
	var result: Variant = _host.call("dev_details")
	if typeof(result) == TYPE_DICTIONARY:
		result["action"] = action
		return result
	return {"action": action}


func _mark_native(details: Dictionary, native_api: Array) -> void:
	details["native_godot_api"] = true
	details["native_api"] = native_api
	details["dev_first"] = true
	details["stage"] = "15.15"


func _edited_scene_root() -> Node:
	if _editor_interface != null:
		return _editor_interface.get_edited_scene_root()
	var editor_interface: Variant = _host.call("editor_interface")
	if editor_interface != null:
		return editor_interface.get_edited_scene_root()
	return null


func _resolve_target_node(root: Node, node_path: String, details: Dictionary) -> Node:
	var result: Variant = _host.call("resolve_write_target_node", root, node_path, details)
	if result is Node:
		return result
	return null


func _scene_node_path(root: Node, node: Node) -> String:
	return str(_host.call("workbench_scene_node_path", root, node))


func _resolve_undo_redo() -> EditorUndoRedoManager:
	var result: Variant = _host.call("resolve_undo_redo")
	if result is EditorUndoRedoManager:
		return result
	return null


func _prepare_scene_save(details: Dictionary, root: Node) -> Dictionary:
	var result: Variant = _host.call("prepare_scene_save", details, root)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"ok": false, "message": "scene save preparation did not return a result"}


func _finalize_scene_save(details: Dictionary, root: Node, save_context: Dictionary) -> Dictionary:
	var result: Variant = _host.call("finalize_scene_save", details, root, save_context)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"ok": false, "message": "scene save finalization did not return a result"}


func _write_audit(details: Dictionary) -> void:
	_host.call("write_audit", details)


func _send_editor_state() -> void:
	_host.call("send_editor_state")


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
