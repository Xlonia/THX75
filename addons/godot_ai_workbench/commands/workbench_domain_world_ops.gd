extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"domain.animation_info",
		"domain.navigation_config",
		"domain.particles_config",
		"domain.scene3d_helper"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"domain.animation_info":
			_handle_animation_info(command)
			return true
		"domain.navigation_config":
			_handle_navigation_config(command)
			return true
		"domain.particles_config":
			_handle_particles_config(command)
			return true
		"domain.scene3d_helper":
			_handle_scene3d_helper(command)
			return true
	return false


func _handle_animation_info(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var max_tracks: int = int(clamp(_int(args.get("max_tracks", 32), 32), 0, 200))
	var max_keys: int = int(clamp(_int(args.get("max_keys", 8), 8), 0, 100))
	var details: Dictionary = _read_base_details("domain.animation_info")
	_mark_native(details, ["AnimationPlayer", "AnimationTree", "AnimationLibrary", "Animation"])
	details["node_path"] = node_path
	details["max_tracks"] = max_tracks
	details["max_keys"] = max_keys
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	if node is AnimationPlayer:
		details["animation_player"] = _animation_player_snapshot(node, max_tracks, max_keys)
	elif node is AnimationTree:
		details["animation_tree"] = _animation_tree_snapshot(node, max_tracks)
	else:
		_ack(command, "error", "target node must be AnimationPlayer or AnimationTree", details)
		return
	_add_operation("Domain: animation info %s" % str(details.get("resolved_node_path", "")))
	_ack(command, "ok", "animation info inspected", details)


func _handle_navigation_config(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "set")))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.navigation_config")
	_mark_native(details, ["NavigationAgent2D", "NavigationAgent3D", "NavigationRegion2D", "NavigationRegion3D", "EditorUndoRedoManager"])
	details["action_mode"] = action
	details["node_path"] = node_path
	details["save_scene"] = save_scene
	if action != "inspect" and not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	if not _is_navigation_node(node):
		_ack(command, "error", "target node must be a NavigationAgent or NavigationRegion", details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["navigation"] = _navigation_snapshot(node)
	if action == "inspect":
		_add_operation("Domain: navigation inspect %s" % str(details.get("resolved_node_path", "")))
		_ack(command, "ok", "navigation inspected", details)
		return
	var changes: Array[Dictionary] = []
	_collect_property_arg(changes, node, args, "navigation_layers", "navigation_layers", "int")
	_collect_property_arg(changes, node, args, "enabled", "enabled", "bool")
	_collect_property_arg(changes, node, args, "use_edge_connections", "use_edge_connections", "bool")
	_collect_property_arg(changes, node, args, "enter_cost", "enter_cost", "float")
	_collect_property_arg(changes, node, args, "travel_cost", "travel_cost", "float")
	_collect_property_arg(changes, node, args, "path_desired_distance", "path_desired_distance", "float")
	_collect_property_arg(changes, node, args, "target_desired_distance", "target_desired_distance", "float")
	_collect_property_arg(changes, node, args, "path_max_distance", "path_max_distance", "float")
	_collect_property_arg(changes, node, args, "radius", "radius", "float")
	_collect_property_arg(changes, node, args, "neighbor_distance", "neighbor_distance", "float")
	_collect_property_arg(changes, node, args, "max_speed", "max_speed", "float")
	_collect_property_arg(changes, node, args, "avoidance_enabled", "avoidance_enabled", "bool")
	_collect_property_arg(changes, node, args, "debug_enabled", "debug_enabled", "bool")
	if args.has("target_position") and _has_property(node, "target_position"):
		_add_property_change(changes, node, "target_position", _typed_vector_for_node(args.get("target_position"), node))
	if _bool(args.get("ensure_region_resource", false), false):
		if node is NavigationRegion2D and _has_property(node, "navigation_polygon") and node.get("navigation_polygon") == null:
			_add_property_change(changes, node, "navigation_polygon", NavigationPolygon.new())
		if node is NavigationRegion3D and _has_property(node, "navigation_mesh") and node.get("navigation_mesh") == null:
			_add_property_change(changes, node, "navigation_mesh", NavigationMesh.new())
	_commit_property_changes(command, details, root, node, changes, "navigation config", save_scene, "navigation updated")


func _handle_particles_config(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "set")))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.particles_config")
	_mark_native(details, ["GPUParticles2D", "GPUParticles3D", "CPUParticles2D", "CPUParticles3D", "ParticleProcessMaterial", "EditorUndoRedoManager"])
	details["action_mode"] = action
	details["node_path"] = node_path
	details["save_scene"] = save_scene
	if action != "inspect" and not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	if not _is_particles_node(node):
		_ack(command, "error", "target node must be a Godot particles node", details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["particles"] = _particles_snapshot(node)
	if action == "inspect":
		_add_operation("Domain: particles inspect %s" % str(details.get("resolved_node_path", "")))
		_ack(command, "ok", "particles inspected", details)
		return
	var changes: Array[Dictionary] = []
	_collect_property_arg(changes, node, args, "emitting", "emitting", "bool")
	_collect_property_arg(changes, node, args, "amount", "amount", "int")
	_collect_property_arg(changes, node, args, "amount_ratio", "amount_ratio", "float")
	_collect_property_arg(changes, node, args, "lifetime", "lifetime", "float")
	_collect_property_arg(changes, node, args, "one_shot", "one_shot", "bool")
	_collect_property_arg(changes, node, args, "speed_scale", "speed_scale", "float")
	_collect_property_arg(changes, node, args, "explosiveness", "explosiveness", "float")
	_collect_property_arg(changes, node, args, "randomness", "randomness", "float")
	_collect_property_arg(changes, node, args, "fixed_fps", "fixed_fps", "int")
	_collect_property_arg(changes, node, args, "preprocess", "preprocess", "float")
	_collect_property_arg(changes, node, args, "use_local_coordinates", "use_local_coordinates", "bool")
	_collect_property_arg(changes, node, args, "interp_to_end", "interp_to_end", "float")
	_collect_particles_material_change(changes, node, args, details)
	_commit_property_changes(command, details, root, node, changes, "particles config", save_scene, "particles updated")


func _handle_scene3d_helper(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "set")))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var max_cells: int = int(clamp(_int(args.get("max_cells", 64), 64), 1, 512))
	var details: Dictionary = _write_base_details("domain.scene3d_helper")
	_mark_native(details, ["Node3D", "MeshInstance3D", "Light3D", "Camera3D", "WorldEnvironment", "Environment", "GridMap", "EditorUndoRedoManager"])
	details["action_mode"] = action
	details["node_path"] = node_path
	details["max_cells"] = max_cells
	details["save_scene"] = save_scene
	if action not in ["inspect", "grid_get", "grid_used"] and not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	if not (node is Node3D or node.get_class() == "GridMap" or node is WorldEnvironment):
		_ack(command, "error", "target node must be Node3D, GridMap or WorldEnvironment", details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["scene3d"] = _scene3d_snapshot(node, max_cells)
	if action == "inspect":
		_add_operation("Domain: 3D inspect %s" % str(details.get("resolved_node_path", "")))
		_ack(command, "ok", "3D node inspected", details)
		return
	if action == "grid_get":
		if node.get_class() != "GridMap":
			_ack(command, "error", "grid_get requires a GridMap node", details)
			return
		details["cell"] = _gridmap_cell_info(node, _vector3i(args.get("coords", args.get("cell", {"x": 0, "y": 0, "z": 0})), Vector3i.ZERO))
		_ack(command, "ok", "GridMap cell read", details)
		return
	if action == "grid_used":
		if node.get_class() != "GridMap":
			_ack(command, "error", "grid_used requires a GridMap node", details)
			return
		details["used_cells"] = _gridmap_used_cells(node, max_cells)
		_ack(command, "ok", "GridMap used cells read", details)
		return
	if action == "grid_set" or action == "grid_clear":
		_handle_gridmap_write(command, details, root, node, args, action, save_scene)
		return
	var changes: Array[Dictionary] = []
	if node is Node3D:
		if args.has("position"):
			_add_property_change(changes, node, "position", _vector3(args.get("position"), node.position))
		if args.has("rotation_degrees"):
			_add_property_change(changes, node, "rotation_degrees", _vector3(args.get("rotation_degrees"), node.rotation_degrees))
		if args.has("scale"):
			_add_property_change(changes, node, "scale", _vector3(args.get("scale"), node.scale))
	if node is MeshInstance3D and args.has("mesh_kind"):
		_add_property_change(changes, node, "mesh", _new_mesh(str(args.get("mesh_kind", "box"))))
	_collect_property_arg(changes, node, args, "light_energy", "light_energy", "float")
	_collect_property_arg(changes, node, args, "light_color", "light_color", "color")
	_collect_property_arg(changes, node, args, "shadow_enabled", "shadow_enabled", "bool")
	_collect_property_arg(changes, node, args, "current", "current", "bool")
	_collect_property_arg(changes, node, args, "fov", "fov", "float")
	_collect_property_arg(changes, node, args, "near", "near", "float")
	_collect_property_arg(changes, node, args, "far", "far", "float")
	_collect_property_arg(changes, node, args, "cell_size", "cell_size", "vector3")
	_collect_property_arg(changes, node, args, "cell_scale", "cell_scale", "float")
	if node is WorldEnvironment:
		_collect_environment_changes(changes, node, args, details)
	_commit_property_changes(command, details, root, node, changes, "3D helper", save_scene, "3D node updated")


func _handle_gridmap_write(command: Dictionary, details: Dictionary, root: Node, node: Node, args: Dictionary, action: String, save_scene: bool) -> void:
	if node.get_class() != "GridMap":
		_ack(command, "error", "%s requires a GridMap node" % action, details)
		return
	var coords: Vector3i = _vector3i(args.get("coords", args.get("cell", {"x": 0, "y": 0, "z": 0})), Vector3i.ZERO)
	var next_item: int = -1 if action == "grid_clear" else _int(args.get("item", args.get("item_id", 0)), 0)
	var next_orientation: int = _int(args.get("orientation", 0), 0)
	var previous: Dictionary = _gridmap_cell_info(node, coords)
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
	undo_redo.create_action("Godot AI Workbench: GridMap %s %s" % [action, str(details.get("resolved_node_path", ""))], 0, root)
	undo_redo.add_do_method(self, "_gridmap_set_cell_native", node, coords, next_item, next_orientation)
	undo_redo.add_undo_method(self, "_gridmap_set_cell_native", node, coords, int(previous.get("item", -1)), int(previous.get("orientation", 0)))
	undo_redo.commit_action()
	details["status"] = "applied"
	details["coords"] = {"x": coords.x, "y": coords.y, "z": coords.z}
	details["previous_cell"] = previous
	details["next_cell"] = {"item": next_item, "orientation": next_orientation}
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
	_add_operation("Domain: GridMap %s %s" % [action, str(details.get("resolved_node_path", ""))])
	_ack(command, "ok", "GridMap cell updated", details)


func _commit_property_changes(command: Dictionary, details: Dictionary, root: Node, node: Node, changes: Array[Dictionary], label: String, save_scene: bool, ok_message: String) -> void:
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


func _animation_player_snapshot(player: AnimationPlayer, max_tracks: int, max_keys: int) -> Dictionary:
	var result: Dictionary = {
		"type": player.get_class(),
		"autoplay": player.autoplay,
		"libraries": []
	}
	var library_names: Array[String] = []
	if player.has_method("get_animation_library_list"):
		library_names = _string_array(player.call("get_animation_library_list"))
	if library_names.is_empty():
		library_names.append("")
	for library_name: String in library_names:
		var library: AnimationLibrary = null
		if player.has_method("get_animation_library"):
			var candidate: Variant = player.call("get_animation_library", library_name)
			if candidate is AnimationLibrary:
				library = candidate
		if library == null:
			continue
		var library_info: Dictionary = {
			"name": library_name,
			"path": library.resource_path,
			"animations": []
		}
		for animation_name: String in _string_array(library.get_animation_list()):
			var animation: Animation = library.get_animation(animation_name)
			library_info["animations"].append(_animation_snapshot(animation_name, animation, max_tracks, max_keys))
		result["libraries"].append(library_info)
	return result


func _animation_snapshot(animation_name: String, animation: Animation, max_tracks: int, max_keys: int) -> Dictionary:
	var info: Dictionary = {
		"name": animation_name,
		"length": animation.length,
		"loop_mode": animation.loop_mode,
		"track_count": animation.get_track_count(),
		"tracks": []
	}
	var track_limit: int = min(animation.get_track_count(), max_tracks)
	for index: int in range(track_limit):
		var track: Dictionary = {
			"index": index,
			"type": animation.track_get_type(index),
			"path": str(animation.track_get_path(index)),
			"key_count": animation.track_get_key_count(index),
			"keys": []
		}
		var key_limit: int = min(animation.track_get_key_count(index), max_keys)
		for key_index: int in range(key_limit):
			track["keys"].append({
				"index": key_index,
				"time": animation.track_get_key_time(index, key_index),
				"value": _bounded_value(animation.track_get_key_value(index, key_index))
			})
		track["keys_truncated"] = animation.track_get_key_count(index) > max_keys
		info["tracks"].append(track)
	info["tracks_truncated"] = animation.get_track_count() > max_tracks
	return info


func _animation_tree_snapshot(tree: AnimationTree, max_items: int) -> Dictionary:
	var result: Dictionary = {
		"type": tree.get_class(),
		"tree_root": _resource_snapshot(tree.get("tree_root")),
		"anim_player": str(tree.get("anim_player")),
		"parameters": []
	}
	if _has_property(tree, "active"):
		result["active"] = tree.get("active")
	var count: int = 0
	for info: Dictionary in tree.get_property_list():
		var name: String = str(info.get("name", ""))
		if name.begins_with("parameters/"):
			if count >= max_items:
				break
			result["parameters"].append({"name": name, "value": _bounded_value(tree.get(name))})
			count += 1
	result["parameters_truncated"] = count >= max_items
	return result


func _navigation_snapshot(node: Node) -> Dictionary:
	var names: Array[String] = ["navigation_layers", "enabled", "use_edge_connections", "enter_cost", "travel_cost", "target_position", "path_desired_distance", "target_desired_distance", "path_max_distance", "radius", "neighbor_distance", "max_speed", "avoidance_enabled", "debug_enabled"]
	return _property_snapshot(node, names)


func _particles_snapshot(node: Node) -> Dictionary:
	var names: Array[String] = ["emitting", "amount", "amount_ratio", "lifetime", "one_shot", "speed_scale", "explosiveness", "randomness", "fixed_fps", "preprocess", "use_local_coordinates", "interp_to_end", "process_material"]
	return _property_snapshot(node, names)


func _scene3d_snapshot(node: Node, max_cells: int) -> Dictionary:
	var result: Dictionary = {
		"type": node.get_class()
	}
	if node is Node3D:
		result["transform"] = {
			"position": _bounded_value(node.position),
			"rotation_degrees": _bounded_value(node.rotation_degrees),
			"scale": _bounded_value(node.scale)
		}
		result["global_transform"] = _transform3d_snapshot(node.global_transform)
		result["bounds"] = _node3d_bounds_snapshot(node)
	if node is MeshInstance3D:
		result["mesh"] = _resource_snapshot(node.mesh)
		result["material_override"] = _resource_snapshot(node.material_override)
	if node is Light3D:
		result["light"] = _property_snapshot(node, ["light_energy", "light_color", "shadow_enabled"])
	if node is Camera3D:
		result["camera"] = _property_snapshot(node, ["current", "fov", "near", "far"])
	if node is WorldEnvironment:
		result["environment"] = _environment_snapshot(node.environment)
	if node.get_class() == "GridMap":
		result["gridmap"] = _property_snapshot(node, ["mesh_library", "cell_size", "cell_octant_size", "cell_center_x", "cell_center_y", "cell_center_z", "cell_scale", "collision_layer", "collision_mask"])
		result["used_cells"] = _gridmap_used_cells(node, max_cells)
	return result


func _node3d_bounds_snapshot(node: Node3D) -> Dictionary:
	var result: Dictionary = {
		"available": false,
		"type": node.get_class()
	}
	if not node.has_method("get_aabb"):
		result["reason"] = "node does not expose get_aabb"
		return result
	var value: Variant = node.call("get_aabb")
	if typeof(value) != TYPE_AABB:
		result["reason"] = "get_aabb did not return AABB"
		return result
	var local_aabb: AABB = value
	result["available"] = true
	result["local"] = _aabb_snapshot(local_aabb)
	result["global"] = _aabb_snapshot(_transform_aabb(node.global_transform, local_aabb))
	return result


func _transform_aabb(transform: Transform3D, box: AABB) -> AABB:
	var origin: Vector3 = box.position
	var size: Vector3 = box.size
	var points: Array[Vector3] = [
		origin,
		origin + Vector3(size.x, 0.0, 0.0),
		origin + Vector3(0.0, size.y, 0.0),
		origin + Vector3(0.0, 0.0, size.z),
		origin + Vector3(size.x, size.y, 0.0),
		origin + Vector3(size.x, 0.0, size.z),
		origin + Vector3(0.0, size.y, size.z),
		origin + size
	]
	var first: Vector3 = transform * points[0]
	var min_v: Vector3 = first
	var max_v: Vector3 = first
	for index: int in range(1, points.size()):
		var point: Vector3 = transform * points[index]
		min_v.x = min(min_v.x, point.x)
		min_v.y = min(min_v.y, point.y)
		min_v.z = min(min_v.z, point.z)
		max_v.x = max(max_v.x, point.x)
		max_v.y = max(max_v.y, point.y)
		max_v.z = max(max_v.z, point.z)
	return AABB(min_v, max_v - min_v)


func _aabb_snapshot(box: AABB) -> Dictionary:
	var center: Vector3 = box.position + (box.size * 0.5)
	return {
		"position": _bounded_value(box.position),
		"size": _bounded_value(box.size),
		"end": _bounded_value(box.position + box.size),
		"center": _bounded_value(center),
		"volume": box.size.x * box.size.y * box.size.z
	}


func _transform3d_snapshot(transform: Transform3D) -> Dictionary:
	return {
		"origin": _bounded_value(transform.origin),
		"basis": {
			"x": _bounded_value(transform.basis.x),
			"y": _bounded_value(transform.basis.y),
			"z": _bounded_value(transform.basis.z)
		}
	}


func _environment_snapshot(environment: Environment) -> Dictionary:
	var result: Dictionary = {
		"available": environment != null,
		"resource": _resource_snapshot(environment)
	}
	if environment == null:
		return result
	result["properties"] = _property_snapshot(environment, [
		"background_mode",
		"background_color",
		"background_energy_multiplier",
		"background_intensity",
		"ambient_light_source",
		"ambient_light_color",
		"ambient_light_energy",
		"ambient_light_sky_contribution",
		"tonemap_mode",
		"tonemap_exposure",
		"tonemap_white",
		"glow_enabled",
		"glow_intensity",
		"glow_strength",
		"glow_bloom",
		"fog_enabled",
		"fog_density",
		"fog_light_color"
	])
	return result


func _gridmap_cell_info(node: Node, coords: Vector3i) -> Dictionary:
	var item: int = -1
	var orientation: int = 0
	if node.has_method("get_cell_item"):
		item = int(node.call("get_cell_item", coords))
	if node.has_method("get_cell_item_orientation"):
		orientation = int(node.call("get_cell_item_orientation", coords))
	return {
		"coords": {"x": coords.x, "y": coords.y, "z": coords.z},
		"item": item,
		"orientation": orientation,
		"empty": item < 0
	}


func _gridmap_used_cells(node: Node, max_cells: int) -> Array[Dictionary]:
	var used: Array = []
	if node.has_method("get_used_cells"):
		used = node.call("get_used_cells")
	var result: Array[Dictionary] = []
	var count: int = 0
	for item: Variant in used:
		if count >= max_cells:
			break
		result.append(_gridmap_cell_info(node, _vector3i(item, Vector3i.ZERO)))
		count += 1
	return result


func _gridmap_set_cell_native(node: Node, coords: Vector3i, item: int, orientation: int) -> void:
	if node == null or not node.has_method("set_cell_item"):
		return
	node.call("set_cell_item", coords, item, orientation)


func _collect_particles_material_change(changes: Array[Dictionary], node: Node, args: Dictionary, details: Dictionary) -> void:
	if not _has_property(node, "process_material"):
		return
	var wants_material: bool = _bool(args.get("ensure_process_material", false), false)
	var material_keys: Array[String] = ["direction", "spread", "flatness", "initial_velocity_min", "initial_velocity_max", "gravity", "color"]
	for key: String in material_keys:
		if args.has(key):
			wants_material = true
	if not wants_material:
		return
	var old_material: Variant = node.get("process_material")
	var material := ParticleProcessMaterial.new()
	if old_material is ParticleProcessMaterial:
		var duplicate: Resource = old_material.duplicate(true)
		if duplicate is ParticleProcessMaterial:
			material = duplicate
	if args.has("direction") and _has_property(material, "direction"):
		material.set("direction", _vector3(args.get("direction"), material.get("direction")))
	if args.has("spread") and _has_property(material, "spread"):
		material.set("spread", _float(args.get("spread"), 45.0))
	if args.has("flatness") and _has_property(material, "flatness"):
		material.set("flatness", _float(args.get("flatness"), 0.0))
	if args.has("initial_velocity_min") and _has_property(material, "initial_velocity_min"):
		material.set("initial_velocity_min", _float(args.get("initial_velocity_min"), 0.0))
	if args.has("initial_velocity_max") and _has_property(material, "initial_velocity_max"):
		material.set("initial_velocity_max", _float(args.get("initial_velocity_max"), 0.0))
	if args.has("gravity") and _has_property(material, "gravity"):
		material.set("gravity", _vector3(args.get("gravity"), material.get("gravity")))
	if args.has("color") and _has_property(material, "color"):
		material.set("color", _color(args.get("color"), Color.WHITE))
	details["process_material"] = _resource_snapshot(material)
	_add_property_change(changes, node, "process_material", material)


func _collect_environment_changes(changes: Array[Dictionary], node: WorldEnvironment, args: Dictionary, details: Dictionary) -> void:
	var property_keys: Array[String] = [
		"background_mode",
		"background_color",
		"background_energy_multiplier",
		"background_intensity",
		"ambient_light_source",
		"ambient_light_color",
		"ambient_light_energy",
		"ambient_light_sky_contribution",
		"tonemap_mode",
		"tonemap_exposure",
		"tonemap_white",
		"glow_enabled",
		"glow_intensity",
		"glow_strength",
		"glow_bloom",
		"fog_enabled",
		"fog_density",
		"fog_light_color"
	]
	var wants_environment: bool = _bool(args.get("ensure_environment", false), false)
	for key: String in property_keys:
		if args.has(key):
			wants_environment = true
			break
	if not wants_environment:
		return
	var environment: Environment = node.environment
	if environment == null:
		environment = Environment.new()
		_add_property_change(changes, node, "environment", environment)
		details["created_environment"] = true
	else:
		details["created_environment"] = false
	_add_environment_arg(changes, environment, args, "background_mode", "int")
	_add_environment_arg(changes, environment, args, "background_color", "color")
	_add_environment_arg(changes, environment, args, "background_energy_multiplier", "float")
	_add_environment_arg(changes, environment, args, "background_intensity", "float")
	_add_environment_arg(changes, environment, args, "ambient_light_source", "int")
	_add_environment_arg(changes, environment, args, "ambient_light_color", "color")
	_add_environment_arg(changes, environment, args, "ambient_light_energy", "float")
	_add_environment_arg(changes, environment, args, "ambient_light_sky_contribution", "float")
	_add_environment_arg(changes, environment, args, "tonemap_mode", "int")
	_add_environment_arg(changes, environment, args, "tonemap_exposure", "float")
	_add_environment_arg(changes, environment, args, "tonemap_white", "float")
	_add_environment_arg(changes, environment, args, "glow_enabled", "bool")
	_add_environment_arg(changes, environment, args, "glow_intensity", "float")
	_add_environment_arg(changes, environment, args, "glow_strength", "float")
	_add_environment_arg(changes, environment, args, "glow_bloom", "float")
	_add_environment_arg(changes, environment, args, "fog_enabled", "bool")
	_add_environment_arg(changes, environment, args, "fog_density", "float")
	_add_environment_arg(changes, environment, args, "fog_light_color", "color")
	details["environment"] = _environment_snapshot(environment)


func _add_environment_arg(changes: Array[Dictionary], environment: Environment, args: Dictionary, property_name: String, value_type: String) -> void:
	if not args.has(property_name):
		return
	if not _has_property(environment, property_name):
		return
	var raw_value: Variant = args.get(property_name)
	if property_name == "background_mode":
		raw_value = _environment_background_mode(raw_value, int(environment.get(property_name)))
	elif property_name == "tonemap_mode":
		raw_value = _environment_tonemap_mode(raw_value, int(environment.get(property_name)))
	_add_property_change(changes, environment, property_name, _coerce_value(raw_value, value_type, environment.get(property_name)))


func _environment_background_mode(value: Variant, default_value: int) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	match _normalize_key(str(value)):
		"clear", "clear_color":
			return 0
		"color", "solid_color":
			return 1
		"sky":
			return 2
		"canvas":
			return 3
		"keep":
			return 4
		"camera_feed":
			return 5
	return default_value


func _environment_tonemap_mode(value: Variant, default_value: int) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	match _normalize_key(str(value)):
		"linear":
			return 0
		"reinhard":
			return 1
		"filmic":
			return 2
		"aces":
			return 3
		"agx":
			return 4
	return default_value


func _collect_property_arg(changes: Array[Dictionary], target: Object, args: Dictionary, arg_name: String, property_name: String, value_type: String) -> void:
	if not args.has(arg_name):
		return
	if not _has_property(target, property_name):
		return
	_add_property_change(changes, target, property_name, _coerce_value(args.get(arg_name), value_type, target.get(property_name)))


func _add_property_change(changes: Array[Dictionary], target: Object, property_name: String, new_value: Variant) -> void:
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


func _change_summaries(changes: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for change: Dictionary in changes:
		var target: Object = change.get("target")
		result.append({
			"target_type": target.get_class() if target != null else "null",
			"property": str(change.get("property", "")),
			"old": _bounded_value(change.get("old")),
			"new": _bounded_value(change.get("new"))
		})
	return result


func _property_snapshot(target: Object, names: Array[String]) -> Dictionary:
	var result: Dictionary = {
		"type": target.get_class()
	}
	for name: String in names:
		if _has_property(target, name):
			result[name] = _bounded_value(target.get(name))
	return result


func _new_mesh(mesh_kind: String) -> Mesh:
	match _normalize_key(mesh_kind):
		"sphere", "sphere3d":
			return SphereMesh.new()
		"plane", "plane3d":
			return PlaneMesh.new()
		"cylinder":
			return CylinderMesh.new()
		"capsule":
			return CapsuleMesh.new()
	return BoxMesh.new()


func _is_navigation_node(node: Node) -> bool:
	return node is NavigationAgent2D or node is NavigationAgent3D or node is NavigationRegion2D or node is NavigationRegion3D


func _is_particles_node(node: Node) -> bool:
	var node_class: String = node.get_class()
	return node_class.contains("Particles") and _has_property(node, "amount") and _has_property(node, "lifetime")


func _typed_vector_for_node(value: Variant, node: Node) -> Variant:
	if node is NavigationAgent3D:
		return _vector3(value, node.get("target_position"))
	return _vector2(value, node.get("target_position"))


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
		"color":
			return _color(value, default_value if typeof(default_value) == TYPE_COLOR else Color.WHITE)
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


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item: Variant in value:
			result.append(str(item))
	return result


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


func _vector3i(value: Variant, default_value: Vector3i) -> Vector3i:
	if typeof(value) == TYPE_VECTOR3I:
		return value
	if typeof(value) == TYPE_VECTOR3:
		var vector: Vector3 = value
		return Vector3i(int(vector.x), int(vector.y), int(vector.z))
	if typeof(value) == TYPE_ARRAY:
		var items: Array = value
		if items.size() >= 3:
			return Vector3i(_int(items[0], default_value.x), _int(items[1], default_value.y), _int(items[2], default_value.z))
	if typeof(value) == TYPE_DICTIONARY:
		var map: Dictionary = value
		return Vector3i(_int(map.get("x", default_value.x), default_value.x), _int(map.get("y", default_value.y), default_value.y), _int(map.get("z", default_value.z), default_value.z))
	return default_value


func _color(value: Variant, default_value: Color) -> Color:
	if typeof(value) == TYPE_COLOR:
		return value
	if typeof(value) == TYPE_ARRAY:
		var items: Array = value
		if items.size() >= 3:
			return Color(_float(items[0], default_value.r), _float(items[1], default_value.g), _float(items[2], default_value.b), _float(items[3] if items.size() > 3 else default_value.a, default_value.a))
	if typeof(value) == TYPE_DICTIONARY:
		var map: Dictionary = value
		return Color(_float(map.get("r", default_value.r), default_value.r), _float(map.get("g", default_value.g), default_value.g), _float(map.get("b", default_value.b), default_value.b), _float(map.get("a", default_value.a), default_value.a))
	var text: String = str(value).strip_edges()
	if text != "":
		return Color.html(text)
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
	for info: Dictionary in target.get_property_list():
		if str(info.get("name", "")) == property_name:
			return true
	return false
