extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"domain.control_setup"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"domain.control_setup":
			_handle_control_setup(command)
			return true
	return false


func _handle_control_setup(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "inspect")))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.control_setup")
	_mark_native(details, ["Control", "Label", "Button", "LineEdit", "EditorUndoRedoManager"])
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
	if not node is Control:
		_ack(command, "error", "target node must be a Control", details)
		return
	var control: Control = node
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["control"] = _control_snapshot(control)
	if action == "inspect":
		_add_operation("Domain: control inspect %s" % str(details.get("resolved_node_path", "")))
		_ack(command, "ok", "Control inspected", details)
		return
	if action != "set":
		_ack(command, "error", "action must be inspect or set", details)
		return
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var changes: Array = []
	if args.has("anchor_preset"):
		_collect_anchor_preset_changes(changes, control, str(args.get("anchor_preset", "")), args, details)
	if args.has("anchors"):
		_collect_box_changes(changes, control, _dict(args.get("anchors", {})), "anchor", ["left", "top", "right", "bottom"])
	if args.has("offsets"):
		_collect_box_changes(changes, control, _dict(args.get("offsets", {})), "offset", ["left", "top", "right", "bottom"])
	if args.has("position") and _has_property(control, "position"):
		_add_property_change(changes, control, "position", _vector2(args.get("position"), control.position))
	if args.has("size") and _has_property(control, "size"):
		_add_property_change(changes, control, "size", _vector2(args.get("size"), control.size))
	if args.has("custom_minimum_size") and _has_property(control, "custom_minimum_size"):
		_add_property_change(changes, control, "custom_minimum_size", _vector2(args.get("custom_minimum_size"), control.custom_minimum_size))
	_collect_property_arg(changes, control, args, "visible", "visible", "bool")
	_collect_property_arg(changes, control, args, "clip_contents", "clip_contents", "bool")
	_collect_property_arg(changes, control, args, "mouse_filter", "mouse_filter", "int")
	_collect_property_arg(changes, control, args, "focus_mode", "focus_mode", "int")
	_collect_property_arg(changes, control, args, "layout_direction", "layout_direction", "int")
	_collect_property_arg(changes, control, args, "disabled", "disabled", "bool")
	_collect_property_arg(changes, control, args, "text", "text", "string")
	_collect_property_arg(changes, control, args, "placeholder_text", "placeholder_text", "string")
	_collect_property_arg(changes, control, args, "tooltip_text", "tooltip_text", "string")
	_collect_property_arg(changes, control, args, "theme_type_variation", "theme_type_variation", "string")
	_commit_control_changes(command, details, root, control, changes, save_scene)


func _collect_anchor_preset_changes(changes: Array, control: Control, preset_value: String, args: Dictionary, details: Dictionary) -> void:
	var preset: String = _normalize_key(preset_value)
	details["anchor_preset"] = preset
	match preset:
		"full_rect", "full", "fill":
			_add_property_change(changes, control, "anchor_left", 0.0)
			_add_property_change(changes, control, "anchor_top", 0.0)
			_add_property_change(changes, control, "anchor_right", 1.0)
			_add_property_change(changes, control, "anchor_bottom", 1.0)
			_add_property_change(changes, control, "offset_left", 0.0)
			_add_property_change(changes, control, "offset_top", 0.0)
			_add_property_change(changes, control, "offset_right", 0.0)
			_add_property_change(changes, control, "offset_bottom", 0.0)
		"top_left", "top-left":
			_add_property_change(changes, control, "anchor_left", 0.0)
			_add_property_change(changes, control, "anchor_top", 0.0)
			_add_property_change(changes, control, "anchor_right", 0.0)
			_add_property_change(changes, control, "anchor_bottom", 0.0)
		"center", "centered":
			var wanted_size: Vector2 = control.size
			if args.has("size"):
				wanted_size = _vector2(args.get("size"), control.size)
			_add_property_change(changes, control, "anchor_left", 0.5)
			_add_property_change(changes, control, "anchor_top", 0.5)
			_add_property_change(changes, control, "anchor_right", 0.5)
			_add_property_change(changes, control, "anchor_bottom", 0.5)
			_add_property_change(changes, control, "offset_left", -wanted_size.x / 2.0)
			_add_property_change(changes, control, "offset_top", -wanted_size.y / 2.0)
			_add_property_change(changes, control, "offset_right", wanted_size.x / 2.0)
			_add_property_change(changes, control, "offset_bottom", wanted_size.y / 2.0)
		"":
			return
		_:
			details["anchor_preset_warning"] = "unsupported anchor_preset; use full_rect, top_left or center"


