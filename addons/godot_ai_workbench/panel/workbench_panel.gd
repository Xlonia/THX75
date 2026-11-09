@tool
extends VBoxContainer

signal workbench_reload_requested(settings: Dictionary)

const WorkbenchBridgeSpec = preload("res://addons/godot_ai_workbench/transport/workbench_bridge_spec.gd")

const ADDON_VERSION := WorkbenchBridgeSpec.ADDON_VERSION
const PROTOCOL_VERSION := WorkbenchBridgeSpec.PROTOCOL_VERSION
const DEFAULT_URL := WorkbenchBridgeSpec.DEFAULT_URL
const DEFAULT_PORT := 8765
const BRIDGE_CLIENT_SCRIPT_PATH := "res://addons/godot_ai_workbench/transport/workbench_bridge_client.gd"
const DISPATCH_HUB_SCRIPT_PATH := "res://addons/godot_ai_workbench/commands/workbench_dispatch_hub.gd"
const OUTPUT_PROBE_SCRIPT_PATH := "res://addons/godot_ai_workbench/services/workbench_output_probe.gd"
const VARIANT_CODEC_SCRIPT_PATH := "res://addons/godot_ai_workbench/services/workbench_variant_codec.gd"
const SCRIPT_RESOURCE_SCRIPT_PATH := "res://addons/godot_ai_workbench/services/workbench_script_resource.gd"
const DEBUG_SNAPSHOT_INTERVAL_MSEC := 5000
const DEBUG_OUTPUT_REFRESH_DELAY_MSEC := 250
const DEV_CONTROL_POLL_INTERVAL_MSEC := 150
const OUTPUT_PANEL_SCAN_LIMIT := 80
const RECONNECT_INITIAL_DELAY_MSEC := 750
const RECONNECT_MAX_DELAY_MSEC := 10000
const CONNECT_TIMEOUT_MSEC := 3500
const USER_SETTINGS_PATH := "user://godot_ai_workbench.cfg"
const USER_SETTINGS_SECTION := "connection"

var _editor_interface: EditorInterface
var _debug_probe: EditorDebuggerPlugin
var _undo_redo: EditorUndoRedoManager
var _connect_desired := false
var _handshake_sent := false
var _handshake_complete := false
var _last_state_sent_msec := 0
var _last_debug_snapshot_sent_msec := 0
var _connect_started_msec := 0
var _debug_output_refresh_after_msec := 0
var _last_heartbeat_msec := 0
var _last_dev_control_poll_msec := 0
var _dev_control_poll_pending := false
var _last_connection_event := "Never connected"
var _last_connection_error := ""
var _legacy_timers_removed := false
var _reload_after_msec := 0
var _reconnect_after_msec := 0
var _ui_ready := false
var _pending_restore_settings: Dictionary = {}
var _server_active_profile := "analysis"
var _server_write_allowed := false
var _bridge_client
var _dispatch_hub
var _output_probe
var _property_codec
var _script_resource_service
var _backend_load_failures: Array[Dictionary] = []

var _status_label: Label
var _port_spin: SpinBox
var _profile_picker: OptionButton
var _connect_button: Button
var _disconnect_button: Button
var _protocol_label: Label
var _addon_label: Label
var _godot_label: Label
var _project_label: Label
var _access_label: Label
var _connection_label: Label
var _reconnect_label: Label
var _compatibility_label: Label
var _debug_label: Label
var _operations: ItemList

func setup(editor_interface: EditorInterface, debug_probe: EditorDebuggerPlugin = null, undo_redo: EditorUndoRedoManager = null) -> void:
	_editor_interface = editor_interface
	_debug_probe = debug_probe
	_undo_redo = undo_redo
	_request_resource_filesystem_scan()
	_reload_backend_modules()
	if _output_probe != null:
		_output_probe.setup(_editor_interface, _debug_probe)
	if _dispatch_hub != null:
		_dispatch_hub.setup(self, _editor_interface)


func _reload_backend_modules() -> void:
	_backend_load_failures.clear()
	_bridge_client = _new_ref_counted_module(BRIDGE_CLIENT_SCRIPT_PATH)
	_dispatch_hub = _new_ref_counted_module(DISPATCH_HUB_SCRIPT_PATH)
	_output_probe = _new_ref_counted_module(OUTPUT_PROBE_SCRIPT_PATH)
	_property_codec = _new_ref_counted_module(VARIANT_CODEC_SCRIPT_PATH)
	_script_resource_service = _new_ref_counted_module(SCRIPT_RESOURCE_SCRIPT_PATH)


func request_resource_filesystem_scan(path: String = "") -> Dictionary:
	return _request_resource_filesystem_scan(path)


func _request_resource_filesystem_scan(path: String = "") -> Dictionary:
	var result: Dictionary = {"ok": false, "path": path, "methods": []}
	if _editor_interface == null or not _editor_interface.has_method("get_resource_filesystem"):
		result["message"] = "EditorInterface resource filesystem is unavailable"
		return result
	var resource_filesystem: Variant = _editor_interface.call("get_resource_filesystem")
	if resource_filesystem == null:
		result["message"] = "EditorFileSystem is unavailable"
		return result
	var methods: Array[String] = []
	if path != "" and resource_filesystem.has_method("update_file"):
		resource_filesystem.call("update_file", path)
		methods.append("update_file")
	if resource_filesystem.has_method("scan_sources"):
		resource_filesystem.call("scan_sources")
		methods.append("scan_sources")
	elif resource_filesystem.has_method("scan"):
		resource_filesystem.call("scan")
		methods.append("scan")
	if methods.is_empty():
		result["message"] = "EditorFileSystem has no supported scan method"
		return result
	result["ok"] = true
	result["methods"] = methods
	result["message"] = "resource filesystem scan requested"
	return result


