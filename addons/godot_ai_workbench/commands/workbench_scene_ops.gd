extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"scene.create",
		"scene.open",
		"scene.save_as",
		"scene.delete",
		"scene.instance"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"scene.create":
			_handle_scene_create(command)
			return true
		"scene.open":
			_handle_scene_open(command)
			return true
		"scene.save_as":
			_handle_scene_save_as(command)
			return true
		"scene.delete":
			_handle_scene_delete(command)
			return true
		"scene.instance":
			_handle_scene_instance(command)
			return true
	return false


func _handle_scene_create(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var open_after: bool = _bool(args.get("open_after", true), true)
	var overwrite: bool = _bool(args.get("overwrite", false), false)
	var scene_path: String = str(args.get("path", "")).strip_edges()
	var root_type: String = str(args.get("root_type", "Node2D")).strip_edges()
	var root_name: String = str(args.get("root_name", "")).strip_edges()
	var details: Dictionary = _write_base_details("scene.create")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["open_after"] = open_after
	details["overwrite"] = overwrite
	details["path"] = scene_path
	details["root_type"] = root_type
	details["root_name"] = root_name
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var path_result: Dictionary = _validate_scene_path(scene_path, false)
	if path_result.get("ok", false) != true:
		_ack(command, "error", str(path_result.get("message", "invalid scene path")), details)
		return
	scene_path = str(path_result.get("path", scene_path))
	details["path"] = scene_path
	details["absolute_path"] = str(path_result.get("absolute_path", ""))
	if root_type == "":
		_ack(command, "error", "root_type is required", details)
		return
	if not ClassDB.class_exists(root_type) or not ClassDB.is_parent_class(root_type, "Node"):
		_ack(command, "error", "root_type must be a Godot Node class", details)
		return
	if root_name == "":
		root_name = _default_root_name(scene_path)
	var name_validation: Dictionary = _validate_node_name(root_name)
	if name_validation.get("ok", false) != true:
		details["name_error"] = str(name_validation.get("message", "invalid root_name"))
		_ack(command, "error", "invalid root_name", details)
		return
	details["root_name"] = root_name
	var exists_before: bool = FileAccess.file_exists(str(path_result.get("absolute_path", "")))
	details["exists_before"] = exists_before
	details["would_change"] = true
	if exists_before and not overwrite:
		_ack(command, "error", "scene file already exists; pass overwrite=true to replace it", details)
		return
	var root_value: Variant = ClassDB.instantiate(root_type)
	if not root_value is Node:
		_ack(command, "error", "failed to instantiate root_type", details)
		return
	var root: Node = root_value
	root.name = root_name
	var packed: PackedScene = PackedScene.new()
	var pack_error: int = packed.pack(root)
	if pack_error != OK:
		root.free()
		details["pack_error"] = error_string(pack_error)
		_ack(command, "error", "scene pack failed", details)
		return
	var save_error: int = ResourceSaver.save(packed, scene_path)
	root.free()
	details["save_error"] = save_error
	if save_error != OK:
		_ack(command, "error", "scene save failed", details)
		return
	_scan_filesystem()
	var validation: Dictionary = _validate_saved_scene(scene_path)
	details["validation"] = validation
	if validation.get("ok", false) != true:
		_ack(command, "error", str(validation.get("message", "created scene validation failed")), details)
		return
	details["affected_files"] = [scene_path]
	details["status"] = "applied"
	details["saved"] = true
	if open_after:
		var open_result: Dictionary = _open_scene_path(scene_path)
		details["open_result"] = open_result
		if open_result.get("ok", false) != true:
			_write_audit(details)
			_add_operation("Dev write: create scene %s, open failed" % scene_path)
			_ack(command, "error", str(open_result.get("message", "scene created but open failed")), details)
			return
	_send_editor_state()
	_write_audit(details)
	_add_operation("Dev write: create scene %s" % scene_path)
	_ack(command, "ok", "scene created", details)


func _handle_scene_open(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var allow_unsaved_current: bool = _bool(args.get("allow_unsaved_current", false), false)
	var scene_path: String = str(args.get("path", "")).strip_edges()
	var details: Dictionary = _write_base_details("scene.open")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["allow_unsaved_current"] = allow_unsaved_current
	details["path"] = scene_path
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var path_result: Dictionary = _validate_scene_path(scene_path, true)
	if path_result.get("ok", false) != true:
		_ack(command, "error", str(path_result.get("message", "invalid scene path")), details)
		return
	scene_path = str(path_result.get("path", scene_path))
	details["path"] = scene_path
	details["absolute_path"] = str(path_result.get("absolute_path", ""))
	var dirty_state: Dictionary = _scene_dirty_state()
	details["current_dirty_state"] = dirty_state
	if dirty_state.get("available", false) == true and dirty_state.get("changed", false) == true and not allow_unsaved_current:
		_ack(command, "error", "current editor scene has unsaved changes; pass allow_unsaved_current=true to switch anyway", details)
		return
	var open_result: Dictionary = _open_scene_path(scene_path)
	details["open_result"] = open_result
	if open_result.get("ok", false) != true:
		_ack(command, "error", str(open_result.get("message", "scene open failed")), details)
		return
	details["status"] = "applied"
	details["affected_files"] = [scene_path]
	_send_editor_state()
	_write_audit(details)
	_add_operation("Dev write: open scene %s" % scene_path)
	_ack(command, "ok", "scene opened", details)


func _handle_scene_save_as(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var overwrite: bool = _bool(args.get("overwrite", false), false)
	var with_preview: bool = _bool(args.get("with_preview", false), false)
	var scene_path: String = str(args.get("path", "")).strip_edges()
	var details: Dictionary = _write_base_details("scene.save_as")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["overwrite"] = overwrite
	details["with_preview"] = with_preview
	details["path"] = scene_path
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if _editor_interface == null or not _editor_interface.has_method("save_scene_as"):
		_ack(command, "error", "EditorInterface.save_scene_as is unavailable", details)
		return
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	details["source_scene_path"] = root.scene_file_path
	var path_result: Dictionary = _validate_scene_path(scene_path, false)
	if path_result.get("ok", false) != true:
		_ack(command, "error", str(path_result.get("message", "invalid scene path")), details)
		return
	scene_path = str(path_result.get("path", scene_path))
	details["path"] = scene_path
	details["absolute_path"] = str(path_result.get("absolute_path", ""))
	var exists_before: bool = FileAccess.file_exists(str(path_result.get("absolute_path", "")))
	details["exists_before"] = exists_before
	details["would_change"] = true
	if exists_before and not overwrite:
		_ack(command, "error", "target scene file already exists; pass overwrite=true to replace it", details)
		return
	_editor_interface.call("save_scene_as", scene_path, with_preview)
	_scan_filesystem()
	var validation: Dictionary = _validate_saved_scene(scene_path)
	details["validation"] = validation
	if validation.get("ok", false) != true:
		_ack(command, "error", str(validation.get("message", "scene save_as validation failed")), details)
		return
	var current_root: Node = _edited_scene_root()
	if current_root != null:
		details["current_scene_path"] = current_root.scene_file_path
	details["affected_files"] = [scene_path]
	details["status"] = "applied"
	details["saved"] = true
	_send_editor_state()
	_write_audit(details)
	_add_operation("Dev write: save scene as %s" % scene_path)
	_ack(command, "ok", "scene saved as", details)


func _handle_scene_delete(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var scene_path: String = str(args.get("path", "")).strip_edges()
	var details: Dictionary = _write_base_details("scene.delete")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["path"] = scene_path
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var path_result: Dictionary = _validate_scene_path(scene_path, true)
	if path_result.get("ok", false) != true:
		_ack(command, "error", str(path_result.get("message", "invalid scene path")), details)
		return
	scene_path = str(path_result.get("path", scene_path))
	details["path"] = scene_path
	var absolute_path: String = str(path_result.get("absolute_path", ""))
	details["absolute_path"] = absolute_path
	if scene_path.begins_with("res://addons/"):
		_ack(command, "error", "deleting addon scenes is refused", details)
		return
	var root: Node = _edited_scene_root()
	if root != null and root.scene_file_path == scene_path:
		_ack(command, "error", "deleting the currently open scene is refused", details)
		return
	details["would_change"] = true
	details["affected_files"] = [scene_path]
	var remove_error: int = _remove_absolute_file(absolute_path)
	details["remove_error"] = remove_error
	if remove_error != OK:
		_ack(command, "error", "scene delete failed: %s" % error_string(remove_error), details)
		return
	_scan_filesystem()
	details["exists_after"] = FileAccess.file_exists(absolute_path)
	if details["exists_after"] == true:
		_ack(command, "error", "scene delete verification failed", details)
		return
	details["status"] = "applied"
	_write_audit(details)
	_add_operation("Dev write: delete scene %s" % scene_path)
	_ack(command, "ok", "scene deleted", details)


func _handle_scene_instance(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var scene_path: String = str(args.get("path", "")).strip_edges()
	var parent_path: String = str(args.get("parent_path", "")).strip_edges()
	var requested_name: String = str(args.get("node_name", "")).strip_edges()
	var details: Dictionary = _write_base_details("scene.instance")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save_scene"] = save_scene
	details["path"] = scene_path
	details["parent_path"] = parent_path
	details["node_name"] = requested_name
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var path_result: Dictionary = _validate_scene_path(scene_path, true)
	if path_result.get("ok", false) != true:
		_ack(command, "error", str(path_result.get("message", "invalid scene path")), details)
		return
	scene_path = str(path_result.get("path", scene_path))
	details["path"] = scene_path
	details["absolute_path"] = str(path_result.get("absolute_path", ""))
	var root: Node = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var parent: Node = _find_scene_node(root, parent_path)
	if parent == null:
		_ack(command, "error", "parent node not found", details)
		return
	var packed_resource: Resource = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed_resource == null or not packed_resource is PackedScene:
		_ack(command, "error", "resource did not load as PackedScene", details)
		return
	var packed: PackedScene = packed_resource
	if packed.has_method("can_instantiate") and not packed.can_instantiate():
		_ack(command, "error", "PackedScene cannot instantiate", details)
		return
	var node_name: String = requested_name
	if node_name == "":
		node_name = _unique_child_name(parent, scene_path.get_file().get_basename())
	var name_validation: Dictionary = _validate_node_name(node_name)
	if name_validation.get("ok", false) != true:
		details["name_error"] = str(name_validation.get("message", "invalid node_name"))
		_ack(command, "error", "invalid node_name", details)
		return
	if parent.get_node_or_null(NodePath(node_name)) != null:
		_ack(command, "error", "parent already has a child with node_name", details)
		return
	var resolved_parent_path: String = _scene_node_path(root, parent)
	details["scene_path"] = root.scene_file_path
	details["resolved_parent_path"] = resolved_parent_path
	details["node_name"] = node_name
	details["new_path"] = "%s/%s" % [resolved_parent_path, node_name]
	details["would_change"] = true
	root = _edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root before apply", details)
		return
	if root.scene_file_path != str(details.get("scene_path", "")):
		details["current_scene_path"] = root.scene_file_path
		_ack(command, "error", "edited scene changed before apply", details)
		return
	parent = _find_scene_node(root, resolved_parent_path)
	if parent == null:
		_ack(command, "error", "parent node not found before apply", details)
		return
	if parent.get_node_or_null(NodePath(node_name)) != null:
		_ack(command, "error", "parent already has a child with node_name before apply", details)
		return
	var instance_value: Variant = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if not instance_value is Node:
		_ack(command, "error", "PackedScene instantiate failed", details)
		return
	var instance_node: Node = instance_value
	instance_node.name = node_name
	var undo_redo: EditorUndoRedoManager = _resolve_undo_redo()
	if undo_redo == null:
		instance_node.free()
		_ack(command, "error", "EditorUndoRedoManager is unavailable", details)
		return
	undo_redo.create_action("Godot AI Workbench: instance scene %s -> %s" % [scene_path, str(details.get("new_path", ""))], 0, root)
	undo_redo.add_do_method(parent, "add_child", instance_node)
	undo_redo.add_do_method(instance_node, "set_owner", root)
	undo_redo.add_undo_method(parent, "remove_child", instance_node)
	undo_redo.add_do_reference(instance_node)
	undo_redo.commit_action()
	if instance_node.get_parent() != parent:
		_ack(command, "error", "scene instance verification failed", details)
		return
	var created_path: String = _scene_node_path(root, instance_node)
	details["created_path"] = created_path
	details["affected_nodes"] = [created_path]
	details["source_scene_path"] = scene_path
	details["affected_files"] = []
	details["status"] = "applied"
	details["saved"] = false
	details["native_undo_redo"] = true
	if save_scene:
		if root.scene_file_path == "":
			_write_audit(details)
			_send_editor_state()
			_add_operation("Dev write save failed: instance %s" % scene_path)
			_ack(command, "error", "current scene has no file path to save", details)
			return
		var save_result: Dictionary = _save_current_scene_native()
		details["save_result"] = save_result
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Dev write save failed: instance %s" % scene_path)
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
		var validation: Dictionary = _validate_saved_scene(root.scene_file_path)
		details["save_validation"] = validation
		if validation.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Dev write save validation failed: instance %s" % scene_path)
			_ack(command, "error", str(validation.get("message", "scene save validation failed")), details)
			return
		details["saved"] = true
		details["affected_files"] = [root.scene_file_path]
	_write_audit(details)
	_send_editor_state()
	_add_operation("Dev write: instance %s -> %s" % [scene_path, created_path])
	_ack(command, "ok", "scene instanced", details)


func _validate_scene_path(scene_path: String, must_exist: bool) -> Dictionary:
	var result: Dictionary = {"ok": false, "path": scene_path}
	var clean_path: String = scene_path.strip_edges().replace("\\", "/")
	result["path"] = clean_path
	if clean_path == "":
		result["message"] = "scene path is required"
		return result
	if not clean_path.begins_with("res://"):
		result["message"] = "scene path must use res://"
		return result
	if clean_path.contains("/../") or clean_path.begins_with("res://../") or clean_path.ends_with("/.."):
		result["message"] = "scene path must not contain .. segments"
		return result
	var extension: String = clean_path.get_extension().to_lower()
	if extension != "tscn" and extension != "scn":
		result["message"] = "scene path must end with .tscn or .scn"
		return result
	var absolute_path: String = ProjectSettings.globalize_path(clean_path)
	var project_root: String = ProjectSettings.globalize_path("res://")
	if not _path_within_root(absolute_path, project_root):
		result["message"] = "scene path escapes the project root"
		result["absolute_path"] = absolute_path
		return result
	if must_exist and not FileAccess.file_exists(absolute_path):
		result["message"] = "scene file does not exist"
		result["absolute_path"] = absolute_path
		return result
	result["ok"] = true
	result["path"] = clean_path
	result["absolute_path"] = absolute_path
	return result


func _validate_saved_scene(scene_path: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "path": scene_path}
	var path_result: Dictionary = _validate_scene_path(scene_path, true)
	if path_result.get("ok", false) != true:
		result["message"] = str(path_result.get("message", "scene path invalid"))
		return result
	var absolute_path: String = str(path_result.get("absolute_path", ""))
	result["absolute_path"] = absolute_path
	result["file_size"] = _file_size(absolute_path)
	if int(result.get("file_size", 0)) <= 0:
		result["message"] = "scene file is empty"
		return result
	var loaded: Resource = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not loaded is PackedScene:
		result["message"] = "scene file did not load as PackedScene"
		return result
	result["ok"] = true
	result["message"] = "scene validation ok"
	return result


func _open_scene_path(scene_path: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "path": scene_path}
	if _editor_interface == null or not _editor_interface.has_method("open_scene_from_path"):
		result["message"] = "EditorInterface.open_scene_from_path is unavailable"
		return result
	var open_result: Variant = _editor_interface.call("open_scene_from_path", scene_path)
	if typeof(open_result) == TYPE_INT and int(open_result) != OK:
		result["message"] = "open_scene_from_path failed: %s" % error_string(int(open_result))
		result["error"] = int(open_result)
		return result
	result["ok"] = true
	result["message"] = "scene opened"
	return result


func _save_current_scene_native() -> Dictionary:
	var result: Dictionary = {"ok": false}
	if _editor_interface == null or not _editor_interface.has_method("save_scene"):
		result["message"] = "EditorInterface.save_scene is unavailable"
		return result
	var save_result: Variant = _editor_interface.call("save_scene")
	if typeof(save_result) == TYPE_INT and int(save_result) != OK:
		result["message"] = "save_scene failed: %s" % error_string(int(save_result))
		result["error"] = int(save_result)
		return result
	result["ok"] = true
	result["message"] = "scene saved"
	return result


func _remove_absolute_file(absolute_path: String) -> int:
	var dir_path: String = absolute_path.get_base_dir()
	var file_name: String = absolute_path.get_file()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return ERR_CANT_OPEN
	return dir.remove(file_name)


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


func _default_root_name(scene_path: String) -> String:
	var base: String = scene_path.get_file().get_basename()
	var cleaned: String = _clean_node_name(base)
	if cleaned == "":
		return "Root"
	return cleaned


func _clean_node_name(value: String) -> String:
	var output: String = ""
	var capitalize_next: bool = true
	for index: int in range(value.length()):
		var character: String = value.substr(index, 1)
		var is_alpha_num: bool = character.to_lower() != character.to_upper() or character.is_valid_int()
		if is_alpha_num:
			if capitalize_next:
				output += character.to_upper()
				capitalize_next = false
			else:
				output += character
		else:
			capitalize_next = true
	if output == "":
		return ""
	if output.substr(0, 1).is_valid_int():
		output = "Scene%s" % output
	return output


func _validate_node_name(node_name: String) -> Dictionary:
	var result: Dictionary = {"ok": false}
	if node_name.strip_edges() == "":
		result["message"] = "node name is required"
		return result
	for forbidden: String in ["/", ":", "@", "\n", "\r", "\t"]:
		if node_name.contains(forbidden):
			result["message"] = "node name contains forbidden characters"
			return result
	result["ok"] = true
	return result


func _unique_child_name(parent: Node, base_name: String) -> String:
	var clean_base: String = _clean_node_name(base_name)
	if clean_base == "":
		clean_base = "SceneInstance"
	var candidate: String = clean_base
	if parent.get_node_or_null(NodePath(candidate)) == null:
		return candidate
	var index: int = 2
	while index < 10000:
		candidate = "%s%d" % [clean_base, index]
		if parent.get_node_or_null(NodePath(candidate)) == null:
			return candidate
		index += 1
	return "%s%d" % [clean_base, Time.get_ticks_msec()]


func _path_within_root(path: String, root: String) -> bool:
	var normalized_path: String = path.replace("\\", "/")
	var normalized_root: String = root.replace("\\", "/")
	if not normalized_root.ends_with("/"):
		normalized_root += "/"
	if OS.get_name().to_lower().contains("windows"):
		normalized_path = normalized_path.to_lower()
		normalized_root = normalized_root.to_lower()
	return normalized_path.begins_with(normalized_root)


func _edited_scene_root() -> Node:
	if _editor_interface != null:
		return _editor_interface.get_edited_scene_root()
	return null


func _find_scene_node(root: Node, path: String) -> Node:
	var result: Variant = _host.call("find_scene_node", root, path)
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


func _scene_dirty_state() -> Dictionary:
	var result: Variant = _host.call("scene_dirty_state")
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"available": false, "changed": false}


func _file_size(path: String) -> int:
	return int(_host.call("file_size", path))


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


func _write_audit(details: Dictionary) -> void:
	_host.call("write_audit", details)


func _send_editor_state() -> void:
	_host.call("send_editor_state")


func _add_operation(text: String) -> void:
	_host.call("add_operation", text)


func _ack(command: Dictionary, status: String, message: String, details: Dictionary) -> void:
	_host.call("ack_dev_command", command, status, message, details)
