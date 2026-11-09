extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"editor.inspect_node",
		"signal.connect",
		"signal.disconnect",
		"editor.add_node_to_group",
		"editor.remove_node_from_group"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"editor.inspect_node":
			_handle_inspect_node(command)
			return true
		"signal.connect":
			_handle_signal_connect(command)
			return true
		"signal.disconnect":
			_handle_signal_disconnect(command)
			return true
		"editor.add_node_to_group":
			_handle_group_add(command)
			return true
		"editor.remove_node_from_group":
			_handle_group_remove(command)
			return true
	return false


func _handle_inspect_node(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var include_properties: bool = _bool(args.get("include_properties", true), true)
	var include_values: bool = _bool(args.get("include_values", true), true)
	var include_signals: bool = _bool(args.get("include_signals", true), true)
	var include_connections: bool = _bool(args.get("include_connections", true), true)
	var include_groups: bool = _bool(args.get("include_groups", true), true)
	var max_properties: int = int(clamp(_int(args.get("max_properties", 80), 80), 1, 500))
	var max_signals: int = int(clamp(_int(args.get("max_signals", 80), 80), 1, 300))
	var details: Dictionary = _read_base_details("editor.inspect_node")
	details["native_godot_api"] = true
	details["node_path"] = node_path
	details["include_properties"] = include_properties
	details["include_values"] = include_values
	details["include_signals"] = include_signals
	details["include_connections"] = include_connections
	details["include_groups"] = include_groups
	details["max_properties"] = max_properties
	details["max_signals"] = max_signals
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	var resolved_node_path: String = _scene_node_path(root, node)
	details["scene_path"] = root.scene_file_path
	details["node"] = _node_snapshot(root, node)
	details["resolved_node_path"] = resolved_node_path
	if include_groups:
		details["groups"] = _node_groups(node)
	if include_properties:
		details["properties"] = _property_metadata(node, max_properties, include_values)
	if include_signals:
		details["signals"] = _signal_metadata(root, node, max_signals, include_connections)
	_add_operation("Read: inspect node %s" % resolved_node_path)
	_ack(command, "ok", "node inspected", details)


func _handle_signal_connect(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var source_path: String = str(args.get("source_path", args.get("node_path", ""))).strip_edges()
	var signal_name: String = str(args.get("signal_name", "")).strip_edges()
	var target_path: String = str(args.get("target_path", "")).strip_edges()
	var method_name: String = str(args.get("method_name", "")).strip_edges()
	var flags: int = _int(args.get("flags", 0), 0)
	var details: Dictionary = _write_base_details("signal.connect")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save_scene"] = save_scene
	details["source_path"] = source_path
	details["signal_name"] = signal_name
	details["target_path"] = target_path
	details["method_name"] = method_name
	details["flags"] = flags
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var plan: Dictionary = _signal_plan(source_path, signal_name, target_path, method_name, details)
	if plan.get("ok", false) != true:
		_ack(command, "error", str(plan.get("message", "signal connection plan failed")), details)
		return
	var source: Node = plan.get("source")
	var target: Node = plan.get("target")
	var callable: Callable = Callable(target, method_name)
	if source.is_connected(signal_name, callable):
		details["status"] = "unchanged"
		details["would_change"] = false
		_ack(command, "ok", "signal already connected", details)
		return
	details["would_change"] = true
	var root: Node = _edited_scene_root()
	if root == null or root.scene_file_path != str(details.get("scene_path", "")):
		_ack(command, "error", "edited scene changed before apply", details)
		return
	source = _find_scene_node(root, str(details.get("resolved_source_path", "")))
	target = _find_scene_node(root, str(details.get("resolved_target_path", "")))
	if source == null or target == null:
		_ack(command, "error", "source or target node missing before apply", details)
		return
	callable = Callable(target, method_name)
	if source.is_connected(signal_name, callable):
		details["status"] = "unchanged"
		_ack(command, "ok", "signal already connected before apply", details)
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
	undo_redo.create_action("Godot AI Workbench: connect signal %s.%s -> %s.%s" % [str(details.get("resolved_source_path", "")), signal_name, str(details.get("resolved_target_path", "")), method_name], 0, root)
	undo_redo.add_do_method(source, "connect", signal_name, callable, flags)
	undo_redo.add_undo_method(source, "disconnect", signal_name, callable)
	undo_redo.commit_action()
	if not source.is_connected(signal_name, callable):
		_ack(command, "error", "signal connect verification failed", details)
		return
	details["status"] = "applied"
	details["saved"] = false
	details["affected_nodes"] = [str(details.get("resolved_source_path", "")), str(details.get("resolved_target_path", ""))]
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_send_editor_state()
			_add_operation("Dev write save failed: connect signal %s.%s" % [str(details.get("resolved_source_path", "")), signal_name])
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Dev write: connect signal %s.%s -> %s.%s" % [str(details.get("resolved_source_path", "")), signal_name, str(details.get("resolved_target_path", "")), method_name])
	_ack(command, "ok", "signal connected", details)


func _handle_signal_disconnect(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var source_path: String = str(args.get("source_path", args.get("node_path", ""))).strip_edges()
	var signal_name: String = str(args.get("signal_name", "")).strip_edges()
	var target_path: String = str(args.get("target_path", "")).strip_edges()
	var method_name: String = str(args.get("method_name", "")).strip_edges()
	var details: Dictionary = _write_base_details("signal.disconnect")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save_scene"] = save_scene
	details["source_path"] = source_path
	details["signal_name"] = signal_name
	details["target_path"] = target_path
	details["method_name"] = method_name
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var plan: Dictionary = _signal_plan(source_path, signal_name, target_path, method_name, details)
	if plan.get("ok", false) != true:
		_ack(command, "error", str(plan.get("message", "signal disconnect plan failed")), details)
		return
	var source: Node = plan.get("source")
	var target: Node = plan.get("target")
	var callable: Callable = Callable(target, method_name)
	var connection: Dictionary = _find_signal_connection(source, signal_name, callable)
	if connection.is_empty():
		details["status"] = "unchanged"
		details["would_change"] = false
		_ack(command, "ok", "signal is not connected", details)
		return
	var flags: int = _int(connection.get("flags", 0), 0)
	details["flags"] = flags
	details["would_change"] = true
	var root: Node = _edited_scene_root()
	if root == null or root.scene_file_path != str(details.get("scene_path", "")):
		_ack(command, "error", "edited scene changed before apply", details)
		return
	source = _find_scene_node(root, str(details.get("resolved_source_path", "")))
	target = _find_scene_node(root, str(details.get("resolved_target_path", "")))
	if source == null or target == null:
		_ack(command, "error", "source or target node missing before apply", details)
		return
	callable = Callable(target, method_name)
	if not source.is_connected(signal_name, callable):
		details["status"] = "unchanged"
		_ack(command, "ok", "signal already disconnected before apply", details)
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
	undo_redo.create_action("Godot AI Workbench: disconnect signal %s.%s -> %s.%s" % [str(details.get("resolved_source_path", "")), signal_name, str(details.get("resolved_target_path", "")), method_name], 0, root)
	undo_redo.add_do_method(source, "disconnect", signal_name, callable)
	undo_redo.add_undo_method(source, "connect", signal_name, callable, flags)
	undo_redo.commit_action()
	if source.is_connected(signal_name, callable):
		_ack(command, "error", "signal disconnect verification failed", details)
		return
	details["status"] = "applied"
	details["saved"] = false
	details["affected_nodes"] = [str(details.get("resolved_source_path", "")), str(details.get("resolved_target_path", ""))]
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_send_editor_state()
			_add_operation("Dev write save failed: disconnect signal %s.%s" % [str(details.get("resolved_source_path", "")), signal_name])
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Dev write: disconnect signal %s.%s -> %s.%s" % [str(details.get("resolved_source_path", "")), signal_name, str(details.get("resolved_target_path", "")), method_name])
	_ack(command, "ok", "signal disconnected", details)


func _handle_group_add(command: Dictionary) -> void:
	_handle_group_change(command, true)


func _handle_group_remove(command: Dictionary) -> void:
	_handle_group_change(command, false)


func _handle_group_change(command: Dictionary, add_group: bool) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var command_name: String = "editor.add_node_to_group"
	if not add_group:
		command_name = "editor.remove_node_from_group"
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var group_name: String = str(args.get("group_name", "")).strip_edges()
	var persistent: bool = _bool(args.get("persistent", true), true)
	var details: Dictionary = _write_base_details(command_name)
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save_scene"] = save_scene
	details["node_path"] = node_path
	details["group_name"] = group_name
	details["persistent"] = persistent
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if _valid_group_name(group_name) != true:
		_ack(command, "error", "group_name is required and must not contain path/control characters", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	var resolved_node_path: String = _scene_node_path(root, node)
	var already_in_group: bool = node.is_in_group(group_name)
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = resolved_node_path
	details["already_in_group"] = already_in_group
	details["would_change"] = (add_group and not already_in_group) or ((not add_group) and already_in_group)
	if not _bool(details.get("would_change", false), false):
		details["status"] = "unchanged"
		_ack(command, "ok", "node group already matches request", details)
		return
	root = _edited_scene_root()
	if root == null or root.scene_file_path != str(details.get("scene_path", "")):
		_ack(command, "error", "edited scene changed before apply", details)
		return
	node = _find_scene_node(root, resolved_node_path)
	if node == null:
		_ack(command, "error", "node missing before apply", details)
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
	var action_label: String = "Godot AI Workbench: add group %s -> %s" % [group_name, resolved_node_path]
	if not add_group:
		action_label = "Godot AI Workbench: remove group %s -> %s" % [group_name, resolved_node_path]
	undo_redo.create_action(action_label, 0, root)
	if add_group:
		undo_redo.add_do_method(node, "add_to_group", group_name, persistent)
		undo_redo.add_undo_method(node, "remove_from_group", group_name)
	else:
		undo_redo.add_do_method(node, "remove_from_group", group_name)
		undo_redo.add_undo_method(node, "add_to_group", group_name, persistent)
	undo_redo.commit_action()
	var now_in_group: bool = node.is_in_group(group_name)
	if add_group and not now_in_group:
		_ack(command, "error", "group add verification failed", details)
		return
	if (not add_group) and now_in_group:
		_ack(command, "error", "group remove verification failed", details)
		return
	details["status"] = "applied"
	details["saved"] = false
	details["affected_nodes"] = [resolved_node_path]
	details["groups"] = _node_groups(node)
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_send_editor_state()
			_add_operation("Dev write save failed: group %s on %s" % [group_name, resolved_node_path])
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	if add_group:
		_add_operation("Dev write: add group %s -> %s" % [group_name, resolved_node_path])
		_ack(command, "ok", "node added to group", details)
	else:
		_add_operation("Dev write: remove group %s -> %s" % [group_name, resolved_node_path])
		_ack(command, "ok", "node removed from group", details)


func _signal_plan(source_path: String, signal_name: String, target_path: String, method_name: String, details: Dictionary) -> Dictionary:
	if signal_name == "":
		return {"ok": false, "message": "signal_name is required"}
	if target_path == "":
		return {"ok": false, "message": "target_path is required"}
	if method_name == "":
		return {"ok": false, "message": "method_name is required"}
	var root: Node = _edited_scene_root()
	if root == null:
		return {"ok": false, "message": "no edited scene root"}
	var source: Node = _resolve_target_node(root, source_path, details)
	if source == null:
		return {"ok": false, "message": str(details.get("target_error", "source node not found"))}
	var target: Node = _find_scene_node(root, target_path)
	if target == null:
		return {"ok": false, "message": "target node not found"}
	if not source.has_signal(signal_name):
		details["available_signals"] = _signal_names(source)
		return {"ok": false, "message": "source node does not expose signal_name"}
	if not target.has_method(method_name):
		return {"ok": false, "message": "target node does not expose method_name"}
	details["scene_path"] = root.scene_file_path
	details["resolved_source_path"] = _scene_node_path(root, source)
	details["resolved_target_path"] = _scene_node_path(root, target)
	return {"ok": true, "source": source, "target": target}


func _find_signal_connection(source: Node, signal_name: String, callable: Callable) -> Dictionary:
	for connection_value: Variant in source.get_signal_connection_list(signal_name):
		if typeof(connection_value) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = connection_value
		var candidate: Variant = connection.get("callable")
		if candidate is Callable and candidate == callable:
			return connection
	return {}


func _property_metadata(node: Node, max_properties: int, include_values: bool) -> Dictionary:
	var items: Array[Dictionary] = []
	var total := 0
	for property_value: Variant in node.get_property_list():
		if typeof(property_value) != TYPE_DICTIONARY:
			continue
		total += 1
		if items.size() >= max_properties:
			continue
		var property_info: Dictionary = property_value
		var name: String = str(property_info.get("name", ""))
		var item: Dictionary = {
			"name": name,
			"type": int(property_info.get("type", TYPE_NIL)),
			"type_name": _property_type_name(property_info, node.get(name)),
			"hint": int(property_info.get("hint", 0)),
			"hint_string": str(property_info.get("hint_string", "")),
			"usage": int(property_info.get("usage", 0)),
			"class_name": str(property_info.get("class_name", "")),
			"writable": _property_writable(property_info),
			"editor_visible": _property_editor_visible(property_info),
			"storage": _property_storage(property_info)
		}
		if include_values and name != "":
			item["value"] = _variant_snapshot(node.get(name))
		items.append(item)
	return {
		"total": total,
		"returned": items.size(),
		"truncated": total > items.size(),
		"items": items
	}


func _signal_metadata(root: Node, node: Node, max_signals: int, include_connections: bool) -> Dictionary:
	var items: Array[Dictionary] = []
	var total := 0
	for signal_value: Variant in node.get_signal_list():
		if typeof(signal_value) != TYPE_DICTIONARY:
			continue
		total += 1
		if items.size() >= max_signals:
			continue
		var signal_info: Dictionary = signal_value
		var signal_name: String = str(signal_info.get("name", ""))
		var item: Dictionary = {
			"name": signal_name,
			"args": _signal_args(signal_info),
			"default_args": _workbench_array(signal_info.get("default_args", [])),
			"flags": int(signal_info.get("flags", 0))
		}
		if include_connections:
			item["connections"] = _signal_connections(root, node, signal_name)
		items.append(item)
	return {
		"total": total,
		"returned": items.size(),
		"truncated": total > items.size(),
		"items": items
	}


func _signal_args(signal_info: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for arg_value: Variant in _workbench_array(signal_info.get("args", [])):
		if typeof(arg_value) != TYPE_DICTIONARY:
			continue
		var arg: Dictionary = arg_value
		result.append({
			"name": str(arg.get("name", "")),
			"type": int(arg.get("type", TYPE_NIL)),
			"type_name": _property_type_name(arg, null),
			"hint": int(arg.get("hint", 0)),
			"hint_string": str(arg.get("hint_string", "")),
			"usage": int(arg.get("usage", 0))
		})
	return result


func _signal_connections(root: Node, node: Node, signal_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for connection_value: Variant in node.get_signal_connection_list(signal_name):
		if typeof(connection_value) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = connection_value
		var item: Dictionary = {
			"flags": int(connection.get("flags", 0))
		}
		var callable_value: Variant = connection.get("callable")
		if callable_value is Callable:
			var callable: Callable = callable_value
			item["method"] = str(callable.get_method())
			var target_object: Object = callable.get_object()
			if target_object is Node:
				item["target_path"] = _scene_node_path(root, target_object)
				item["target_name"] = str(target_object.name)
				item["target_type"] = target_object.get_class()
			else:
				item["target_path"] = ""
				item["target_type"] = str(target_object)
		result.append(item)
	return result


func _node_snapshot(root: Node, node: Node) -> Dictionary:
	var parent_path := ""
	if node != root and node.get_parent() != null:
		parent_path = _scene_node_path(root, node.get_parent())
	return {
		"path": _scene_node_path(root, node),
		"name": str(node.name),
		"type": node.get_class(),
		"parent": parent_path,
		"owner": _node_owner_path(root, node),
		"script": _script_snapshot(node.get_script())
	}


func _node_groups(node: Node) -> Array[String]:
	var groups: Array[String] = []
	for group_value: Variant in node.get_groups():
		var group_name: String = str(group_value)
		if group_name == "":
			continue
		groups.append(group_name)
	groups.sort()
	return groups


func _signal_names(node: Node) -> Array[String]:
	var result: Array[String] = []
	for signal_value: Variant in node.get_signal_list():
		if typeof(signal_value) != TYPE_DICTIONARY:
			continue
		var signal_info: Dictionary = signal_value
		result.append(str(signal_info.get("name", "")))
	result.sort()
	return result


func _script_snapshot(script_value: Variant) -> Dictionary:
	if script_value is Script:
		var script: Script = script_value
		return {
			"has_script": true,
			"path": script.resource_path,
			"class": script.get_class()
		}
	return {"has_script": false}


func _property_writable(property_info: Dictionary) -> bool:
	var usage: int = int(property_info.get("usage", 0))
	return (usage & PROPERTY_USAGE_READ_ONLY) == 0


func _property_editor_visible(property_info: Dictionary) -> bool:
	var usage: int = int(property_info.get("usage", 0))
	return (usage & PROPERTY_USAGE_EDITOR) != 0


func _property_storage(property_info: Dictionary) -> bool:
	var usage: int = int(property_info.get("usage", 0))
	return (usage & PROPERTY_USAGE_STORAGE) != 0


func _valid_group_name(group_name: String) -> bool:
	if group_name == "":
		return false
	var blocked: Array[String] = ["/", "\\", ":", "\n", "\r", "\t"]
	for item: String in blocked:
		if group_name.contains(item):
			return false
	return true


func _node_owner_path(root: Node, node: Node) -> String:
	if node == null or node.owner == null:
		return ""
	return _scene_node_path(root, node.owner)


func _edited_scene_root() -> Node:
	if _editor_interface != null:
		return _editor_interface.get_edited_scene_root()
	return null


func _resolve_target_node(root: Node, node_path: String, details: Dictionary) -> Node:
	var result: Variant = _host.call("resolve_write_target_node", root, node_path, details)
	if result is Node:
		return result
	return null


func _find_scene_node(root: Node, path: String) -> Node:
	var result: Variant = _host.call("find_scene_node", root, path)
	if result is Node:
		return result
	return null


func _scene_node_path(root: Node, node: Node) -> String:
	return str(_host.call("workbench_scene_node_path", root, node))


func _dict(value: Variant) -> Dictionary:
	var result: Variant = _host.call("workbench_dictionary", value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _workbench_array(value: Variant) -> Array:
	var result: Variant = _host.call("workbench_array", value)
	if typeof(result) == TYPE_ARRAY:
		return result
	return []


func _bool(value: Variant, default_value: bool) -> bool:
	return bool(_host.call("workbench_bool", value, default_value))


func _int(value: Variant, default_value: int) -> int:
	return int(_host.call("workbench_int", value, default_value))


func _read_base_details(action: String) -> Dictionary:
	return {
		"action": action,
		"profile": str(_host.call("selected_profile_id")),
		"captured_at": Time.get_datetime_string_from_system(false, true)
	}


func _write_gate_open() -> bool:
	return bool(_host.call("write_gate_open"))


func _write_base_details(action: String) -> Dictionary:
	var result: Variant = _host.call("write_base_details", action)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"action": action}


func _variant_snapshot(value: Variant) -> Dictionary:
	var result: Variant = _host.call("variant_snapshot", value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"type": "Variant", "value": str(value)}


func _property_type_name(property_info: Dictionary, old_value: Variant) -> String:
	return str(_host.call("property_type_name", property_info, old_value))


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