func _new_ref_counted_module(script_path: String) -> Variant:
	var script_resource: Variant = ResourceLoader.load(script_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
	if script_resource == null or not (script_resource is GDScript):
		_backend_load_failures.append({
			"path": script_path,
			"exists": FileAccess.file_exists(ProjectSettings.globalize_path(script_path)),
			"reason": "resource_load_failed"
		})
		push_error("Godot AI Workbench: module load failed: %s" % script_path)
		return null
	var instance: Variant = script_resource.new()
	if instance == null:
		_backend_load_failures.append({
			"path": script_path,
			"exists": FileAccess.file_exists(ProjectSettings.globalize_path(script_path)),
			"reason": "instance_create_failed"
		})
		push_error("Godot AI Workbench: module instance failed: %s" % script_path)
		return null
	return instance


func restore_dev_settings(settings: Dictionary) -> void:
	if not _ui_ready:
		_pending_restore_settings = settings.duplicate(true)
		return
	_apply_dev_settings(settings)


func _apply_dev_settings(settings: Dictionary) -> void:
	if settings.has("port"):
		_set_bridge_port(settings.get("port", DEFAULT_PORT))
	elif settings.has("url"):
		_set_bridge_port(_port_from_url(str(settings.get("url", DEFAULT_URL))))
	if settings.has("profile"):
		_select_profile_id(str(settings.get("profile", "analysis")))
	elif settings.has("profile_index"):
		var profile_index: int = int(settings.get("profile_index", 0))
		if profile_index == 2:
			_select_profile_id("full_control")
		elif profile_index >= 0 and profile_index < _profile_picker.item_count:
			_profile_picker.select(profile_index)
	var should_reconnect: bool = settings.get("reconnect", false) == true
	if settings.get("connect_desired", false) == true:
		should_reconnect = true
	if should_reconnect:
		call_deferred("_on_connect_pressed")


func _load_persisted_connection_settings() -> void:
	var config := ConfigFile.new()
	var error_code: int = config.load(USER_SETTINGS_PATH)
	if error_code != OK:
		return
	if config.has_section_key(USER_SETTINGS_SECTION, "port"):
		_set_bridge_port(config.get_value(USER_SETTINGS_SECTION, "port", DEFAULT_PORT))
	elif config.has_section_key(USER_SETTINGS_SECTION, "url"):
		_set_bridge_port(_port_from_url(str(config.get_value(USER_SETTINGS_SECTION, "url", DEFAULT_URL))))
	_select_profile_id(str(config.get_value(USER_SETTINGS_SECTION, "profile", "analysis")))


func _save_persisted_connection_settings() -> void:
	if _port_spin == null or _profile_picker == null:
		return
	var config := ConfigFile.new()
	config.set_value(USER_SETTINGS_SECTION, "port", _bridge_port())
	config.set_value(USER_SETTINGS_SECTION, "profile", _selected_profile_id())
	var error_code: int = config.save(USER_SETTINGS_PATH)
	if error_code != OK:
		_last_connection_error = "Connection settings save failed: %s" % error_string(error_code)


func _on_connection_port_changed(_new_value: float) -> void:
	_save_persisted_connection_settings()


func _bridge_url() -> String:
	return "ws://127.0.0.1:%d/bridge" % _bridge_port()


func _bridge_port() -> int:
	if _port_spin == null:
		return DEFAULT_PORT
	return int(clamp(int(round(_port_spin.value)), 1, 65535))


func _set_bridge_port(value: Variant) -> void:
	if _port_spin == null:
		return
	_port_spin.value = _port_from_value(value)


func _port_from_value(value: Variant) -> int:
	var text := str(value).strip_edges()
	if text.begins_with("ws://") or text.begins_with("wss://"):
		return _port_from_url(text)
	if text.is_valid_int():
		return int(clamp(text.to_int(), 1, 65535))
	return DEFAULT_PORT


func _port_from_url(url: String) -> int:
	var value := url.strip_edges()
	var scheme_marker := "://"
	var host_and_path := value
	var scheme_index := value.find(scheme_marker)
	if scheme_index >= 0:
		host_and_path = value.substr(scheme_index + scheme_marker.length())
	var slash_index := host_and_path.find("/")
	if slash_index >= 0:
		host_and_path = host_and_path.substr(0, slash_index)
	var colon_index := host_and_path.rfind(":")
	if colon_index < 0:
		return DEFAULT_PORT
	var raw_port := host_and_path.substr(colon_index + 1)
	if not raw_port.is_valid_int():
		return DEFAULT_PORT
	return int(clamp(raw_port.to_int(), 1, 65535))


func snapshot_dev_settings() -> Dictionary:
	var state: int = _bridge_ready_state()
	return {
		"port": _bridge_port(),
		"profile": _selected_profile_id(),
		"profile_index": _profile_picker.selected,
		"connect_desired": _connect_desired,
		"reconnect": _connect_desired or _handshake_complete or state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CONNECTING
	}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_load_persisted_connection_settings()
	_ui_ready = true
	_connect_editor_signals()
	_refresh_static_info()
	_set_status("Disconnected")
	if not _pending_restore_settings.is_empty():
		var settings: Dictionary = _pending_restore_settings
		_pending_restore_settings = {}
		restore_dev_settings(settings)


func service_workbench_bridge(_delta: float) -> void:
	_remove_legacy_timer_children()
	_poll_socket()
	if _dispatch_hub != null and _dispatch_hub.has_method("service"):
		_dispatch_hub.service(_delta)
	_service_auto_reconnect()
	_service_deferred_dev_actions()


func _on_poll_timer() -> void:
	pass


func _on_heartbeat_timer() -> void:
	pass


func _on_state_timer() -> void:
	pass


func _poll_socket() -> void:
	if _bridge_client == null:
		return
	var poll_result: Dictionary = _bridge_client.poll()
	var state: int = int(poll_result.get("state", WebSocketPeer.STATE_CLOSED))
	if state == WebSocketPeer.STATE_OPEN:
		_connect_started_msec = 0
		if not _handshake_sent:
			_send_hello()
		_handle_transport_responses(_workbench_array(poll_result.get("responses", [])))
		_handle_invalid_transport_messages(_workbench_array(poll_result.get("invalid_messages", [])))
		_tick_dev_control_poll()
		_tick_heartbeat()
		_tick_editor_state()
		_tick_debug_snapshot()
	elif state == WebSocketPeer.STATE_CONNECTING:
		_handle_connecting_socket()
	elif state == WebSocketPeer.STATE_CLOSED:
		_handle_closed_socket()
	_update_connection_labels()
	_update_buttons()


func _build_ui() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Godot AI Workbench"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	_status_label = Label.new()
	_status_label.text = "Disconnected"
	_status_label.add_theme_font_size_override("font_size", 14)
	add_child(_status_label)
	add_child(_separator())

	add_child(_section_title("Connection Settings"))
	var settings_grid := GridContainer.new()
	settings_grid.columns = 2
	settings_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(settings_grid)

	settings_grid.add_child(_label("Port"))
	_port_spin = SpinBox.new()
	_port_spin.min_value = 1
	_port_spin.max_value = 65535
	_port_spin.step = 1
	_port_spin.value = DEFAULT_PORT
	_port_spin.custom_minimum_size = Vector2(160, 0)
	_port_spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_port_spin.tooltip_text = "Local bridge port. Address is fixed to ws://127.0.0.1:<port>/bridge."
	_port_spin.value_changed.connect(_on_connection_port_changed)
	settings_grid.add_child(_port_spin)

	settings_grid.add_child(_label("Profile"))
	_profile_picker = OptionButton.new()
	_profile_picker.add_item("Analysis", 0)
	_profile_picker.add_item("Full Control", 1)
	_profile_picker.custom_minimum_size = Vector2(220, 0)
	_profile_picker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_profile_picker.item_selected.connect(_on_profile_selected)
	settings_grid.add_child(_profile_picker)

	var connection_actions := HBoxContainer.new()
	connection_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(connection_actions)

	_connect_button = Button.new()
	_connect_button.text = "Connect"
	_connect_button.tooltip_text = "Connect this Godot editor to the local bridge."
	_connect_button.custom_minimum_size = Vector2(96, 0)
	_connect_button.pressed.connect(_on_connect_pressed)
	connection_actions.add_child(_connect_button)

	_disconnect_button = Button.new()
	_disconnect_button.text = "Disconnect"
	_disconnect_button.tooltip_text = "Disconnect and stop automatic reconnect attempts."
	_disconnect_button.custom_minimum_size = Vector2(96, 0)
	_disconnect_button.pressed.connect(_on_disconnect_pressed)
	connection_actions.add_child(_disconnect_button)

	add_child(_separator())
	add_child(_section_title("Bridge Status"))
	var info_grid := GridContainer.new()
	info_grid.columns = 2
	info_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(info_grid)

	info_grid.add_child(_label("Protocol"))
	_protocol_label = _value_label()
	info_grid.add_child(_protocol_label)

	info_grid.add_child(_label("Addon"))
	_addon_label = _value_label()
	info_grid.add_child(_addon_label)

	info_grid.add_child(_label("Godot"))
	_godot_label = _value_label()
	info_grid.add_child(_godot_label)

	info_grid.add_child(_label("Project"))
	_project_label = _value_label()
	info_grid.add_child(_project_label)

	info_grid.add_child(_label("Access"))
	_access_label = _value_label()
	info_grid.add_child(_access_label)

	info_grid.add_child(_label("Connection"))
	_connection_label = _value_label()
	info_grid.add_child(_connection_label)

	info_grid.add_child(_label("Reconnect"))
	_reconnect_label = _value_label()
	info_grid.add_child(_reconnect_label)

	info_grid.add_child(_label("Compatibility"))
	_compatibility_label = _value_label()
	info_grid.add_child(_compatibility_label)

	info_grid.add_child(_label("Debugger"))
	_debug_label = _value_label()
	info_grid.add_child(_debug_label)

	add_child(_separator())
	add_child(_section_title("Last Operations"))

	_operations = ItemList.new()
	_operations.custom_minimum_size = Vector2(0, 130)
	_operations.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_operations)

	_update_buttons()