func _collect_box_changes(changes: Array, control: Control, values: Dictionary, prefix: String, names: Array) -> void:
	for name: String in names:
		if not values.has(name):
			continue
		var property_name: String = "%s_%s" % [prefix, name]
		if _has_property(control, property_name):
			_add_property_change(changes, control, property_name, _float(values.get(name), float(control.get(property_name))))


func _commit_control_changes(command: Dictionary, details: Dictionary, root: Node, control: Control, changes: Array, save_scene: bool) -> void:
	if changes.is_empty():
		_ack(command, "error", "no supported Control property changes requested", details)
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
	undo_redo.create_action("Godot AI Workbench: control setup %s" % str(details.get("resolved_node_path", "")), 0, root)
	for change: Dictionary in changes:
		var target: Object = change.get("target")
		var property_name: String = str(change.get("property", ""))
		if target == null or property_name == "":
			continue
		undo_redo.add_do_property(target, property_name, change.get("new"))
		undo_redo.add_undo_property(target, property_name, change.get("old"))
	undo_redo.commit_action()
	details["status"] = "applied"
	details["changes"] = _change_summaries(changes)
	details["after"] = _control_snapshot(control)
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
	_add_operation("Domain: control setup %s" % str(details.get("resolved_node_path", "")))
	_ack(command, "ok", "Control updated", details)


func _control_snapshot(control: Control) -> Dictionary:
	var result: Dictionary = {
		"type": control.get_class(),
		"anchors": {
			"left": control.anchor_left,
			"top": control.anchor_top,
			"right": control.anchor_right,
			"bottom": control.anchor_bottom
		},
		"offsets": {
			"left": control.offset_left,
			"top": control.offset_top,
			"right": control.offset_right,
			"bottom": control.offset_bottom
		},
		"position": _bounded_value(control.position),
		"size": _bounded_value(control.size),
		"custom_minimum_size": _bounded_value(control.custom_minimum_size)
	}
	for name: String in ["visible", "clip_contents", "mouse_filter", "focus_mode", "layout_direction", "disabled", "text", "placeholder_text", "tooltip_text", "theme_type_variation"]:
		if _has_property(control, name):
			result[name] = _bounded_value(control.get(name))
	return result


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
		"vector2":
			return _vector2(value, default_value if typeof(default_value) == TYPE_VECTOR2 else Vector2.ZERO)
		"string":
			return str(value)
	return value


func _bounded_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_COLOR:
			return value.to_html()
		TYPE_OBJECT:
			if value is Resource:
				return {"type": value.get_class(), "path": value.resource_path}
			if value is Object:
				return {"type": value.get_class()}
	return value


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


func _vector2(value: Variant, default_value: Vector2) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_VECTOR2I:
		var vector_i: Vector2i = value
		return Vector2(vector_i.x, vector_i.y)
	if typeof(value) == TYPE_ARRAY:
		var items: Array = value
		if items.size() >= 2:
			return Vector2(_float(items[0], default_value.x), _float(items[1], default_value.y))
	if typeof(value) == TYPE_DICTIONARY:
		var map: Dictionary = value
		return Vector2(_float(map.get("x", default_value.x), default_value.x), _float(map.get("y", default_value.y), default_value.y))
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
