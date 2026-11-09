extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"domain.create_preset",
		"domain.configure_collision",
		"domain.assign_material",
		"domain.assign_theme",
		"domain.inspect_node",
		"domain.animation_clip",
		"domain.audio_bus",
		"domain.shader_param",
		"domain.theme_item",
		"domain.tilemap_cells"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"domain.create_preset":
			_handle_create_preset(command)
			return true
		"domain.configure_collision":
			_handle_configure_collision(command)
			return true
		"domain.assign_material":
			_handle_assign_material(command)
			return true
		"domain.assign_theme":
			_handle_assign_theme(command)
			return true
		"domain.inspect_node":
			_handle_inspect_node(command)
			return true
		"domain.animation_clip":
			_handle_animation_clip(command)
			return true
		"domain.audio_bus":
			_handle_audio_bus(command)
			return true
		"domain.shader_param":
			_handle_shader_param(command)
			return true
		"domain.theme_item":
			_handle_theme_item(command)
			return true
		"domain.tilemap_cells":
			_handle_tilemap_cells(command)
			return true
	return false


func _handle_create_preset(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var preset: String = _normalize_key(str(args.get("preset", "")))
	var parent_path: String = str(args.get("parent_path", "")).strip_edges()
	var node_name: String = str(args.get("node_name", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.create_preset")
	_mark_native(details, ["ClassDB.instantiate", "Node.add_child", "EditorUndoRedoManager", "Resource.new"])
	details["preset"] = preset
	details["parent_path"] = parent_path
	details["requested_node_name"] = node_name
	details["save_scene"] = save_scene
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var spec: Dictionary = _preset_spec(preset)
	if spec.is_empty():
		details["supported_presets"] = _supported_presets()
		_ack(command, "error", "unsupported domain preset", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var parent: Node = _find_scene_node(root, parent_path)
	if parent == null:
		_ack(command, "error", "parent node not found", details)
		return
	if node_name == "":
		node_name = _unique_child_name(parent, str(spec.get("default_name", "DomainNode")))
	var name_validation: Dictionary = _validate_requested_node_name(node_name)
	if name_validation.get("ok", false) != true:
		details["name_error"] = str(name_validation.get("message", "invalid node name"))
		_ack(command, "error", "invalid node name", details)
		return
	if parent.get_node_or_null(NodePath(node_name)) != null:
		_ack(command, "error", "parent already has a child with this name", details)
		return
	var node_type: String = str(spec.get("node_type", ""))
	var new_node_variant: Variant = ClassDB.instantiate(node_type)
	if not new_node_variant is Node:
		_ack(command, "error", "failed to instantiate preset node", details)
		return
	var new_node: Node = new_node_variant
	new_node.name = node_name
	_apply_preset_defaults(new_node, preset, args, details)
	_apply_common_properties(new_node, args, details)
	var shape_kind: String = _shape_kind_from_args(args, str(spec.get("default_shape", "")))
	var shape_child: Node = null
	if shape_kind != "" and _can_have_collision_shape(new_node):
		shape_child = _new_collision_shape_child(new_node, shape_kind, args, details)
		if shape_child == null:
			_ack(command, "error", str(details.get("shape_error", "collision shape could not be created")), details)
			return
		new_node.add_child(shape_child)
	details["node_type"] = node_type
	details["node_name"] = node_name
	details["scene_path"] = root.scene_file_path
	details["resolved_parent_path"] = _scene_node_path(root, parent)
	details["would_change"] = true
	root = _edited_scene_root()
	if root == null or root.scene_file_path != str(details.get("scene_path", "")):
		_ack(command, "error", "edited scene changed before apply", details)
		return
	parent = _find_scene_node(root, str(details.get("resolved_parent_path", "")))
	if parent == null:
		_ack(command, "error", "parent node not found before apply", details)
		return
	if parent.get_node_or_null(NodePath(node_name)) != null:
		_ack(command, "error", "parent already has a child with this name before apply", details)
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
	undo_redo.create_action("Godot AI Workbench: domain preset %s/%s" % [str(details.get("resolved_parent_path", "")), node_name], 0, root)
	undo_redo.add_do_method(parent, "add_child", new_node)
	undo_redo.add_do_method(self, "_set_owner_recursive", new_node, root)
	undo_redo.add_undo_method(parent, "remove_child", new_node)
	undo_redo.add_do_reference(new_node)
	undo_redo.commit_action()
	var created_path: String = _scene_node_path(root, new_node)
	details["created_path"] = created_path
	details["affected_nodes"] = [created_path]
	if shape_child != null:
		details["collision_shape_path"] = "%s/%s" % [created_path, str(shape_child.name)]
		details["affected_nodes"].append(str(details.get("collision_shape_path", "")))
	details["status"] = "applied"
	details["saved"] = false
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Domain save failed: create preset %s" % preset)
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Domain: create %s %s" % [preset, created_path])
	_ack(command, "ok", "domain preset created", details)


func _handle_configure_collision(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.configure_collision")
	_mark_native(details, ["CollisionObject2D.set_collision_layer", "CollisionObject3D.set_collision_mask", "CollisionShape2D.shape", "CollisionShape3D.shape", "EditorUndoRedoManager"])
	details["node_path"] = node_path
	details["save_scene"] = save_scene
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
	var target: Node = _resolve_write_target_node(root, node_path, details)
	if target == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	var shape_node: Node = _shape_target_for(target)
	var new_shape: Shape2D = null
	var new_shape_3d: Shape3D = null
	var shape_kind: String = _shape_kind_from_args(args, "")
	if shape_kind != "":
		if shape_node == null:
			details["shape_error"] = "target is not a CollisionShape2D/3D and has no CollisionShape child"
			_ack(command, "error", "collision shape target not found", details)
			return
		if shape_node is CollisionShape2D:
			new_shape = _new_shape_2d(shape_kind, args, details)
			if new_shape == null:
				_ack(command, "error", str(details.get("shape_error", "unsupported 2D shape")), details)
				return
		elif shape_node is CollisionShape3D:
			new_shape_3d = _new_shape_3d(shape_kind, args, details)
			if new_shape_3d == null:
				_ack(command, "error", str(details.get("shape_error", "unsupported 3D shape")), details)
				return
	var layer: int = _int(args.get("collision_layer", -1), -1)
	var mask: int = _int(args.get("collision_mask", -1), -1)
	var disabled_set: bool = args.has("disabled")
	var disabled: bool = _bool(args.get("disabled", false), false)
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, target)
	details["shape_node_path"] = "" if shape_node == null else _scene_node_path(root, shape_node)
	details["shape_kind"] = shape_kind
	details["collision_layer"] = layer
	details["collision_mask"] = mask
	details["disabled"] = disabled
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
	undo_redo.create_action("Godot AI Workbench: configure collision %s" % str(details.get("resolved_node_path", "")), 0, root)
	if target is CollisionObject2D or target is CollisionObject3D:
		if layer >= 0:
			undo_redo.add_do_property(target, "collision_layer", layer)
			undo_redo.add_undo_property(target, "collision_layer", target.get("collision_layer"))
		if mask >= 0:
			undo_redo.add_do_property(target, "collision_mask", mask)
			undo_redo.add_undo_property(target, "collision_mask", target.get("collision_mask"))
	if shape_node != null:
		if new_shape != null:
			undo_redo.add_do_property(shape_node, "shape", new_shape)
			undo_redo.add_undo_property(shape_node, "shape", shape_node.get("shape"))
			undo_redo.add_do_reference(new_shape)
		if new_shape_3d != null:
			undo_redo.add_do_property(shape_node, "shape", new_shape_3d)
			undo_redo.add_undo_property(shape_node, "shape", shape_node.get("shape"))
			undo_redo.add_do_reference(new_shape_3d)
		if disabled_set:
			undo_redo.add_do_property(shape_node, "disabled", disabled)
			undo_redo.add_undo_property(shape_node, "disabled", shape_node.get("disabled"))
	undo_redo.commit_action()
	details["status"] = "applied"
	details["saved"] = false
	details["affected_nodes"] = [str(details.get("resolved_node_path", ""))]
	if details.get("shape_node_path", "") != "":
		details["affected_nodes"].append(str(details.get("shape_node_path", "")))
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Domain: configure collision %s" % str(details.get("resolved_node_path", "")))
	_ack(command, "ok", "collision configured", details)


func _handle_assign_material(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var material_kind: String = _normalize_key(str(args.get("material_kind", "auto")))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.assign_material")
	_mark_native(details, ["StandardMaterial3D.new", "CanvasItemMaterial.new", "GeometryInstance3D.material_override", "CanvasItem.material", "EditorUndoRedoManager"])
	details["node_path"] = node_path
	details["material_kind"] = material_kind
	details["save_scene"] = save_scene
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	var property_name: String = _material_property_for(node)
	if property_name == "":
		_ack(command, "error", "target node does not expose a simple native material property", details)
		return
	var material: Material = _new_material_for(node, material_kind, args, details)
	if material == null:
		_ack(command, "error", str(details.get("material_error", "material could not be created")), details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["property_name"] = property_name
	var old_material: Variant = node.get(property_name)
	details["old_material"] = _resource_snapshot(old_material)
	details["new_material"] = _resource_snapshot(material)
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
	undo_redo.create_action("Godot AI Workbench: assign material %s.%s" % [str(details.get("resolved_node_path", "")), property_name], 0, root)
	undo_redo.add_do_property(node, property_name, material)
	undo_redo.add_undo_property(node, property_name, old_material)
	undo_redo.add_do_reference(material)
	if old_material is Resource:
		undo_redo.add_undo_reference(old_material)
	undo_redo.commit_action()
	details["status"] = "applied"
	details["saved"] = false
	details["affected_nodes"] = [str(details.get("resolved_node_path", ""))]
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Domain: assign material %s" % str(details.get("resolved_node_path", "")))
	_ack(command, "ok", "material assigned", details)


func _handle_assign_theme(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.assign_theme")
	_mark_native(details, ["Theme.new", "Control.theme", "EditorUndoRedoManager"])
	details["node_path"] = node_path
	details["save_scene"] = save_scene
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	if not node is Control:
		_ack(command, "error", "target node must be a Control", details)
		return
	var theme := Theme.new()
	var default_font_size: int = _int(args.get("default_font_size", 0), 0)
	if default_font_size > 0:
		theme.default_font_size = default_font_size
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["old_theme"] = _resource_snapshot(node.get("theme"))
	details["new_theme"] = _resource_snapshot(theme)
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
	undo_redo.create_action("Godot AI Workbench: assign theme %s" % str(details.get("resolved_node_path", "")), 0, root)
	undo_redo.add_do_property(node, "theme", theme)
	undo_redo.add_undo_property(node, "theme", node.get("theme"))
	undo_redo.add_do_reference(theme)
	if node.get("theme") is Resource:
		undo_redo.add_undo_reference(node.get("theme"))
	undo_redo.commit_action()
	details["status"] = "applied"
	details["saved"] = false
	details["affected_nodes"] = [str(details.get("resolved_node_path", ""))]
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Domain: assign theme %s" % str(details.get("resolved_node_path", "")))
	_ack(command, "ok", "theme assigned", details)


func _handle_inspect_node(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var max_children: int = int(clamp(_int(args.get("max_children", 40), 40), 0, 200))
	var details: Dictionary = _read_base_details("domain.inspect_node")
	_mark_native(details, ["Node.get_class", "Object.get_property_list", "Resource.get_class"])
	details["node_path"] = node_path
	details["max_children"] = max_children
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
	details["node"] = _domain_snapshot(root, node, max_children)
	_add_operation("Domain: inspect %s" % str(details.get("resolved_node_path", "")))
	_ack(command, "ok", "domain node inspected", details)


func _handle_animation_clip(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "upsert")))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var animation_name: String = str(args.get("animation_name", args.get("name", ""))).strip_edges()
	var library_name: String = str(args.get("library", args.get("library_name", ""))).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.animation_clip")
	_mark_native(details, ["AnimationPlayer", "AnimationLibrary", "Animation", "EditorUndoRedoManager"])
	details["action_mode"] = action
	details["node_path"] = node_path
	details["animation_name"] = animation_name
	details["library_name"] = library_name
	details["save_scene"] = save_scene
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if node_path == "" or animation_name == "":
		_ack(command, "error", "node_path and animation_name are required", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	if not node is AnimationPlayer:
		_ack(command, "error", "target node must be an AnimationPlayer", details)
		return
	var player: AnimationPlayer = node
	var library_exists: bool = player.has_animation_library(library_name)
	var library: AnimationLibrary = null
	if library_exists:
		library = player.get_animation_library(library_name)
	if library == null:
		library = AnimationLibrary.new()
	var old_animation: Animation = null
	if library_exists and library.has_animation(animation_name):
		old_animation = library.get_animation(animation_name)
	if action == "remove" and old_animation == null:
		_ack(command, "error", "animation does not exist", details)
		return
	var new_animation: Animation = null
	if action != "remove":
		new_animation = Animation.new()
		if old_animation != null:
			var duplicate: Resource = old_animation.duplicate(true)
			if duplicate is Animation:
				new_animation = duplicate
		new_animation.length = max(_float(args.get("length", new_animation.length), new_animation.length), 0.001)
		if args.has("loop"):
			new_animation.loop_mode = Animation.LOOP_LINEAR if _bool(args.get("loop", false), false) else Animation.LOOP_NONE
		if args.has("track_path") or args.has("property_name"):
			var track_path: String = _animation_track_path(args)
			if track_path == "":
				_ack(command, "error", "track_path or property_name is required for keyframe insertion", details)
				return
			var key_time: float = max(_float(args.get("time", args.get("key_time", 0.0)), 0.0), 0.0)
			var key_value: Variant = _animation_key_value(args)
			var track_index: int = _animation_find_track(new_animation, NodePath(track_path))
			if track_index < 0:
				track_index = new_animation.add_track(Animation.TYPE_VALUE)
				new_animation.track_set_path(track_index, NodePath(track_path))
			new_animation.track_insert_key(track_index, key_time, key_value)
			if new_animation.length < key_time:
				new_animation.length = key_time
			details["track_path"] = track_path
			details["key_time"] = key_time
			details["key_value_type"] = type_string(typeof(key_value))
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, player)
	details["library_existed"] = library_exists
	details["animation_existed"] = old_animation != null
	details["old_animation"] = _resource_snapshot(old_animation)
	details["new_animation"] = _resource_snapshot(new_animation)
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
	undo_redo.create_action("Godot AI Workbench: animation %s/%s" % [str(details.get("resolved_node_path", "")), animation_name], 0, root)
	if not library_exists:
		undo_redo.add_do_method(player, "add_animation_library", library_name, library)
		undo_redo.add_undo_method(player, "remove_animation_library", library_name)
		undo_redo.add_do_reference(library)
	if action == "remove":
		undo_redo.add_do_method(self, "_animation_set_clip_native", library, animation_name, null)
		undo_redo.add_undo_method(self, "_animation_set_clip_native", library, animation_name, old_animation)
		if old_animation is Resource:
			undo_redo.add_undo_reference(old_animation)
	else:
		undo_redo.add_do_method(self, "_animation_set_clip_native", library, animation_name, new_animation)
		undo_redo.add_undo_method(self, "_animation_set_clip_native", library, animation_name, old_animation)
		undo_redo.add_do_reference(new_animation)
		if old_animation is Resource:
			undo_redo.add_undo_reference(old_animation)
	undo_redo.commit_action()
	details["status"] = "applied"
	details["saved"] = false
	details["affected_nodes"] = [str(details.get("resolved_node_path", ""))]
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Domain: animation %s %s" % [action, str(details.get("resolved_node_path", ""))])
	_ack(command, "ok", "animation clip updated", details)


func _handle_audio_bus(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "inspect")))
	var bus_name: String = str(args.get("bus_name", args.get("name", "Master"))).strip_edges()
	var details: Dictionary = _write_base_details("domain.audio_bus")
	_mark_native(details, ["AudioServer"])
	details["action_mode"] = action
	details["bus_name"] = bus_name
	if action != "inspect" and not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if action == "inspect":
		details["buses"] = _audio_bus_snapshots()
		_add_operation("Domain: inspect audio buses")
		_ack(command, "ok", "audio buses inspected", details)
		return
	if bus_name == "":
		_ack(command, "error", "bus_name is required", details)
		return
	var index: int = _audio_bus_index(bus_name)
	match action:
		"add":
			if index >= 0:
				_ack(command, "error", "audio bus already exists", details)
				return
			AudioServer.add_bus(AudioServer.get_bus_count())
			index = AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(index, bus_name)
		"set":
			if index < 0:
				_ack(command, "error", "audio bus not found", details)
				return
		"remove":
			if index <= 0:
				_ack(command, "error", "cannot remove Master or missing bus", details)
				return
			AudioServer.remove_bus(index)
			details["status"] = "applied"
			details["buses"] = _audio_bus_snapshots()
			_write_audit(details)
			_add_operation("Domain: remove audio bus %s" % bus_name)
			_ack(command, "ok", "audio bus removed", details)
			return
		_:
			_ack(command, "error", "unsupported audio bus action", details)
			return
	if args.has("volume_db"):
		AudioServer.set_bus_volume_db(index, _float(args.get("volume_db", 0.0), 0.0))
	if args.has("mute"):
		AudioServer.set_bus_mute(index, _bool(args.get("mute", false), false))
	if args.has("solo"):
		AudioServer.set_bus_solo(index, _bool(args.get("solo", false), false))
	if args.has("bypass_effects"):
		AudioServer.set_bus_bypass_effects(index, _bool(args.get("bypass_effects", false), false))
	if args.has("send"):
		AudioServer.set_bus_send(index, str(args.get("send", "Master")))
	if args.has("effect_type"):
		var effect_type: String = str(args.get("effect_type", "")).strip_edges()
		if not effect_type.begins_with("AudioEffect"):
			_ack(command, "error", "effect_type must be an AudioEffect class", details)
			return
		var effect_variant: Variant = ClassDB.instantiate(effect_type)
		if not effect_variant is AudioEffect:
			_ack(command, "error", "failed to instantiate audio effect", details)
			return
		AudioServer.add_bus_effect(index, effect_variant)
		details["effect_type"] = effect_type
	details["status"] = "applied"
	details["bus"] = _audio_bus_snapshot(index)
	details["buses"] = _audio_bus_snapshots()
	_write_audit(details)
	_add_operation("Domain: audio bus %s %s" % [action, bus_name])
	_ack(command, "ok", "audio bus updated", details)


func _handle_shader_param(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var parameter_name: String = str(args.get("parameter_name", args.get("param", ""))).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.shader_param")
	_mark_native(details, ["ShaderMaterial", "Shader", "set_shader_parameter", "EditorUndoRedoManager"])
	details["node_path"] = node_path
	details["parameter_name"] = parameter_name
	details["save_scene"] = save_scene
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if node_path == "" or parameter_name == "":
		_ack(command, "error", "node_path and parameter_name are required", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	var property_name: String = _material_property_for(node)
	if property_name == "":
		_ack(command, "error", "target node does not expose a simple native material property", details)
		return
	var old_material: Variant = node.get(property_name)
	var shader_material := ShaderMaterial.new()
	if old_material is ShaderMaterial:
		var material_duplicate: Resource = old_material.duplicate(true)
		if material_duplicate is ShaderMaterial:
			shader_material = material_duplicate
	var shader_path: String = str(args.get("shader_path", "")).strip_edges()
	if shader_path != "":
		if not shader_path.begins_with("res://") or not shader_path.ends_with(".gdshader"):
			_ack(command, "error", "shader_path must be a res:// .gdshader path", details)
			return
		var shader_resource: Resource = ResourceLoader.load(shader_path)
		if not shader_resource is Shader:
			_ack(command, "error", "shader_path did not load a Shader resource", details)
			return
		shader_material.shader = shader_resource
	if shader_material.shader == null:
		_ack(command, "error", "target has no ShaderMaterial shader; pass shader_path first", details)
		return
	var value: Variant = _typed_value(args.get("value", args.get("parameter_value", null)), str(args.get("value_type", "")))
	shader_material.set_shader_parameter(parameter_name, value)
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["property_name"] = property_name
	details["shader_path"] = shader_path
	details["old_material"] = _resource_snapshot(old_material)
	details["new_material"] = _resource_snapshot(shader_material)
	details["value_type"] = type_string(typeof(value))
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
	undo_redo.create_action("Godot AI Workbench: shader param %s.%s" % [str(details.get("resolved_node_path", "")), parameter_name], 0, root)
	undo_redo.add_do_property(node, property_name, shader_material)
	undo_redo.add_undo_property(node, property_name, old_material)
	undo_redo.add_do_reference(shader_material)
	if old_material is Resource:
		undo_redo.add_undo_reference(old_material)
	undo_redo.commit_action()
	details["status"] = "applied"
	details["saved"] = false
	details["affected_nodes"] = [str(details.get("resolved_node_path", ""))]
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Domain: shader param %s %s" % [parameter_name, str(details.get("resolved_node_path", ""))])
	_ack(command, "ok", "shader parameter updated", details)


func _handle_theme_item(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var item_kind: String = _normalize_key(str(args.get("item_kind", args.get("kind", "color"))))
	var item_name: String = str(args.get("item_name", args.get("name", ""))).strip_edges()
	var theme_type: String = str(args.get("theme_type", "")).strip_edges()
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.theme_item")
	_mark_native(details, ["Theme", "Control.theme", "StyleBoxFlat", "EditorUndoRedoManager"])
	details["node_path"] = node_path
	details["item_kind"] = item_kind
	details["item_name"] = item_name
	details["theme_type"] = theme_type
	details["save_scene"] = save_scene
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if node_path == "" or item_name == "":
		_ack(command, "error", "node_path and item_name are required", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	if not node is Control:
		_ack(command, "error", "target node must be a Control", details)
		return
	if theme_type == "":
		theme_type = node.get_class()
	var old_theme: Variant = node.get("theme")
	var theme := Theme.new()
	if old_theme is Theme:
		var theme_duplicate: Resource = old_theme.duplicate(true)
		if theme_duplicate is Theme:
			theme = theme_duplicate
	match item_kind:
		"color":
			theme.set_color(item_name, theme_type, _color(args.get("value", args.get("color", "#ffffff")), Color.WHITE))
		"constant":
			theme.set_constant(item_name, theme_type, _int(args.get("value", 0), 0))
		"font_size", "font_size_override":
			theme.set_font_size(item_name, theme_type, _int(args.get("value", args.get("font_size", 16)), 16))
		"stylebox", "stylebox_flat":
			var stylebox := StyleBoxFlat.new()
			stylebox.bg_color = _color(args.get("bg_color", args.get("value", "#ffffff")), Color.WHITE)
			var corner_radius: int = _int(args.get("corner_radius", 0), 0)
			if corner_radius > 0:
				stylebox.corner_radius_top_left = corner_radius
				stylebox.corner_radius_top_right = corner_radius
				stylebox.corner_radius_bottom_left = corner_radius
				stylebox.corner_radius_bottom_right = corner_radius
			theme.set_stylebox(item_name, theme_type, stylebox)
		_:
			_ack(command, "error", "unsupported theme item kind", details)
			return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	details["old_theme"] = _resource_snapshot(old_theme)
	details["new_theme"] = _resource_snapshot(theme)
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
	undo_redo.create_action("Godot AI Workbench: theme item %s.%s" % [str(details.get("resolved_node_path", "")), item_name], 0, root)
	undo_redo.add_do_property(node, "theme", theme)
	undo_redo.add_undo_property(node, "theme", old_theme)
	undo_redo.add_do_reference(theme)
	if old_theme is Resource:
		undo_redo.add_undo_reference(old_theme)
	undo_redo.commit_action()
	details["status"] = "applied"
	details["saved"] = false
	details["affected_nodes"] = [str(details.get("resolved_node_path", ""))]
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Domain: theme %s %s" % [item_kind, str(details.get("resolved_node_path", ""))])
	_ack(command, "ok", "theme item updated", details)


func _handle_tilemap_cells(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var action: String = _normalize_key(str(args.get("action", "inspect")))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var layer: int = _int(args.get("layer", 0), 0)
	var max_cells: int = int(clamp(_int(args.get("max_cells", 64), 64), 1, 1024))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var details: Dictionary = _write_base_details("domain.tilemap_cells")
	_mark_native(details, ["TileMap", "TileMapLayer", "get_used_cells", "set_cell", "EditorUndoRedoManager"])
	details["action_mode"] = action
	details["node_path"] = node_path
	details["layer"] = layer
	details["max_cells"] = max_cells
	details["save_scene"] = save_scene
	if action not in ["inspect", "get", "used"] and not _write_gate_open():
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
	if not _is_tilemap_node(node):
		_ack(command, "error", "target node must be a TileMap or TileMapLayer", details)
		return
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = _scene_node_path(root, node)
	if action == "inspect" or action == "used":
		details["tilemap"] = _tilemap_snapshot(node)
		details["used_cells"] = _tilemap_used_cells_snapshot(node, layer, max_cells)
		_add_operation("Domain: tilemap inspect %s" % str(details.get("resolved_node_path", "")))
		_ack(command, "ok", "tilemap inspected", details)
		return
	if action == "get":
		var coords: Vector2i = _vector2i(args.get("coords", args.get("cell", {"x": 0, "y": 0})), Vector2i.ZERO)
		details["cell"] = _tilemap_cell_info(node, layer, coords)
		_add_operation("Domain: tilemap get %s" % str(details.get("resolved_node_path", "")))
		_ack(command, "ok", "tilemap cell read", details)
		return
	var changes: Array[Dictionary] = _tilemap_changes_for_action(node, layer, action, args, max_cells, details)
	if changes.is_empty():
		_ack(command, "error", str(details.get("tilemap_error", "no tilemap cells requested")), details)
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
	undo_redo.create_action("Godot AI Workbench: tilemap %s %s" % [action, str(details.get("resolved_node_path", ""))], 0, root)
	for change: Dictionary in changes:
		var coords_value: Vector2i = change.get("coords", Vector2i.ZERO)
		var next_cell: Dictionary = change.get("next", {})
		var previous_cell: Dictionary = change.get("previous", {})
		undo_redo.add_do_method(self, "_tilemap_set_cell_native", node, layer, coords_value, int(next_cell.get("source_id", -1)), next_cell.get("atlas_coords", Vector2i(-1, -1)), int(next_cell.get("alternative_tile", 0)))
		undo_redo.add_undo_method(self, "_tilemap_set_cell_native", node, layer, coords_value, int(previous_cell.get("source_id", -1)), previous_cell.get("atlas_coords", Vector2i(-1, -1)), int(previous_cell.get("alternative_tile", 0)))
	undo_redo.commit_action()
	details["status"] = "applied"
	details["changed_cell_count"] = changes.size()
	details["changed_cells"] = _tilemap_change_summaries(changes, max_cells)
	details["saved"] = false
	details["affected_nodes"] = [str(details.get("resolved_node_path", ""))]
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Domain: tilemap %s cells=%d %s" % [action, changes.size(), str(details.get("resolved_node_path", ""))])
	_ack(command, "ok", "tilemap cells updated", details)


func _preset_spec(preset: String) -> Dictionary:
	match preset:
		"sprite2d", "sprite":
			return {"node_type": "Sprite2D", "default_name": "Sprite2D"}
		"camera2d":
			return {"node_type": "Camera2D", "default_name": "Camera2D"}
		"area2d":
			return {"node_type": "Area2D", "default_name": "Area2D", "default_shape": "circle"}
		"static_body2d":
			return {"node_type": "StaticBody2D", "default_name": "StaticBody2D", "default_shape": "rectangle"}
		"rigid_body2d":
			return {"node_type": "RigidBody2D", "default_name": "RigidBody2D", "default_shape": "circle"}
		"character_body2d":
			return {"node_type": "CharacterBody2D", "default_name": "CharacterBody2D", "default_shape": "capsule"}
		"collision_shape2d":
			return {"node_type": "CollisionShape2D", "default_name": "CollisionShape2D", "default_shape": "rectangle"}
		"raycast2d", "ray_cast2d":
			return {"node_type": "RayCast2D", "default_name": "RayCast2D"}
		"animation_player", "animationplayer":
			return {"node_type": "AnimationPlayer", "default_name": "AnimationPlayer"}
		"animation_tree", "animationtree":
			return {"node_type": "AnimationTree", "default_name": "AnimationTree"}
		"gpu_particles2d", "gpuparticles2d", "particles2d":
			return {"node_type": "GPUParticles2D", "default_name": "GPUParticles2D"}
		"cpu_particles2d", "cpuparticles2d":
			return {"node_type": "CPUParticles2D", "default_name": "CPUParticles2D"}
		"tilemap", "tile_map":
			return {"node_type": "TileMap", "default_name": "TileMap"}
		"tilemap_layer", "tile_map_layer":
			return {"node_type": "TileMapLayer", "default_name": "TileMapLayer"}
		"mesh_cube3d", "cube3d", "mesh3d":
			return {"node_type": "MeshInstance3D", "default_name": "MeshInstance3D", "mesh": "box"}
		"mesh_sphere3d", "sphere3d":
			return {"node_type": "MeshInstance3D", "default_name": "SphereMesh3D", "mesh": "sphere"}
		"mesh_plane3d", "plane3d":
			return {"node_type": "MeshInstance3D", "default_name": "PlaneMesh3D", "mesh": "plane"}
		"camera3d":
			return {"node_type": "Camera3D", "default_name": "Camera3D"}
		"light3d", "directional_light3d":
			return {"node_type": "DirectionalLight3D", "default_name": "DirectionalLight3D"}
		"omni_light3d":
			return {"node_type": "OmniLight3D", "default_name": "OmniLight3D"}
		"spot_light3d":
			return {"node_type": "SpotLight3D", "default_name": "SpotLight3D"}
		"world_environment", "environment3d":
			return {"node_type": "WorldEnvironment", "default_name": "WorldEnvironment", "environment": true}
		"area3d":
			return {"node_type": "Area3D", "default_name": "Area3D", "default_shape": "sphere"}
		"static_body3d":
			return {"node_type": "StaticBody3D", "default_name": "StaticBody3D", "default_shape": "box"}
		"rigid_body3d":
			return {"node_type": "RigidBody3D", "default_name": "RigidBody3D", "default_shape": "sphere"}
		"character_body3d":
			return {"node_type": "CharacterBody3D", "default_name": "CharacterBody3D", "default_shape": "capsule"}
		"collision_shape3d":
			return {"node_type": "CollisionShape3D", "default_name": "CollisionShape3D", "default_shape": "box"}
		"raycast3d", "ray_cast3d":
			return {"node_type": "RayCast3D", "default_name": "RayCast3D"}
		"gpu_particles3d", "gpuparticles3d", "particles3d":
			return {"node_type": "GPUParticles3D", "default_name": "GPUParticles3D"}
		"cpu_particles3d", "cpuparticles3d":
			return {"node_type": "CPUParticles3D", "default_name": "CPUParticles3D"}
		"gridmap", "grid_map":
			return {"node_type": "GridMap", "default_name": "GridMap"}
		"audio", "audio_player":
			return {"node_type": "AudioStreamPlayer", "default_name": "AudioStreamPlayer"}
		"audio2d", "audio_player2d":
			return {"node_type": "AudioStreamPlayer2D", "default_name": "AudioStreamPlayer2D"}
		"audio3d", "audio_player3d":
			return {"node_type": "AudioStreamPlayer3D", "default_name": "AudioStreamPlayer3D"}
		"navigation_agent2d":
			return {"node_type": "NavigationAgent2D", "default_name": "NavigationAgent2D"}
		"navigation_agent3d":
			return {"node_type": "NavigationAgent3D", "default_name": "NavigationAgent3D"}
		"navigation_region2d":
			return {"node_type": "NavigationRegion2D", "default_name": "NavigationRegion2D", "navigation_polygon": true}
		"navigation_region3d":
			return {"node_type": "NavigationRegion3D", "default_name": "NavigationRegion3D", "navigation_mesh": true}
		"color_rect":
			return {"node_type": "ColorRect", "default_name": "ColorRect"}
		"label":
			return {"node_type": "Label", "default_name": "Label"}
		"button":
			return {"node_type": "Button", "default_name": "Button"}
	return {}


func _supported_presets() -> Array[String]:
	return [
		"sprite2d", "camera2d", "area2d", "static_body2d", "rigid_body2d", "character_body2d",
		"collision_shape2d", "raycast2d", "animation_player", "animation_tree",
		"gpu_particles2d", "cpu_particles2d", "tilemap", "tilemap_layer",
		"mesh_cube3d", "mesh_sphere3d", "mesh_plane3d",
		"camera3d", "directional_light3d", "omni_light3d", "spot_light3d", "world_environment",
		"area3d", "static_body3d", "rigid_body3d", "character_body3d", "collision_shape3d",
		"raycast3d", "gpu_particles3d", "cpu_particles3d", "gridmap", "audio", "audio2d", "audio3d",
		"navigation_agent2d", "navigation_agent3d",
		"navigation_region2d", "navigation_region3d", "color_rect", "label", "button"
	]


func _apply_preset_defaults(node: Node, preset: String, args: Dictionary, details: Dictionary) -> void:
	var spec: Dictionary = _preset_spec(preset)
	var mesh_kind: String = str(spec.get("mesh", ""))
	if node is MeshInstance3D and mesh_kind != "":
		node.mesh = _new_mesh(mesh_kind)
	if node is WorldEnvironment and bool(spec.get("environment", false)):
		node.environment = Environment.new()
	if node is NavigationRegion2D and bool(spec.get("navigation_polygon", false)):
		node.navigation_polygon = NavigationPolygon.new()
	if node is NavigationRegion3D and bool(spec.get("navigation_mesh", false)):
		node.navigation_mesh = NavigationMesh.new()
	if node is CollisionShape2D:
		node.shape = _new_shape_2d(_shape_kind_from_args(args, str(spec.get("default_shape", "rectangle"))), args, details)
	if node is CollisionShape3D:
		node.shape = _new_shape_3d(_shape_kind_from_args(args, str(spec.get("default_shape", "box"))), args, details)
	if node is Camera2D and args.has("current"):
		node.enabled = _bool(args.get("current", false), false)
	if node is Camera3D and args.has("current"):
		node.current = _bool(args.get("current", false), false)
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if args.has("autoplay"):
			node.autoplay = _bool(args.get("autoplay", false), false)
		if args.has("volume_db"):
			node.volume_db = _float(args.get("volume_db", 0.0), 0.0)
		if args.has("bus") and node is AudioStreamPlayer:
			node.bus = str(args.get("bus", "Master"))


func _apply_common_properties(node: Node, args: Dictionary, details: Dictionary) -> void:
	if args.has("position"):
		if node is Node2D:
			node.position = _vector2(args.get("position"), node.position)
		elif node is Node3D:
			node.position = _vector3(args.get("position"), node.position)
	if args.has("scale"):
		if node is Node2D:
			node.scale = _vector2(args.get("scale"), node.scale)
		elif node is Node3D:
			node.scale = _vector3(args.get("scale"), node.scale)
	if args.has("rotation_degrees") and node is Node2D:
		node.rotation_degrees = _float(args.get("rotation_degrees", 0.0), 0.0)
	if args.has("visible") and node is CanvasItem:
		node.visible = _bool(args.get("visible", true), true)
	if node is CollisionObject2D or node is CollisionObject3D:
		if args.has("collision_layer"):
			node.set("collision_layer", _int(args.get("collision_layer", 1), 1))
		if args.has("collision_mask"):
			node.set("collision_mask", _int(args.get("collision_mask", 1), 1))
	if args.has("properties") and typeof(args.get("properties")) == TYPE_DICTIONARY:
		var properties: Dictionary = args.get("properties")
		var applied: Array[String] = []
		for key: Variant in properties.keys():
			var property_name: String = str(key)
			if _has_writable_property(node, property_name):
				node.set(property_name, properties.get(key))
				applied.append(property_name)
		details["applied_extra_properties"] = applied


func _new_collision_shape_child(parent: Node, shape_kind: String, args: Dictionary, details: Dictionary) -> Node:
	if parent is Node2D:
		var node_2d := CollisionShape2D.new()
		node_2d.name = str(args.get("collision_node_name", "CollisionShape2D"))
		node_2d.shape = _new_shape_2d(shape_kind, args, details)
		if node_2d.shape == null:
			return null
		return node_2d
	if parent is Node3D:
		var node_3d := CollisionShape3D.new()
		node_3d.name = str(args.get("collision_node_name", "CollisionShape3D"))
		node_3d.shape = _new_shape_3d(shape_kind, args, details)
		if node_3d.shape == null:
			return null
		return node_3d
	return null


func _new_shape_2d(shape_kind: String, args: Dictionary, details: Dictionary) -> Shape2D:
	match _normalize_key(shape_kind):
		"rectangle", "rect", "box":
			var shape := RectangleShape2D.new()
			shape.size = _vector2(args.get("shape_size", args.get("size", {"x": 64, "y": 64})), Vector2(64, 64))
			return shape
		"circle", "sphere":
			var shape := CircleShape2D.new()
			shape.radius = _float(args.get("radius", args.get("shape_radius", 32.0)), 32.0)
			return shape
		"capsule":
			var shape := CapsuleShape2D.new()
			shape.radius = _float(args.get("radius", args.get("shape_radius", 24.0)), 24.0)
			shape.height = _float(args.get("height", args.get("shape_height", 96.0)), 96.0)
			return shape
	details["shape_error"] = "unsupported 2D shape kind: %s" % shape_kind
	return null


func _new_shape_3d(shape_kind: String, args: Dictionary, details: Dictionary) -> Shape3D:
	match _normalize_key(shape_kind):
		"box", "rectangle", "rect":
			var shape := BoxShape3D.new()
			shape.size = _vector3(args.get("shape_size", args.get("size", {"x": 1, "y": 1, "z": 1})), Vector3.ONE)
			return shape
		"sphere", "circle":
			var shape := SphereShape3D.new()
			shape.radius = _float(args.get("radius", args.get("shape_radius", 0.5)), 0.5)
			return shape
		"capsule":
			var shape := CapsuleShape3D.new()
			shape.radius = _float(args.get("radius", args.get("shape_radius", 0.5)), 0.5)
			shape.height = _float(args.get("height", args.get("shape_height", 2.0)), 2.0)
			return shape
	details["shape_error"] = "unsupported 3D shape kind: %s" % shape_kind
	return null


func _new_mesh(mesh_kind: String) -> Mesh:
	match _normalize_key(mesh_kind):
		"sphere":
			return SphereMesh.new()
		"plane":
			return PlaneMesh.new()
	return BoxMesh.new()


func _new_material_for(node: Node, material_kind: String, args: Dictionary, details: Dictionary) -> Material:
	var normalized: String = material_kind
	if normalized == "" or normalized == "auto":
		if node is GeometryInstance3D:
			normalized = "standard3d"
		else:
			normalized = "canvas_item"
	match normalized:
		"standard3d", "standard_material3d":
			var material := StandardMaterial3D.new()
			if args.has("albedo_color") or args.has("color"):
				material.albedo_color = _color(args.get("albedo_color", args.get("color")), Color(1, 1, 1, 1))
			if args.has("roughness"):
				material.roughness = _float(args.get("roughness", 0.5), 0.5)
			return material
		"canvas_item", "canvasitem":
			var material := CanvasItemMaterial.new()
			return material
	details["material_error"] = "unsupported material_kind: %s" % material_kind
	return null


func _material_property_for(node: Node) -> String:
	if node is GeometryInstance3D:
		return "material_override"
	if node is CanvasItem:
		return "material"
	return ""


func _shape_target_for(node: Node) -> Node:
	if node is CollisionShape2D or node is CollisionShape3D:
		return node
	for child: Node in node.get_children():
		if child is CollisionShape2D or child is CollisionShape3D:
			return child
	return null


func _domain_snapshot(root: Node, node: Node, max_children: int) -> Dictionary:
	var snapshot: Dictionary = {
		"path": _scene_node_path(root, node),
		"name": str(node.name),
		"type": node.get_class(),
		"domain_tags": _domain_tags(node),
		"children": []
	}
	if node is CollisionObject2D or node is CollisionObject3D:
		snapshot["collision"] = {
			"layer": node.get("collision_layer"),
			"mask": node.get("collision_mask")
		}
	var shape_node: Node = _shape_target_for(node)
	if shape_node != null:
		snapshot["collision_shape"] = _shape_snapshot(root, shape_node)
	if node is MeshInstance3D:
		snapshot["mesh"] = _resource_snapshot(node.mesh)
		snapshot["material_override"] = _resource_snapshot(node.material_override)
	if node is CanvasItem:
		snapshot["material"] = _resource_snapshot(node.material)
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		snapshot["audio"] = {
			"autoplay": node.get("autoplay"),
			"volume_db": node.get("volume_db"),
			"stream": _resource_snapshot(node.get("stream"))
		}
		if node is AudioStreamPlayer:
			snapshot["audio"]["bus"] = node.bus
	if node is NavigationAgent2D or node is NavigationAgent3D:
		snapshot["navigation_agent"] = {
			"target_desired_distance": node.get("target_desired_distance"),
			"path_desired_distance": node.get("path_desired_distance")
		}
	if node is NavigationRegion2D:
		snapshot["navigation_region"] = {"navigation_polygon": _resource_snapshot(node.navigation_polygon)}
	if node is NavigationRegion3D:
		snapshot["navigation_region"] = {"navigation_mesh": _resource_snapshot(node.navigation_mesh)}
	if node is Control:
		snapshot["theme"] = _resource_snapshot(node.theme)
		snapshot["ui"] = {"anchors_preset": "native_control", "custom_minimum_size": node.custom_minimum_size}
	if node.get_class() == "TileMap" or node.get_class() == "TileMapLayer":
		snapshot["tilemap"] = _tilemap_snapshot(node)
	var count := 0
	for child: Node in node.get_children():
		if count >= max_children:
			break
		snapshot["children"].append({
			"name": str(child.name),
			"path": _scene_node_path(root, child),
			"type": child.get_class(),
			"domain_tags": _domain_tags(child)
		})
		count += 1
	snapshot["child_count"] = node.get_child_count()
	snapshot["children_truncated"] = node.get_child_count() > max_children
	return snapshot


func _shape_snapshot(root: Node, shape_node: Node) -> Dictionary:
	var shape: Variant = shape_node.get("shape")
	return {
		"path": _scene_node_path(root, shape_node),
		"type": shape_node.get_class(),
		"disabled": shape_node.get("disabled"),
		"shape": _resource_snapshot(shape)
	}


func _tilemap_snapshot(node: Node) -> Dictionary:
	var result: Dictionary = {
		"type": node.get_class(),
		"native_inspect_only": true
	}
	if _has_property(node, "tile_set"):
		result["tile_set"] = _resource_snapshot(node.get("tile_set"))
	if _has_property(node, "rendering_quadrant_size"):
		result["rendering_quadrant_size"] = node.get("rendering_quadrant_size")
	if _has_property(node, "collision_enabled"):
		result["collision_enabled"] = node.get("collision_enabled")
	return result


func _domain_tags(node: Node) -> Array[String]:
	var tags: Array[String] = []
	if node is Node2D:
		tags.append("2d")
	if node is Node3D:
		tags.append("3d")
	if node is CollisionObject2D or node is CollisionObject3D or node is CollisionShape2D or node is CollisionShape3D:
		tags.append("collision")
	if node is PhysicsBody2D or node is PhysicsBody3D:
		tags.append("physics")
	if node is Area2D or node is Area3D:
		tags.append("area")
	if node is Camera2D or node is Camera3D:
		tags.append("camera")
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		tags.append("audio")
	if node is NavigationAgent2D or node is NavigationAgent3D or node is NavigationRegion2D or node is NavigationRegion3D:
		tags.append("navigation")
	if node is Control:
		tags.append("ui")
	if node.get_class() == "TileMap" or node.get_class() == "TileMapLayer":
		tags.append("tilemap")
	if node is MeshInstance3D:
		tags.append("mesh")
	return tags


func _can_have_collision_shape(node: Node) -> bool:
	return node is CollisionObject2D or node is CollisionObject3D or node is PhysicsBody2D or node is PhysicsBody3D or node is Area2D or node is Area3D


func _shape_kind_from_args(args: Dictionary, default_value: String) -> String:
	return _normalize_key(str(args.get("shape_kind", args.get("collision_shape", default_value))))


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


func _animation_track_path(args: Dictionary) -> String:
	var track_path: String = str(args.get("track_path", "")).strip_edges()
	var property_name: String = str(args.get("property_name", "")).strip_edges()
	if track_path == "" and property_name != "":
		track_path = ".:%s" % property_name
	elif track_path != "" and property_name != "" and not track_path.contains(":"):
		track_path = "%s:%s" % [track_path, property_name]
	return track_path


func _animation_find_track(animation: Animation, track_path: NodePath) -> int:
	for index: int in range(animation.get_track_count()):
		if animation.track_get_path(index) == track_path:
			return index
	return -1


func _animation_set_clip_native(library: AnimationLibrary, animation_name: String, animation: Animation) -> void:
	if library == null:
		return
	if library.has_animation(animation_name):
		library.remove_animation(animation_name)
	if animation != null:
		library.add_animation(animation_name, animation)


func _animation_key_value(args: Dictionary) -> Variant:
	return _typed_value(args.get("key_value", args.get("value", null)), str(args.get("value_type", "")))


func _typed_value(value: Variant, value_type: String) -> Variant:
	match _normalize_key(value_type):
		"vector2", "vec2":
			return _vector2(value, Vector2.ZERO)
		"vector2i", "vec2i":
			return _vector2i(value, Vector2i.ZERO)
		"vector3", "vec3":
			return _vector3(value, Vector3.ZERO)
		"color", "colour":
			return _color(value, Color.WHITE)
		"float":
			return _float(value, 0.0)
		"int", "integer":
			return _int(value, 0)
		"bool", "boolean":
			return _bool(value, false)
	return value


func _audio_bus_index(bus_name: String) -> int:
	for index: int in range(AudioServer.get_bus_count()):
		if AudioServer.get_bus_name(index) == bus_name:
			return index
	return -1


func _audio_bus_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(AudioServer.get_bus_count()):
		result.append(_audio_bus_snapshot(index))
	return result


func _audio_bus_snapshot(index: int) -> Dictionary:
	if index < 0 or index >= AudioServer.get_bus_count():
		return {"index": index, "exists": false}
	var effects: Array[Dictionary] = []
	for effect_index: int in range(AudioServer.get_bus_effect_count(index)):
		var effect: AudioEffect = AudioServer.get_bus_effect(index, effect_index)
		effects.append({
			"index": effect_index,
			"type": effect.get_class(),
			"enabled": AudioServer.is_bus_effect_enabled(index, effect_index)
		})
	return {
		"index": index,
		"exists": true,
		"name": AudioServer.get_bus_name(index),
		"volume_db": AudioServer.get_bus_volume_db(index),
		"mute": AudioServer.is_bus_mute(index),
		"solo": AudioServer.is_bus_solo(index),
		"bypass_effects": AudioServer.is_bus_bypassing_effects(index),
		"send": AudioServer.get_bus_send(index),
		"effects": effects
	}


func _is_tilemap_node(node: Node) -> bool:
	return node.get_class() == "TileMap" or node.get_class() == "TileMapLayer"


func _tilemap_used_cells_snapshot(node: Node, layer: int, max_cells: int) -> Array[Dictionary]:
	var used: Array = []
	if node.get_class() == "TileMapLayer" and node.has_method("get_used_cells"):
		used = node.call("get_used_cells")
	elif node.get_class() == "TileMap" and node.has_method("get_used_cells"):
		used = node.call("get_used_cells", layer)
	var result: Array[Dictionary] = []
	var count: int = 0
	for item: Variant in used:
		if count >= max_cells:
			break
		var coords: Vector2i = _vector2i(item, Vector2i.ZERO)
		result.append(_tilemap_cell_info(node, layer, coords))
		count += 1
	return result


func _tilemap_cell_info(node: Node, layer: int, coords: Vector2i) -> Dictionary:
	var source_id: int = -1
	var atlas_coords: Vector2i = Vector2i(-1, -1)
	var alternative_tile: int = 0
	if node.get_class() == "TileMapLayer":
		if node.has_method("get_cell_source_id"):
			source_id = int(node.call("get_cell_source_id", coords))
		if node.has_method("get_cell_atlas_coords"):
			atlas_coords = _vector2i(node.call("get_cell_atlas_coords", coords), Vector2i(-1, -1))
		if node.has_method("get_cell_alternative_tile"):
			alternative_tile = int(node.call("get_cell_alternative_tile", coords))
	elif node.get_class() == "TileMap":
		if node.has_method("get_cell_source_id"):
			source_id = int(node.call("get_cell_source_id", layer, coords))
		if node.has_method("get_cell_atlas_coords"):
			atlas_coords = _vector2i(node.call("get_cell_atlas_coords", layer, coords), Vector2i(-1, -1))
		if node.has_method("get_cell_alternative_tile"):
			alternative_tile = int(node.call("get_cell_alternative_tile", layer, coords))
	return {
		"coords": {"x": coords.x, "y": coords.y},
		"layer": layer,
		"source_id": source_id,
		"atlas_coords": atlas_coords,
		"alternative_tile": alternative_tile,
		"empty": source_id < 0
	}


func _tilemap_changes_for_action(node: Node, layer: int, action: String, args: Dictionary, max_cells: int, details: Dictionary) -> Array[Dictionary]:
	var coords_list: Array[Vector2i] = []
	if action == "fill":
		var origin: Vector2i = _vector2i(args.get("origin", args.get("coords", {"x": 0, "y": 0})), Vector2i.ZERO)
		var size: Vector2i = _vector2i(args.get("size", {"x": 1, "y": 1}), Vector2i.ONE)
		if size.x <= 0 or size.y <= 0:
			details["tilemap_error"] = "fill size must be positive"
			return []
		if size.x * size.y > max_cells:
			details["tilemap_error"] = "fill request exceeds max_cells"
			return []
		for y: int in range(origin.y, origin.y + size.y):
			for x: int in range(origin.x, origin.x + size.x):
				coords_list.append(Vector2i(x, y))
	elif args.has("cells") and typeof(args.get("cells")) == TYPE_ARRAY:
		var cells: Array = args.get("cells")
		for item: Variant in cells:
			if coords_list.size() >= max_cells:
				break
			if typeof(item) == TYPE_DICTIONARY and item.has("coords"):
				coords_list.append(_vector2i(item.get("coords"), Vector2i.ZERO))
			else:
				coords_list.append(_vector2i(item, Vector2i.ZERO))
	else:
		coords_list.append(_vector2i(args.get("coords", args.get("cell", {"x": 0, "y": 0})), Vector2i.ZERO))
	var next_cell: Dictionary = {
		"source_id": -1,
		"atlas_coords": Vector2i(-1, -1),
		"alternative_tile": 0
	}
	if action == "set" or action == "fill":
		next_cell["source_id"] = _int(args.get("source_id", 0), 0)
		next_cell["atlas_coords"] = _vector2i(args.get("atlas_coords", {"x": 0, "y": 0}), Vector2i.ZERO)
		next_cell["alternative_tile"] = _int(args.get("alternative_tile", 0), 0)
	elif action != "clear":
		details["tilemap_error"] = "unsupported tilemap action"
		return []
	var changes: Array[Dictionary] = []
	for coords: Vector2i in coords_list:
		var previous: Dictionary = _tilemap_cell_info(node, layer, coords)
		changes.append({
			"coords": coords,
			"previous": {
				"source_id": int(previous.get("source_id", -1)),
				"atlas_coords": previous.get("atlas_coords", Vector2i(-1, -1)),
				"alternative_tile": int(previous.get("alternative_tile", 0))
			},
			"next": next_cell.duplicate(true)
		})
	return changes


func _tilemap_change_summaries(changes: Array[Dictionary], max_cells: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count: int = 0
	for change: Dictionary in changes:
		if count >= max_cells:
			break
		var coords: Vector2i = change.get("coords", Vector2i.ZERO)
		result.append({
			"coords": {"x": coords.x, "y": coords.y},
			"previous": change.get("previous", {}),
			"next": change.get("next", {})
		})
		count += 1
	return result


func _tilemap_set_cell_native(node: Node, layer: int, coords: Vector2i, source_id: int, atlas_coords: Variant, alternative_tile: int) -> void:
	if node == null:
		return
	var atlas: Vector2i = _vector2i(atlas_coords, Vector2i(-1, -1))
	if node.get_class() == "TileMapLayer":
		if source_id < 0 and node.has_method("erase_cell"):
			node.call("erase_cell", coords)
		elif node.has_method("set_cell"):
			node.call("set_cell", coords, source_id, atlas, alternative_tile)
	elif node.get_class() == "TileMap":
		if source_id < 0 and node.has_method("erase_cell"):
			node.call("erase_cell", layer, coords)
		elif node.has_method("set_cell"):
			node.call("set_cell", layer, coords, source_id, atlas, alternative_tile)


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


func _vector2i(value: Variant, default_value: Vector2i) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value
	if typeof(value) == TYPE_VECTOR2:
		var vector: Vector2 = value
		return Vector2i(int(vector.x), int(vector.y))
	if typeof(value) == TYPE_ARRAY:
		var items: Array = value
		if items.size() >= 2:
			return Vector2i(_int(items[0], default_value.x), _int(items[1], default_value.y))
	if typeof(value) == TYPE_DICTIONARY:
		var map: Dictionary = value
		return Vector2i(_int(map.get("x", default_value.x), default_value.x), _int(map.get("y", default_value.y), default_value.y))
	return default_value


func _vector3(value: Variant, default_value: Vector3) -> Vector3:
	if typeof(value) == TYPE_VECTOR3:
		return value
	if typeof(value) == TYPE_ARRAY:
		var items: Array = value
		if items.size() >= 3:
			return Vector3(_float(items[0], default_value.x), _float(items[1], default_value.y), _float(items[2], default_value.z))
	if typeof(value) == TYPE_DICTIONARY:
		var map: Dictionary = value
		return Vector3(_float(map.get("x", default_value.x), default_value.x), _float(map.get("y", default_value.y), default_value.y), _float(map.get("z", default_value.z), default_value.z))
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


func _set_owner_recursive(node: Node, owner: Node) -> void:
	if node == null:
		return
	node.owner = owner
	for child: Node in node.get_children():
		_set_owner_recursive(child, owner)


func _unique_child_name(parent: Node, preferred_name: String) -> String:
	var clean_name: String = preferred_name.strip_edges()
	if clean_name == "":
		clean_name = "DomainNode"
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


func _has_writable_property(node: Node, property_name: String) -> bool:
	for info: Dictionary in node.get_property_list():
		if str(info.get("name", "")) == property_name:
			return (int(info.get("usage", 0)) & PROPERTY_USAGE_STORAGE) != 0
	return false


func _has_property(node: Object, property_name: String) -> bool:
	for info: Dictionary in node.get_property_list():
		if str(info.get("name", "")) == property_name:
			return true
	return false