func _connect_editor_signals() -> void:
	if _editor_interface == null:
		return
	var selection: EditorSelection = _editor_interface.get_selection()
	if selection == null:
		return
	var callback: Callable = Callable(self, "_on_editor_selection_changed")
	if selection.has_signal("selection_changed") and not selection.is_connected("selection_changed", callback):
		selection.connect("selection_changed", callback)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return separator


func _value_label() -> Label:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _refresh_static_info() -> void:
	_protocol_label.text = PROTOCOL_VERSION
	_addon_label.text = ADDON_VERSION
	var version: Dictionary = Engine.get_version_info()
	_godot_label.text = str(version.get("string", "unknown"))
	_project_label.text = ProjectSettings.globalize_path("res://")
	_access_label.text = "Local only, read-only"
	var implemented_commands: Array = []
	if _dispatch_hub != null:
		implemented_commands = _dispatch_hub.implemented_commands()
	var contract: Dictionary = WorkbenchBridgeSpec.handler_contract(implemented_commands)
	if contract.get("ok", false) == true:
		_compatibility_label.text = "Not connected"
	else:
		_compatibility_label.text = "Local handler mismatch"
		_add_operation("Missing local handlers: %s" % _join_values(_workbench_array(contract.get("missing", [])), ", "))
	_refresh_debug_label({})
	_update_connection_labels()


func _on_connect_pressed() -> void:
	_connect_desired = true
	_reset_reconnect_backoff()
	_last_connection_error = ""
	_save_persisted_connection_settings()
	_connect_to_bridge(true)


func _connect_to_bridge(add_log: bool) -> void:
	_disconnect_socket(false)
	if _bridge_client == null:
		_set_status("Connect failed")
		_schedule_reconnect("Bridge client is not loaded", true)
		return
	var bridge_url: String = _bridge_url()
	var connect_result: Dictionary = _bridge_client.connect_to_url(bridge_url)
	if connect_result.get("ok", false) != true:
		_set_status("Connect failed")
		_schedule_reconnect("WebSocket error: %s" % str(connect_result.get("message", "unknown")), true)
		return
	_handshake_sent = false
	_handshake_complete = false
	_connect_started_msec = Time.get_ticks_msec()
	_last_connection_event = "Connecting to %s" % bridge_url
	_set_status("Connecting")
	if add_log:
		_add_operation("Connecting to %s" % bridge_url)
	_update_buttons()


func _on_disconnect_pressed() -> void:
	_connect_desired = false
	_reset_reconnect_backoff()
	_last_connection_event = "Disconnected by user"
	_disconnect_socket(false)
	_set_status("Disconnected")
	_add_operation("Disconnected by user")


func _on_self_test_pressed() -> void:
	if not _handshake_complete:
		_add_operation("Self-test: local panel ok, bridge disconnected")
		return
	_send_request("bridge.self_test", {})


func _on_send_state_pressed() -> void:
	if not _handshake_complete:
		_add_operation("Send state skipped: bridge disconnected")
		return
	_send_request("bridge.heartbeat", {})
	_send_editor_state()
	_add_operation("Manual state send")


func _on_debug_snapshot_pressed() -> void:
	if not _handshake_complete:
		_add_operation("Debug snapshot skipped: bridge disconnected")
		return
	_send_debug_snapshot(true)
	_add_operation("Manual debug snapshot")


func _on_profile_selected(_index: int) -> void:
	_save_persisted_connection_settings()
	if _handshake_complete:
		_add_operation("Profile change will apply after reconnect")


func _send_hello() -> void:
	_handshake_sent = true
	var declared_handlers: Array = WorkbenchBridgeSpec.declared_handlers()
	var params: Dictionary = {
		"token": "",
		"protocol_version": PROTOCOL_VERSION,
		"addon_version": ADDON_VERSION,
		"godot_version": str(Engine.get_version_info().get("string", "unknown")),
		"project_path": ProjectSettings.globalize_path("res://"),
		"profile": _selected_profile_id(),
		"capabilities": {
			"editor_state": true,
			"scene_tree": true,
			"selection": true,
			"debug_snapshot": _debug_probe != null,
			"editor_output": true,
			"screenshot": _debug_probe != null and declared_handlers.has("runtime.screenshot"),
			"runtime_playback": true,
			"write_tools": _selected_profile_id() == "full_control"
		},
		"handlers": declared_handlers
	}
	_send_request("bridge.hello", params)


func _send_request(method: String, params: Dictionary) -> void:
	if _bridge_client == null:
		_set_warning("Bridge client is not loaded")
		return
	_bridge_client.send_request(method, params)


func _handle_transport_responses(responses: Array) -> void:
	for response_value: Variant in responses:
		if typeof(response_value) != TYPE_DICTIONARY:
			continue
		_handle_response(_workbench_dictionary(response_value))


