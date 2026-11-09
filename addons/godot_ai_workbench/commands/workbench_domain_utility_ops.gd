extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"domain.find_nodes",
		"domain.scene_dependencies",
		"domain.audio_player"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"domain.find_nodes":
			_handle_find_nodes(command)
			return true
		"domain.scene_dependencies":
			_handle_scene_dependencies(command)
			return true
		"domain.audio_player":
			_handle_audio_player(command)
			return true
	return false


func _handle_find_nodes(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var details: Dictionary = _read_base_details("domain.find_nodes")
	_mark_native(details, ["Node", "Script", "PackedScene", "EditorInterface"])
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var root_path: String = str(args.get("root_path", "")).strip_edges()
	var search_root: Node = root
	if root_path != "":
		search_root = _resolve_target_node(root, root_path, details)
		if search_root == null:
			_ack(command, "error", str(details.get("target_error", "root node not found")), details)
			return
	var max_results: int = int(clamp(_int(args.get("max_results", 80), 80), 1, 500))
	var options: Dictionary = {
		"type_filter": str(args.get("class_name", args.get("type", ""))).strip_edges(),
		"name_query": str(args.get("name_query", args.get("name", ""))).strip_edges(),
		"group_filter": str(args.get("group", "")).strip_edges(),
		"script_path": str(args.get("script_path", "")).strip_edges(),
		"has_script_set": args.has("has_script"),
		"has_script": _bool(args.get("has_script", false), false),
		"include_groups": _bool(args.get("include_groups", true), true),
		"include_children_count": _bool(args.get("include_children_count", true), true),
		"max_results": max_results
	}
	details["scene_path"] = root.scene_file_path
	details["root_path"] = _scene_node_path(root, search_root)
	details["filters"] = {
		"class_name": options.get("type_filter", ""),
		"name_query": options.get("name_query", ""),
		"group": options.get("group_filter", ""),
		"script_path": options.get("script_path", ""),
		"has_script": options.get("has_script") if bool(options.get("has_script_set", false)) else null
	}
	var results: Array = []
	var stats: Dictionary = {"visited": 0, "matched": 0, "truncated": false}
	_visit_nodes(root, search_root, options, results, stats)
	details["nodes"] = results
	details["visited_count"] = int(stats.get("visited", 0))
	details["matched_count"] = int(stats.get("matched", 0))
	details["returned_count"] = results.size()
	details["truncated"] = bool(stats.get("truncated", false))
	_add_operation("Domain: find nodes returned %d" % results.size())
	_ack(command, "ok", "domain nodes searched", details)


func _handle_scene_dependencies(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var details: Dictionary = _read_base_details("domain.scene_dependencies")
	_mark_native(details, ["ResourceLoader", "Node", "Resource", "EditorInterface"])
	var root: Node = _edited_scene_root()
	var scene_path: String = str(args.get("scene_path", "")).strip_edges()
	if scene_path == "":
		if root == null:
			_ack(command, "error", "scene_path is required when no edited scene root is open", details)
			return
		scene_path = root.scene_file_path
	if scene_path == "":
		_ack(command, "error", "open scene has no saved scene_file_path", details)
		return
	var max_dependencies: int = int(clamp(_int(args.get("max_dependencies", 300), 300), 1, 2000))
	var max_live_resources: int = int(clamp(_int(args.get("max_live_resources", 200), 200), 0, 1000))
	var include_live_node_resources: bool = _bool(args.get("include_live_node_resources", true), true)
	details["scene_path"] = scene_path
	details["max_dependencies"] = max_dependencies
	details["max_live_resources"] = max_live_resources
	details["include_live_node_resources"] = include_live_node_resources
	var static_rows: Array = []
	var static_values: PackedStringArray = ResourceLoader.get_dependencies(scene_path)
	var static_count: int = 0
	for dependency_text: String in static_values:
		static_count += 1
		if static_rows.size() >= max_dependencies:
			continue
		static_rows.append(_dependency_row(dependency_text))
	details["static_dependencies"] = static_rows
	details["static_dependency_count"] = static_count
	details["static_truncated"] = static_count > static_rows.size()
	if include_live_node_resources and root != null and max_live_resources > 0:
		var live_map: Dictionary = {}
		var live_stats: Dictionary = {"nodes": 0, "properties": 0, "local_resources": 0, "truncated": false}
		_collect_live_resources(root, root, live_map, live_stats, max_live_resources)
		details["live_resources"] = _resource_map_rows(live_map)
		details["live_resource_count"] = live_map.size()
		details["live_resource_stats"] = live_stats
	else:
		details["live_resources"] = []
		details["live_resource_count"] = 0
		details["live_resource_stats"] = {}
	_add_operation("Domain: scene dependencies %s" % scene_path)
	_ack(command, "ok", "scene dependencies inspected", details)


func _handle_audio_player(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "inspect")))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.audio_player")
	_mark_native(details, ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D", "AudioStream", "EditorUndoRedoManager"])
	details["action_mode"] = action
	details["node_path"] = node_path
	details["save_scene"] = save_scene
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	if not _is_audio_player_node(node):
		_ack(command, "error", "target node must be AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D", details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["audio_player"] = _audio_player_snapshot(node)
	if action == "inspect":
		_add_operation("Domain: audio player inspect %s" % str(details.get("resolved_node_path", "")))
		_ack(command, "ok", "AudioStreamPlayer inspected", details)
		return
	if action != "set":
		_ack(command, "error", "action must be inspect or set", details)
		return
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var changes: Array = []
	if _bool(args.get("clear_stream", false), false) and _has_property(node, "stream"):
		_add_property_change(changes, node, "stream", null)
	elif args.has("stream_path") and _has_property(node, "stream"):
		var stream_result: Dictionary = _load_audio_stream(str(args.get("stream_path", "")).strip_edges())
		if stream_result.get("ok", false) != true:
			details["stream_path"] = str(args.get("stream_path", "")).strip_edges()
			_ack(command, "error", str(stream_result.get("message", "audio stream load failed")), details)
			return
		_add_property_change(changes, node, "stream", stream_result.get("stream"))
		details["stream_path"] = str(stream_result.get("path", ""))
	_collect_property_arg(changes, node, args, "bus", "bus", "string")
	_collect_property_arg(changes, node, args, "volume_db", "volume_db", "float")
	_collect_property_arg(changes, node, args, "pitch_scale", "pitch_scale", "float")
	_collect_property_arg(changes, node, args, "autoplay", "autoplay", "bool")
	_collect_property_arg(changes, node, args, "stream_paused", "stream_paused", "bool")
	_collect_property_arg(changes, node, args, "max_polyphony", "max_polyphony", "int")
	_collect_property_arg(changes, node, args, "mix_target", "mix_target", "int")
	_collect_property_arg(changes, node, args, "max_distance", "max_distance", "float")
	_collect_property_arg(changes, node, args, "attenuation", "attenuation", "float")
	_collect_property_arg(changes, node, args, "panning_strength", "panning_strength", "float")
	_collect_property_arg(changes, node, args, "area_mask", "area_mask", "int")
	_collect_property_arg(changes, node, args, "unit_size", "unit_size", "float")
	_collect_property_arg(changes, node, args, "max_db", "max_db", "float")
	_collect_property_arg(changes, node, args, "emission_angle_enabled", "emission_angle_enabled", "bool")
	_collect_property_arg(changes, node, args, "emission_angle_degrees", "emission_angle_degrees", "float")
	_commit_property_changes(command, details, root, node, changes, "audio player", save_scene, "AudioStreamPlayer updated")


func _visit_nodes(scene_root: Node, node: Node, options: Dictionary, results: Array, stats: Dictionary) -> void:
	if bool(stats.get("truncated", false)):
		return
	stats["visited"] = int(stats.get("visited", 0)) + 1
	if _node_matches_filters(node, options):
		stats["matched"] = int(stats.get("matched", 0)) + 1
		if results.size() < int(options.get("max_results", 80)):
			results.append(_node_summary(scene_root, node, options))
		else:
			stats["truncated"] = true
			return
	for child: Node in node.get_children():
		_visit_nodes(scene_root, child, options, results, stats)
		if bool(stats.get("truncated", false)):
			return


func _node_matches_filters(node: Node, options: Dictionary) -> bool:
	var type_filter: String = str(options.get("type_filter", "")).strip_edges()
	if type_filter != "":
		if not (node.get_class() == type_filter or node.is_class(type_filter)):
			return false
	var name_query: String = str(options.get("name_query", "")).strip_edges().to_lower()
	if name_query != "" and not node.name.to_lower().contains(name_query):
		return false
	var group_filter: String = str(options.get("group_filter", "")).strip_edges()
	if group_filter != "" and not node.is_in_group(group_filter):
		return false
	var script_path: String = str(options.get("script_path", "")).strip_edges()
	var script_resource: Variant = node.get_script()
	var node_script_path: String = script_resource.resource_path if script_resource is Resource else ""
	if script_path != "" and node_script_path != script_path:
		return false
	if bool(options.get("has_script_set", false)):
		var wants_script: bool = bool(options.get("has_script", false))
		if wants_script != (script_resource is Resource):
			return false
	return true


func _node_summary(scene_root: Node, node: Node, options: Dictionary) -> Dictionary:
	var script_resource: Variant = node.get_script()
	var result: Dictionary = {
		"path": _scene_node_path(scene_root, node),
		"name": str(node.name),
		"type": node.get_class(),
		"parent": _scene_node_path(scene_root, node.get_parent()) if node.get_parent() != null and node.get_parent() != scene_root.get_parent() else "",
		"script_path": script_resource.resource_path if script_resource is Resource else ""
	}
	if bool(options.get("include_groups", true)):
		result["groups"] = _group_names(node)
	if bool(options.get("include_children_count", true)):
		result["child_count"] = node.get_child_count()
	return result


func _group_names(node: Node) -> Array:
	var result: Array = []
	for group_name: Variant in node.get_groups():
		var text: String = str(group_name)
		if not text.begins_with("_"):
			result.append(text)
	result.sort()
	return result


func _audio_player_snapshot(node: Node) -> Dictionary:
	var names: Array = ["stream", "bus", "volume_db", "pitch_scale", "autoplay", "playing", "stream_paused", "max_polyphony", "mix_target", "max_distance", "attenuation", "panning_strength", "area_mask", "unit_size", "max_db", "emission_angle_enabled", "emission_angle_degrees"]
	var result: Dictionary = {"type": node.get_class()}
	for name: String in names:
		if _has_property(node, name):
			result[name] = _bounded_value(node.get(name))
	return result


func _is_audio_player_node(node: Node) -> bool:
	return node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D


func _load_audio_stream(path: String) -> Dictionary:
	if path == "":
		return {"ok": false, "message": "stream_path must not be empty; use clear_stream=true to clear the stream"}
	if not path.begins_with("res://"):
		return {"ok": false, "message": "stream_path must be a res:// resource path"}
	var resource: Variant = ResourceLoader.load(path, "AudioStream", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		return {"ok": false, "message": "AudioStream resource could not be loaded"}
	if not resource is AudioStream:
		return {"ok": false, "message": "resource is not an AudioStream"}
	return {"ok": true, "stream": resource, "path": path}


func _dependency_row(raw: String) -> Dictionary:
	var row: Dictionary = {"raw": raw, "path": raw, "uid": "", "exists": false}
	if raw.contains("::"):
		var parts: PackedStringArray = raw.split("::", false, 1)
		if parts.size() >= 2:
			row["uid"] = str(parts[0])
			row["path"] = str(parts[1])
	var path: String = str(row.get("path", ""))
	if path.begins_with("res://"):
		row["exists"] = ResourceLoader.exists(path) or FileAccess.file_exists(path)
	return row


func _collect_live_resources(scene_root: Node, node: Node, resources: Dictionary, stats: Dictionary, max_live_resources: int) -> void:
	if bool(stats.get("truncated", false)):
		return
	stats["nodes"] = int(stats.get("nodes", 0)) + 1
	var node_path: String = _scene_node_path(scene_root, node)
	var script_resource: Variant = node.get_script()
	if script_resource is Resource:
		_add_live_resource(resources, script_resource, node_path, "script", stats, max_live_resources)
	for info: Dictionary in node.get_property_list():
		if bool(stats.get("truncated", false)):
			return
		var property_name: String = str(info.get("name", ""))
		if property_name == "" or property_name == "script":
			continue
		var usage: int = int(info.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		stats["properties"] = int(stats.get("properties", 0)) + 1
		var value: Variant = node.get(property_name)
		if value is Resource:
			_add_live_resource(resources, value, node_path, property_name, stats, max_live_resources)
	for child: Node in node.get_children():
		_collect_live_resources(scene_root, child, resources, stats, max_live_resources)
		if bool(stats.get("truncated", false)):
			return


func _add_live_resource(resources: Dictionary, resource: Resource, owner_path: String, property_name: String, stats: Dictionary, max_live_resources: int) -> void:
	var path: String = resource.resource_path
	if path == "":
		stats["local_resources"] = int(stats.get("local_resources", 0)) + 1
		return
	if not resources.has(path) and resources.size() >= max_live_resources:
		stats["truncated"] = true
		return
	if not resources.has(path):
		resources[path] = {
			"path": path,
			"type": resource.get_class(),
			"exists": ResourceLoader.exists(path) or FileAccess.file_exists(path),
			"owners": [],
			"owner_count": 0
		}
	var row: Dictionary = resources.get(path)
	row["owner_count"] = int(row.get("owner_count", 0)) + 1
	var owners: Array = row.get("owners", [])
	if owners.size() < 12:
		owners.append({"node": owner_path, "property": property_name})
	row["owners"] = owners
	resources[path] = row


func _resource_map_rows(resources: Dictionary) -> Array:
	var keys: Array = resources.keys()
	keys.sort()
	var rows: Array = []
	for key: Variant in keys:
		rows.append(resources.get(key))
	return rows


func _commit_property_changes(command: Dictionary, details: Dictionary, root: Node, node: Node, changes: Array, label: String, save_scene: bool, ok_message: String) -> void:
	if changes.is_empty():
		_ack(command, "error", "no supported property changes requested", details)
		return
	var undo_redo: EditorUndoRedoManager = _resolve_undo_redo()
	if undo_redo == null:
		_ack(command, "error", "EditorUndoRedoManager is unavailable", details)
		return
	var save_context: Dictionary = {}
	if save_scene:
		save_context = _prepare_scene_save(details, root)
		if save_context.get("ok", false) != true:
			_ack(command, "error", str(save_context.get("message", "scene save preparation failed; write aborted")), details)
			return
	undo_redo.create_action("Godot AI Workbench: %s %s" % [label, str(details.get("resolved_node_path", ""))], 0, root)
	for change: Dictionary in changes:
		var target: Object = change.get("target")
		var property_name: String = str(change.get("property", ""))
		if target == null or property_name == "":
			continue
		undo_redo.add_do_property(target, property_name, change.get("new"))
		undo_redo.add_undo_property(target, property_name, change.get("old"))
		if change.get("new") is Resource:
			undo_redo.add_do_reference(change.get("new"))
		if change.get("old") is Resource:
			undo_redo.add_undo_reference(change.get("old"))
	undo_redo.commit_action()
	details["status"] = "applied"
	details["changes"] = _change_summaries(changes)
	details["after"] = _audio_player_snapshot(node)
	details["affected_nodes"] = [str(details.get("resolved_node_path", ""))]
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
	_add_operation("Domain: %s %s" % [label, str(details.get("resolved_node_path", ""))])
	_ack(command, "ok", ok_message, details)


func _collect_property_arg(changes: Array, target: Object, args: Dictionary, arg_name: String, property_name: String, value_type: String) -> void:
	if not args.has(arg_name):
		return
	if not _has_property(target, property_name):
		return
	_add_property_change(changes, target, property_name, _coerce_value(args.get(arg_name), value_type, target.get(property_name)))


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


func _coerce_value(value: Variant, value_type: String, default_value: Variant) -> Variant:
	match _normalize_key(value_type):
		"bool", "boolean":
			return _bool(value, bool(default_value))
		"int", "integer":
			return _int(value, int(default_value))
		"float", "number":
			return _float(value, float(default_value))
		"string":
			return str(value)
	return value


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


func _normalize_key(value: String) -> String:
	return value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")


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
