extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"domain.animation_tree",
		"domain.raycast_config"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"domain.animation_tree":
			_handle_animation_tree(command)
			return true
		"domain.raycast_config":
			_handle_raycast_config(command)
			return true
	return false


func _handle_animation_tree(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "inspect")))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.animation_tree")
	_mark_native(details, ["AnimationTree", "AnimationNodeStateMachine", "AnimationNodeAnimation", "AnimationNodeStateMachineTransition", "EditorUndoRedoManager"])
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
	if not node is AnimationTree:
		_ack(command, "error", "target node must be AnimationTree", details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["animation_tree"] = _animation_tree_snapshot(node, _int(args.get("max_items", 80), 80))
	if action == "inspect":
		_add_operation("Domain: animation tree inspect %s" % str(details.get("resolved_node_path", "")))
		_ack(command, "ok", "AnimationTree inspected", details)
		return
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if not ["set", "ensure_state_machine"].has(action):
		_ack(command, "error", "action must be inspect, set or ensure_state_machine", details)
		return
	var changes: Array = []
	if args.has("active") and _has_property(node, "active"):
		_add_property_change(changes, node, "active", _bool(args.get("active", false), false))
	if args.has("anim_player") and _has_property(node, "anim_player"):
		_add_property_change(changes, node, "anim_player", NodePath(str(args.get("anim_player", ""))))
	var root_kind: String = _normalize_key(str(args.get("root_kind", "")))
	if action == "ensure_state_machine":
		root_kind = "state_machine"
	if root_kind != "":
		var root_change: Dictionary = _tree_root_change(node, args, root_kind, details)
		if root_change.get("ok", false) != true:
			_ack(command, "error", str(root_change.get("message", "failed to prepare tree_root")), details)
			return
		var tree_root_value: Variant = root_change.get("value")
		if tree_root_value is Resource:
			_add_property_change(changes, node, "tree_root", tree_root_value)
			details["tree_root_plan"] = root_change.get("summary", {})
	_collect_animation_parameter_changes(changes, node, args)
	_commit_property_changes(command, details, root, node, changes, "animation tree", save_scene, "AnimationTree updated")


func _handle_raycast_config(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "inspect")))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.raycast_config")
	_mark_native(details, ["RayCast2D", "RayCast3D", "EditorUndoRedoManager"])
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
	if not (node is RayCast2D or node is RayCast3D):
		_ack(command, "error", "target node must be RayCast2D or RayCast3D", details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["raycast"] = _raycast_snapshot(node)
	if action == "inspect":
		_add_operation("Domain: raycast inspect %s" % str(details.get("resolved_node_path", "")))
		_ack(command, "ok", "RayCast inspected", details)
		return
	if action != "set":
		_ack(command, "error", "action must be inspect or set", details)
		return
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var changes: Array = []
	if args.has("target_position") and _has_property(node, "target_position"):
		if node is RayCast3D:
			_add_property_change(changes, node, "target_position", _vector3(args.get("target_position"), node.get("target_position")))
		else:
			_add_property_change(changes, node, "target_position", _vector2(args.get("target_position"), node.get("target_position")))
	_collect_property_arg(changes, node, args, "enabled", "enabled", "bool")
	_collect_property_arg(changes, node, args, "collision_mask", "collision_mask", "int")
	_collect_property_arg(changes, node, args, "exclude_parent", "exclude_parent", "bool")
	_collect_property_arg(changes, node, args, "collide_with_areas", "collide_with_areas", "bool")
	_collect_property_arg(changes, node, args, "collide_with_bodies", "collide_with_bodies", "bool")
	_collect_property_arg(changes, node, args, "hit_from_inside", "hit_from_inside", "bool")
	_commit_property_changes(command, details, root, node, changes, "raycast config", save_scene, "RayCast updated")


func _tree_root_change(tree: AnimationTree, args: Dictionary, root_kind: String, details: Dictionary) -> Dictionary:
	var old_root: Variant = tree.get("tree_root")
	var next_root: Resource = null
	var summary: Dictionary = {"root_kind": root_kind}
	match root_kind:
		"state_machine", "statemachine":
			if old_root is AnimationNodeStateMachine:
				var duplicate_root: Resource = old_root.duplicate(true)
				if duplicate_root is AnimationNodeStateMachine:
					next_root = duplicate_root
			if next_root == null:
				next_root = AnimationNodeStateMachine.new()
			var plan: Dictionary = _apply_state_machine_plan(next_root, args)
			if plan.get("ok", false) != true:
				return plan
			summary["state_machine"] = plan
		"blend_tree", "blendtree":
			if old_root is AnimationNodeBlendTree:
				var duplicate_blend: Resource = old_root.duplicate(true)
				if duplicate_blend is AnimationNodeBlendTree:
					next_root = duplicate_blend
			if next_root == null:
				next_root = AnimationNodeBlendTree.new()
		"none", "clear":
			next_root = null
		_:
			return {"ok": false, "message": "root_kind must be state_machine, blend_tree or none"}
	return {
		"ok": true,
		"value": next_root,
		"summary": summary
	}


func _apply_state_machine_plan(state_machine: Resource, args: Dictionary) -> Dictionary:
	var summary: Dictionary = {"ok": true, "added_states": [], "added_transitions": []}
	if args.has("states"):
		var states: Array = _array(args.get("states", []))
		if states.size() > 32:
			return {"ok": false, "message": "states supports at most 32 items"}
		for item: Variant in states:
			var state_args: Dictionary = _dict(item)
			var state_name: String = str(state_args.get("name", "")).strip_edges()
			if state_name == "":
				return {"ok": false, "message": "state name is required"}
			if state_machine.has_method("has_node") and bool(state_machine.call("has_node", state_name)):
				continue
			var state_node := AnimationNodeAnimation.new()
			if state_args.has("animation") and _has_property(state_node, "animation"):
				state_node.set("animation", str(state_args.get("animation", "")))
			var position: Vector2 = _vector2(state_args.get("position", {}), Vector2.ZERO)
			if state_machine.has_method("add_node"):
				state_machine.call("add_node", state_name, state_node, position)
				summary["added_states"].append({"name": state_name, "animation": str(state_args.get("animation", "")), "position": _bounded_value(position)})
	if args.has("transitions"):
		var transitions: Array = _array(args.get("transitions", []))
		if transitions.size() > 64:
			return {"ok": false, "message": "transitions supports at most 64 items"}
		for item: Variant in transitions:
			var transition_args: Dictionary = _dict(item)
			var from_state: String = str(transition_args.get("from", "")).strip_edges()
			var to_state: String = str(transition_args.get("to", "")).strip_edges()
			if from_state == "" or to_state == "":
				return {"ok": false, "message": "transition requires from and to"}
			if state_machine.has_method("add_transition"):
				var transition := AnimationNodeStateMachineTransition.new()
				for property_name: String in ["xfade_time", "advance_condition", "advance_expression", "reset"]:
					if transition_args.has(property_name) and _has_property(transition, property_name):
						transition.set(property_name, transition_args.get(property_name))
				state_machine.call("add_transition", from_state, to_state, transition)
				summary["added_transitions"].append({"from": from_state, "to": to_state})
	return summary


func _collect_animation_parameter_changes(changes: Array, tree: AnimationTree, args: Dictionary) -> void:
	if not args.has("parameters"):
		return
	var parameters: Dictionary = _dict(args.get("parameters", {}))
	for key: Variant in parameters.keys():
		var parameter_name: String = str(key).strip_edges()
		if parameter_name == "":
			continue
		if not parameter_name.begins_with("parameters/"):
			parameter_name = "parameters/%s" % parameter_name
		if _has_property(tree, parameter_name):
			_add_property_change(changes, tree, parameter_name, parameters.get(key))


func _animation_tree_snapshot(tree: AnimationTree, max_items: int) -> Dictionary:
	var result: Dictionary = {
		"type": tree.get_class(),
		"active": tree.active if _has_property(tree, "active") else null,
		"anim_player": str(tree.get("anim_player")) if _has_property(tree, "anim_player") else "",
		"tree_root": _resource_snapshot(tree.get("tree_root")),
		"parameters": []
	}
	var count: int = 0
	for info: Dictionary in tree.get_property_list():
		var name: String = str(info.get("name", ""))
		if name.begins_with("parameters/"):
			if count >= max_items:
				break
			result["parameters"].append({"name": name, "value": _bounded_value(tree.get(name))})
			count += 1
	result["parameters_truncated"] = count >= max_items
	var root: Variant = tree.get("tree_root")
	if root is AnimationNodeStateMachine:
		result["state_machine"] = _state_machine_snapshot(root, max_items)
	return result


func _state_machine_snapshot(state_machine: AnimationNodeStateMachine, max_items: int) -> Dictionary:
	var result: Dictionary = {"type": state_machine.get_class(), "states": [], "transitions": []}
	if state_machine.has_method("get_node_list"):
		var names: Array = _array(state_machine.call("get_node_list"))
		var count: int = 0
		for state_name: Variant in names:
			if count >= max_items:
				break
			var state: Variant = null
			if state_machine.has_method("get_node"):
				state = state_machine.call("get_node", state_name)
			result["states"].append({"name": str(state_name), "node": _resource_snapshot(state)})
			count += 1
		result["states_truncated"] = names.size() > max_items
	if state_machine.has_method("get_transition_count"):
		var transition_count: int = int(state_machine.call("get_transition_count"))
		var count: int = min(transition_count, max_items)
		for index: int in range(count):
			var row: Dictionary = {"index": index}
			if state_machine.has_method("get_transition_from"):
				row["from"] = str(state_machine.call("get_transition_from", index))
			if state_machine.has_method("get_transition_to"):
				row["to"] = str(state_machine.call("get_transition_to", index))
			if state_machine.has_method("get_transition"):
				row["transition"] = _resource_snapshot(state_machine.call("get_transition", index))
			result["transitions"].append(row)
		result["transitions_truncated"] = transition_count > max_items
	return result


func _raycast_snapshot(node: Node) -> Dictionary:
	var names: Array = ["enabled", "target_position", "collision_mask", "exclude_parent", "collide_with_areas", "collide_with_bodies", "hit_from_inside"]
	var result: Dictionary = {"type": node.get_class()}
	for name: String in names:
		if _has_property(node, name):
			result[name] = _bounded_value(node.get(name))
	if node.has_method("is_colliding"):
		result["is_colliding"] = bool(node.call("is_colliding"))
	return result


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
		"vector2":
			return _vector2(value, default_value if typeof(default_value) == TYPE_VECTOR2 else Vector2.ZERO)
		"vector3":
			return _vector3(value, default_value if typeof(default_value) == TYPE_VECTOR3 else Vector3.ZERO)
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


func _array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_STRING_ARRAY:
		var result: Array = []
		for item: Variant in value:
			result.append(item)
		return result
	return []


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


func _vector3(value: Variant, default_value: Vector3) -> Vector3:
	if typeof(value) == TYPE_VECTOR3:
		return value
	if typeof(value) == TYPE_VECTOR3I:
		var vector_i: Vector3i = value
		return Vector3(vector_i.x, vector_i.y, vector_i.z)
	if typeof(value) == TYPE_ARRAY:
		var items: Array = value
		if items.size() >= 3:
			return Vector3(_float(items[0], default_value.x), _float(items[1], default_value.y), _float(items[2], default_value.z))
	if typeof(value) == TYPE_DICTIONARY:
		var map: Dictionary = value
		return Vector3(_float(map.get("x", default_value.x), default_value.x), _float(map.get("y", default_value.y), default_value.y), _float(map.get("z", default_value.z), default_value.z))
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