func _handle_invalid_transport_messages(messages: Array) -> void:
	for _message_value: Variant in messages:
		_add_operation("Invalid bridge message")


func _handle_response(response: Dictionary) -> void:
	var method: String = str(response.get("method", ""))
	var payload: Dictionary = _workbench_dictionary(response.get("payload", {}))
	if payload.has("error"):
		var error: Dictionary = payload.get("error", {})
		if method == "workbench.dev_control_poll":
			_dev_control_poll_pending = false
		_set_status("Bridge error")
		_set_warning(str(error.get("message", "unknown error")))
		_add_operation("%s failed" % method)
		return
	var result: Dictionary = payload.get("result", {})
	if method == "bridge.hello":
		_handshake_complete = true
		_reset_reconnect_backoff()
		_last_connection_error = ""
		_last_connection_event = "Handshake complete"
		_set_status("Connected")
		_apply_hello_result(result)
		_handle_dev_commands(_workbench_array(result.get("dev_commands", [])))
		_send_editor_state()
		_request_debug_output_refresh()
		_add_operation("Handshake complete")
	elif method == "bridge.heartbeat":
		_handle_dev_commands(_workbench_array(result.get("dev_commands", [])))
	elif method == "workbench.dev_control_poll":
		_dev_control_poll_pending = false
		_handle_dev_commands(_workbench_array(result.get("dev_commands", [])))
	elif method == "bridge.self_test":
		_add_operation("Self-test ok")
	elif method == "editor.state":
		pass
	elif method == "debug.snapshot":
		pass
	_update_buttons()


func _apply_hello_result(result: Dictionary) -> void:
	_server_active_profile = str(result.get("active_profile", "analysis"))
	var auth_required: bool = result.get("auth_required", false)
	if auth_required:
		_access_label.text = "Local only, read-only, protected"
	else:
		_access_label.text = "Local only, read-only, dev auth disabled"
	var write_access: Dictionary = _workbench_dictionary(result.get("write_access", {}))
	_server_write_allowed = write_access.get("allowed", false) == true
	if _server_write_allowed:
		_access_label.text = "Local only, full control"
	elif str(write_access.get("reason", "")) != "":
		_access_label.text = "Local only, read-only: %s" % str(write_access.get("reason", "profile gate"))
	var compatibility: Dictionary = _workbench_dictionary(result.get("compatibility", {}))
	var missing: Array = _workbench_array(compatibility.get("missing_handlers", []))
	if missing.size() == 0:
		_compatibility_label.text = "OK"
	else:
		_compatibility_label.text = "Missing handlers: %s" % _join_values(missing, ", ")
	var warnings: Array = _workbench_array(compatibility.get("warnings", []))
	if warnings.size() > 0:
		_add_operation("Compatibility warnings: %s" % _join_values(warnings, "; "))


func _tick_heartbeat() -> void:
	var now: int = Time.get_ticks_msec()
	if _handshake_complete and now - _last_heartbeat_msec > 5000:
		_last_heartbeat_msec = now
		_send_request("bridge.heartbeat", {})


func _tick_dev_control_poll() -> void:
	var now: int = Time.get_ticks_msec()
	if _handshake_complete and not _dev_control_poll_pending and now - _last_dev_control_poll_msec > DEV_CONTROL_POLL_INTERVAL_MSEC:
		_last_dev_control_poll_msec = now
		_dev_control_poll_pending = true
		_send_request("workbench.dev_control_poll", {})


func _tick_editor_state() -> void:
	var now: int = Time.get_ticks_msec()
	if _handshake_complete and now - _last_state_sent_msec > 3000:
		_last_state_sent_msec = now
		_send_editor_state()


func _tick_debug_snapshot() -> void:
	var now: int = Time.get_ticks_msec()
	if _handshake_complete and now - _last_debug_snapshot_sent_msec > DEBUG_SNAPSHOT_INTERVAL_MSEC:
		_last_debug_snapshot_sent_msec = now
		_send_debug_snapshot(true)


func _handle_dev_commands(commands: Array) -> void:
	for command_value: Variant in commands:
		if typeof(command_value) != TYPE_DICTIONARY:
			continue
		var command: Dictionary = command_value
		_handle_dev_command(command)


func _handle_dev_command(command: Dictionary) -> void:
	if _dispatch_hub == null:
		_ack_dev_command(command, "error", "command modules are not loaded", _dev_details())
		return
	_dispatch_hub.dispatch(command)



func _runtime_status() -> Dictionary:
	if _dispatch_hub != null and _dispatch_hub.runtime_ops != null:
		return _dispatch_hub.runtime_ops.runtime_status()
	return {"available": false, "playing": false, "runtime_access": false}


func _runtime_gate_open() -> bool:
	if _dispatch_hub != null and _dispatch_hub.runtime_ops != null:
		return _dispatch_hub.runtime_ops.runtime_gate_open()
	return false


func _runtime_scene_path_allowed(scene_path: String) -> bool:
	if scene_path == "":
		return true
	if not scene_path.begins_with("res://"):
		return false
	if scene_path.find("..") >= 0:
		return false
	return scene_path.ends_with(".tscn") or scene_path.ends_with(".scn")


func _runtime_target_scene(scene_path: String) -> String:
	if _dispatch_hub != null and _dispatch_hub.runtime_ops != null:
		return _dispatch_hub.runtime_ops.target_scene(scene_path)
	return scene_path


func _ack_dev_command(command: Dictionary, status: String, message: String, details: Dictionary) -> void:
	if not _handshake_complete:
		return
	_send_request("workbench.dev_control_ack", {
		"id": str(command.get("id", "")),
		"command": str(command.get("command", "")),
		"status": status,
		"message": message,
		"details": details
	})
	if str(command.get("command", "")) != "debug.output_snapshot":
		_request_debug_output_refresh()


func _service_deferred_dev_actions() -> void:
	var now: int = Time.get_ticks_msec()
	if _reload_after_msec > 0 and now >= _reload_after_msec:
		_reload_after_msec = 0
		_request_panel_reload()
	if _reconnect_after_msec > 0 and now >= _reconnect_after_msec:
		_reconnect_after_msec = 0
		_reconnect_after_dev_command()
	if _debug_output_refresh_after_msec > 0 and now >= _debug_output_refresh_after_msec:
		_debug_output_refresh_after_msec = 0
		if _handshake_complete:
			_last_debug_snapshot_sent_msec = now
			_send_debug_snapshot(true)


func _handle_closed_socket() -> void:
	var had_session: bool = _handshake_sent or _handshake_complete
	_handshake_sent = false
	_handshake_complete = false
	_connect_started_msec = 0
	if had_session:
		if _bridge_client != null:
			_bridge_client.clear_pending()
		_last_connection_event = "Socket closed"
		_last_connection_error = "Bridge connection closed"
		_add_operation("Disconnected")
		if _connect_desired:
			_schedule_reconnect(_last_connection_error, false)
	elif _connect_desired and not _bridge_reconnect_scheduled():
		_schedule_reconnect("Bridge is not connected", false)


