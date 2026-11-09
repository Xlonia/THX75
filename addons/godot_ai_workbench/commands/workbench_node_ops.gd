extends RefCounted

var _host


func setup(host) -> void:
	_host = host


func handled_commands() -> Array:
	return ["editor.create_node", "editor.set_property", "editor.duplicate_node"]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"editor.create_node":
			_handle_create_node(command)
			return true
		"editor.set_property":
			_handle_set_property(command)
			return true
		"editor.duplicate_node":
			_handle_duplicate_node(command)
			return true
	return false


func _handle_create_node(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var root: Node = _edited_scene_root()
	var parent_path: String = str(args.get("parent_path", ""))
	var node_type: String = str(args.get("node_type", "")).strip_edges()
	var node_name: String = str(args.get("node_name", "")).strip_edges()
	var details: Dictionary = _write_base_details("editor.create_node")
	details["save_scene"] = save_scene
	details["parent_path"] = parent_path
	details["node_type"] = node_type
	details["node_name"] = node_name
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	if node_type == "":
		_ack(command, "error", "node_type is required", details)
		return
	if node_name == "":
		_ack(command, "error", "node_name is required", details)
		return
	if not ClassDB.class_exists(node_type) or not ClassDB.is_parent_class(node_type, "Node"):
		_ack(command, "error", "node_type must be a Godot Node class", details)
		return
	var parent: Node = _find_scene_node(root, parent_path)
	if parent == null:
		_ack(command, "error", "parent node not found", details)
		return
	if parent.get_node_or_null(NodePath(node_name)) != null:
		_ack(command, "error", "parent already has a child with this name", details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_parent_path"] = _scene_node_path(root, parent)
	details["would_change"] = true
	root = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root before apply", details)
		return
	if root.scene_file_path != str(details.get("scene_path", "")):
		details["current_scene_path"] = root.scene_file_path
		_ack(command, "error", "edited scene changed before apply", details)
		return
	parent = _find_scene_node(root, parent_path)
	if parent == null:
		_ack(command, "error", "parent node not found before apply", details)
		return
	var current_parent_path: String = _scene_node_path(root, parent)
	if current_parent_path != str(details.get("resolved_parent_path", "")):
		details["current_parent_path"] = current_parent_path
		_ack(command, "error", "parent path changed before apply", details)
		return
	if parent.get_node_or_null(NodePath(node_name)) != null:
		_ack(command, "error", "parent already has a child with this name before apply", details)
		return
	details["apply_rechecked"] = true
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
	var new_node_variant: Variant = ClassDB.instantiate(node_type)
	if not new_node_variant is Node:
		_ack(command, "error", "failed to instantiate node_type", details)
		return
	var new_node: Node = new_node_variant
	new_node.name = node_name
	undo_redo.create_action("Godot AI Workbench: create node %s/%s" % [current_parent_path, node_name], 0, root)
	undo_redo.add_do_method(parent, "add_child", new_node)
	undo_redo.add_do_method(new_node, "set_owner", root)
	undo_redo.add_undo_method(parent, "remove_child", new_node)
	undo_redo.add_do_reference(new_node)
	undo_redo.commit_action()
	details["created_path"] = _scene_node_path(root, new_node)
	details["affected_nodes"] = [details["created_path"]]
	details["status"] = "applied"
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Write save failed: create %s" % node_name)
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	else:
		details["saved"] = false
	_write_audit(details)
	_send_editor_state()
	_add_operation("Write: create %s" % node_name)
	_ack(command, "ok", "node created", details)


func _handle_duplicate_node(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var requested_name: String = str(args.get("new_name", "")).strip_edges()
	var details: Dictionary = _write_base_details("editor.duplicate_node")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save_scene"] = save_scene
	details["node_path"] = node_path
	details["requested_name"] = requested_name
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if node_path == "":
		_ack(command, "error", "node_path is required", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	if node == root:
		_ack(command, "error", "duplicating the scene root is deferred", details)
		return
	var parent: Node = node.get_parent()
	if parent == null:
		_ack(command, "error", "target node has no parent", details)
		return
	var resolved_node_path: String = _scene_node_path(root, node)
	var parent_path: String = _scene_node_path(root, parent)
	var new_name: String = requested_name
	if new_name == "":
		new_name = _unique_child_name(parent, "%sCopy" % str(node.name))
	var name_validation: Dictionary = _validate_requested_node_name(new_name)
	if name_validation.get("ok", false) != true:
		details["name_error"] = str(name_validation.get("message", "invalid duplicate name"))
		_ack(command, "error", "invalid duplicate name", details)
		return
	if parent.get_node_or_null(NodePath(new_name)) != null:
		_ack(command, "error", "parent already has a child with duplicate name", details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = resolved_node_path
	details["parent_path"] = parent_path
	details["new_name"] = new_name
	details["new_path"] = "%s/%s" % [parent_path, new_name]
	details["would_change"] = true
	root = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root before apply", details)
		return
	node = _find_scene_node(root, resolved_node_path)
	if node == null:
		_ack(command, "error", "node not found before apply", details)
		return
	parent = _find_scene_node(root, parent_path)
	if parent == null or node.get_parent() != parent:
		_ack(command, "error", "node parent changed before apply", details)
		return
	if parent.get_node_or_null(NodePath(new_name)) != null:
		_ack(command, "error", "parent already has a child with duplicate name before apply", details)
		return
	var undo_redo: EditorUndoRedoManager = _resolve_undo_redo()
	if undo_redo == null:
		_ack(command, "error", "EditorUndoRedoManager is unavailable", details)
		return
	var duplicate_flags: int = Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION
	var duplicate_value: Variant = node.duplicate(duplicate_flags)
	if not duplicate_value is Node:
		_ack(command, "error", "Godot failed to duplicate target node", details)
		return
	var duplicated_node: Node = duplicate_value
	duplicated_node.name = new_name
	var save_context: Dictionary = {}
	if save_scene:
		save_context = _prepare_scene_save(details, root)
		if save_context.get("ok", false) != true:
			_ack(command, "error", str(save_context.get("message", "scene save preparation failed; write aborted")), details)
			return
	var insert_index: int = node.get_index() + 1
	undo_redo.create_action("Godot AI Workbench: duplicate node %s -> %s" % [resolved_node_path, str(details.get("new_path", ""))], 0, root)
	undo_redo.add_do_method(parent, "add_child", duplicated_node)
	undo_redo.add_do_method(self, "_set_owner_recursive", duplicated_node, root)
	undo_redo.add_do_method(parent, "move_child", duplicated_node, insert_index)
	undo_redo.add_undo_method(parent, "remove_child", duplicated_node)
	undo_redo.add_do_reference(duplicated_node)
	undo_redo.commit_action()
	if duplicated_node.get_parent() != parent:
		_ack(command, "error", "node duplicate verification failed", details)
		return
	var created_path: String = _scene_node_path(root, duplicated_node)
	details["created_path"] = created_path
	details["affected_nodes"] = [resolved_node_path, created_path]
	details["status"] = "applied"
	details["saved"] = false
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Dev write save failed: duplicate %s" % resolved_node_path)
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Dev write: duplicate %s -> %s" % [resolved_node_path, created_path])
	_ack(command, "ok", "node duplicated", details)


func _handle_set_property(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var property_name: String = str(args.get("property_name", "")).strip_edges()
	var details: Dictionary = _write_base_details("editor.set_property")
	details["save_scene"] = save_scene
	details["node_path"] = node_path
	details["property_name"] = property_name
	if args.has("value"):
		details["requested_value"] = _variant_snapshot(args.get("value"))
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if property_name == "":
		_ack(command, "error", "property_name is required", details)
		return
	if not args.has("value"):
		_ack(command, "error", "value is required", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	var resolved_node_path: String = _scene_node_path(root, node)
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = resolved_node_path
	var property_info: Dictionary = _find_writable_property_info(node, property_name, details)
	if property_info.is_empty():
		_ack(command, "error", str(details.get("property_error", "property is not writable")), details)
		return
	var old_value: Variant = node.get(property_name)
	var parse_result: Dictionary = _parse_property_value(args.get("value"), property_info, old_value)
	if parse_result.get("ok", false) != true:
		details["property_type"] = _property_type_name(property_info, old_value)
		details["parse_error"] = str(parse_result.get("message", "value could not be parsed"))
		_ack(command, "error", "value type mismatch", details)
		return
	var new_value: Variant = parse_result.get("value")
	details["property_type"] = str(parse_result.get("type_name", _property_type_name(property_info, old_value)))
	details["old_value"] = _variant_snapshot(old_value)
	details["new_value"] = _variant_snapshot(new_value)
	details["would_change"] = not _variants_equal(old_value, new_value)
	if not _bool(details.get("would_change", false), false):
		details["status"] = "unchanged"
		_ack(command, "ok", "property already has requested value", details)
		return
	root = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root before apply", details)
		return
	if root.scene_file_path != str(details.get("scene_path", "")):
		details["current_scene_path"] = root.scene_file_path
		_ack(command, "error", "edited scene changed before apply", details)
		return
	node = _find_scene_node(root, resolved_node_path)
	if node == null:
		_ack(command, "error", "node not found before apply", details)
		return
	property_info = _find_writable_property_info(node, property_name, details)
	if property_info.is_empty():
		_ack(command, "error", str(details.get("property_error", "property is not writable before apply")), details)
		return
	var current_value: Variant = node.get(property_name)
	if not _variants_equal(current_value, old_value):
		details["current_value"] = _variant_snapshot(current_value)
		_ack(command, "error", "property changed before apply", details)
		return
	details["apply_rechecked"] = true
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
	undo_redo.create_action("Godot AI Workbench: set property %s.%s" % [resolved_node_path, property_name], 0, root)
	undo_redo.add_do_property(node, property_name, new_value)
	undo_redo.add_undo_property(node, property_name, old_value)
	undo_redo.commit_action()
	var applied_value: Variant = node.get(property_name)
	if not _variants_equal(applied_value, new_value):
		details["applied_value"] = _variant_snapshot(applied_value)
		_ack(command, "error", "property apply verification failed", details)
		return
	details["applied_value"] = _variant_snapshot(applied_value)
	details["affected_nodes"] = [resolved_node_path]
	details["status"] = "applied"
	details["saved"] = false
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Write save failed: set %s.%s" % [resolved_node_path, property_name])
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	else:
		details["saved"] = false
	_write_audit(details)
	_send_editor_state()
	_add_operation("Write: set %s.%s" % [resolved_node_path, property_name])
	_ack(command, "ok", "property set", details)


func _edited_scene_root() -> Node:
	var editor_interface: Variant = _host.call("editor_interface")
	if editor_interface != null:
		return editor_interface.get_edited_scene_root()
	return null


func _dict(value: Variant) -> Dictionary:
	var result: Variant = _host.call("workbench_dictionary", value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _bool(value: Variant, default_value: bool) -> bool:
	return bool(_host.call("workbench_bool", value, default_value))


func _write_gate_open() -> bool:
	return bool(_host.call("write_gate_open"))


func _write_base_details(action: String) -> Dictionary:
	var result: Variant = _host.call("write_base_details", action)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"action": action}


func _find_scene_node(root: Node, path: String) -> Node:
	var result: Variant = _host.call("find_scene_node", root, path)
	if result is Node:
		return result
	return null


func _resolve_write_target_node(root: Node, node_path: String, details: Dictionary) -> Node:
	var result: Variant = _host.call("resolve_write_target_node", root, node_path, details)
	if result is Node:
		return result
	return null


func _scene_node_path(root: Node, node: Node) -> String:
	return str(_host.call("workbench_scene_node_path", root, node))


func _find_writable_property_info(node: Node, property_name: String, details: Dictionary) -> Dictionary:
	var result: Variant = _host.call("find_writable_property_info", node, property_name, details)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _parse_property_value(raw_value: Variant, property_info: Dictionary, old_value: Variant) -> Dictionary:
	var result: Variant = _host.call("parse_property_value", raw_value, property_info, old_value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"ok": false, "message": "property parser did not return a result"}


func _variant_snapshot(value: Variant) -> Dictionary:
	var result: Variant = _host.call("variant_snapshot", value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"type": "Variant", "value": str(value)}


func _variants_equal(left: Variant, right: Variant) -> bool:
	return bool(_host.call("variants_equal", left, right))


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


func _set_owner_recursive(node: Node, owner: Node) -> void:
	if node == null:
		return
	node.owner = owner
	for child: Node in node.get_children():
		_set_owner_recursive(child, owner)


func _unique_child_name(parent: Node, preferred_name: String) -> String:
	var clean_name: String = preferred_name.strip_edges()
	if clean_name == "":
		clean_name = "DuplicatedNode"
	if parent == null or parent.get_node_or_null(NodePath(clean_name)) == null:
		return clean_name
	var index := 2
	while index < 10000:
		var candidate := "%s%d" % [clean_name, index]
		if parent.get_node_or_null(NodePath(candidate)) == null:
			return candidate
		index += 1
	return "%s%d" % [clean_name, Time.get_ticks_msec()]


func _validate_requested_node_name(node_name: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "message": ""}
	if node_name == "":
		result["message"] = "node name is required"
		return result
	if node_name == "." or node_name == "..":
		result["message"] = "node name must not be a path segment"
		return result
	if node_name.length() > 80:
		result["message"] = "node name is too long"
		return result
	if node_name.begins_with("@"):
		result["message"] = "node name must not use Godot internal auto-name prefix"
		return result
	var blocked: Array[String] = ["/", "\\", ":", "%", "\n", "\r", "\t"]
	for item: String in blocked:
		if node_name.contains(item):
			result["message"] = "node name contains a blocked character"
			result["blocked"] = item
			return result
	result["ok"] = true
	result["message"] = "node name ok"
	return result
