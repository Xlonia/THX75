extends RefCounted

const RUNTIME_TREE_DEFAULT_MAX_NODES := 256
const RUNTIME_TREE_HARD_MAX_NODES := 2048
const RUNTIME_TREE_DEFAULT_TIMEOUT_MSEC := 2000
const RUNTIME_TREE_MIN_TIMEOUT_MSEC := 250
const RUNTIME_TREE_MAX_TIMEOUT_MSEC := 10000
const RUNTIME_LOGS_DEFAULT_LIMIT := 80
const RUNTIME_LOGS_MAX_LIMIT := 200
const RUNTIME_SCREENSHOT_DEFAULT_MAX_WIDTH := 1280
const RUNTIME_SCREENSHOT_DEFAULT_MAX_HEIGHT := 720
const RUNTIME_SCREENSHOT_HARD_MAX_DIMENSION := 4096
const RUNTIME_SCREENSHOT_DIR := "user://godot_ai_workbench/screenshots"
const RUNTIME_SCREENSHOT_DEFAULT_TIMEOUT_MSEC := 5000
const RUNTIME_SCREENSHOT_MIN_TIMEOUT_MSEC := 500
const RUNTIME_SCREENSHOT_MAX_TIMEOUT_MSEC := 15000
const RUNTIME_SCREENSHOT_DEFAULT_RETENTION_FILES := 50
const RUNTIME_SCREENSHOT_MAX_RETENTION_FILES := 500
const RUNTIME_SCREENSHOT_DEFAULT_RETENTION_BYTES := 52428800
const RUNTIME_SCREENSHOT_MAX_RETENTION_BYTES := 524288000
const RUNTIME_SCREENSHOT_COMPARE_DEFAULT_TOLERANCE := 0.01
const RUNTIME_SCREENSHOT_COMPARE_DEFAULT_MAX_CHANGED_RATIO := 0.01
const RUNTIME_SCREENSHOT_COMPARE_DEFAULT_MAX_AVG_DELTA := 0.01
const RUNTIME_SCREENSHOT_COMPARE_DEFAULT_MAX_SAMPLES := 100000
const RUNTIME_SCREENSHOT_COMPARE_MIN_SAMPLES := 1000
const RUNTIME_SCREENSHOT_COMPARE_MAX_SAMPLES := 250000
const RUNTIME_INPUT_DEFAULT_TIMEOUT_MSEC := 3000
const RUNTIME_INPUT_MIN_TIMEOUT_MSEC := 500
const RUNTIME_INPUT_MAX_TIMEOUT_MSEC := 10000
const RUNTIME_INPUT_MAX_EVENTS := 20
const RUNTIME_CHECK_DEFAULT_TIMEOUT_MSEC := 3000
const RUNTIME_CHECK_MIN_TIMEOUT_MSEC := 100
const RUNTIME_CHECK_MAX_TIMEOUT_MSEC := 120000
const RUNTIME_CHECK_DEFAULT_POLL_INTERVAL_MSEC := 100
const RUNTIME_CHECK_MIN_POLL_INTERVAL_MSEC := 50
const RUNTIME_CHECK_MAX_POLL_INTERVAL_MSEC := 5000
const RUNTIME_ANIMATION_DEFAULT_TIMEOUT_MSEC := 3000
const RUNTIME_ANIMATION_MIN_TIMEOUT_MSEC := 500
const RUNTIME_ANIMATION_MAX_TIMEOUT_MSEC := 10000
const RUNTIME_ANIMATION_DEFAULT_MAX_ITEMS := 80
const RUNTIME_ANIMATION_MAX_ITEMS := 200
const RUNTIME_WATCH_DEFAULT_DURATION_MSEC := 1000
const RUNTIME_WATCH_MIN_DURATION_MSEC := 100
const RUNTIME_WATCH_MAX_DURATION_MSEC := 5000
const RUNTIME_WATCH_DEFAULT_INTERVAL_MSEC := 100
const RUNTIME_WATCH_MIN_INTERVAL_MSEC := 50
const RUNTIME_WATCH_MAX_INTERVAL_MSEC := 1000
const RUNTIME_WATCH_DEFAULT_MAX_EVENTS := 80
const RUNTIME_WATCH_MAX_EVENTS := 300
const RUNTIME_WATCH_MAX_TARGETS := 16
const RUNTIME_STATE_DEFAULT_TIMEOUT_MSEC := 2000
const RUNTIME_STATE_MIN_TIMEOUT_MSEC := 250
const RUNTIME_STATE_MAX_TIMEOUT_MSEC := 10000
const RUNTIME_STATE_MAX_TARGETS := 16
const RUNTIME_STATE_MAX_PROPERTIES := 64

var _host
var _editor_interface
var _pending_tree_commands: Dictionary = {}
var _pending_screenshot_commands: Dictionary = {}
var _pending_input_commands: Dictionary = {}
var _pending_inspect_commands: Dictionary = {}
var _pending_state_commands: Dictionary = {}
var _pending_ui_find_commands: Dictionary = {}
var _pending_click_text_commands: Dictionary = {}
var _pending_check_commands: Dictionary = {}
var _pending_animation_state_commands: Dictionary = {}
var _pending_animation_control_commands: Dictionary = {}
var _pending_watch_commands: Dictionary = {}


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return ["runtime.status", "runtime.tree", "runtime.logs", "runtime.screenshot", "runtime.compare_screenshots", "runtime.input", "runtime.inspect_node", "runtime.get_node_properties", "runtime.state", "runtime.find_ui", "runtime.click_text", "runtime.wait_for", "runtime.assert", "runtime.animation_state", "runtime.animation_control", "runtime.watch", "runtime.record_events", "runtime.play_scene", "runtime.stop_scene"]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"runtime.status":
			_handle_runtime_status(command)
			return true
		"runtime.tree":
			_handle_runtime_tree(command)
			return true
		"runtime.logs":
			_handle_runtime_logs(command)
			return true
		"runtime.screenshot":
			_handle_runtime_screenshot(command)
			return true
		"runtime.compare_screenshots":
			_handle_runtime_compare_screenshots(command)
			return true
		"runtime.input":
			_handle_runtime_input(command)
			return true
		"runtime.inspect_node":
			_handle_runtime_inspect(command, false)
			return true
		"runtime.get_node_properties":
			_handle_runtime_inspect(command, true)
			return true
		"runtime.state":
			_handle_runtime_state(command)
			return true
		"runtime.find_ui":
			_handle_runtime_find_ui(command)
			return true
		"runtime.click_text":
			_handle_runtime_click_text(command)
			return true
		"runtime.wait_for":
			_handle_runtime_check(command, "wait")
			return true
		"runtime.assert":
			_handle_runtime_check(command, "assert")
			return true
		"runtime.animation_state":
			_handle_runtime_animation_state(command)
			return true
		"runtime.animation_control":
			_handle_runtime_animation_control(command)
			return true
		"runtime.watch":
			_handle_runtime_watch(command, "watch")
			return true
		"runtime.record_events":
			_handle_runtime_watch(command, "record_events")
			return true
		"runtime.play_scene":
			_handle_runtime_play_scene(command)
			return true
		"runtime.stop_scene":
			_handle_runtime_stop_scene(command)
			return true
	return false


func service(_delta: float) -> void:
	_service_runtime_tree_requests()
	_service_runtime_screenshot_requests()
	_service_runtime_input_requests()
	_service_runtime_inspect_requests()
	_service_runtime_state_requests()
	_service_runtime_ui_find_requests()
	_service_runtime_click_text_requests()
	_service_runtime_check_requests()
	_service_runtime_animation_state_requests()
	_service_runtime_animation_control_requests()
	_service_runtime_watch_requests()


