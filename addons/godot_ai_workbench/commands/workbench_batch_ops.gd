extends RefCounted

var _host
var _editor_interface
const BATCH_OPERATION_LIMIT := 64


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return ["editor.batch_operations"]


func handle(command: Dictionary) -> bool:
	if str(command.get("command", "")) != "editor.batch_operations":
		return false
	_handle_batch_operations(command)
	return true


func _handle_batch_operations(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var operations: Array = _array(args.get("operations", []))
	var details: Dictionary = _host.call("write_base_details", "editor.batch_operations")
	details["operation_count"] = operations.size()
	if not _host.call("write_gate_open"):
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if operations.is_empty():
		_ack(command, "error", "operations must contain at least one operation", details)
		return
	if operations.size() > BATCH_OPERATION_LIMIT:
		_ack(command, "error", "batch supports at most %d operations in v0" % BATCH_OPERATION_LIMIT, details)
		return
	var root: Node = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	details["scene_path"] = root.scene_file_path
	var plan: Dictionary = _plan_operations(root, operations)
	details["steps"] = _array(plan.get("steps", []))
	details["would_change"] = _bool(plan.get("would_change", false), false)
	if plan.get("ok", false) != true:
		details["failed_index"] = int(plan.get("failed_index", -1))
		_ack(command, "error", str(plan.get("message", "batch validation failed")), details)
		return
	var undo_redo = _host.call("resolve_undo_redo")
	if undo_redo == null:
		_ack(command, "error", "EditorUndoRedoManager is unavailable", details)
		return
	var change_entries: Array = []
	var apply_steps: Array = []
	var affected_nodes: Array = []
	var affected_files: Array = []
	for index: int in range(operations.size()):
		var operation: Dictionary = _dict(operations[index])
		var apply_result: Dictionary = _apply_operation(root, operation, index)
		var step: Dictionary = _dict(apply_result.get("step", {}))
		apply_steps.append(step)
		if apply_result.get("ok", false) != true:
			details["steps"] = apply_steps
			details["failed_index"] = index
			details["status"] = "partial" if change_entries.size() > 0 else "error"
			details["changed_count"] = change_entries.size()
			_host.call("write_audit", details)
			_host.call("send_editor_state")
			_ack(command, "error", str(apply_result.get("message", "batch apply failed")), details)
			return
		for entry_value: Variant in _array(apply_result.get("change_entries", [])):
			change_entries.append(entry_value)
		for node_value: Variant in _array(step.get("affected_nodes", [])):
			var node_path: String = str(node_value)
			if not affected_nodes.has(node_path):
				affected_nodes.append(node_path)
		for file_value: Variant in _array(step.get("affected_files", [])):
			var file_path: String = str(file_value)
			if not affected_files.has(file_path):
				affected_files.append(file_path)
	var undo_result: Dictionary = _register_undo(root, change_entries)
	if undo_result.get("ok", false) != true:
		details["steps"] = apply_steps
		details["status"] = "error"
		details["changed_count"] = change_entries.size()
		_ack(command, "error", str(undo_result.get("message", "batch undo registration failed")), details)
		return
	details["steps"] = apply_steps
	details["affected_nodes"] = affected_nodes
	details["affected_files"] = affected_files
	details["changed_count"] = change_entries.size()
	details["status"] = "applied" if change_entries.size() > 0 else "unchanged"
	details["saved"] = false
	_host.call("write_audit", details)
	_host.call("send_editor_state")
	_host.call("add_operation", "Write: batch %d operations" % operations.size())
	_ack(command, "ok", "batch operations applied", details)


func _plan_operations(root: Node, operations: Array) -> Dictionary:
	var result: Dictionary = {"ok": true, "steps": [], "would_change": false}
	var planned_nodes: Dictionary = {}
	var steps: Array = []
	for index: int in range(operations.size()):
		var operation: Dictionary = _dict(operations[index])
		var tool_name: String = _operation_name(operation)
		var operation_args: Dictionary = _operation_args(operation)
		var step: Dictionary = {"index": index, "tool": tool_name}
		var validation: Dictionary = _validate_common(tool_name, operation_args)
		if validation.get("ok", false) != true:
			return _plan_failure(result, steps, step, index, str(validation.get("message", "invalid batch operation")))
		match tool_name:
			"editor.create_node":
				validation = _plan_create_node(root, operation_args, planned_nodes)
			"editor.set_property":
				validation = _plan_set_property(root, operation_args, planned_nodes)
			"editor.attach_script":
				validation = _plan_attach_script(root, operation_args, planned_nodes)
			_:
				validation = {"ok": false, "message": "operation is not supported by Godot-side batch v1"}
		if validation.get("ok", false) != true:
			return _plan_failure(result, steps, step, index, str(validation.get("message", "batch operation failed validation")))
		for key: Variant in validation.keys():
			if str(key) != "temp_node":
				step[str(key)] = validation[key]
		step["status"] = "planned"
		steps.append(step)
		if _bool(validation.get("would_change", false), false):
			result["would_change"] = true
		if tool_name == "editor.create_node":
			var planned_path: String = str(validation.get("created_path", ""))
			if planned_path != "" and validation.has("temp_node"):
				planned_nodes[planned_path] = validation.get("temp_node")
	result["steps"] = steps
	return result


func _plan_failure(result: Dictionary, steps: Array, step: Dictionary, index: int, message: String) -> Dictionary:
	step["status"] = "error"
	step["message"] = message
	steps.append(step)
	result["ok"] = false
	result["failed_index"] = index
	result["message"] = message
	result["steps"] = steps
	return result


func _validate_common(tool_name: String, operation_args: Dictionary) -> Dictionary:
	if not _supported_tool(tool_name):
		return {"ok": false, "message": "unsupported batch operation: %s" % tool_name}
	if operation_args.is_empty():
		return {"ok": false, "message": "operation arguments are required"}
	for blocked_key: String in ["status_url", "control_url", "token"]:
		if operation_args.has(blocked_key):
			return {"ok": false, "message": "operation must not include %s" % blocked_key}
	if _bool(operation_args.get("save_scene", false), false):
		return {"ok": false, "message": "save_scene=true is not supported inside batch; save separately"}
	return {"ok": true}


func _supported_tool(tool_name: String) -> bool:
	return ["editor.create_node", "editor.set_property", "editor.attach_script"].has(tool_name)


func _operation_name(operation: Dictionary) -> String:
	var tool_name: String = str(operation.get("tool", "")).strip_edges()
	if tool_name == "":
		tool_name = str(operation.get("command", "")).strip_edges()
	return tool_name


func _operation_args(operation: Dictionary) -> Dictionary:
	if operation.has("arguments"):
		return _dict(operation.get("arguments", {}))
	return _dict(operation.get("args", {}))


func _plan_create_node(root: Node, operation_args: Dictionary, planned_nodes: Dictionary) -> Dictionary:
	var parent_path: String = str(operation_args.get("parent_path", "")).strip_edges()
	var node_type: String = str(operation_args.get("node_type", "")).strip_edges()
	var node_name: String = str(operation_args.get("node_name", "")).strip_edges()
	if node_type == "":
		return {"ok": false, "message": "node_type is required"}
	if node_name == "":
		return {"ok": false, "message": "node_name is required"}
	if not ClassDB.class_exists(node_type) or not ClassDB.is_parent_class(node_type, "Node"):
		return {"ok": false, "message": "node_type must be a Godot Node class"}
	var parent: Node = _lookup_node(root, parent_path, planned_nodes)
	if parent == null:
		return {"ok": false, "message": "parent node not found"}
	var created_path: String = _child_path(root, parent_path, node_name)
	if planned_nodes.has(created_path):
		return {"ok": false, "message": "batch already plans a node at %s" % created_path}
	if not planned_nodes.has(_normalized_node_path(root, parent_path)) and parent.get_node_or_null(NodePath(node_name)) != null:
		return {"ok": false, "message": "parent already has a child with this name"}
	var node_variant: Variant = ClassDB.instantiate(node_type)
	if not node_variant is Node:
		return {"ok": false, "message": "failed to instantiate node_type"}
	var temp_node: Node = node_variant
	temp_node.name = node_name
	return {
		"ok": true,
		"would_change": true,
		"parent_path": parent_path,
		"resolved_parent_path": _normalized_node_path(root, parent_path),
		"node_type": node_type,
		"node_name": node_name,
		"created_path": created_path,
		"affected_nodes": [created_path],
		"temp_node": temp_node
	}


func _plan_set_property(root: Node, operation_args: Dictionary, planned_nodes: Dictionary) -> Dictionary:
	var node_path: String = str(operation_args.get("node_path", "")).strip_edges()
	var property_name: String = str(operation_args.get("property_name", "")).strip_edges()
	if node_path == "":
		return {"ok": false, "message": "node_path is required inside batch"}
	if property_name == "":
		return {"ok": false, "message": "property_name is required"}
	if not operation_args.has("value"):
		return {"ok": false, "message": "value is required"}
	var resolved_path: String = _normalized_node_path(root, node_path)
	var node: Node = _lookup_node(root, node_path, planned_nodes)
	if node == null:
		return {"ok": false, "message": "node not found"}
	var property_details: Dictionary = {}
	var property_info: Dictionary = _host.call("find_writable_property_info", node, property_name, property_details)
	if property_info.is_empty():
		return {"ok": false, "message": str(property_details.get("property_error", "property is not writable"))}
	var old_value: Variant = node.get(property_name)
	var parse_result: Dictionary = _host.call("parse_property_value", operation_args.get("value"), property_info, old_value)
	if parse_result.get("ok", false) != true:
		return {"ok": false, "message": str(parse_result.get("message", "value type mismatch"))}
	var new_value: Variant = parse_result.get("value")
	var would_change: bool = not _host.call("variants_equal", old_value, new_value)
	if planned_nodes.has(resolved_path):
		node.set(property_name, new_value)
	return {
		"ok": true,
		"would_change": would_change,
		"node_path": node_path,
		"resolved_node_path": resolved_path,
		"property_name": property_name,
		"property_type": str(parse_result.get("type_name", _host.call("property_type_name", property_info, old_value))),
		"old_value": _host.call("variant_snapshot", old_value),
		"new_value": _host.call("variant_snapshot", new_value),
		"affected_nodes": [resolved_path]
	}


func _plan_attach_script(root: Node, operation_args: Dictionary, planned_nodes: Dictionary) -> Dictionary:
	var node_path: String = str(operation_args.get("node_path", "")).strip_edges()
	var script_path: String = str(operation_args.get("script_path", "")).strip_edges()
	if node_path == "":
		return {"ok": false, "message": "node_path is required inside batch"}
	if script_path == "":
		return {"ok": false, "message": "script_path is required"}
	var script_path_result: Dictionary = _host.call("validate_script_resource_path", script_path)
	if script_path_result.get("ok", false) != true:
		return {"ok": false, "message": str(script_path_result.get("message", "invalid script path"))}
	script_path = str(script_path_result.get("path", script_path))
	var script_scan: Dictionary = _request_resource_filesystem_scan(script_path)
	var loaded_script: Variant = ResourceLoader.load(script_path, "Script", ResourceLoader.CACHE_MODE_REPLACE)
	if not loaded_script is Script:
		return {"ok": false, "message": "resource did not load as Script"}
	var script_resource: Script = loaded_script
	var resolved_path: String = _normalized_node_path(root, node_path)
	var node: Node = _lookup_node(root, node_path, planned_nodes)
	if node == null:
		return {"ok": false, "message": "node not found"}
	var compatibility: Dictionary = _host.call("script_compatibility", node, script_resource)
	if compatibility.get("ok", false) != true:
		return {"ok": false, "message": str(compatibility.get("message", "script is not compatible with node"))}
	var old_script: Variant = node.get_script()
	var would_change: bool = not _host.call("scripts_equal", old_script, script_resource)
	if planned_nodes.has(resolved_path):
		node.set_script(script_resource)
	return {
		"ok": true,
		"would_change": would_change,
		"node_path": node_path,
		"resolved_node_path": resolved_path,
		"script_path": script_path,
		"script_resource_scan": script_scan,
		"old_script": _host.call("script_snapshot", old_script),
		"new_script": _host.call("script_snapshot", script_resource),
		"affected_nodes": [resolved_path],
		"affected_files": [script_path]
	}


func _apply_operation(root: Node, operation: Dictionary, index: int) -> Dictionary:
	var tool_name: String = _operation_name(operation)
	var operation_args: Dictionary = _operation_args(operation)
	match tool_name:
		"editor.create_node":
			return _apply_create_node(root, operation_args, index)
		"editor.set_property":
			return _apply_set_property(root, operation_args, index)
		"editor.attach_script":
			return _apply_attach_script(root, operation_args, index)
	return {"ok": false, "message": "unsupported batch operation: %s" % tool_name, "step": {"index": index, "tool": tool_name, "status": "error"}}


func _apply_create_node(root: Node, operation_args: Dictionary, index: int) -> Dictionary:
	var parent_path: String = str(operation_args.get("parent_path", "")).strip_edges()
	var node_type: String = str(operation_args.get("node_type", "")).strip_edges()
	var node_name: String = str(operation_args.get("node_name", "")).strip_edges()
	var step: Dictionary = {"index": index, "tool": "editor.create_node", "parent_path": parent_path, "node_type": node_type, "node_name": node_name}
	var parent: Node = _host.call("find_scene_node", root, parent_path)
	if parent == null:
		return {"ok": false, "message": "parent node not found", "step": step}
	if parent.get_node_or_null(NodePath(node_name)) != null:
		return {"ok": false, "message": "parent already has a child with this name", "step": step}
	var node_variant: Variant = ClassDB.instantiate(node_type)
	if not node_variant is Node:
		return {"ok": false, "message": "failed to instantiate node_type", "step": step}
	var new_node: Node = node_variant
	new_node.name = node_name
	parent.add_child(new_node)
	new_node.set_owner(root)
	var created_path: String = _host.call("workbench_scene_node_path", root, new_node)
	step["status"] = "applied"
	step["created_path"] = created_path
	step["affected_nodes"] = [created_path]
	return {
		"ok": true,
		"step": step,
		"change_entries": [{
			"kind": "create_node",
			"node": new_node,
			"parent": parent,
			"owner": root,
			"node_path": created_path
		}]
	}


func _apply_set_property(root: Node, operation_args: Dictionary, index: int) -> Dictionary:
	var node_path: String = str(operation_args.get("node_path", "")).strip_edges()
	var property_name: String = str(operation_args.get("property_name", "")).strip_edges()
	var step: Dictionary = {"index": index, "tool": "editor.set_property", "node_path": node_path, "property_name": property_name}
	var node: Node = _host.call("find_scene_node", root, node_path)
	if node == null:
		return {"ok": false, "message": "node not found", "step": step}
	var resolved_path: String = _host.call("workbench_scene_node_path", root, node)
	var property_details: Dictionary = {}
	var property_info: Dictionary = _host.call("find_writable_property_info", node, property_name, property_details)
	if property_info.is_empty():
		return {"ok": false, "message": str(property_details.get("property_error", "property is not writable")), "step": step}
	var old_value: Variant = node.get(property_name)
	var parse_result: Dictionary = _host.call("parse_property_value", operation_args.get("value"), property_info, old_value)
	if parse_result.get("ok", false) != true:
		return {"ok": false, "message": str(parse_result.get("message", "value type mismatch")), "step": step}
	var new_value: Variant = parse_result.get("value")
	step["resolved_node_path"] = resolved_path
	step["property_type"] = str(parse_result.get("type_name", _host.call("property_type_name", property_info, old_value)))
	step["old_value"] = _host.call("variant_snapshot", old_value)
	step["new_value"] = _host.call("variant_snapshot", new_value)
	step["affected_nodes"] = [resolved_path]
	if _host.call("variants_equal", old_value, new_value):
		step["status"] = "unchanged"
		return {"ok": true, "step": step, "change_entries": []}
	node.set(property_name, new_value)
	var applied_value: Variant = node.get(property_name)
	if not _host.call("variants_equal", applied_value, new_value):
		step["applied_value"] = _host.call("variant_snapshot", applied_value)
		return {"ok": false, "message": "property apply verification failed", "step": step}
	step["status"] = "applied"
	step["applied_value"] = _host.call("variant_snapshot", applied_value)
	return {
		"ok": true,
		"step": step,
		"change_entries": [{
			"kind": "set_property",
			"node": node,
			"node_path": resolved_path,
			"property_name": property_name,
			"old_value": old_value,
			"new_value": applied_value
		}]
	}


func _apply_attach_script(root: Node, operation_args: Dictionary, index: int) -> Dictionary:
	var node_path: String = str(operation_args.get("node_path", "")).strip_edges()
	var script_path: String = str(operation_args.get("script_path", "")).strip_edges()
	var step: Dictionary = {"index": index, "tool": "editor.attach_script", "node_path": node_path, "script_path": script_path}
	var node: Node = _host.call("find_scene_node", root, node_path)
	if node == null:
		return {"ok": false, "message": "node not found", "step": step}
	var script_path_result: Dictionary = _host.call("validate_script_resource_path", script_path)
	if script_path_result.get("ok", false) != true:
		return {"ok": false, "message": str(script_path_result.get("message", "invalid script path")), "step": step}
	script_path = str(script_path_result.get("path", script_path))
	step["script_resource_scan"] = _request_resource_filesystem_scan(script_path)
	var loaded_script: Variant = ResourceLoader.load(script_path, "Script", ResourceLoader.CACHE_MODE_REPLACE)
	if not loaded_script is Script:
		return {"ok": false, "message": "resource did not load as Script", "step": step}
	var script_resource: Script = loaded_script
	var compatibility: Dictionary = _host.call("script_compatibility", node, script_resource)
	if compatibility.get("ok", false) != true:
		return {"ok": false, "message": str(compatibility.get("message", "script is not compatible with node")), "step": step}
	var old_script: Variant = node.get_script()
	var resolved_path: String = _host.call("workbench_scene_node_path", root, node)
	step["resolved_node_path"] = resolved_path
	step["script_path"] = script_path
	step["old_script"] = _host.call("script_snapshot", old_script)
	step["new_script"] = _host.call("script_snapshot", script_resource)
	step["affected_nodes"] = [resolved_path]
	step["affected_files"] = [script_path]
	if _host.call("scripts_equal", old_script, script_resource):
		step["status"] = "unchanged"
		return {"ok": true, "step": step, "change_entries": []}
	node.set_script(script_resource)
	var applied_script: Variant = node.get_script()
	if not _host.call("scripts_equal", applied_script, script_resource):
		step["applied_script"] = _host.call("script_snapshot", applied_script)
		return {"ok": false, "message": "script attach verification failed", "step": step}
	step["status"] = "applied"
	step["applied_script"] = _host.call("script_snapshot", applied_script)
	return {
		"ok": true,
		"step": step,
		"change_entries": [{
			"kind": "attach_script",
			"node": node,
			"node_path": resolved_path,
			"old_script": old_script,
			"new_script": applied_script
		}]
	}


func _register_undo(root: Node, change_entries: Array) -> Dictionary:
	if change_entries.is_empty():
		return {"ok": true, "registered": false}
	var undo_redo = _host.call("resolve_undo_redo")
	if undo_redo == null:
		return {"ok": false, "message": "EditorUndoRedoManager is unavailable"}
	undo_redo.create_action("Godot AI Workbench: batch operations %d changes" % change_entries.size(), 0, root)
	for entry_value: Variant in change_entries:
		var entry: Dictionary = _dict(entry_value)
		match str(entry.get("kind", "")):
			"create_node":
				var created_node_value: Variant = entry.get("node", null)
				var parent_value: Variant = entry.get("parent", null)
				if created_node_value is Node and parent_value is Node:
					var created_node: Node = created_node_value
					var parent: Node = parent_value
					undo_redo.add_do_method(parent, "add_child", created_node)
					undo_redo.add_do_method(created_node, "set_owner", root)
					undo_redo.add_undo_method(parent, "remove_child", created_node)
					undo_redo.add_do_reference(created_node)
			"set_property":
				var property_node_value: Variant = entry.get("node", null)
				if property_node_value is Node:
					var property_node: Node = property_node_value
					var property_name: String = str(entry.get("property_name", ""))
					undo_redo.add_do_property(property_node, property_name, entry.get("new_value"))
					undo_redo.add_undo_property(property_node, property_name, entry.get("old_value"))
			"attach_script":
				var script_node_value: Variant = entry.get("node", null)
				if script_node_value is Node:
					var script_node: Node = script_node_value
					var new_script: Variant = entry.get("new_script")
					var old_script: Variant = entry.get("old_script")
					undo_redo.add_do_method(script_node, "set_script", new_script)
					undo_redo.add_undo_method(script_node, "set_script", old_script)
					if new_script is Script:
						undo_redo.add_do_reference(new_script)
					if old_script is Script:
						undo_redo.add_undo_reference(old_script)
	undo_redo.commit_action(false)
	return {"ok": true, "registered": true}


func _lookup_node(root: Node, node_path: String, planned_nodes: Dictionary) -> Node:
	var normalized_path: String = _normalized_node_path(root, node_path)
	if planned_nodes.has(normalized_path):
		var planned_value: Variant = planned_nodes.get(normalized_path)
		if planned_value is Node:
			return planned_value
	return _host.call("find_scene_node", root, node_path)


func _normalized_node_path(root: Node, node_path: String) -> String:
	var clean_path: String = node_path.strip_edges()
	if root == null:
		return clean_path
	if clean_path == "" or clean_path == "." or clean_path == str(root.name):
		return str(root.name)
	var root_prefix := "%s/" % str(root.name)
	if clean_path.begins_with(root_prefix):
		return clean_path
	return "%s/%s" % [str(root.name), clean_path]


func _child_path(root: Node, parent_path: String, node_name: String) -> String:
	var normalized_parent: String = _normalized_node_path(root, parent_path)
	if normalized_parent == "":
		return node_name
	return "%s/%s" % [normalized_parent, node_name]


func _ack(command: Dictionary, status: String, message: String, details: Dictionary) -> void:
	_host.call("ack_dev_command", command, status, message, details)


func _array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _request_resource_filesystem_scan(path: String) -> Dictionary:
	if _host != null and _host.has_method("request_resource_filesystem_scan"):
		var result: Variant = _host.call("request_resource_filesystem_scan", path)
		if typeof(result) == TYPE_DICTIONARY:
			return result
	return {"ok": false, "path": path, "message": "resource filesystem scan helper is unavailable"}


func _bool(value: Variant, default_value: bool) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value == true
		TYPE_INT:
			return int(value) != 0
		TYPE_FLOAT:
			return float(value) != 0.0
		TYPE_STRING:
			var text := str(value).strip_edges().to_lower()
			if text == "true" or text == "1" or text == "yes":
				return true
			if text == "false" or text == "0" or text == "no":
				return false
	return default_value
