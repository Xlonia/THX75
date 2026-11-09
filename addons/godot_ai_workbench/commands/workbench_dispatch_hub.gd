extends RefCounted

const DEBUG_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_debug_ops.gd"
const BATCH_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_batch_ops.gd"
const DOMAIN_BEHAVIOR_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_domain_behavior_ops.gd"
const DOMAIN_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_domain_ops.gd"
const DOMAIN_RESOURCE_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_domain_resource_ops.gd"
const DOMAIN_UI_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_domain_ui_ops.gd"
const DOMAIN_UTILITY_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_domain_utility_ops.gd"
const DOMAIN_WORLD_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_domain_world_ops.gd"
const EDITOR_CAMERA_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_editor_camera_ops.gd"
const EDITOR_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_editor_ops.gd"
const NODE_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_node_ops.gd"
const RUNTIME_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_runtime_ops.gd"
const RESOURCE_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_resource_ops.gd"
const SCENE_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_scene_ops.gd"
const SCENE_EDIT_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_scene_edit_ops.gd"
const SETTINGS_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_settings_ops.gd"
const SCRIPT_OPS_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_script_ops.gd"

var _host
var _command_modules: Array = []
var _processed_ids: Dictionary = {}
var runtime_ops


func setup(host, editor_interface = null) -> void:
	_host = host
	_command_modules.clear()
	_append_module(DEBUG_OPS_SCRIPT_PATH, false, editor_interface)
	_append_module(SCRIPT_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(SETTINGS_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(SCENE_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(NODE_OPS_SCRIPT_PATH, false, editor_interface)
	_append_module(EDITOR_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(EDITOR_CAMERA_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(SCENE_EDIT_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(RESOURCE_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(DOMAIN_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(DOMAIN_WORLD_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(DOMAIN_RESOURCE_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(DOMAIN_BEHAVIOR_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(DOMAIN_UTILITY_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(DOMAIN_UI_OPS_SCRIPT_PATH, true, editor_interface)
	_append_module(BATCH_OPS_SCRIPT_PATH, true, editor_interface)
	runtime_ops = _append_module(RUNTIME_OPS_SCRIPT_PATH, true, editor_interface)


func _append_module(script_path: String, needs_editor_interface: bool, editor_interface = null):
	var module = _new_ref_counted_module(script_path)
	if module == null:
		return null
	if module.has_method("setup"):
		if needs_editor_interface:
			module.setup(_host, editor_interface)
		else:
			module.setup(_host)
	_command_modules.append(module)
	return module


func _new_ref_counted_module(script_path: String) -> Variant:
	var script_resource: Variant = ResourceLoader.load(script_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
	if script_resource == null or not (script_resource is GDScript):
		push_error("Godot AI Workbench: command module load failed: %s" % script_path)
		return null
	return script_resource.new()


func implemented_commands() -> Array:
	var commands: Array = [
		"editor.state",
		"scene.tree",
		"selection",
		"debug.snapshot",
		"debug.output_snapshot",
		"debug.output_clear",
		"workbench.dev_control"
	]
	for module in _command_modules:
		if module.has_method("handled_commands"):
			for command_name: Variant in module.handled_commands():
				if not commands.has(str(command_name)):
					commands.append(str(command_name))
	return commands


func service(delta: float) -> void:
	for module in _command_modules:
		if module.has_method("service"):
			module.service(delta)


func dispatch(command: Dictionary) -> void:
	var id: String = str(command.get("id", ""))
	if id == "":
		return
	if _processed_ids.has(id):
		return
	_processed_ids[id] = true
	var command_name: String = str(command.get("command", ""))
	match command_name:
		"panel.reload":
			_host.call("add_operation", "Dev control: panel reload")
			_host.call("ack_dev_command", command, "ok", "panel reload scheduled", _host.call("dev_details"))
			_host.call("schedule_panel_reload")
			return
		"bridge.reconnect":
			_host.call("add_operation", "Dev control: reconnect")
			_host.call("ack_dev_command", command, "ok", "bridge reconnect scheduled", _host.call("dev_details"))
			_host.call("schedule_bridge_reconnect")
			return
		"editor.send_state":
			if _host.call("handshake_complete"):
				_host.call("send_editor_state")
				_host.call("add_operation", "Dev control: editor state sent")
				_host.call("ack_dev_command", command, "ok", "editor state sent", _host.call("dev_details"))
			else:
				_host.call("ack_dev_command", command, "error", "bridge handshake is not complete", _host.call("dev_details"))
			return
		"panel.self_test":
			_host.call("add_operation", "Dev control: self-test ok")
			_host.call("ack_dev_command", command, "ok", "panel self-test ok", _host.call("dev_details"))
			return
		"debug.output_snapshot":
			var snapshot: Dictionary = _host.call("debug_snapshot", true)
			_host.call("send_request", "debug.snapshot", snapshot)
			_host.call("refresh_debug_label", snapshot)
			_host.call("add_operation", "Dev control: debug snapshot sent")
			_host.call("ack_dev_command", command, "ok", "debug snapshot sent", snapshot)
			return
		"debug.output_clear":
			var clear_snapshot: Dictionary = _host.call("clear_debug_output")
			_host.call("send_request", "debug.snapshot", {
				"sequence": int(clear_snapshot.get("sequence", 0)),
				"captured_at": str(clear_snapshot.get("captured_at", "")),
				"total_events": 0,
				"events": [],
				"sessions": [],
				"probe_available": true,
				"editor_output": clear_snapshot
			})
			_host.call("add_operation", "Dev control: debug output cleared")
			_host.call("ack_dev_command", command, "ok", "debug output cleared", clear_snapshot)
			return
		"profile.full_control", "profile.analysis":
			var target_profile: String = command_name.replace("profile.", "")
			_host.call("select_profile_id", target_profile)
			_host.call("add_operation", "Dev control: profile %s" % target_profile)
			_host.call("ack_dev_command", command, "ok", "profile switch scheduled", _host.call("dev_details"))
			_host.call("schedule_bridge_reconnect")
			return
	for module in _command_modules:
		if module.has_method("handle") and module.handle(command):
			return
	_host.call("add_operation", "Dev control: unknown command %s" % command_name)
	_host.call("ack_dev_command", command, "error", "unknown dev control command", _host.call("dev_details"))