func runtime_status() -> Dictionary:
	var editor_interface = _editor_interface_from_host()
	var status: Dictionary = {
		"available": editor_interface != null,
		"playing": false,
		"playing_scene": "",
		"current_scene_path": "",
		"can_play_current_scene": false,
		"can_play_main_scene": false,
		"can_play_custom_scene": false,
		"can_stop_scene": false,
		"addon_profile": str(_host.call("selected_profile_id")),
		"server_profile": str(_host.call("server_active_profile")),
		"runtime_access": runtime_gate_open()
	}
	if editor_interface == null:
		return status
	var root: Node = editor_interface.get_edited_scene_root()
	if root != null:
		status["current_scene_path"] = root.scene_file_path
	status["can_play_current_scene"] = editor_interface.has_method("play_current_scene")
	status["can_play_main_scene"] = editor_interface.has_method("play_main_scene")
	status["can_play_custom_scene"] = editor_interface.has_method("play_custom_scene")
	status["can_stop_scene"] = editor_interface.has_method("stop_playing_scene")
	if editor_interface.has_method("is_playing_scene"):
		var playing_value: Variant = editor_interface.call("is_playing_scene")
		status["playing"] = _host.call("workbench_bool", playing_value, false)
	if editor_interface.has_method("get_playing_scene"):
		var scene_value: Variant = editor_interface.call("get_playing_scene")
		status["playing_scene"] = str(scene_value)
	return status


func runtime_gate_open() -> bool:
	var addon_profile: String = str(_host.call("selected_profile_id"))
	var addon_allowed: bool = addon_profile == "full_control"
	var server_profile: String = str(_host.call("server_active_profile"))
	var server_allowed: bool = server_profile == "full_control"
	return addon_allowed and server_allowed


func target_scene(scene_path: String) -> String:
	if scene_path != "":
		return scene_path
	var editor_interface = _editor_interface_from_host()
	if editor_interface == null:
		return ""
	var root: Node = editor_interface.get_edited_scene_root()
	if root != null:
		return root.scene_file_path
	return ""


func _handle_runtime_status(command: Dictionary) -> void:
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.status"
	_host.call("add_operation", "Runtime: status playing=%s" % str(details.get("playing", false)))
	_host.call("ack_dev_command", command, "ok", "runtime status", details)