func _handle_connecting_socket() -> void:
	if not _connect_desired:
		return
	if _connect_started_msec <= 0:
		_connect_started_msec = Time.get_ticks_msec()
		return
	var elapsed_msec: int = Time.get_ticks_msec() - _connect_started_msec
	if elapsed_msec < CONNECT_TIMEOUT_MSEC:
		return
	_last_connection_event = "Connect timed out"
	_last_connection_error = "Bridge connect timed out"
	_disconnect_socket(false)
	_schedule_reconnect(_last_connection_error, true)


func _service_auto_reconnect() -> void:
	if not _connect_desired:
		return
	var state: int = _bridge_ready_state()
	if state != WebSocketPeer.STATE_CLOSED:
		return
	if _bridge_client == null or not _bridge_client.reconnect_due():
		_update_connection_labels()
		return
	_set_status("Reconnecting")
	var reconnect_status: Dictionary = _bridge_reconnect_status()
	_last_connection_event = "Reconnect attempt %d" % int(reconnect_status.get("attempt_display", 1))
	_bridge_client.clear_reconnect_due()
	_connect_to_bridge(false)


func _schedule_reconnect(reason: String, add_log: bool) -> void:
	if not _connect_desired:
		return
	_last_connection_error = reason
	_last_connection_event = "Waiting to reconnect"
	var reconnect_status: Dictionary = _bridge_schedule_reconnect()
	var delay_msec: int = int(reconnect_status.get("current_delay_msec", RECONNECT_INITIAL_DELAY_MSEC))
	_set_status("Waiting to reconnect")
	if add_log:
		_add_operation("%s; retry in %.1fs" % [reason, float(delay_msec) / 1000.0])
	_update_connection_labels()


func _reset_reconnect_backoff() -> void:
	if _bridge_client != null:
		_bridge_client.reset_reconnect_backoff(RECONNECT_INITIAL_DELAY_MSEC)
	_update_connection_labels()


func _request_panel_reload() -> void:
	var settings: Dictionary = snapshot_dev_settings()
	settings["connect_desired"] = true
	settings["reconnect"] = true
	workbench_reload_requested.emit(settings)


func _reconnect_after_dev_command() -> void:
	var settings: Dictionary = snapshot_dev_settings()
	_disconnect_socket()
	settings["reconnect"] = true
	restore_dev_settings(settings)


func _request_debug_output_refresh() -> void:
	_debug_output_refresh_after_msec = Time.get_ticks_msec() + DEBUG_OUTPUT_REFRESH_DELAY_MSEC


func _dev_details() -> Dictionary:
	return {
		"addon_version": ADDON_VERSION,
		"godot_version": str(Engine.get_version_info().get("string", "unknown")),
		"project_path": ProjectSettings.globalize_path("res://"),
		"profile": _selected_profile_id(),
		"server_profile": _server_active_profile,
		"write_allowed": _server_write_allowed,
		"backend_modules": _backend_module_status()
	}


func _backend_module_status() -> Dictionary:
	return {
		"bridge_client": _module_loaded(_bridge_client),
		"dispatch_hub": _module_loaded(_dispatch_hub),
		"output_probe": _module_loaded(_output_probe),
		"property_codec": _module_loaded(_property_codec),
		"script_resource": _module_loaded(_script_resource_service),
		"load_failures": _backend_load_failures.duplicate(true)
	}


func _module_loaded(module: Variant) -> bool:
	return module != null and module is Object and is_instance_valid(module)


func editor_interface() -> EditorInterface:
	return _editor_interface


func selected_profile_id() -> String:
	return _selected_profile_id()


func server_active_profile() -> String:
	return _server_active_profile


func handshake_complete() -> bool:
	return _handshake_complete


func dev_details() -> Dictionary:
	return _dev_details()


func workbench_dictionary(value: Variant) -> Dictionary:
	return _workbench_dictionary(value)


func workbench_bool(value: Variant, default_value: bool) -> bool:
	return _workbench_bool(value, default_value)


func workbench_array(value: Variant) -> Array:
	return _workbench_array(value)


func workbench_int(value: Variant, default_value: int) -> int:
	return _workbench_int(value, default_value)


func write_gate_open() -> bool:
	return _write_gate_open()


func write_base_details(action: String) -> Dictionary:
	return _write_base_details(action)


func resolve_undo_redo() -> EditorUndoRedoManager:
	return _resolve_undo_redo()


func find_scene_node(root: Node, path: String) -> Node:
	return _find_scene_node(root, path)


func resolve_write_target_node(root: Node, node_path: String, details: Dictionary) -> Node:
	return _resolve_write_target_node(root, node_path, details)


func find_writable_property_info(node: Node, property_name: String, details: Dictionary) -> Dictionary:
	return _find_writable_property_info(node, property_name, details)


func parse_property_value(raw_value: Variant, property_info: Dictionary, old_value: Variant) -> Dictionary:
	return _parse_property_value(raw_value, property_info, old_value)


func variant_snapshot(value: Variant) -> Dictionary:
	return _variant_snapshot(value)


func variants_equal(left: Variant, right: Variant) -> bool:
	return _variants_equal(left, right)


func property_type_name(property_info: Dictionary, old_value: Variant) -> String:
	return _property_type_name(property_info, old_value)


func validate_script_resource_path(script_path: String) -> Dictionary:
	return _validate_script_resource_path(script_path)


func script_compatibility(node: Node, script_resource: Script) -> Dictionary:
	return _script_compatibility(node, script_resource)


func script_snapshot(script_value: Variant) -> Dictionary:
	return _script_snapshot(script_value)


func scripts_equal(left: Variant, right: Variant) -> bool:
	return _scripts_equal(left, right)


func workbench_scene_node_path(root: Node, node: Node) -> String:
	return _workbench_scene_node_path(root, node)


func remember_write_operation(details: Dictionary, runtime: Dictionary = {}) -> void:
	_remember_write_operation(details, runtime)


func operation_id_for_command(command: Dictionary) -> String:
	return _operation_id_for_command(command)


func prepare_scene_save(details: Dictionary, root: Node, allow_existing_changes: bool = false, allow_structure_changes: bool = false) -> Dictionary:
	return _prepare_scene_save(details, root, allow_existing_changes, allow_structure_changes)


func finalize_scene_save(details: Dictionary, root: Node, save_context: Dictionary) -> Dictionary:
	return _finalize_scene_save(details, root, save_context)


func file_size(path: String) -> int:
	return _file_size(path)


func file_md5(path: String) -> String:
	return _file_md5(path)


func scene_dirty_state() -> Dictionary:
	return _scene_dirty_state()


func scene_structure_state(root: Node, scene_path: String) -> Dictionary:
	return _scene_structure_state(root, scene_path)


func write_audit(details: Dictionary) -> void:
	_write_audit(details)


func send_request(method: String, params: Dictionary) -> void:
	_send_request(method, params)


