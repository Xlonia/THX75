extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"editor.attach_script",
		"script.detach",
		"editor.rename_node",
		"editor.save_scene",
		"editor.move_node",
		"editor.delete_node"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"editor.attach_script":
			_handle_attach_script_command(command)
			return true
		"script.detach":
			_handle_detach_script_command(command)
			return true
		"editor.rename_node":
			_handle_rename_node_command(command)
			return true
		"editor.save_scene":
			_handle_save_scene_command(command)
			return true
		"editor.move_node":
			_handle_move_node_command(command)
			return true
		"editor.delete_node":
			_handle_delete_node_command(command)
			return true
	return false


func _handle_attach_script_command(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var script_path: String = str(args.get("script_path", "")).strip_edges()
	var details: Dictionary = _write_base_details("editor.attach_script")
	details["save_scene"] = save_scene
	details["node_path"] = node_path
	details["script_path"] = script_path
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if script_path == "":
		_ack(command, "error", "script_path is required", details)
		return
	var script_path_result: Dictionary = _validate_script_resource_path(script_path)
	if script_path_result.get("ok", false) != true:
		details["script_error"] = str(script_path_result.get("message", "invalid script path"))
		_ack(command, "error", "script path rejected", details)
		return
	script_path = str(script_path_result.get("path", script_path))
	details["script_path"] = script_path
	details["script_absolute_path"] = str(script_path_result.get("absolute_path", ""))
	details["script_resource_scan"] = _request_resource_filesystem_scan(script_path)
	var loaded_script: Variant = ResourceLoader.load(script_path, "Script", ResourceLoader.CACHE_MODE_REPLACE)
	if not loaded_script is Script:
		details["script_error"] = "resource did not load as Script"
		_ack(command, "error", "script resource rejected", details)
		return
	var script_resource: Script = loaded_script
	details["script"] = _script_snapshot(script_resource)
	var root: Node = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	var resolved_node_path: String = _workbench_scene_node_path(root, node)
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = resolved_node_path
	var compatibility: Dictionary = _script_compatibility(node, script_resource)
	details["script_compatibility"] = compatibility
	if compatibility.get("ok", false) != true:
		_ack(command, "error", str(compatibility.get("message", "script is not compatible with node")), details)
		return
	var old_script: Variant = node.get_script()
	details["old_script"] = _script_snapshot(old_script)
	details["new_script"] = _script_snapshot(script_resource)
	details["would_change"] = not _scripts_equal(old_script, script_resource)
	if not _bool(details.get("would_change", false), false):
		details["status"] = "unchanged"
		_ack(command, "ok", "node already has requested script", details)
		return
	root = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
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
	script_path_result = _validate_script_resource_path(script_path)
	if script_path_result.get("ok", false) != true:
		details["script_error"] = str(script_path_result.get("message", "invalid script path before apply"))
		_ack(command, "error", "script path rejected before apply", details)
		return
	details["script_resource_scan_before_apply"] = _request_resource_filesystem_scan(script_path)
	loaded_script = ResourceLoader.load(script_path, "Script", ResourceLoader.CACHE_MODE_REPLACE)
	if not loaded_script is Script:
		details["script_error"] = "resource did not load as Script before apply"
		_ack(command, "error", "script resource rejected before apply", details)
		return
	script_resource = loaded_script
	compatibility = _script_compatibility(node, script_resource)
	details["script_compatibility"] = compatibility
	if compatibility.get("ok", false) != true:
		_ack(command, "error", str(compatibility.get("message", "script is not compatible with node before apply")), details)
		return
	var current_script: Variant = node.get_script()
	if not _scripts_equal(current_script, old_script):
		details["current_script"] = _script_snapshot(current_script)
		_ack(command, "error", "node script changed before apply", details)
		return
	details["apply_rechecked"] = true
	var undo_redo := _resolve_undo_redo()
	if undo_redo == null:
		_ack(command, "error", "EditorUndoRedoManager is unavailable", details)
		return
	var save_context: Dictionary = {}
	if save_scene:
		save_context = _prepare_scene_save(details, root)
		if save_context.get("ok", false) != true:
			_ack(command, "error", str(save_context.get("message", "scene save preparation failed; write aborted")), details)
			return
	undo_redo.create_action("Godot AI Workbench: attach script %s -> %s" % [script_path, resolved_node_path], 0, root)
	undo_redo.add_do_method(node, "set_script", script_resource)
	undo_redo.add_undo_method(node, "set_script", old_script)
	undo_redo.add_do_reference(script_resource)
	if old_script is Script:
		undo_redo.add_undo_reference(old_script)
	undo_redo.commit_action()
	var applied_script: Variant = node.get_script()
	if not _scripts_equal(applied_script, script_resource):
		details["applied_script"] = _script_snapshot(applied_script)
		_ack(command, "error", "script attach verification failed", details)
		return
	details["applied_script"] = _script_snapshot(applied_script)
	details["affected_nodes"] = [resolved_node_path]
	details["affected_files"] = [script_path]
	details["status"] = "applied"
	details["saved"] = false
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Write save failed: attach %s" % resolved_node_path)
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	else:
		details["saved"] = false
	_write_audit(details)
	_send_editor_state()
	_add_operation("Write: attach %s -> %s" % [script_path, resolved_node_path])
	_ack(command, "ok", "script attached", details)


func _handle_detach_script_command(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var details: Dictionary = _write_base_details("script.detach")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save_scene"] = save_scene
	details["node_path"] = node_path
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var root: Node = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	var resolved_node_path: String = _workbench_scene_node_path(root, node)
	var old_script: Variant = node.get_script()
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = resolved_node_path
	details["old_script"] = _script_snapshot(old_script)
	details["new_script"] = _script_snapshot(null)
	details["would_change"] = old_script is Script
	if not old_script is Script:
		details["status"] = "unchanged"
		_ack(command, "ok", "node has no script", details)
		return
	root = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
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
	var current_script: Variant = node.get_script()
	if not _scripts_equal(current_script, old_script):
		details["current_script"] = _script_snapshot(current_script)
		_ack(command, "error", "node script changed before apply", details)
		return
	var undo_redo := _resolve_undo_redo()
	if undo_redo == null:
		_ack(command, "error", "EditorUndoRedoManager is unavailable", details)
		return
	var save_context: Dictionary = {}
	if save_scene:
		save_context = _prepare_scene_save(details, root)
		if save_context.get("ok", false) != true:
			_ack(command, "error", str(save_context.get("message", "scene save preparation failed; write aborted")), details)
			return
	undo_redo.create_action("Godot AI Workbench: detach script %s" % resolved_node_path, 0, root)
	undo_redo.add_do_method(node, "set_script", null)
	undo_redo.add_undo_method(node, "set_script", old_script)
	if old_script is Script:
		undo_redo.add_undo_reference(old_script)
	undo_redo.commit_action()
	var applied_script: Variant = node.get_script()
	if applied_script is Script:
		details["applied_script"] = _script_snapshot(applied_script)
		_ack(command, "error", "script detach verification failed", details)
		return
	details["applied_script"] = _script_snapshot(applied_script)
	details["affected_nodes"] = [resolved_node_path]
	var old_script_snapshot: Dictionary = _dict(details.get("old_script", {}))
	var old_script_path: String = str(old_script_snapshot.get("path", ""))
	if old_script_path != "":
		details["affected_files"] = [old_script_path]
	details["status"] = "applied"
	details["saved"] = false
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Dev write save failed: detach script from %s" % resolved_node_path)
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Dev write: detach script from %s" % resolved_node_path)
	_ack(command, "ok", "script detached", details)


func _handle_rename_node_command(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var new_name: String = str(args.get("new_name", "")).strip_edges()
	var details: Dictionary = _write_base_details("editor.rename_node")
	details["save_scene"] = save_scene
	details["node_path"] = node_path
	details["new_name"] = new_name
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var name_validation: Dictionary = _validate_requested_node_name(new_name)
	if name_validation.get("ok", false) != true:
		details["name_error"] = str(name_validation.get("message", "invalid node name"))
		_ack(command, "error", "invalid node name", details)
		return
	var root: Node = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	if node == root:
		_ack(command, "error", "renaming the scene root is deferred", details)
		return
	var parent: Node = node.get_parent()
	if parent == null:
		_ack(command, "error", "target node has no parent", details)
		return
	var old_name: String = str(node.name)
	var resolved_node_path: String = _workbench_scene_node_path(root, node)
	var resolved_parent_path: String = _workbench_scene_node_path(root, parent)
	var new_node_path: String = "%s/%s" % [resolved_parent_path, new_name]
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = resolved_node_path
	details["resolved_parent_path"] = resolved_parent_path
	details["old_name"] = old_name
	details["old_path"] = resolved_node_path
	details["new_path"] = new_node_path
	details["would_change"] = old_name != new_name
	var sibling: Node = parent.get_node_or_null(NodePath(new_name))
	if sibling != null and sibling != node:
		_ack(command, "error", "parent already has a child with new_name", details)
		return
	if not _bool(details.get("would_change", false), false):
		details["status"] = "unchanged"
		_ack(command, "ok", "node already has requested name", details)
		return
	root = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
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
	parent = _find_scene_node(root, resolved_parent_path)
	if parent == null or node.get_parent() != parent:
		_ack(command, "error", "node parent changed before apply", details)
		return
	if str(node.name) != old_name:
		details["current_name"] = str(node.name)
		_ack(command, "error", "node name changed before apply", details)
		return
	sibling = parent.get_node_or_null(NodePath(new_name))
	if sibling != null and sibling != node:
		_ack(command, "error", "parent already has a child with new_name before apply", details)
		return
	details["apply_rechecked"] = true
	var undo_redo := _resolve_undo_redo()
	if undo_redo == null:
		_ack(command, "error", "EditorUndoRedoManager is unavailable", details)
		return
	var save_context: Dictionary = {}
	if save_scene:
		save_context = _prepare_scene_save(details, root)
		if save_context.get("ok", false) != true:
			_ack(command, "error", str(save_context.get("message", "scene save preparation failed; write aborted")), details)
			return
	undo_redo.create_action("Godot AI Workbench: rename node %s -> %s" % [resolved_node_path, new_node_path], 0, root)
	undo_redo.add_do_property(node, "name", new_name)
	undo_redo.add_undo_property(node, "name", old_name)
	undo_redo.commit_action()
	if str(node.name) != new_name:
		details["applied_name"] = str(node.name)
		_ack(command, "error", "node rename verification failed", details)
		return
	new_node_path = _workbench_scene_node_path(root, node)
	details["new_path"] = new_node_path
	details["applied_name"] = str(node.name)
	details["affected_nodes"] = [resolved_node_path, new_node_path]
	details["status"] = "applied"
	details["saved"] = false
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Write save failed: rename %s -> %s" % [resolved_node_path, new_name])
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	else:
		details["saved"] = false
	_write_audit(details)
	_send_editor_state()
	_add_operation("Write: rename %s -> %s" % [resolved_node_path, new_name])
	_ack(command, "ok", "node renamed", details)


func _handle_save_scene_command(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var allow_existing_changes: bool = _bool(args.get("allow_existing_changes", false), false)
	var allow_structure_changes: bool = _bool(args.get("allow_structure_changes", false), false)
	var details: Dictionary = _write_base_details("editor.save_scene")
	details["allow_existing_changes"] = allow_existing_changes
	details["allow_structure_changes"] = allow_structure_changes
	details["save_mode"] = "standalone"
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var root: Node = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var scene_path: String = root.scene_file_path.strip_edges()
	details["scene_path"] = scene_path
	if scene_path == "":
		_ack(command, "error", "save scene requires a scene file path", details)
		return
	details["affected_files"] = [scene_path]
	details["affected_nodes"] = []
	details["scene_file_absolute"] = ProjectSettings.globalize_path(scene_path)
	if FileAccess.file_exists(str(details.get("scene_file_absolute", ""))):
		details["current_scene_hash"] = _file_md5(str(details.get("scene_file_absolute", "")))
		details["current_scene_size"] = _file_size(str(details.get("scene_file_absolute", "")))
	details["pre_save_dirty_state"] = _scene_dirty_state()
	details["pre_save_structure_state"] = _scene_structure_state(root, scene_path)
	details["would_change"] = true
	if not allow_existing_changes:
		_ack(command, "error", "standalone save scene requires allow_existing_changes=true", details)
		return
	root = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root before save", details)
		return
	if root.scene_file_path != scene_path:
		details["current_scene_path"] = root.scene_file_path
		_ack(command, "error", "edited scene changed before save", details)
		return
	var save_context: Dictionary = _prepare_scene_save(details, root, allow_existing_changes, allow_structure_changes)
	if save_context.get("ok", false) != true:
		_ack(command, "error", str(save_context.get("message", "scene save preparation failed; save aborted")), details)
		return
	details["status"] = "applied"
	details["saved"] = false
	var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
	if save_result.get("ok", false) != true:
		_write_audit(details)
		_send_editor_state()
		_add_operation("Write save failed: save scene %s" % scene_path)
		_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
		return
	_write_audit(details)
	_send_editor_state()
	_add_operation("Write: save scene %s" % scene_path)
	_ack(command, "ok", "scene saved", details)


func _handle_move_node_command(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var new_parent_path: String = str(args.get("new_parent_path", "")).strip_edges()
	var details: Dictionary = _write_base_details("editor.move_node")
	details["save_scene"] = save_scene
	details["node_path"] = node_path
	details["new_parent_path"] = new_parent_path
	details["new_index_provided"] = args.has("new_index")
	if args.has("new_index"):
		details["requested_index"] = _int(args.get("new_index", -1), -1)
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if node_path == "":
		_ack(command, "error", "node_path is required", details)
		return
	if new_parent_path == "":
		_ack(command, "error", "new_parent_path is required", details)
		return
	var root: Node = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _resolve_write_target_node(root, node_path, details)
	if node == null:
		_ack(command, "error", str(details.get("target_error", "node not found")), details)
		return
	if node == root:
		_ack(command, "error", "moving the scene root is deferred", details)
		return
	var old_parent: Node = node.get_parent()
	if old_parent == null:
		_ack(command, "error", "target node has no parent", details)
		return
	var new_parent: Node = _find_scene_node(root, new_parent_path)
	if new_parent == null:
		_ack(command, "error", "new_parent_path was not found", details)
		return
	if new_parent == node or node.is_ancestor_of(new_parent):
		_ack(command, "error", "cannot move a node under itself or its descendant", details)
		return
	var node_name: String = str(node.name)
	var old_path: String = _workbench_scene_node_path(root, node)
	var old_parent_path: String = _workbench_scene_node_path(root, old_parent)
	var resolved_new_parent_path: String = _workbench_scene_node_path(root, new_parent)
	var existing_name_peer: Node = new_parent.get_node_or_null(NodePath(node_name))
	if existing_name_peer != null and existing_name_peer != node:
		_ack(command, "error", "new parent already has a child with this node name", details)
		return
	var old_index: int = node.get_index()
	var index_plan: Dictionary = _move_index_plan(args, old_parent, new_parent, old_index)
	if index_plan.get("ok", false) != true:
		details["index_error"] = str(index_plan.get("message", "invalid new_index"))
		details["index_plan"] = index_plan
		_ack(command, "error", "invalid new_index", details)
		return
	var target_index: int = int(index_plan.get("target_index", old_index))
	var new_path: String = "%s/%s" % [resolved_new_parent_path, node_name]
	var would_change: bool = old_parent != new_parent or old_index != target_index
	details["scene_path"] = root.scene_file_path
	details["old_path"] = old_path
	details["new_path"] = new_path
	details["old_parent_path"] = old_parent_path
	details["resolved_new_parent_path"] = resolved_new_parent_path
	details["node_name"] = node_name
	details["old_index"] = old_index
	details["target_index"] = target_index
	details["index_plan"] = index_plan
	details["would_change"] = would_change
	if not would_change:
		details["status"] = "unchanged"
		_ack(command, "ok", "node already has requested parent and index", details)
		return
	root = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root before apply", details)
		return
	if root.scene_file_path != str(details.get("scene_path", "")):
		details["current_scene_path"] = root.scene_file_path
		_ack(command, "error", "edited scene changed before apply", details)
		return
	node = _find_scene_node(root, old_path)
	if node == null:
		_ack(command, "error", "node not found before apply", details)
		return
	old_parent = _find_scene_node(root, old_parent_path)
	new_parent = _find_scene_node(root, resolved_new_parent_path)
	if old_parent == null or new_parent == null:
		_ack(command, "error", "parent path changed before apply", details)
		return
	if node.get_parent() != old_parent:
		_ack(command, "error", "node parent changed before apply", details)
		return
	if new_parent == node or node.is_ancestor_of(new_parent):
		_ack(command, "error", "cannot move a node under itself or its descendant before apply", details)
		return
	if str(node.name) != node_name:
		details["current_name"] = str(node.name)
		_ack(command, "error", "node name changed before apply", details)
		return
	existing_name_peer = new_parent.get_node_or_null(NodePath(node_name))
	if existing_name_peer != null and existing_name_peer != node:
		_ack(command, "error", "new parent already has a child with this node name before apply", details)
		return
	index_plan = _move_index_plan(args, old_parent, new_parent, node.get_index())
	if index_plan.get("ok", false) != true:
		details["index_error"] = str(index_plan.get("message", "invalid new_index before apply"))
		details["index_plan"] = index_plan
		_ack(command, "error", "invalid new_index before apply", details)
		return
	target_index = int(index_plan.get("target_index", node.get_index()))
	details["apply_rechecked"] = true
	details["target_index"] = target_index
	details["index_plan"] = index_plan
	var undo_redo := _resolve_undo_redo()
	if undo_redo == null:
		_ack(command, "error", "EditorUndoRedoManager is unavailable", details)
		return
	var save_context: Dictionary = {}
	if save_scene:
		save_context = _prepare_scene_save(details, root)
		if save_context.get("ok", false) != true:
			_ack(command, "error", str(save_context.get("message", "scene save preparation failed; write aborted")), details)
			return
	var original_owner: Node = node.owner
	undo_redo.create_action("Godot AI Workbench: move node %s -> %s" % [old_path, new_path], 0, root)
	undo_redo.add_do_method(self, "_move_node_direct", node, new_parent, target_index, root)
	undo_redo.add_undo_method(self, "_move_node_direct", node, old_parent, old_index, original_owner)
	undo_redo.commit_action()
	if node.get_parent() != new_parent:
		_ack(command, "error", "node move verification failed", details)
		return
	var applied_path: String = _workbench_scene_node_path(root, node)
	if applied_path != new_path:
		details["applied_path"] = applied_path
		_ack(command, "error", "node move path verification failed", details)
		return
	details["new_path"] = applied_path
	details["applied_index"] = node.get_index()
	details["affected_nodes"] = [old_path, applied_path]
	details["status"] = "applied"
	details["saved"] = false
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Write save failed: move %s" % old_path)
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	else:
		details["saved"] = false
	_write_audit(details)
	_send_editor_state()
	_add_operation("Write: move %s -> %s" % [old_path, resolved_new_parent_path])
	_ack(command, "ok", "node moved", details)


func _handle_delete_node_command(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_scene: bool = _bool(args.get("save_scene", false), false)
	var allow_non_leaf: bool = _bool(args.get("allow_non_leaf", false), false)
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var details: Dictionary = _write_base_details("editor.delete_node")
	details["save_scene"] = save_scene
	details["allow_non_leaf"] = allow_non_leaf
	details["node_path"] = node_path
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if node_path == "":
		_ack(command, "error", "node_path is required", details)
		return
	var root: Node = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root", details)
		return
	var node: Node = _find_scene_node(root, node_path)
	if node == null:
		_ack(command, "error", "node not found", details)
		return
	if node == root:
		_ack(command, "error", "deleting the scene root is deferred", details)
		return
	if node.owner != root:
		details["node_owner"] = _node_owner_label(node)
		_ack(command, "error", "deleting non-owned or instanced nodes is deferred", details)
		return
	var parent: Node = node.get_parent()
	if parent == null:
		_ack(command, "error", "target node has no parent", details)
		return
	var resolved_path: String = _workbench_scene_node_path(root, node)
	var parent_path: String = _workbench_scene_node_path(root, parent)
	var node_name: String = str(node.name)
	var child_count: int = node.get_child_count()
	var descendant_count: int = _node_descendant_count(node)
	details["scene_path"] = root.scene_file_path
	details["resolved_node_path"] = resolved_path
	details["parent_path"] = parent_path
	details["node_name"] = node_name
	details["old_index"] = node.get_index()
	details["child_count"] = child_count
	details["descendant_count"] = descendant_count
	details["would_change"] = true
	if child_count > 0 and not allow_non_leaf:
		_ack(command, "error", "delete node refused because target has children; set allow_non_leaf=true", details)
		return
	root = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	if root == null:
		_ack(command, "error", "no edited scene root before apply", details)
		return
	if root.scene_file_path != str(details.get("scene_path", "")):
		details["current_scene_path"] = root.scene_file_path
		_ack(command, "error", "edited scene changed before apply", details)
		return
	node = _find_scene_node(root, resolved_path)
	if node == null:
		_ack(command, "error", "node not found before apply", details)
		return
	parent = _find_scene_node(root, parent_path)
	if parent == null or node.get_parent() != parent:
		_ack(command, "error", "node parent changed before apply", details)
		return
	if str(node.name) != node_name:
		details["current_name"] = str(node.name)
		_ack(command, "error", "node name changed before apply", details)
		return
	if node.owner != root:
		details["node_owner"] = _node_owner_label(node)
		_ack(command, "error", "node ownership changed before apply", details)
		return
	child_count = node.get_child_count()
	descendant_count = _node_descendant_count(node)
	details["child_count"] = child_count
	details["descendant_count"] = descendant_count
	if child_count > 0 and not allow_non_leaf:
		_ack(command, "error", "delete node refused because target has children before apply", details)
		return
	details["apply_rechecked"] = true
	var undo_redo := _resolve_undo_redo()
	if undo_redo == null:
		_ack(command, "error", "EditorUndoRedoManager is unavailable", details)
		return
	var save_context: Dictionary = {}
	if save_scene:
		save_context = _prepare_scene_save(details, root)
		if save_context.get("ok", false) != true:
			_ack(command, "error", str(save_context.get("message", "scene save preparation failed; write aborted")), details)
			return
	var old_index: int = node.get_index()
	var original_owner: Node = node.owner
	undo_redo.create_action("Godot AI Workbench: delete node %s" % resolved_path, 0, root)
	undo_redo.add_do_method(self, "_detach_node_direct", node)
	undo_redo.add_undo_method(self, "_move_node_direct", node, parent, old_index, original_owner)
	undo_redo.add_undo_reference(node)
	undo_redo.commit_action()
	if node.get_parent() != null:
		_ack(command, "error", "node delete verification failed", details)
		return
	details["affected_nodes"] = [resolved_path]
	details["status"] = "applied"
	details["saved"] = false
	if save_scene:
		var save_result: Dictionary = _finalize_scene_save(details, root, save_context)
		if save_result.get("ok", false) != true:
			_write_audit(details)
			_send_editor_state()
			_add_operation("Write save failed: delete %s" % resolved_path)
			_ack(command, "error", str(save_result.get("message", "scene save failed")), details)
			return
	else:
		details["saved"] = false
	_write_audit(details)
	_send_editor_state()
	_add_operation("Write: delete %s" % resolved_path)
	_ack(command, "ok", "node deleted", details)



func _move_index_plan(args: Dictionary, old_parent: Node, new_parent: Node, old_index: int) -> Dictionary:
	var result: Dictionary = {"ok": false, "provided": args.has("new_index"), "old_index": old_index}
	if old_parent == null or new_parent == null:
		result["message"] = "parent is unavailable"
		return result
	var same_parent: bool = old_parent == new_parent
	var child_count: int = new_parent.get_child_count()
	var max_index: int = child_count
	if same_parent:
		max_index = max(child_count - 1, 0)
	var target_index: int = old_index
	if not same_parent:
		target_index = child_count
	result["same_parent"] = same_parent
	result["child_count"] = child_count
	result["max_index"] = max_index
	if args.has("new_index"):
		var requested_index: int = _int(args.get("new_index", -1), -1)
		result["requested_index"] = requested_index
		if requested_index < -1:
			result["message"] = "new_index must be -1 or greater"
			return result
		if requested_index == -1:
			target_index = max_index
		else:
			if requested_index > max_index:
				result["message"] = "new_index is outside target parent child range"
				return result
			target_index = requested_index
	result["target_index"] = target_index
	result["ok"] = true
	result["message"] = "move index ok"
	return result


func _move_node_direct(node: Node, target_parent: Node, target_index: int, owner: Node) -> void:
	if node == null or target_parent == null:
		return
	var current_parent: Node = node.get_parent()
	if current_parent != target_parent:
		if current_parent != null:
			current_parent.remove_child(node)
		target_parent.add_child(node)
	node.owner = owner
	var max_index: int = max(target_parent.get_child_count() - 1, 0)
	var clamped_index: int = int(clamp(target_index, 0, max_index))
	target_parent.move_child(node, clamped_index)


func _detach_node_direct(node: Node) -> void:
	if node == null:
		return
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)


func _node_descendant_count(node: Node) -> int:
	if node == null:
		return 0
	var count := 0
	for child: Node in node.get_children():
		count += 1
		count += _node_descendant_count(child)
	return count


func _node_owner_label(node: Node) -> String:
	if node == null:
		return "-"
	var owner: Node = node.owner
	if owner == null:
		return "<none>"
	return str(owner.name)



func _dict(value: Variant) -> Dictionary:
	var result: Variant = _host.call("workbench_dictionary", value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _bool(value: Variant, default_value: bool) -> bool:
	return bool(_host.call("workbench_bool", value, default_value))


func _int(value: Variant, default_value: int) -> int:
	return int(_host.call("workbench_int", value, default_value))


func _write_gate_open() -> bool:
	return bool(_host.call("write_gate_open"))


func _write_base_details(action: String) -> Dictionary:
	var result: Variant = _host.call("write_base_details", action)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"action": action}


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


func _validate_script_resource_path(script_path: String) -> Dictionary:
	var result: Variant = _host.call("validate_script_resource_path", script_path)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"ok": false, "message": "script path validator did not return a result"}


func _request_resource_filesystem_scan(path: String) -> Dictionary:
	if _host != null and _host.has_method("request_resource_filesystem_scan"):
		var result: Variant = _host.call("request_resource_filesystem_scan", path)
		if typeof(result) == TYPE_DICTIONARY:
			return result
	return {"ok": false, "path": path, "message": "resource filesystem scan helper is unavailable"}


func _script_snapshot(script_value: Variant) -> Dictionary:
	var result: Variant = _host.call("script_snapshot", script_value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"type": "Variant", "value": str(script_value)}


func _script_compatibility(node: Node, script_resource: Script) -> Dictionary:
	var result: Variant = _host.call("script_compatibility", node, script_resource)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"ok": false, "message": "script compatibility did not return a result"}


func _scripts_equal(left: Variant, right: Variant) -> bool:
	return bool(_host.call("scripts_equal", left, right))


func _resolve_write_target_node(root: Node, node_path: String, details: Dictionary) -> Node:
	var result: Variant = _host.call("resolve_write_target_node", root, node_path, details)
	if result is Node:
		return result
	return null


func _find_scene_node(root: Node, path: String) -> Node:
	var result: Variant = _host.call("find_scene_node", root, path)
	if result is Node:
		return result
	return null


func _workbench_scene_node_path(root: Node, node: Node) -> String:
	return str(_host.call("workbench_scene_node_path", root, node))


func _resolve_undo_redo() -> EditorUndoRedoManager:
	var result: Variant = _host.call("resolve_undo_redo")
	if result is EditorUndoRedoManager:
		return result
	return null


func _prepare_scene_save(details: Dictionary, root: Node, allow_existing_changes: bool = false, allow_structure_changes: bool = false) -> Dictionary:
	var result: Variant = _host.call("prepare_scene_save", details, root, allow_existing_changes, allow_structure_changes)
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


func _file_size(path: String) -> int:
	return int(_host.call("file_size", path))


func _file_md5(path: String) -> String:
	return str(_host.call("file_md5", path))


func _scene_dirty_state() -> Dictionary:
	var result: Variant = _host.call("scene_dirty_state")
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _scene_structure_state(root: Node, scene_path: String) -> Dictionary:
	var result: Variant = _host.call("scene_structure_state", root, scene_path)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _ack(command: Dictionary, status: String, message: String, details: Dictionary) -> void:
	_host.call("ack_dev_command", command, status, message, details)