func _handle_runtime_tree(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var max_nodes: int = clampi(
		int(_host.call("workbench_int", args.get("max_nodes", RUNTIME_TREE_DEFAULT_MAX_NODES), RUNTIME_TREE_DEFAULT_MAX_NODES)),
		1,
		RUNTIME_TREE_HARD_MAX_NODES
	)
	var include_internal: bool = _host.call("workbench_bool", args.get("include_internal", false), false)
	var include_groups: bool = _host.call("workbench_bool", args.get("include_groups", false), false)
	var timeout_msec: int = clampi(
		int(_host.call("workbench_int", args.get("timeout_msec", RUNTIME_TREE_DEFAULT_TIMEOUT_MSEC), RUNTIME_TREE_DEFAULT_TIMEOUT_MSEC)),
		RUNTIME_TREE_MIN_TIMEOUT_MSEC,
		RUNTIME_TREE_MAX_TIMEOUT_MSEC
	)
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.tree"
	details["max_nodes"] = max_nodes
	details["include_internal"] = include_internal
	details["include_groups"] = include_groups
	details["timeout_msec"] = timeout_msec
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime tree requires full_control on bridge and addon", details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "runtime tree requires a running scene", details)
		return
	var request_result: Dictionary = _host.call("workbench_dictionary", _host.call("request_runtime_tree", {
		"max_nodes": max_nodes,
		"include_internal": include_internal,
		"include_groups": include_groups
	}))
	if request_result.get("ok", false) != true:
		details["request"] = request_result
		_host.call("ack_dev_command", command, "error", str(request_result.get("message", "runtime tree request failed")), details)
		return
	var request_id := str(request_result.get("request_id", ""))
	if request_id == "":
		details["request"] = request_result
		_host.call("ack_dev_command", command, "error", "runtime tree request did not return a request id", details)
		return
	details["request"] = request_result
	details["status"] = "waiting"
	_pending_tree_commands[request_id] = {
		"command": command.duplicate(true),
		"details": details,
		"deadline_msec": Time.get_ticks_msec() + timeout_msec
	}
	_host.call("add_operation", "Runtime: tree requested")


func _handle_runtime_logs(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var limit: int = clampi(
		int(_host.call("workbench_int", args.get("limit", RUNTIME_LOGS_DEFAULT_LIMIT), RUNTIME_LOGS_DEFAULT_LIMIT)),
		1,
		RUNTIME_LOGS_MAX_LIMIT
	)
	var since_sequence: int = max(0, int(_host.call("workbench_int", args.get("since_sequence", 0), 0)))
	var include_editor_output: bool = _host.call("workbench_bool", args.get("include_editor_output", true), true)
	var include_session_events: bool = _host.call("workbench_bool", args.get("include_session_events", true), true)
	var categories: Array[String] = _runtime_log_categories(args)
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.logs"
	details["limit"] = limit
	details["since_sequence"] = since_sequence
	details["include_editor_output"] = include_editor_output
	details["include_session_events"] = include_session_events
	details["categories"] = categories
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime logs require full_control on bridge and addon", details)
		return
	var snapshot: Dictionary = _host.call("workbench_dictionary", _host.call("debug_snapshot", include_editor_output))
	var events: Array = _host.call("workbench_array", snapshot.get("events", []))
	var selected_events: Array[Dictionary] = []
	var skipped_by_sequence := 0
	var skipped_by_category := 0
	for event_value: Variant in events:
		var event: Dictionary = _host.call("workbench_dictionary", event_value)
		var sequence := int(event.get("sequence", 0))
		if sequence <= since_sequence:
			skipped_by_sequence += 1
			continue
		var category := str(event.get("category", ""))
		if category == "session" and not include_session_events:
			skipped_by_category += 1
			continue
		if not _runtime_log_category_allowed(category, categories):
			skipped_by_category += 1
			continue
		selected_events.append(event.duplicate(true))
	if selected_events.size() > limit:
		selected_events = selected_events.slice(selected_events.size() - limit)
	var logs: Dictionary = {
		"sequence": int(snapshot.get("sequence", 0)),
		"captured_at": str(snapshot.get("captured_at", "")),
		"total_events": int(snapshot.get("total_events", 0)),
		"returned_events": selected_events.size(),
		"events": selected_events,
		"sessions": _host.call("workbench_array", snapshot.get("sessions", [])),
		"probe_available": snapshot.get("probe_available", false),
		"skipped_by_sequence": skipped_by_sequence,
		"skipped_by_category": skipped_by_category
	}
	if include_editor_output:
		var editor_output: Dictionary = _host.call("workbench_dictionary", snapshot.get("editor_output", {}))
		logs["editor_output"] = editor_output
		details["output_error_count"] = int(editor_output.get("error_count", 0))
		details["output_warning_count"] = int(editor_output.get("warning_count", 0))
	details["logs"] = logs
	_host.call("add_operation", "Runtime: logs events=%d" % selected_events.size())
	_host.call("ack_dev_command", command, "ok", "runtime logs snapshot", details)


func _handle_runtime_screenshot(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var max_width: int = clampi(
		int(_host.call("workbench_int", args.get("max_width", RUNTIME_SCREENSHOT_DEFAULT_MAX_WIDTH), RUNTIME_SCREENSHOT_DEFAULT_MAX_WIDTH)),
		1,
		RUNTIME_SCREENSHOT_HARD_MAX_DIMENSION
	)
	var max_height: int = clampi(
		int(_host.call("workbench_int", args.get("max_height", RUNTIME_SCREENSHOT_DEFAULT_MAX_HEIGHT), RUNTIME_SCREENSHOT_DEFAULT_MAX_HEIGHT)),
		1,
		RUNTIME_SCREENSHOT_HARD_MAX_DIMENSION
	)
	var timeout_msec: int = clampi(
		int(_host.call("workbench_int", args.get("timeout_msec", RUNTIME_SCREENSHOT_DEFAULT_TIMEOUT_MSEC), RUNTIME_SCREENSHOT_DEFAULT_TIMEOUT_MSEC)),
		RUNTIME_SCREENSHOT_MIN_TIMEOUT_MSEC,
		RUNTIME_SCREENSHOT_MAX_TIMEOUT_MSEC
	)
	var cleanup: bool = _host.call("workbench_bool", args.get("cleanup", true), true)
	var retention_max_files: int = clampi(
		int(_host.call("workbench_int", args.get("retention_max_files", RUNTIME_SCREENSHOT_DEFAULT_RETENTION_FILES), RUNTIME_SCREENSHOT_DEFAULT_RETENTION_FILES)),
		1,
		RUNTIME_SCREENSHOT_MAX_RETENTION_FILES
	)
	var retention_max_bytes: int = clampi(
		int(_host.call("workbench_int", args.get("retention_max_bytes", RUNTIME_SCREENSHOT_DEFAULT_RETENTION_BYTES), RUNTIME_SCREENSHOT_DEFAULT_RETENTION_BYTES)),
		1048576,
		RUNTIME_SCREENSHOT_MAX_RETENTION_BYTES
	)
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.screenshot"
	details["max_width"] = max_width
	details["max_height"] = max_height
	details["timeout_msec"] = timeout_msec
	details["cleanup"] = cleanup
	details["retention_max_files"] = retention_max_files
	details["retention_max_bytes"] = retention_max_bytes
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime screenshot requires full_control on bridge and addon", details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "runtime screenshot requires a running scene", details)
		return
	var request_result: Dictionary = _host.call("workbench_dictionary", _host.call("request_runtime_screenshot", {
		"max_width": max_width,
		"max_height": max_height,
		"cleanup": cleanup,
		"retention_max_files": retention_max_files,
		"retention_max_bytes": retention_max_bytes
	}))
	if request_result.get("ok", false) != true:
		details["request"] = request_result
		_host.call("ack_dev_command", command, "error", str(request_result.get("message", "runtime screenshot request failed")), details)
		return
	var request_id := str(request_result.get("request_id", ""))
	if request_id == "":
		details["request"] = request_result
		_host.call("ack_dev_command", command, "error", "runtime screenshot request did not return a request id", details)
		return
	details["request"] = request_result
	details["status"] = "waiting"
	_pending_screenshot_commands[request_id] = {
		"command": command.duplicate(true),
		"details": details,
		"deadline_msec": Time.get_ticks_msec() + timeout_msec
	}
	_host.call("add_operation", "Runtime: screenshot requested")


func _handle_runtime_compare_screenshots(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var baseline_path: String = str(args.get("baseline_path", args.get("path_a", ""))).strip_edges()
	var candidate_path: String = str(args.get("candidate_path", args.get("path_b", ""))).strip_edges()
	var tolerance: float = clampf(float(args.get("tolerance", RUNTIME_SCREENSHOT_COMPARE_DEFAULT_TOLERANCE)), 0.0, 1.0)
	var max_changed_ratio: float = clampf(float(args.get("max_changed_ratio", RUNTIME_SCREENSHOT_COMPARE_DEFAULT_MAX_CHANGED_RATIO)), 0.0, 1.0)
	var max_avg_delta: float = clampf(float(args.get("max_avg_delta", RUNTIME_SCREENSHOT_COMPARE_DEFAULT_MAX_AVG_DELTA)), 0.0, 1.0)
	var max_samples: int = clampi(
		int(_host.call("workbench_int", args.get("max_samples", RUNTIME_SCREENSHOT_COMPARE_DEFAULT_MAX_SAMPLES), RUNTIME_SCREENSHOT_COMPARE_DEFAULT_MAX_SAMPLES)),
		RUNTIME_SCREENSHOT_COMPARE_MIN_SAMPLES,
		RUNTIME_SCREENSHOT_COMPARE_MAX_SAMPLES
	)
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.compare_screenshots"
	details["baseline_path"] = baseline_path
	details["candidate_path"] = candidate_path
	details["tolerance"] = tolerance
	details["max_changed_ratio"] = max_changed_ratio
	details["max_avg_delta"] = max_avg_delta
	details["max_samples"] = max_samples
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime screenshot compare requires full_control on bridge and addon", details)
		return
	var comparison: Dictionary = _compare_screenshot_images(baseline_path, candidate_path, tolerance, max_changed_ratio, max_avg_delta, max_samples)
	details["comparison"] = comparison
	details["matched"] = comparison.get("matched", false) == true
	details["changed_ratio"] = float(comparison.get("changed_ratio", 1.0))
	details["avg_delta"] = float(comparison.get("avg_delta", 1.0))
	details["sample_count"] = int(comparison.get("sample_count", 0))
	var ack_status := "ok" if comparison.get("matched", false) == true else "error"
	var ack_message := "runtime screenshots match"
	if comparison.get("ok", false) != true:
		ack_message = str(comparison.get("message", "runtime screenshot compare failed"))
	elif comparison.get("matched", false) != true:
		ack_message = "runtime screenshots differ"
	_host.call("add_operation", "Runtime: compare screenshots matched=%s changed=%.4f" % [str(details.get("matched", false)), float(details.get("changed_ratio", 1.0))])
	_host.call("ack_dev_command", command, ack_status, ack_message, details)


func _handle_runtime_input(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var raw_events: Array = _host.call("workbench_array", args.get("events", []))
	var timeout_msec: int = clampi(
		int(_host.call("workbench_int", args.get("timeout_msec", RUNTIME_INPUT_DEFAULT_TIMEOUT_MSEC), RUNTIME_INPUT_DEFAULT_TIMEOUT_MSEC)),
		RUNTIME_INPUT_MIN_TIMEOUT_MSEC,
		RUNTIME_INPUT_MAX_TIMEOUT_MSEC
	)
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.input"
	details["event_count"] = raw_events.size()
	details["max_events"] = RUNTIME_INPUT_MAX_EVENTS
	details["timeout_msec"] = timeout_msec
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime input requires full_control on bridge and addon", details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "runtime input requires a running scene", details)
		return
	if raw_events.is_empty():
		_host.call("ack_dev_command", command, "error", "runtime input requires at least one event", details)
		return
	if raw_events.size() > RUNTIME_INPUT_MAX_EVENTS:
		_host.call("ack_dev_command", command, "error", "runtime input event batch is too large", details)
		return
	var events: Array[Dictionary] = []
	for index: int in range(raw_events.size()):
		var event_value: Variant = raw_events[index]
		if typeof(event_value) != TYPE_DICTIONARY:
			details["bad_event_index"] = index
			_host.call("ack_dev_command", command, "error", "runtime input events must be objects", details)
			return
		var event: Dictionary = _host.call("workbench_dictionary", event_value)
		events.append(event.duplicate(true))
	var request_result: Dictionary = _host.call("workbench_dictionary", _host.call("request_runtime_input", {
		"events": events
	}))
	if request_result.get("ok", false) != true:
		details["request"] = request_result
		_host.call("ack_dev_command", command, "error", str(request_result.get("message", "runtime input request failed")), details)
		return
	var request_id := str(request_result.get("request_id", ""))
	if request_id == "":
		details["request"] = request_result
		_host.call("ack_dev_command", command, "error", "runtime input request did not return a request id", details)
		return
	details["request"] = request_result
	details["status"] = "waiting"
	_pending_input_commands[request_id] = {
		"command": command.duplicate(true),
		"details": details,
		"deadline_msec": Time.get_ticks_msec() + timeout_msec
	}
	_host.call("add_operation", "Runtime: input requested events=%d" % events.size())


func _handle_runtime_inspect(command: Dictionary, properties_only: bool) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var timeout_msec: int = clampi(
		int(_host.call("workbench_int", args.get("timeout_msec", RUNTIME_TREE_DEFAULT_TIMEOUT_MSEC), RUNTIME_TREE_DEFAULT_TIMEOUT_MSEC)),
		RUNTIME_TREE_MIN_TIMEOUT_MSEC,
		RUNTIME_TREE_MAX_TIMEOUT_MSEC
	)
	var max_properties: int = clampi(int(_host.call("workbench_int", args.get("max_properties", 120), 120)), 1, 500)
	var max_signals: int = clampi(int(_host.call("workbench_int", args.get("max_signals", 80), 80)), 1, 300)
	var include_values: bool = _host.call("workbench_bool", args.get("include_values", true), true)
	var include_properties: bool = true
	var include_signals: bool = false if properties_only else _host.call("workbench_bool", args.get("include_signals", true), true)
	var include_groups: bool = false if properties_only else _host.call("workbench_bool", args.get("include_groups", true), true)
	var action: String = "runtime.get_node_properties" if properties_only else "runtime.inspect_node"
	var details: Dictionary = runtime_status()
	details["action"] = action
	details["node_path"] = node_path
	details["include_properties"] = include_properties
	details["include_values"] = include_values
	details["include_signals"] = include_signals
	details["include_groups"] = include_groups
	details["max_properties"] = max_properties
	details["max_signals"] = max_signals
	details["timeout_msec"] = timeout_msec
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "%s requires full_control on bridge and addon" % action, details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "%s requires a running scene" % action, details)
		return
	if node_path == "":
		_host.call("ack_dev_command", command, "error", "node_path is required", details)
		return
	var request_result: Dictionary = _host.call("workbench_dictionary", _host.call("request_runtime_inspect", {
		"node_path": node_path,
		"include_properties": include_properties,
		"include_values": include_values,
		"include_signals": include_signals,
		"include_groups": include_groups,
		"max_properties": max_properties,
		"max_signals": max_signals
	}))
	_queue_runtime_probe_command(command, details, request_result, _pending_inspect_commands, timeout_msec, "Runtime: inspect %s" % node_path)


func _handle_runtime_state(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var node_path: String = str(args.get("node_path", args.get("path", ""))).strip_edges()
	var timeout_msec: int = clampi(
		int(_host.call("workbench_int", args.get("timeout_msec", RUNTIME_STATE_DEFAULT_TIMEOUT_MSEC), RUNTIME_STATE_DEFAULT_TIMEOUT_MSEC)),
		RUNTIME_STATE_MIN_TIMEOUT_MSEC,
		RUNTIME_STATE_MAX_TIMEOUT_MSEC
	)
	var properties: Array = _state_properties(args.get("properties", []), RUNTIME_STATE_MAX_PROPERTIES)
	var targets: Array = _state_targets(args.get("targets", []), RUNTIME_STATE_MAX_TARGETS, RUNTIME_STATE_MAX_PROPERTIES)
	if targets.is_empty() and node_path != "":
		targets.append({
			"node_path": node_path,
			"properties": properties
		})
	var include_node: bool = _host.call("workbench_bool", args.get("include_node", true), true)
	var max_value_depth: int = clampi(int(_host.call("workbench_int", args.get("max_value_depth", 4), 4)), 1, 8)
	var max_collection_items: int = clampi(int(_host.call("workbench_int", args.get("max_collection_items", 128), 128)), 1, 1000)
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.state"
	details["node_path"] = node_path
	details["target_count"] = targets.size()
	details["properties"] = properties
	details["include_node"] = include_node
	details["max_value_depth"] = max_value_depth
	details["max_collection_items"] = max_collection_items
	details["timeout_msec"] = timeout_msec
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime.state requires full_control on bridge and addon", details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "runtime.state requires a running scene", details)
		return
	if targets.size() > RUNTIME_STATE_MAX_TARGETS:
		_host.call("ack_dev_command", command, "error", "runtime.state supports at most %d targets" % RUNTIME_STATE_MAX_TARGETS, details)
		return
	var request_result: Dictionary = _host.call("workbench_dictionary", _host.call("request_runtime_state", {
		"node_path": node_path,
		"properties": properties,
		"targets": targets,
		"include_node": include_node,
		"max_value_depth": max_value_depth,
		"max_collection_items": max_collection_items
	}))
	_queue_runtime_probe_command(command, details, request_result, _pending_state_commands, timeout_msec, "Runtime: state targets=%d" % max(1, targets.size()))


func _handle_runtime_find_ui(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var text: String = str(args.get("text", args.get("query", ""))).strip_edges()
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var timeout_msec: int = clampi(
		int(_host.call("workbench_int", args.get("timeout_msec", RUNTIME_TREE_DEFAULT_TIMEOUT_MSEC), RUNTIME_TREE_DEFAULT_TIMEOUT_MSEC)),
		RUNTIME_TREE_MIN_TIMEOUT_MSEC,
		RUNTIME_TREE_MAX_TIMEOUT_MSEC
	)
	var max_matches: int = clampi(int(_host.call("workbench_int", args.get("max_matches", 20), 20)), 1, 100)
	var exact: bool = _host.call("workbench_bool", args.get("exact", false), false)
	var case_sensitive: bool = _host.call("workbench_bool", args.get("case_sensitive", false), false)
	var include_disabled: bool = _host.call("workbench_bool", args.get("include_disabled", true), true)
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.find_ui"
	details["text"] = text
	details["node_path"] = node_path
	details["exact"] = exact
	details["case_sensitive"] = case_sensitive
	details["include_disabled"] = include_disabled
	details["max_matches"] = max_matches
	details["timeout_msec"] = timeout_msec
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime.find_ui requires full_control on bridge and addon", details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "runtime.find_ui requires a running scene", details)
		return
	if text == "":
		_host.call("ack_dev_command", command, "error", "text is required", details)
		return
	var request_result: Dictionary = _host.call("workbench_dictionary", _host.call("request_runtime_ui_find", {
		"text": text,
		"node_path": node_path,
		"exact": exact,
		"case_sensitive": case_sensitive,
		"include_disabled": include_disabled,
		"max_matches": max_matches
	}))
	_queue_runtime_probe_command(command, details, request_result, _pending_ui_find_commands, timeout_msec, "Runtime: find UI text=%s" % text)


func _handle_runtime_click_text(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var text: String = str(args.get("text", args.get("query", ""))).strip_edges()
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var timeout_msec: int = clampi(
		int(_host.call("workbench_int", args.get("timeout_msec", RUNTIME_INPUT_DEFAULT_TIMEOUT_MSEC), RUNTIME_INPUT_DEFAULT_TIMEOUT_MSEC)),
		RUNTIME_INPUT_MIN_TIMEOUT_MSEC,
		RUNTIME_INPUT_MAX_TIMEOUT_MSEC
	)
	var exact: bool = _host.call("workbench_bool", args.get("exact", false), false)
	var case_sensitive: bool = _host.call("workbench_bool", args.get("case_sensitive", false), false)
	var button_index: int = int(_host.call("workbench_int", args.get("button_index", 1), 1))
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.click_text"
	details["text"] = text
	details["node_path"] = node_path
	details["exact"] = exact
	details["case_sensitive"] = case_sensitive
	details["button_index"] = button_index
	details["timeout_msec"] = timeout_msec
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime.click_text requires full_control on bridge and addon", details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "runtime.click_text requires a running scene", details)
		return
	if text == "":
		_host.call("ack_dev_command", command, "error", "text is required", details)
		return
	var request_result: Dictionary = _host.call("workbench_dictionary", _host.call("request_runtime_click_text", {
		"text": text,
		"node_path": node_path,
		"exact": exact,
		"case_sensitive": case_sensitive,
		"button_index": button_index
	}))
	_queue_runtime_probe_command(command, details, request_result, _pending_click_text_commands, timeout_msec, "Runtime: click text=%s" % text)


func _handle_runtime_check(command: Dictionary, mode: String) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var condition: String = str(args.get("condition", args.get("assertion", "node_exists"))).strip_edges().to_lower()
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var text: String = str(args.get("text", "")).strip_edges()
	var property_name: String = str(args.get("property_name", args.get("property", ""))).strip_edges()
	var timeout_msec: int = clampi(
		int(_host.call("workbench_int", args.get("timeout_msec", RUNTIME_CHECK_DEFAULT_TIMEOUT_MSEC), RUNTIME_CHECK_DEFAULT_TIMEOUT_MSEC)),
		RUNTIME_CHECK_MIN_TIMEOUT_MSEC,
		RUNTIME_CHECK_MAX_TIMEOUT_MSEC
	)
	var poll_interval_msec: int = clampi(
		int(_host.call("workbench_int", args.get("poll_interval_msec", RUNTIME_CHECK_DEFAULT_POLL_INTERVAL_MSEC), RUNTIME_CHECK_DEFAULT_POLL_INTERVAL_MSEC)),
		RUNTIME_CHECK_MIN_POLL_INTERVAL_MSEC,
		RUNTIME_CHECK_MAX_POLL_INTERVAL_MSEC
	)
	var details: Dictionary = runtime_status()
	var action: String = "runtime.wait_for" if mode == "wait" else "runtime.assert"
	details["action"] = action
	details["mode"] = mode
	details["condition"] = condition
	details["node_path"] = node_path
	details["text"] = text
	details["property_name"] = property_name
	details["timeout_msec"] = timeout_msec
	details["poll_interval_msec"] = poll_interval_msec
	if args.has("expected"):
		details["expected"] = args.get("expected")
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "%s requires full_control on bridge and addon" % action, details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "%s requires a running scene" % action, details)
		return
	var validation: Dictionary = _validate_runtime_check_args(condition, node_path, text, property_name, args.has("expected"))
	if validation.get("ok", false) != true:
		details["validation"] = validation
		_host.call("ack_dev_command", command, "error", str(validation.get("message", "invalid runtime check")), details)
		return
	var request: Dictionary = {
		"condition": condition,
		"node_path": node_path,
		"text": text,
		"property_name": property_name,
		"timeout_msec": timeout_msec,
		"poll_interval_msec": poll_interval_msec,
		"case_sensitive": _host.call("workbench_bool", args.get("case_sensitive", true), true)
	}
	if args.has("expected"):
		request["expected"] = args.get("expected")
	var request_result: Dictionary = {}
	if mode == "assert":
		request_result = _host.call("workbench_dictionary", _host.call("request_runtime_assert", request))
	else:
		request_result = _host.call("workbench_dictionary", _host.call("request_runtime_wait", request))
	if request_result.get("ok", false) != true:
		details["request"] = request_result
		_host.call("ack_dev_command", command, "error", str(request_result.get("message", "%s request failed" % action)), details)
		return
	var request_id := str(request_result.get("request_id", ""))
	if request_id == "":
		details["request"] = request_result
		_host.call("ack_dev_command", command, "error", "%s request did not return a request id" % action, details)
		return
	details["request"] = request_result
	details["status"] = "waiting"
	_pending_check_commands[request_id] = {
		"command": command.duplicate(true),
		"details": details,
		"deadline_msec": Time.get_ticks_msec() + timeout_msec + poll_interval_msec + 250,
		"mode": mode
	}
	_host.call("add_operation", "Runtime: %s requested condition=%s" % [mode, condition])


func _handle_runtime_animation_state(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var timeout_msec: int = clampi(
		int(_host.call("workbench_int", args.get("timeout_msec", RUNTIME_ANIMATION_DEFAULT_TIMEOUT_MSEC), RUNTIME_ANIMATION_DEFAULT_TIMEOUT_MSEC)),
		RUNTIME_ANIMATION_MIN_TIMEOUT_MSEC,
		RUNTIME_ANIMATION_MAX_TIMEOUT_MSEC
	)
	var max_items: int = clampi(
		int(_host.call("workbench_int", args.get("max_items", RUNTIME_ANIMATION_DEFAULT_MAX_ITEMS), RUNTIME_ANIMATION_DEFAULT_MAX_ITEMS)),
		1,
		RUNTIME_ANIMATION_MAX_ITEMS
	)
	var include_values: bool = _host.call("workbench_bool", args.get("include_values", true), true)
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.animation_state"
	details["node_path"] = node_path
	details["timeout_msec"] = timeout_msec
	details["max_items"] = max_items
	details["include_values"] = include_values
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime.animation_state requires full_control on bridge and addon", details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "runtime.animation_state requires a running scene", details)
		return
	if node_path == "":
		_host.call("ack_dev_command", command, "error", "node_path is required", details)
		return
	var request_result: Dictionary = _host.call("workbench_dictionary", _host.call("request_runtime_animation_state", {
		"node_path": node_path,
		"max_items": max_items,
		"include_values": include_values
	}))
	_queue_runtime_probe_command(command, details, request_result, _pending_animation_state_commands, timeout_msec, "Runtime: animation state %s" % node_path)


func _handle_runtime_animation_control(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var control_action: String = str(args.get("action", "")).strip_edges().to_lower()
	var timeout_msec: int = clampi(
		int(_host.call("workbench_int", args.get("timeout_msec", RUNTIME_ANIMATION_DEFAULT_TIMEOUT_MSEC), RUNTIME_ANIMATION_DEFAULT_TIMEOUT_MSEC)),
		RUNTIME_ANIMATION_MIN_TIMEOUT_MSEC,
		RUNTIME_ANIMATION_MAX_TIMEOUT_MSEC
	)
	var max_items: int = clampi(
		int(_host.call("workbench_int", args.get("max_items", RUNTIME_ANIMATION_DEFAULT_MAX_ITEMS), RUNTIME_ANIMATION_DEFAULT_MAX_ITEMS)),
		1,
		RUNTIME_ANIMATION_MAX_ITEMS
	)
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.animation_control"
	details["node_path"] = node_path
	details["animation_action"] = control_action
	details["timeout_msec"] = timeout_msec
	details["max_items"] = max_items
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime.animation_control requires full_control on bridge and addon", details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "runtime.animation_control requires a running scene", details)
		return
	if node_path == "":
		_host.call("ack_dev_command", command, "error", "node_path is required", details)
		return
	if not _runtime_animation_action_allowed(control_action):
		_host.call("ack_dev_command", command, "error", "unsupported runtime animation action: %s" % control_action, details)
		return
	var request: Dictionary = args.duplicate(true)
	request["node_path"] = node_path
	request["action"] = control_action
	request["max_items"] = max_items
	var request_result: Dictionary = _host.call("workbench_dictionary", _host.call("request_runtime_animation_control", request))
	_queue_runtime_probe_command(command, details, request_result, _pending_animation_control_commands, timeout_msec, "Runtime: animation %s %s" % [control_action, node_path])


func _handle_runtime_watch(command: Dictionary, mode: String) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var duration_msec: int = clampi(
		int(_host.call("workbench_int", args.get("duration_msec", RUNTIME_WATCH_DEFAULT_DURATION_MSEC), RUNTIME_WATCH_DEFAULT_DURATION_MSEC)),
		RUNTIME_WATCH_MIN_DURATION_MSEC,
		RUNTIME_WATCH_MAX_DURATION_MSEC
	)
	var interval_msec: int = clampi(
		int(_host.call("workbench_int", args.get("interval_msec", RUNTIME_WATCH_DEFAULT_INTERVAL_MSEC), RUNTIME_WATCH_DEFAULT_INTERVAL_MSEC)),
		RUNTIME_WATCH_MIN_INTERVAL_MSEC,
		RUNTIME_WATCH_MAX_INTERVAL_MSEC
	)
	var max_events: int = clampi(
		int(_host.call("workbench_int", args.get("max_events", RUNTIME_WATCH_DEFAULT_MAX_EVENTS), RUNTIME_WATCH_DEFAULT_MAX_EVENTS)),
		1,
		RUNTIME_WATCH_MAX_EVENTS
	)
	var targets: Array = _watch_targets(args.get("targets", []))
	var global_properties: Array = _watch_properties(args.get("properties", []), 32)
	var include_initial: bool = _host.call("workbench_bool", args.get("include_initial", true), true)
	var include_final: bool = _host.call("workbench_bool", args.get("include_final", true), true)
	var include_properties: bool = _host.call("workbench_bool", args.get("include_properties", true), true)
	var include_signals: bool = _host.call("workbench_bool", args.get("include_signals", true), true)
	var details: Dictionary = runtime_status()
	var action := "runtime.record_events" if mode == "record_events" else "runtime.watch"
	details["action"] = action
	details["duration_msec"] = duration_msec
	details["interval_msec"] = interval_msec
	details["max_events"] = max_events
	details["target_count"] = targets.size()
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "%s requires full_control on bridge and addon" % action, details)
		return
	if details.get("playing", false) != true:
		_host.call("ack_dev_command", command, "error", "%s requires a running scene" % action, details)
		return
	if targets.size() > RUNTIME_WATCH_MAX_TARGETS:
		_host.call("ack_dev_command", command, "error", "runtime watch supports at most %d targets" % RUNTIME_WATCH_MAX_TARGETS, details)
		return
	var request: Dictionary = {
		"mode": mode,
		"duration_msec": duration_msec,
		"interval_msec": interval_msec,
		"max_events": max_events,
		"targets": targets,
		"properties": global_properties,
		"include_initial": include_initial,
		"include_final": include_final,
		"include_properties": include_properties,
		"include_signals": include_signals
	}
	var request_result: Dictionary = _host.call("workbench_dictionary", _host.call("request_runtime_watch", request))
	_queue_runtime_probe_command(command, details, request_result, _pending_watch_commands, duration_msec + 2000, "Runtime: %s duration=%dms targets=%d" % [mode, duration_msec, targets.size()])


func _handle_runtime_play_scene(command: Dictionary) -> void:
	var args: Dictionary = _host.call("workbench_dictionary", command.get("args", {}))
	var scene_path: String = str(args.get("scene_path", "")).strip_edges()
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.play_scene"
	details["requested_scene_path"] = scene_path
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime control requires full_control on bridge and addon", details)
		return
	if scene_path != "" and not _runtime_scene_path_allowed(scene_path):
		_host.call("ack_dev_command", command, "error", "scene_path must be a safe res:// .tscn or .scn path", details)
		return
	if details.get("playing", false) == true:
		_host.call("ack_dev_command", command, "error", "a scene is already running; stop it first", details)
		return
	var editor_interface = _editor_interface_from_host()
	if editor_interface == null:
		_host.call("ack_dev_command", command, "error", "editor interface is not available", details)
		return
	var method_name: String = ""
	if scene_path != "":
		if not editor_interface.has_method("play_custom_scene"):
			_host.call("ack_dev_command", command, "error", "EditorInterface.play_custom_scene is not available", details)
			return
		editor_interface.call("play_custom_scene", scene_path)
		method_name = "play_custom_scene"
	else:
		var root: Node = editor_interface.get_edited_scene_root()
		if root != null and editor_interface.has_method("play_current_scene"):
			editor_interface.call("play_current_scene")
			method_name = "play_current_scene"
		elif editor_interface.has_method("play_main_scene"):
			editor_interface.call("play_main_scene")
			method_name = "play_main_scene"
		else:
			_host.call("ack_dev_command", command, "error", "EditorInterface playback methods are not available", details)
			return
	details["status"] = "started"
	details["method"] = method_name
	details["post_status"] = runtime_status()
	_host.call("send_editor_state")
	_host.call("add_operation", "Runtime: play scene via %s" % method_name)
	_host.call("ack_dev_command", command, "ok", "runtime play scene requested", details)


func _handle_runtime_stop_scene(command: Dictionary) -> void:
	var details: Dictionary = runtime_status()
	details["action"] = "runtime.stop_scene"
	if not runtime_gate_open():
		_host.call("ack_dev_command", command, "error", "runtime control requires full_control on bridge and addon", details)
		return
	var editor_interface = _editor_interface_from_host()
	if editor_interface == null:
		_host.call("ack_dev_command", command, "error", "editor interface is not available", details)
		return
	if details.get("playing", false) != true:
		details["status"] = "already_stopped"
		_host.call("ack_dev_command", command, "ok", "no scene is running", details)
		return
	if not editor_interface.has_method("stop_playing_scene"):
		_host.call("ack_dev_command", command, "error", "EditorInterface.stop_playing_scene is not available", details)
		return
	editor_interface.call("stop_playing_scene")
	details["status"] = "stopped"
	details["method"] = "stop_playing_scene"
	details["post_status"] = runtime_status()
	_host.call("send_editor_state")
	_host.call("add_operation", "Runtime: stop scene")
	_host.call("ack_dev_command", command, "ok", "runtime stop scene requested", details)


func _service_runtime_tree_requests() -> void:
	if _pending_tree_commands.is_empty():
		return
	var completed: Array[String] = []
	for request_id_value: Variant in _pending_tree_commands.keys():
		var request_id := str(request_id_value)
		var pending: Dictionary = _pending_tree_commands.get(request_id, {})
		var command: Dictionary = _host.call("workbench_dictionary", pending.get("command", {}))
		var details: Dictionary = _host.call("workbench_dictionary", pending.get("details", {}))
		var response_state: Dictionary = _host.call("workbench_dictionary", _host.call("runtime_tree_response", request_id))
		if response_state.get("available", false) == true:
			var runtime_tree: Dictionary = _host.call("workbench_dictionary", response_state.get("response", {}))
			details["runtime_tree"] = runtime_tree
			details["status"] = "captured"
			details["node_count"] = int(runtime_tree.get("node_count", 0))
			details["truncated"] = runtime_tree.get("truncated", false)
			var ack_status := "ok"
			var ack_message := "runtime tree snapshot"
			if runtime_tree.get("ok", false) != true:
				ack_status = "error"
				ack_message = str(runtime_tree.get("message", "runtime tree snapshot failed"))
			_host.call("add_operation", "Runtime: tree nodes=%d" % int(details.get("node_count", 0)))
			_host.call("ack_dev_command", command, ack_status, ack_message, details)
			completed.append(request_id)
			continue
		if Time.get_ticks_msec() >= int(pending.get("deadline_msec", 0)):
			details["status"] = "timeout"
			details["response_state"] = response_state
			_host.call("ack_dev_command", command, "error", "runtime tree request timed out", details)
			completed.append(request_id)
	for request_id: String in completed:
		_pending_tree_commands.erase(request_id)


func _service_runtime_screenshot_requests() -> void:
	if _pending_screenshot_commands.is_empty():
		return
	var completed: Array[String] = []
	for request_id_value: Variant in _pending_screenshot_commands.keys():
		var request_id := str(request_id_value)
		var pending: Dictionary = _pending_screenshot_commands.get(request_id, {})
		var command: Dictionary = _host.call("workbench_dictionary", pending.get("command", {}))
		var details: Dictionary = _host.call("workbench_dictionary", pending.get("details", {}))
		var response_state: Dictionary = _host.call("workbench_dictionary", _host.call("runtime_screenshot_response", request_id))
		if response_state.get("available", false) == true:
			var screenshot: Dictionary = _host.call("workbench_dictionary", response_state.get("response", {}))
			details["screenshot"] = screenshot
			details["status"] = "captured"
			details["path"] = str(screenshot.get("path", ""))
			details["absolute_path"] = str(screenshot.get("absolute_path", ""))
			details["width"] = int(screenshot.get("width", 0))
			details["height"] = int(screenshot.get("height", 0))
			details["file_size"] = int(screenshot.get("file_size", 0))
			var ack_status := "ok"
			var ack_message := "runtime screenshot"
			if screenshot.get("ok", false) != true:
				ack_status = "error"
				ack_message = str(screenshot.get("message", "runtime screenshot failed"))
			_host.call("add_operation", "Runtime: screenshot %dx%d" % [int(details.get("width", 0)), int(details.get("height", 0))])
			_host.call("ack_dev_command", command, ack_status, ack_message, details)
			completed.append(request_id)
			continue
		if Time.get_ticks_msec() >= int(pending.get("deadline_msec", 0)):
			details["status"] = "timeout"
			details["response_state"] = response_state
			_host.call("ack_dev_command", command, "error", "runtime screenshot request timed out", details)
			completed.append(request_id)
	for request_id: String in completed:
		_pending_screenshot_commands.erase(request_id)


func _service_runtime_input_requests() -> void:
	if _pending_input_commands.is_empty():
		return
	var completed: Array[String] = []
	for request_id_value: Variant in _pending_input_commands.keys():
		var request_id := str(request_id_value)
		var pending: Dictionary = _pending_input_commands.get(request_id, {})
		var command: Dictionary = _host.call("workbench_dictionary", pending.get("command", {}))
		var details: Dictionary = _host.call("workbench_dictionary", pending.get("details", {}))
		var response_state: Dictionary = _host.call("workbench_dictionary", _host.call("runtime_input_response", request_id))
		if response_state.get("available", false) == true:
			var input_result: Dictionary = _host.call("workbench_dictionary", response_state.get("response", {}))
			details["input"] = input_result
			details["status"] = "applied"
			details["applied_count"] = int(input_result.get("applied_count", 0))
			details["failure_count"] = int(input_result.get("failure_count", 0))
			var ack_status := "ok"
			var ack_message := "runtime input"
			if input_result.get("ok", false) != true:
				ack_status = "error"
				ack_message = str(input_result.get("message", "runtime input failed"))
			_host.call("add_operation", "Runtime: input applied=%d failures=%d" % [int(details.get("applied_count", 0)), int(details.get("failure_count", 0))])
			_host.call("ack_dev_command", command, ack_status, ack_message, details)
			completed.append(request_id)
			continue
		if Time.get_ticks_msec() >= int(pending.get("deadline_msec", 0)):
			details["status"] = "timeout"
			details["response_state"] = response_state
			_host.call("ack_dev_command", command, "error", "runtime input request timed out", details)
			completed.append(request_id)
	for request_id: String in completed:
		_pending_input_commands.erase(request_id)


func _service_runtime_inspect_requests() -> void:
	_service_runtime_probe_requests(_pending_inspect_commands, "runtime_inspect_response", "inspect", "runtime inspect request timed out")


func _service_runtime_state_requests() -> void:
	_service_runtime_probe_requests(_pending_state_commands, "runtime_state_response", "state", "runtime state request timed out")


func _service_runtime_ui_find_requests() -> void:
	_service_runtime_probe_requests(_pending_ui_find_commands, "runtime_ui_find_response", "ui_find", "runtime UI find request timed out")


func _service_runtime_click_text_requests() -> void:
	_service_runtime_probe_requests(_pending_click_text_commands, "runtime_click_text_response", "click_text", "runtime click text request timed out")


func _queue_runtime_probe_command(command: Dictionary, details: Dictionary, request_result: Dictionary, pending_commands: Dictionary, timeout_msec: int, operation_text: String) -> void:
	if request_result.get("ok", false) != true:
		details["request"] = request_result
		_host.call("ack_dev_command", command, "error", str(request_result.get("message", "runtime probe request failed")), details)
		return
	var request_id := str(request_result.get("request_id", ""))
	if request_id == "":
		details["request"] = request_result
		_host.call("ack_dev_command", command, "error", "runtime probe request did not return a request id", details)
		return
	details["request"] = request_result
	details["status"] = "waiting"
	pending_commands[request_id] = {
		"command": command.duplicate(true),
		"details": details,
		"deadline_msec": Time.get_ticks_msec() + timeout_msec
	}
	_host.call("add_operation", operation_text)


func _service_runtime_probe_requests(pending_commands: Dictionary, response_method: String, result_key: String, timeout_message: String) -> void:
	if pending_commands.is_empty():
		return
	var completed: Array[String] = []
	for request_id_value: Variant in pending_commands.keys():
		var request_id := str(request_id_value)
		var pending: Dictionary = pending_commands.get(request_id, {})
		var command: Dictionary = _host.call("workbench_dictionary", pending.get("command", {}))
		var details: Dictionary = _host.call("workbench_dictionary", pending.get("details", {}))
		var response_state: Dictionary = _host.call("workbench_dictionary", _host.call(response_method, request_id))
		if response_state.get("available", false) == true:
			var response: Dictionary = _host.call("workbench_dictionary", response_state.get("response", {}))
			details[result_key] = response
			details["response"] = response
			details["ok"] = response.get("ok", false) == true
			if response.has("node"):
				details["node"] = response.get("node")
			if response.has("properties"):
				details["properties"] = response.get("properties")
				details["property_count"] = int(response.get("property_count", 0))
			if response.has("nodes"):
				details["nodes"] = response.get("nodes")
				details["node_count"] = int(response.get("node_count", 0))
			if response.has("values"):
				details["values"] = response.get("values")
				details["value_count"] = int(response.get("value_count", 0))
			if response.has("missing"):
				details["missing"] = response.get("missing")
			if response.has("matches"):
				details["matches"] = response.get("matches")
				details["match_count"] = int(response.get("match_count", 0))
			if response.has("selected"):
				details["selected"] = response.get("selected")
			if response.has("click"):
				details["click"] = response.get("click")
			var ack_status := "ok" if response.get("ok", false) == true else "error"
			var ack_message := result_key.replace("_", " ")
			if response.get("ok", false) != true:
				ack_message = str(response.get("message", "%s failed" % ack_message))
			_host.call("ack_dev_command", command, ack_status, ack_message, details)
			completed.append(request_id)
			continue
		if Time.get_ticks_msec() >= int(pending.get("deadline_msec", 0)):
			details["status"] = "timeout"
			details["response_state"] = response_state
			_host.call("ack_dev_command", command, "error", timeout_message, details)
			completed.append(request_id)
	for request_id: String in completed:
		pending_commands.erase(request_id)


func _service_runtime_check_requests() -> void:
	if _pending_check_commands.is_empty():
		return
	var completed: Array[String] = []
	for request_id_value: Variant in _pending_check_commands.keys():
		var request_id := str(request_id_value)
		var pending: Dictionary = _pending_check_commands.get(request_id, {})
		var command: Dictionary = _host.call("workbench_dictionary", pending.get("command", {}))
		var details: Dictionary = _host.call("workbench_dictionary", pending.get("details", {}))
		var mode: String = str(pending.get("mode", "wait"))
		var response_state: Dictionary = {}
		if mode == "assert":
			response_state = _host.call("workbench_dictionary", _host.call("runtime_assert_response", request_id))
		else:
			response_state = _host.call("workbench_dictionary", _host.call("runtime_wait_response", request_id))
		if response_state.get("available", false) == true:
			var check_result: Dictionary = _host.call("workbench_dictionary", response_state.get("response", {}))
			var matched: bool = check_result.get("matched", false) == true
			details["check"] = check_result
			details["matched"] = matched
			details["status"] = "matched" if matched else "failed"
			details["elapsed_msec"] = int(check_result.get("elapsed_msec", 0))
			details["attempts"] = int(check_result.get("attempts", 0))
			var ack_status := "ok" if matched else "error"
			var ack_message := "runtime %s matched" % mode
			if not matched:
				ack_message = str(check_result.get("message", "runtime %s failed" % mode))
			_host.call("add_operation", "Runtime: %s condition=%s matched=%s" % [mode, str(details.get("condition", "")), str(matched)])
			_host.call("ack_dev_command", command, ack_status, ack_message, details)
			completed.append(request_id)
			continue
		if Time.get_ticks_msec() >= int(pending.get("deadline_msec", 0)):
			details["status"] = "timeout"
			details["response_state"] = response_state
			_host.call("ack_dev_command", command, "error", "runtime %s request timed out" % mode, details)
			completed.append(request_id)
	for request_id: String in completed:
		_pending_check_commands.erase(request_id)


func _service_runtime_animation_state_requests() -> void:
	_service_runtime_probe_requests(_pending_animation_state_commands, "runtime_animation_state_response", "animation_state", "runtime animation state request timed out")


func _service_runtime_animation_control_requests() -> void:
	_service_runtime_probe_requests(_pending_animation_control_commands, "runtime_animation_control_response", "animation_control", "runtime animation control request timed out")


func _service_runtime_watch_requests() -> void:
	_service_runtime_probe_requests(_pending_watch_commands, "runtime_watch_response", "watch", "runtime watch request timed out")


func _validate_runtime_check_args(condition: String, node_path: String, text: String, property_name: String, has_expected: bool) -> Dictionary:
	var allowed: Array[String] = ["node_exists", "node_missing", "node_visible", "node_hidden", "text_contains", "text_equals", "text_missing", "property_exists", "property_missing", "property_equals", "property_not_equals", "property_contains", "property_gt", "property_gte", "property_lt", "property_lte"]
	if not allowed.has(condition):
		return {"ok": false, "message": "unsupported runtime check condition: %s" % condition}
	match condition:
		"node_exists", "node_missing", "node_visible", "node_hidden":
			if node_path == "":
				return {"ok": false, "message": "node_path is required"}
		"text_contains", "text_equals", "text_missing":
			if text == "":
				return {"ok": false, "message": "text is required"}
		"property_exists", "property_missing":
			if node_path == "":
				return {"ok": false, "message": "node_path is required"}
			if property_name == "":
				return {"ok": false, "message": "property_name is required"}
		"property_equals", "property_not_equals", "property_contains", "property_gt", "property_gte", "property_lt", "property_lte":
			if node_path == "":
				return {"ok": false, "message": "node_path is required"}
			if property_name == "":
				return {"ok": false, "message": "property_name is required"}
			if not has_expected:
				return {"ok": false, "message": "expected is required"}
	return {"ok": true, "message": "runtime check arguments ok"}


func _runtime_animation_action_allowed(action: String) -> bool:
	return ["play", "stop", "pause", "seek", "set_speed", "tree_active", "tree_travel", "tree_set_parameter"].has(action)


func _watch_targets(value: Variant) -> Array:
	var result: Array = []
	var raw_targets: Array = _host.call("workbench_array", value)
	for target_value: Variant in raw_targets:
		if typeof(target_value) == TYPE_DICTIONARY:
			var target: Dictionary = _host.call("workbench_dictionary", target_value)
			var normalized: Dictionary = {
				"node_path": str(target.get("node_path", target.get("path", ""))).strip_edges(),
				"properties": _watch_properties(target.get("properties", []), 32)
			}
			if target.has("include_signals"):
				normalized["include_signals"] = _host.call("workbench_bool", target.get("include_signals", true), true)
			if target.has("include_groups"):
				normalized["include_groups"] = _host.call("workbench_bool", target.get("include_groups", false), false)
			result.append(normalized)
		else:
			var node_path := str(target_value).strip_edges()
			if node_path != "":
				result.append({
					"node_path": node_path,
					"properties": []
				})
	return result


func _watch_properties(value: Variant, limit: int) -> Array:
	var result: Array = []
	if typeof(value) == TYPE_STRING:
		var single := str(value).strip_edges()
		if single != "":
			result.append(single)
		return result
	var raw_properties: Array = _host.call("workbench_array", value)
	for property_value: Variant in raw_properties:
		var property_name := str(property_value).strip_edges()
		if property_name == "" or result.has(property_name):
			continue
		result.append(property_name)
		if result.size() >= limit:
			break
	return result


func _state_targets(value: Variant, target_limit: int, property_limit: int) -> Array:
	var result: Array = []
	var raw_targets: Array = _host.call("workbench_array", value)
	for target_value: Variant in raw_targets:
		if result.size() >= target_limit:
			break
		if typeof(target_value) == TYPE_DICTIONARY:
			var target: Dictionary = _host.call("workbench_dictionary", target_value)
			var node_path: String = str(target.get("node_path", target.get("path", ""))).strip_edges()
			if node_path == "":
				continue
			result.append({
				"node_path": node_path,
				"properties": _state_properties(target.get("properties", []), property_limit)
			})
		else:
			var path_value := str(target_value).strip_edges()
			if path_value != "":
				result.append({
					"node_path": path_value,
					"properties": []
				})
	return result


func _state_properties(value: Variant, limit: int) -> Array:
	var result: Array = []
	if typeof(value) == TYPE_STRING:
		var single := str(value).strip_edges()
		if single != "":
			result.append(single)
		return result
	var raw_properties: Array = _host.call("workbench_array", value)
	for property_value: Variant in raw_properties:
		var property_name := str(property_value).strip_edges()
		if property_name == "" or result.has(property_name):
			continue
		result.append(property_name)
		if result.size() >= limit:
			break
	return result


func _runtime_scene_path_allowed(scene_path: String) -> bool:
	if scene_path == "":
		return true
	if not scene_path.begins_with("res://"):
		return false
	if scene_path.find("..") >= 0:
		return false
	return scene_path.ends_with(".tscn") or scene_path.ends_with(".scn")


func _runtime_log_categories(args: Dictionary) -> Array[String]:
	var raw_categories: Array = _host.call("workbench_array", args.get("categories", []))
	var categories: Array[String] = []
	if raw_categories.is_empty():
		return ["runtime", "output", "error", "warning", "session", "debugger"]
	for category_value: Variant in raw_categories:
		var category := str(category_value).strip_edges().to_lower()
		if category == "":
			continue
		if category == "all":
			return []
		if not categories.has(category):
			categories.append(category)
	return categories


func _runtime_log_category_allowed(category: String, categories: Array[String]) -> bool:
	if categories.is_empty():
		return true
	return categories.has(category)


func _compare_screenshot_images(baseline_path: String, candidate_path: String, tolerance: float, max_changed_ratio: float, max_avg_delta: float, max_samples: int) -> Dictionary:
	if baseline_path == "" or candidate_path == "":
		return _screenshot_compare_error("baseline_path and candidate_path are required")
	var baseline_result: Dictionary = _load_screenshot_image(baseline_path, "baseline")
	if baseline_result.get("ok", false) != true:
		return baseline_result
	var candidate_result: Dictionary = _load_screenshot_image(candidate_path, "candidate")
	if candidate_result.get("ok", false) != true:
		return candidate_result
	var baseline: Image = baseline_result.get("image", null)
	var candidate: Image = candidate_result.get("image", null)
	if baseline == null or candidate == null or baseline.is_empty() or candidate.is_empty():
		return _screenshot_compare_error("screenshot image is empty")
	var width: int = baseline.get_width()
	var height: int = baseline.get_height()
	var candidate_width: int = candidate.get_width()
	var candidate_height: int = candidate.get_height()
	if width != candidate_width or height != candidate_height:
		return {
			"ok": true,
			"matched": false,
			"message": "screenshot dimensions differ",
			"baseline_path": baseline_path,
			"candidate_path": candidate_path,
			"width": width,
			"height": height,
			"candidate_width": candidate_width,
			"candidate_height": candidate_height,
			"dimension_match": false,
			"sample_count": 0,
			"changed_count": 0,
			"changed_ratio": 1.0,
			"avg_delta": 1.0,
			"max_delta": 1.0
		}
	var total_pixels: int = max(1, width * height)
	var sample_step: int = max(1, int(ceil(sqrt(float(total_pixels) / float(max_samples)))))
	var sample_count := 0
	var changed_count := 0
	var delta_sum := 0.0
	var max_delta := 0.0
	for y: int in range(0, height, sample_step):
		for x: int in range(0, width, sample_step):
			var left: Color = baseline.get_pixel(x, y)
			var right: Color = candidate.get_pixel(x, y)
			var delta: float = max(
				max(abs(left.r - right.r), abs(left.g - right.g)),
				max(abs(left.b - right.b), abs(left.a - right.a))
			)
			sample_count += 1
			delta_sum += delta
			max_delta = max(max_delta, delta)
			if delta > tolerance:
				changed_count += 1
	var changed_ratio := float(changed_count) / float(max(1, sample_count))
	var avg_delta := delta_sum / float(max(1, sample_count))
	var matched: bool = changed_ratio <= max_changed_ratio and avg_delta <= max_avg_delta
	return {
		"ok": true,
		"matched": matched,
		"message": "screenshots match" if matched else "screenshots differ",
		"baseline_path": baseline_path,
		"candidate_path": candidate_path,
		"width": width,
		"height": height,
		"dimension_match": true,
		"sample_step": sample_step,
		"sample_count": sample_count,
		"changed_count": changed_count,
		"changed_ratio": changed_ratio,
		"avg_delta": avg_delta,
		"max_delta": max_delta,
		"tolerance": tolerance,
		"max_changed_ratio": max_changed_ratio,
		"max_avg_delta": max_avg_delta,
		"baseline_file_size": _file_size_for_path(baseline_path),
		"candidate_file_size": _file_size_for_path(candidate_path)
	}


func _load_screenshot_image(path: String, label: String) -> Dictionary:
	if not _screenshot_path_allowed(path):
		return _screenshot_compare_error("%s screenshot path must be under %s" % [label, RUNTIME_SCREENSHOT_DIR])
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return _screenshot_compare_error("%s screenshot file is empty or not readable: %s" % [label, path])
	var image := Image.new()
	var load_error: Error = image.load_png_from_buffer(bytes)
	if load_error != OK:
		return _screenshot_compare_error("%s screenshot PNG load failed: %s" % [label, error_string(load_error)])
	return {
		"ok": true,
		"image": image,
		"path": path,
		"width": image.get_width(),
		"height": image.get_height()
	}


func _screenshot_path_allowed(path: String) -> bool:
	if path == "" or not path.to_lower().ends_with(".png"):
		return false
	var normalized: String = path.replace("\\", "/")
	if normalized.begins_with("%s/" % RUNTIME_SCREENSHOT_DIR):
		return true
	var absolute_dir: String = ProjectSettings.globalize_path(RUNTIME_SCREENSHOT_DIR).replace("\\", "/")
	if not absolute_dir.ends_with("/"):
		absolute_dir += "/"
	return normalized.begins_with(absolute_dir)


func _screenshot_compare_error(message: String) -> Dictionary:
	return {
		"ok": false,
		"matched": false,
		"message": message,
		"sample_count": 0,
		"changed_count": 0,
		"changed_ratio": 1.0,
		"avg_delta": 1.0,
		"max_delta": 1.0
	}


func _file_size_for_path(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := int(file.get_length())
	file.close()
	return size


func _editor_interface_from_host() -> Variant:
	return _editor_interface