func ack_dev_command(command: Dictionary, status: String, message: String, details: Dictionary) -> void:
	_ack_dev_command(command, status, message, details)


func add_operation(text: String) -> void:
	_add_operation(text)


func send_editor_state() -> void:
	_send_editor_state()


func debug_snapshot(include_editor_output: bool) -> Dictionary:
	return _debug_snapshot(include_editor_output)


func request_runtime_tree(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_tree"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_tree", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_tree_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_tree_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_tree_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func request_runtime_screenshot(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_screenshot"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_screenshot", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_screenshot_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_screenshot_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_screenshot_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func request_runtime_input(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_input"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_input", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_input_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_input_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_input_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func request_runtime_inspect(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_inspect"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_inspect", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func request_runtime_state(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_state"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_state", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_inspect_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_inspect_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_inspect_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func runtime_state_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_state_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_state_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func request_runtime_ui_find(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_ui_find"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_ui_find", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_ui_find_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_ui_find_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_ui_find_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func request_runtime_click_text(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_click_text"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_click_text", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_click_text_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_click_text_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_click_text_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func request_runtime_wait(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_wait"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_wait", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_wait_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_wait_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_wait_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func request_runtime_assert(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_assert"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_assert", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_assert_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_assert_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_assert_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func request_runtime_animation_state(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_animation_state"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_animation_state", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_animation_state_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_animation_state_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_animation_state_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func request_runtime_animation_control(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_animation_control"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_animation_control", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_animation_control_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_animation_control_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_animation_control_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func request_runtime_watch(options: Dictionary) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("request_runtime_watch"):
		return _workbench_dictionary(_debug_probe.call("request_runtime_watch", options))
	return {
		"ok": false,
		"message": "debug probe is not available"
	}


func runtime_watch_response(request_id: String) -> Dictionary:
	if _debug_probe != null and _debug_probe.has_method("runtime_watch_response"):
		return _workbench_dictionary(_debug_probe.call("runtime_watch_response", request_id))
	return {
		"available": false,
		"pending": false,
		"message": "debug probe is not available"
	}


func clear_debug_output() -> Dictionary:
	if _output_probe == null:
		return _debug_snapshot(true)
	return _output_probe.clear_editor_output(OUTPUT_PANEL_SCAN_LIMIT)


func refresh_debug_label(snapshot: Dictionary) -> void:
	_refresh_debug_label(snapshot)


func schedule_panel_reload() -> void:
	_reload_after_msec = Time.get_ticks_msec() + 250


func schedule_bridge_reconnect() -> void:
	_reconnect_after_msec = Time.get_ticks_msec() + 250


func select_profile_id(profile_id: String) -> void:
	_select_profile_id(profile_id)






func _operation_id_for_command(command: Dictionary) -> String:
	var command_id: String = str(command.get("id", "")).strip_edges()
	if command_id != "":
		return "op_%s" % command_id
	return "op_%d" % Time.get_ticks_msec()


func _remember_write_operation(details: Dictionary, runtime: Dictionary = {}) -> void:
	if not runtime.is_empty():
		details["runtime"] = runtime.duplicate(true)


func _write_gate_open() -> bool:
	return _selected_profile_id() == "full_control" and _server_active_profile == "full_control" and _server_write_allowed


func _resolve_undo_redo() -> EditorUndoRedoManager:
	if _undo_redo != null:
		return _undo_redo
	if _editor_interface != null and _editor_interface.has_method("get_editor_undo_redo"):
		var manager: Variant = _editor_interface.call("get_editor_undo_redo")
		if manager is EditorUndoRedoManager:
			_undo_redo = manager
	return _undo_redo


func _write_base_details(action: String) -> Dictionary:
	var details: Dictionary = _dev_details()
	details["action"] = action
	details["audit_time"] = Time.get_datetime_string_from_system(false, true)
	return details


func _find_scene_node(root: Node, path: String) -> Node:
	if root == null:
		return null
	var clean_path: String = path.strip_edges()
	if clean_path == "" or clean_path == "." or clean_path == str(root.name):
		return root
	var prefix := "%s/" % str(root.name)
	if clean_path.begins_with(prefix):
		clean_path = clean_path.substr(prefix.length())
	return root.get_node_or_null(NodePath(clean_path))


func _resolve_write_target_node(root: Node, node_path: String, details: Dictionary) -> Node:
	if node_path != "":
		var node: Node = _find_scene_node(root, node_path)
		if node == null:
			details["target_error"] = "node not found"
		return node
	if _editor_interface == null:
		details["target_error"] = "node_path is required when EditorInterface is unavailable"
		return null
	var selection: EditorSelection = _editor_interface.get_selection()
	if selection == null:
		details["target_error"] = "node_path is required when no editor selection is available"
		return null
	var selected: Array = selection.get_selected_nodes()
	if selected.size() != 1:
		details["target_error"] = "node_path is required unless exactly one node is selected"
		details["selected_count"] = selected.size()
		return null
	var selected_node: Node = selected[0]
	if selected_node == null or (selected_node != root and not root.is_ancestor_of(selected_node)):
		details["target_error"] = "selected node is outside the edited scene"
		return null
	details["resolved_from_selection"] = true
	return selected_node



func _validate_script_resource_path(script_path: String) -> Dictionary:
	if _script_resource_service == null:
		return {"ok": false, "message": "script resource service is not loaded"}
	return _script_resource_service.validate_script_resource_path(script_path)



func _script_compatibility(node: Node, script_resource: Script) -> Dictionary:
	if _script_resource_service == null:
		return {"ok": false, "message": "script resource service is not loaded"}
	return _script_resource_service.script_compatibility(node, script_resource)


func _script_snapshot(script_value: Variant) -> Dictionary:
	if _script_resource_service == null:
		return {"type": "Nil", "path": "", "class_name": "", "base_type": ""}
	return _script_resource_service.script_snapshot(script_value)


func _script_base_type(script_resource: Script) -> String:
	if _script_resource_service != null:
		return _script_resource_service.script_base_type(script_resource)
	return ""


func _script_global_name(script_resource: Script) -> String:
	if _script_resource_service != null:
		return _script_resource_service.script_global_name(script_resource)
	return ""


func _scripts_equal(left: Variant, right: Variant) -> bool:
	if _script_resource_service != null:
		return _script_resource_service.scripts_equal(left, right)
	return left == right


func _find_writable_property_info(node: Node, property_name: String, details: Dictionary) -> Dictionary:
	return _property_codec.find_writable_property_info(node, property_name, details)


func _parse_property_value(raw_value: Variant, property_info: Dictionary, old_value: Variant) -> Dictionary:
	return _property_codec.parse_property_value(raw_value, property_info, old_value)


func _variant_snapshot(value: Variant) -> Dictionary:
	return _property_codec.variant_snapshot(value)


func _variants_equal(left: Variant, right: Variant) -> bool:
	return _property_codec.variants_equal(left, right)


func _property_type_name(property_info: Dictionary, old_value: Variant) -> String:
	return _property_codec.property_type_name(property_info, old_value)


func _variant_type_name(type_id: int) -> String:
	return _property_codec.variant_type_name(type_id)


func _prepare_scene_save(details: Dictionary, root: Node, allow_existing_changes: bool = false, allow_structure_changes: bool = false) -> Dictionary:
	var result: Dictionary = {"ok": false, "message": ""}
	details["allow_existing_changes"] = allow_existing_changes
	details["allow_structure_changes"] = allow_structure_changes
	if root == null:
		details["save_error"] = "no_edited_scene_root"
		result["message"] = "save_scene requires an active edited scene"
		return result
	var scene_path: String = root.scene_file_path.strip_edges()
	if scene_path == "":
		details["save_error"] = "no_active_scene_file"
		result["message"] = "save_scene requires a scene file path"
		return result
	details["scene_path"] = scene_path
	details["affected_files"] = [scene_path]
	details["scene_file_absolute"] = ProjectSettings.globalize_path(scene_path)
	details["pre_save_dirty_state"] = _scene_dirty_state()
	details["pre_save_structure_state"] = _scene_structure_state(root, scene_path)
	result["ok"] = true
	result["scene_path"] = scene_path
	return result


func _finalize_scene_save(details: Dictionary, root: Node, save_context: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "message": ""}
	var scene_path: String = str(details.get("scene_path", save_context.get("scene_path", ""))).strip_edges()
	if root == null or scene_path == "":
		details["status"] = "save_failed"
		details["saved"] = false
		result["message"] = "scene save failed: no active scene"
		return result
	if root.scene_file_path != scene_path:
		details["status"] = "save_failed"
		details["saved"] = false
		details["current_scene_path"] = root.scene_file_path
		result["message"] = "edited scene changed before save"
		return result
	var save_error: int = _save_current_scene()
	details["save_attempted"] = true
	if save_error != OK:
		details["status"] = "save_failed"
		details["saved"] = false
		details["save_error"] = error_string(save_error)
		result["message"] = "scene save failed"
		return result
	var validation: Dictionary = _validate_scene_file(scene_path)
	details["save_validation"] = validation
	if validation.get("ok", false) != true:
		details["status"] = "save_validation_failed"
		details["saved"] = true
		result["message"] = "saved scene validation failed"
		return result
	details["saved"] = true
	details["saved_scene_hash"] = _file_md5(ProjectSettings.globalize_path(scene_path))
	details["saved_scene_size"] = validation.get("file_size", 0)
	details["post_save_dirty_state"] = _scene_dirty_state()
	result["ok"] = true
	result["message"] = "scene saved"
	return result


func _save_current_scene() -> int:
	if _editor_interface == null:
		return ERR_UNAVAILABLE
	if _editor_interface.has_method("save_scene"):
		var save_result: Variant = _editor_interface.call("save_scene")
		if typeof(save_result) == TYPE_INT:
			return int(save_result)
		return OK
	return ERR_UNAVAILABLE


func _validate_scene_file(scene_path: String) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"scene_path": scene_path,
		"file_size": 0,
		"message": ""
	}
	var absolute_path: String = ProjectSettings.globalize_path(scene_path)
	if scene_path.strip_edges() == "":
		result["message"] = "scene_path is empty"
		return result
	if not FileAccess.file_exists(absolute_path):
		result["message"] = "scene file does not exist after save"
		return result
	var file_size: int = _file_size(absolute_path)
	result["file_size"] = file_size
	if file_size <= 0:
		result["message"] = "scene file is empty after save"
		return result
	result["ok"] = true
	result["message"] = "scene file exists"
	return result


func _file_size(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return int(size)


func _file_md5(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return str(FileAccess.get_md5(path))


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


func _scene_dirty_state() -> Dictionary:
	var root: Node = null
	if _editor_interface != null:
		root = _editor_interface.get_edited_scene_root()
	return {
		"available": root != null,
		"changed": false,
		"scene_path": root.scene_file_path if root != null else ""
	}


func _scene_structure_state(root: Node, scene_path: String) -> Dictionary:
	return {
		"available": root != null,
		"ok": root != null and root.scene_file_path == scene_path,
		"scene_path": scene_path,
		"node_count": _live_scene_node_paths(root).size() if root != null else 0
	}


func _live_scene_node_paths(root: Node) -> Array[String]:
	var scene_nodes: Array[Dictionary] = []
	var paths: Array[String] = []
	_collect_scene_nodes(root, root, scene_nodes)
	for node_info: Dictionary in scene_nodes:
		paths.append(str(node_info.get("path", "")))
	return paths


func _write_audit(details: Dictionary) -> void:
	var action: String = str(details.get("action", "write")).strip_edges()
	var target: String = str(details.get("resolved_node_path", details.get("created_path", details.get("scene_path", "")))).strip_edges()
	if target == "":
		target = str(details.get("path", details.get("name", ""))).strip_edges()
	if target == "":
		target = action
	_add_operation("Godot AI Workbench: %s %s" % [action, target])


func _audit_record(details: Dictionary) -> Dictionary:
	return details.duplicate(true)


func _on_editor_selection_changed() -> void:
	if _handshake_complete:
		_send_editor_state()


func _send_editor_state() -> void:
	var selected_nodes: Array[String] = []
	var scene_nodes: Array[Dictionary] = []
	var scene_path := ""
	if _editor_interface != null:
		var root: Node = _editor_interface.get_edited_scene_root()
		if root != null:
			scene_path = root.scene_file_path
			_collect_scene_nodes(root, root, scene_nodes)
		var selection: EditorSelection = _editor_interface.get_selection()
		if selection != null:
			for node: Node in selection.get_selected_nodes():
				selected_nodes.append(_workbench_scene_node_path(root, node))
	var runtime: Dictionary = _runtime_status()
	_send_request("editor.state", {
		"scene_path": scene_path,
		"selected_nodes": selected_nodes,
		"scene_nodes": scene_nodes,
		"playing": runtime.get("playing", false)
	})


func _send_debug_snapshot(include_editor_output: bool) -> void:
	var snapshot: Dictionary = _debug_snapshot(include_editor_output)
	_refresh_debug_label(snapshot)
	_send_request("debug.snapshot", snapshot)


func _debug_snapshot(include_editor_output: bool) -> Dictionary:
	if _output_probe == null:
		return {
			"sequence": 0,
			"captured_at": Time.get_datetime_string_from_system(false, true),
			"total_events": 0,
			"events": [],
			"sessions": [],
			"probe_available": _debug_probe != null,
			"editor_output": {
				"available": false,
				"source": "module_unavailable",
				"line_count": 0,
				"error_count": 0,
				"warning_count": 0,
				"lines": []
			}
		}
	return _output_probe.debug_snapshot(include_editor_output, OUTPUT_PANEL_SCAN_LIMIT)


func _refresh_debug_label(snapshot: Dictionary) -> void:
	if _debug_label == null:
		return
	var probe_available: bool = snapshot.get("probe_available", _debug_probe != null) == true
	if not probe_available:
		_debug_label.text = "Probe not loaded"
		return
	var sessions: Array = _workbench_array(snapshot.get("sessions", []))
	var active_sessions := 0
	var breaked_sessions := 0
	for session_value: Variant in sessions:
		if typeof(session_value) != TYPE_DICTIONARY:
			continue
		var session: Dictionary = session_value
		if session.get("active", false) == true:
			active_sessions += 1
		if session.get("breaked", false) == true:
			breaked_sessions += 1
	var total_events := int(snapshot.get("total_events", 0))
	_debug_label.text = "sessions=%d active=%d breaked=%d events=%d" % [
		sessions.size(),
		active_sessions,
		breaked_sessions,
		total_events
	]


func _collect_scene_nodes(root: Node, node: Node, output: Array[Dictionary]) -> void:
	var parent_path := ""
	if node != root and node.get_parent() != null:
		parent_path = _workbench_scene_node_path(root, node.get_parent())
	output.append({
		"path": _workbench_scene_node_path(root, node),
		"name": node.name,
		"type": node.get_class(),
		"parent": parent_path
	})
	for child: Node in node.get_children():
		_collect_scene_nodes(root, child, output)


func _workbench_scene_node_path(root: Node, node: Node) -> String:
	if node == null:
		return ""
	if root == null:
		return str(node.name)
	if node == root:
		return str(root.name)
	if not root.is_ancestor_of(node):
		return str(node.name)
	return "%s/%s" % [str(root.name), str(root.get_path_to(node))]


func _selected_profile_id() -> String:
	match _profile_picker.selected:
		0:
			return "analysis"
		1:
			return "full_control"
		_:
			return "analysis"


func _select_profile_id(profile_id: String) -> void:
	var index: int = _profile_index_for_id(profile_id)
	if index >= 0 and index < _profile_picker.item_count:
		_profile_picker.select(index)


func _profile_index_for_id(profile_id: String) -> int:
	match profile_id:
		"analysis":
			return 0
		"full_control":
			return 1
		_:
			return -1


func _disconnect_socket(clear_desired: bool = false) -> void:
	if clear_desired:
		_connect_desired = false
	if _bridge_client != null:
		_bridge_client.close()
	_handshake_sent = false
	_handshake_complete = false
	_connect_started_msec = 0
	_dev_control_poll_pending = false
	_update_connection_labels()
	_update_buttons()


func _remove_legacy_timer_children() -> void:
	if _legacy_timers_removed:
		return
	_legacy_timers_removed = true
	var legacy_timer_names: Array[String] = [
		"BridgePollTimer",
		"BridgeHeartbeatTimer",
		"BridgeStateTimer"
	]
	for timer_name: String in legacy_timer_names:
		var legacy_timer: Node = get_node_or_null(NodePath(timer_name))
		if legacy_timer != null:
			legacy_timer.queue_free()


func _set_status(text: String) -> void:
	_status_label.text = "Status: %s" % text
	_update_connection_labels()


func _set_warning(text: String) -> void:
	_add_operation(text)


func _update_connection_labels() -> void:
	if _connection_label == null or _reconnect_label == null:
		return
	var state: int = _bridge_ready_state()
	var socket_name: String = _socket_state_name(state)
	if _handshake_complete:
		_connection_label.text = "Connected, profile %s" % _selected_profile_id()
	elif state == WebSocketPeer.STATE_CONNECTING:
		_connection_label.text = "Socket: %s" % socket_name
	elif _connect_desired:
		_connection_label.text = "Socket: %s, wanted" % socket_name
	else:
		_connection_label.text = "Socket: %s" % socket_name

	var reconnect_status: Dictionary = _bridge_reconnect_status()
	var remaining_msec: int = int(reconnect_status.get("remaining_msec", 0))
	if _connect_desired and remaining_msec > 0:
		var remaining_sec: float = float(remaining_msec) / 1000.0
		_reconnect_label.text = "Retry in %.1fs, attempt %d, last: %s" % [remaining_sec, int(reconnect_status.get("attempt", 0)), _last_connection_error]
	elif _connect_desired and not _handshake_complete:
		_reconnect_label.text = "Auto reconnect armed, attempt %d" % int(reconnect_status.get("attempt_display", 1))
	elif _handshake_complete:
		_reconnect_label.text = "Healthy; backoff reset"
	else:
		_reconnect_label.text = "Off; %s" % _last_connection_event


func _socket_state_name(state: int) -> String:
	match state:
		WebSocketPeer.STATE_CONNECTING:
			return "connecting"
		WebSocketPeer.STATE_OPEN:
			return "open"
		WebSocketPeer.STATE_CLOSING:
			return "closing"
		WebSocketPeer.STATE_CLOSED:
			return "closed"
		_:
			return "unknown"


func _add_operation(text: String) -> void:
	if _operations == null:
		return
	var stamp := Time.get_datetime_string_from_system(false, true)
	_operations.add_item("%s  %s" % [stamp, text])
	while _operations.get_item_count() > 20:
		_operations.remove_item(0)


func _update_buttons() -> void:
	var state: int = _bridge_ready_state()
	var connected := state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CONNECTING
	_connect_button.disabled = connected
	_disconnect_button.disabled = not connected


func _bridge_ready_state() -> int:
	if _bridge_client == null:
		return WebSocketPeer.STATE_CLOSED
	return int(_bridge_client.ready_state())


func _bridge_schedule_reconnect() -> Dictionary:
	if _bridge_client == null:
		return {
			"next_msec": 0,
			"attempt": 0,
			"attempt_display": 1,
			"current_delay_msec": RECONNECT_INITIAL_DELAY_MSEC,
			"remaining_msec": 0
		}
	return _bridge_client.schedule_reconnect(RECONNECT_INITIAL_DELAY_MSEC, RECONNECT_MAX_DELAY_MSEC)


func _bridge_reconnect_scheduled() -> bool:
	return int(_bridge_reconnect_status().get("next_msec", 0)) > 0


func _bridge_reconnect_status() -> Dictionary:
	if _bridge_client == null:
		return {
			"next_msec": 0,
			"attempt": 0,
			"attempt_display": 1,
			"current_delay_msec": RECONNECT_INITIAL_DELAY_MSEC,
			"remaining_msec": 0
		}
	return _bridge_client.reconnect_status()


func _join_values(values: Array, separator: String) -> String:
	var output := ""
	var index := 0
	for value: Variant in values:
		if index > 0:
			output += separator
		output += str(value)
		index += 1
	return output


func _workbench_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _workbench_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _workbench_bool(value: Variant, default_value: bool) -> bool:
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


func _workbench_int(value: Variant, default_value: int) -> int:
	match typeof(value):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return int(value)
		TYPE_STRING:
			var text := str(value).strip_edges()
			if text.is_valid_int():
				return int(text)
	return default_value
