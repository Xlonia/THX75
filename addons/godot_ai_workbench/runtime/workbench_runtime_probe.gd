extends Node

const MESSAGE_PREFIX := "gaw_runtime"
const MAX_NODES_DEFAULT := 256
const MAX_NODES_HARD_LIMIT := 2048
const MAX_TEXT_LENGTH := 512
const SCREENSHOT_DIR := "user://godot_ai_workbench/screenshots"
const SCREENSHOT_DEFAULT_MAX_WIDTH := 1280
const SCREENSHOT_DEFAULT_MAX_HEIGHT := 720
const SCREENSHOT_HARD_MAX_DIMENSION := 4096
const SCREENSHOT_RETENTION_DEFAULT_MAX_FILES := 50
const SCREENSHOT_RETENTION_HARD_MAX_FILES := 500
const SCREENSHOT_RETENTION_DEFAULT_MAX_BYTES := 52428800
const SCREENSHOT_RETENTION_HARD_MAX_BYTES := 524288000
const INPUT_MAX_EVENTS := 20
const INSPECT_DEFAULT_MAX_PROPERTIES := 120
const INSPECT_MAX_PROPERTIES := 500
const INSPECT_DEFAULT_MAX_SIGNALS := 80
const INSPECT_MAX_SIGNALS := 300
const CHECK_DEFAULT_TIMEOUT_MSEC := 3000
const CHECK_MIN_TIMEOUT_MSEC := 100
const CHECK_MAX_TIMEOUT_MSEC := 120000
const CHECK_DEFAULT_POLL_INTERVAL_MSEC := 100
const CHECK_MIN_POLL_INTERVAL_MSEC := 50
const CHECK_MAX_POLL_INTERVAL_MSEC := 5000
const CHECK_TEXT_SEARCH_MAX_NODES := 512
const UI_FIND_DEFAULT_MAX_MATCHES := 20
const UI_FIND_MAX_MATCHES := 100
const UI_FIND_MAX_NODES := 1024
const ANIMATION_DEFAULT_MAX_ITEMS := 80
const ANIMATION_MAX_ITEMS := 200
const WATCH_DEFAULT_DURATION_MSEC := 1000
const WATCH_MIN_DURATION_MSEC := 100
const WATCH_MAX_DURATION_MSEC := 5000
const WATCH_DEFAULT_INTERVAL_MSEC := 100
const WATCH_MIN_INTERVAL_MSEC := 50
const WATCH_MAX_INTERVAL_MSEC := 1000
const WATCH_DEFAULT_MAX_EVENTS := 80
const WATCH_MAX_EVENTS := 300
const WATCH_MAX_TARGETS := 16
const WATCH_MAX_PROPERTIES := 32
const WATCH_MAX_SIGNALS := 64
const WATCH_MAX_CONNECTIONS_PER_SIGNAL := 16
const STATE_MAX_TARGETS := 16
const STATE_MAX_PROPERTIES := 64
const STATE_DEFAULT_MAX_VALUE_DEPTH := 4
const STATE_MAX_VALUE_DEPTH := 8
const STATE_DEFAULT_MAX_COLLECTION_ITEMS := 128
const STATE_MAX_COLLECTION_ITEMS := 1000

var _capture_registered := false
var _pending_checks: Dictionary = {}
var _pending_watches: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_capture()
	if EngineDebugger.is_active():
		EngineDebugger.send_message("%s:probe_ready" % MESSAGE_PREFIX, [JSON.stringify(_probe_status())])


func _process(_delta: float) -> void:
	_service_pending_checks()
	_service_pending_watches()


func _exit_tree() -> void:
	if _capture_registered:
		EngineDebugger.unregister_message_capture(MESSAGE_PREFIX)
		_capture_registered = false


func _register_capture() -> void:
	if _capture_registered:
		return
	if EngineDebugger.has_capture(MESSAGE_PREFIX):
		return
	EngineDebugger.register_message_capture(MESSAGE_PREFIX, Callable(self, "_capture_runtime_message"))
	_capture_registered = true


func _capture_runtime_message(message: String, data: Array) -> bool:
	match message:
		"tree_request":
			_handle_tree_request(data)
			return true
		"screenshot_request":
			_handle_screenshot_request(data)
			return true
		"input_request":
			_handle_input_request(data)
			return true
		"inspect_request":
			_handle_inspect_request(data)
			return true
		"state_request":
			_handle_state_request(data)
			return true
		"ui_find_request":
			_handle_ui_find_request(data)
			return true
		"click_text_request":
			_handle_click_text_request(data)
			return true
		"animation_state_request":
			_handle_animation_state_request(data)
			return true
		"animation_control_request":
			_handle_animation_control_request(data)
			return true
		"watch_request":
			_handle_watch_request(data)
			return true
		"wait_request":
			_handle_check_request(data, "wait_response", "wait")
			return true
		"assert_request":
			_handle_check_request(data, "assert_response", "assert")
			return true
		"ping":
			EngineDebugger.send_message("%s:pong" % MESSAGE_PREFIX, [JSON.stringify(_probe_status())])
			return true
	return false


func _handle_tree_request(data: Array) -> void:
	var request: Dictionary = _request_dictionary(data)
	var response: Dictionary = _runtime_tree_snapshot(request)
	EngineDebugger.send_message("%s:tree_response" % MESSAGE_PREFIX, [JSON.stringify(response)])


func _handle_screenshot_request(data: Array) -> void:
	var request: Dictionary = _request_dictionary(data)
	var response: Dictionary = _runtime_screenshot(request)
	EngineDebugger.send_message("%s:screenshot_response" % MESSAGE_PREFIX, [JSON.stringify(response)])


func _handle_input_request(data: Array) -> void:
	var request: Dictionary = _request_dictionary(data)
	var response: Dictionary = _runtime_input(request)
	EngineDebugger.send_message("%s:input_response" % MESSAGE_PREFIX, [JSON.stringify(response)])


func _handle_inspect_request(data: Array) -> void:
	var request: Dictionary = _request_dictionary(data)
	var response: Dictionary = _runtime_inspect_node(request)
	EngineDebugger.send_message("%s:inspect_response" % MESSAGE_PREFIX, [JSON.stringify(response)])


func _handle_state_request(data: Array) -> void:
	var request: Dictionary = _request_dictionary(data)
	var response: Dictionary = _runtime_state_snapshot(request)
	EngineDebugger.send_message("%s:state_response" % MESSAGE_PREFIX, [JSON.stringify(response)])


func _handle_ui_find_request(data: Array) -> void:
	var request: Dictionary = _request_dictionary(data)
	var response: Dictionary = _runtime_find_ui(request)
	EngineDebugger.send_message("%s:ui_find_response" % MESSAGE_PREFIX, [JSON.stringify(response)])


func _handle_click_text_request(data: Array) -> void:
	var request: Dictionary = _request_dictionary(data)
	var response: Dictionary = _runtime_click_text(request)
	EngineDebugger.send_message("%s:click_text_response" % MESSAGE_PREFIX, [JSON.stringify(response)])


func _handle_animation_state_request(data: Array) -> void:
	var request: Dictionary = _request_dictionary(data)
	var response: Dictionary = _runtime_animation_state(request)
	EngineDebugger.send_message("%s:animation_state_response" % MESSAGE_PREFIX, [JSON.stringify(response)])


func _handle_animation_control_request(data: Array) -> void:
	var request: Dictionary = _request_dictionary(data)
	var response: Dictionary = _runtime_animation_control(request)
	EngineDebugger.send_message("%s:animation_control_response" % MESSAGE_PREFIX, [JSON.stringify(response)])


func _handle_watch_request(data: Array) -> void:
	var request: Dictionary = _request_dictionary(data)
	var request_id: String = str(request.get("request_id", ""))
	if request_id == "":
		EngineDebugger.send_message("%s:watch_response" % MESSAGE_PREFIX, [JSON.stringify(_runtime_request_error(request_id, "request_id is required"))])
		return
	var now_msec: int = Time.get_ticks_msec()
	var duration_msec: int = clampi(int(request.get("duration_msec", WATCH_DEFAULT_DURATION_MSEC)), WATCH_MIN_DURATION_MSEC, WATCH_MAX_DURATION_MSEC)
	var interval_msec: int = clampi(int(request.get("interval_msec", WATCH_DEFAULT_INTERVAL_MSEC)), WATCH_MIN_INTERVAL_MSEC, WATCH_MAX_INTERVAL_MSEC)
	var pending: Dictionary = {
		"request": request.duplicate(true),
		"started_msec": now_msec,
		"deadline_msec": now_msec + duration_msec,
		"next_sample_msec": now_msec + interval_msec,
		"interval_msec": interval_msec,
		"samples": [],
		"events": [],
		"last_values": {},
		"sample_index": 0
	}
	if _bool_value(request.get("include_initial", true), true):
		_append_watch_sample(pending, now_msec, "initial")
	_pending_watches[request_id] = pending


func _handle_check_request(data: Array, response_message: String, mode: String) -> void:
	var request: Dictionary = _request_dictionary(data)
	var request_id: String = str(request.get("request_id", ""))
	var now_msec: int = Time.get_ticks_msec()
	var timeout_msec: int = clampi(int(request.get("timeout_msec", CHECK_DEFAULT_TIMEOUT_MSEC)), CHECK_MIN_TIMEOUT_MSEC, CHECK_MAX_TIMEOUT_MSEC)
	var poll_interval_msec: int = clampi(int(request.get("poll_interval_msec", CHECK_DEFAULT_POLL_INTERVAL_MSEC)), CHECK_MIN_POLL_INTERVAL_MSEC, CHECK_MAX_POLL_INTERVAL_MSEC)
	var result: Dictionary = _runtime_check_result(request)
	if result.get("matched", false) == true or result.get("terminal", false) == true:
		_send_check_response(response_message, _final_check_response(request, result, mode, 1, now_msec, false))
		return
	_pending_checks[request_id] = {
		"request": request.duplicate(true),
		"response_message": response_message,
		"mode": mode,
		"started_msec": now_msec,
		"deadline_msec": now_msec + timeout_msec,
		"next_poll_msec": now_msec + poll_interval_msec,
		"poll_interval_msec": poll_interval_msec,
		"attempts": 1,
		"last_result": result
	}


func _request_dictionary(data: Array) -> Dictionary:
	if data.is_empty():
		return {}
	if typeof(data[0]) == TYPE_DICTIONARY:
		var direct: Dictionary = data[0]
		return direct
	if typeof(data[0]) == TYPE_STRING:
		var parsed: Variant = JSON.parse_string(str(data[0]))
		if typeof(parsed) == TYPE_DICTIONARY:
			var parsed_dictionary: Dictionary = parsed
			return parsed_dictionary
	return {}


func _runtime_tree_snapshot(request: Dictionary) -> Dictionary:
	var max_nodes: int = clampi(int(request.get("max_nodes", MAX_NODES_DEFAULT)), 1, MAX_NODES_HARD_LIMIT)
	var include_internal: bool = _bool_value(request.get("include_internal", false), false)
	var include_groups: bool = _bool_value(request.get("include_groups", false), false)
	var request_id: String = str(request.get("request_id", ""))
	var root: Window = get_tree().root
	var current_scene: Node = get_tree().current_scene
	var nodes: Array = []
	var queue: Array = []
	queue.append(root)

	while not queue.is_empty():
		var node_value: Variant = queue.pop_front()
		var node: Node = node_value as Node
		if node == null:
			continue
		if not include_internal and _should_skip_node(node):
			continue
		if nodes.size() >= max_nodes:
			break
		nodes.append(_node_summary(node, include_groups))
		for child: Node in node.get_children():
			queue.append(child)

	var current_scene_path := ""
	var current_scene_name := ""
	if current_scene != null:
		current_scene_path = current_scene.scene_file_path
		current_scene_name = str(current_scene.name)

	return {
		"request_id": request_id,
		"ok": true,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"root_path": str(root.get_path()),
		"current_scene_path": current_scene_path,
		"current_scene_name": current_scene_name,
		"node_count": nodes.size(),
		"truncated": not queue.is_empty(),
		"max_nodes": max_nodes,
		"include_internal": include_internal,
		"include_groups": include_groups,
		"nodes": nodes
	}


func _runtime_screenshot(request: Dictionary) -> Dictionary:
	var request_id: String = str(request.get("request_id", ""))
	var max_width: int = clampi(int(request.get("max_width", SCREENSHOT_DEFAULT_MAX_WIDTH)), 1, SCREENSHOT_HARD_MAX_DIMENSION)
	var max_height: int = clampi(int(request.get("max_height", SCREENSHOT_DEFAULT_MAX_HEIGHT)), 1, SCREENSHOT_HARD_MAX_DIMENSION)
	var cleanup_enabled: bool = _bool_value(request.get("cleanup", true), true)
	var retention_max_files: int = clampi(int(request.get("retention_max_files", SCREENSHOT_RETENTION_DEFAULT_MAX_FILES)), 1, SCREENSHOT_RETENTION_HARD_MAX_FILES)
	var retention_max_bytes: int = clampi(int(request.get("retention_max_bytes", SCREENSHOT_RETENTION_DEFAULT_MAX_BYTES)), 1048576, SCREENSHOT_RETENTION_HARD_MAX_BYTES)
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return _screenshot_error(request_id, "runtime viewport is not available")
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		return _screenshot_error(request_id, "runtime viewport texture is not available")
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return _screenshot_error(request_id, "runtime viewport image is empty")
	var original_width := image.get_width()
	var original_height := image.get_height()
	var resized := false
	if original_width > max_width or original_height > max_height:
		var scale := min(float(max_width) / float(original_width), float(max_height) / float(original_height))
		var target_width: int = max(1, int(floor(float(original_width) * scale)))
		var target_height: int = max(1, int(floor(float(original_height) * scale)))
		image.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
		resized = true
	var absolute_dir := ProjectSettings.globalize_path(SCREENSHOT_DIR)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_error != OK:
		return _screenshot_error(request_id, "screenshot directory could not be created: %s" % error_string(dir_error))
	var file_name := "%s.png" % _safe_file_id(request_id)
	var resource_path := "%s/%s" % [SCREENSHOT_DIR, file_name]
	var save_error := image.save_png(resource_path)
	if save_error != OK:
		return _screenshot_error(request_id, "screenshot save failed: %s" % error_string(save_error))
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	var cleanup_result: Dictionary = {
		"enabled": cleanup_enabled,
		"max_files": retention_max_files,
		"max_bytes": retention_max_bytes
	}
	if cleanup_enabled:
		cleanup_result = _cleanup_screenshot_dir(resource_path, retention_max_files, retention_max_bytes)
	return {
		"request_id": request_id,
		"ok": true,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"path": resource_path,
		"absolute_path": absolute_path,
		"width": image.get_width(),
		"height": image.get_height(),
		"original_width": original_width,
		"original_height": original_height,
		"resized": resized,
		"max_width": max_width,
		"max_height": max_height,
		"file_size": _file_size(resource_path),
		"cleanup": cleanup_result,
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name()
	}


func _runtime_input(request: Dictionary) -> Dictionary:
	var request_id: String = str(request.get("request_id", ""))
	var raw_events_value: Variant = request.get("events", [])
	if typeof(raw_events_value) != TYPE_ARRAY:
		return _input_error(request_id, "runtime input events must be an array")
	var raw_events: Array = raw_events_value
	if raw_events.is_empty():
		return _input_error(request_id, "runtime input requires at least one event")
	if raw_events.size() > INPUT_MAX_EVENTS:
		return _input_error(request_id, "runtime input event batch is too large")
	var applied_events: Array[Dictionary] = []
	var failures: Array[Dictionary] = []
	for index: int in range(raw_events.size()):
		var event_value: Variant = raw_events[index]
		if typeof(event_value) != TYPE_DICTIONARY:
			failures.append(_input_failure(index, "input event must be an object", {}))
			continue
		var event: Dictionary = event_value
		var result: Dictionary = _apply_input_event(event, index)
		if result.get("ok", false) == true:
			applied_events.append(result)
		else:
			failures.append(result)
	return {
		"request_id": request_id,
		"ok": failures.is_empty(),
		"message": "runtime input applied" if failures.is_empty() else "runtime input completed with failures",
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"event_count": raw_events.size(),
		"applied_count": applied_events.size(),
		"failure_count": failures.size(),
		"applied_events": applied_events,
		"failures": failures,
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name()
	}


func _runtime_inspect_node(request: Dictionary) -> Dictionary:
	var request_id: String = str(request.get("request_id", ""))
	var node_path: String = str(request.get("node_path", "")).strip_edges()
	if node_path == "":
		return _runtime_request_error(request_id, "node_path is required")
	var node: Node = _runtime_node_from_path(node_path)
	if node == null:
		return _runtime_request_error(request_id, "runtime node not found: %s" % node_path)
	var include_properties: bool = _bool_value(request.get("include_properties", true), true)
	var include_values: bool = _bool_value(request.get("include_values", true), true)
	var include_signals: bool = _bool_value(request.get("include_signals", true), true)
	var include_groups: bool = _bool_value(request.get("include_groups", true), true)
	var max_properties: int = clampi(int(request.get("max_properties", INSPECT_DEFAULT_MAX_PROPERTIES)), 1, INSPECT_MAX_PROPERTIES)
	var max_signals: int = clampi(int(request.get("max_signals", INSPECT_DEFAULT_MAX_SIGNALS)), 1, INSPECT_MAX_SIGNALS)
	var response: Dictionary = {
		"request_id": request_id,
		"ok": true,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name(),
		"node_path": str(node.get_path()),
		"node": _node_summary(node, include_groups),
		"include_properties": include_properties,
		"include_values": include_values,
		"include_signals": include_signals,
		"include_groups": include_groups,
		"max_properties": max_properties,
		"max_signals": max_signals
	}
	if include_properties:
		var properties: Array[Dictionary] = _runtime_property_snapshots(node, include_values, max_properties)
		response["properties"] = properties
		response["property_count"] = properties.size()
		response["properties_truncated"] = node.get_property_list().size() > properties.size()
	if include_signals:
		var signals: Array[Dictionary] = _runtime_signal_snapshots(node, max_signals)
		response["signals"] = signals
		response["signal_count"] = signals.size()
		response["signals_truncated"] = node.get_signal_list().size() > signals.size()
	if include_groups:
		response["groups"] = _runtime_node_groups(node)
	return response


func _runtime_state_snapshot(request: Dictionary) -> Dictionary:
	var request_id: String = str(request.get("request_id", ""))
	var include_node: bool = _bool_value(request.get("include_node", true), true)
	var max_value_depth: int = clampi(int(request.get("max_value_depth", STATE_DEFAULT_MAX_VALUE_DEPTH)), 1, STATE_MAX_VALUE_DEPTH)
	var max_collection_items: int = clampi(int(request.get("max_collection_items", STATE_DEFAULT_MAX_COLLECTION_ITEMS)), 1, STATE_MAX_COLLECTION_ITEMS)
	var global_properties: Array = _state_property_names(request.get("properties", []), STATE_MAX_PROPERTIES)
	var targets: Array = _state_request_targets(request, global_properties)
	var nodes: Array[Dictionary] = []
	var total_values := 0
	var first_values: Dictionary = {}
	var first_missing: Array = []
	for target_value: Variant in targets:
		if nodes.size() >= STATE_MAX_TARGETS:
			break
		var target: Dictionary = target_value
		var node_path: String = str(target.get("node_path", "")).strip_edges()
		if node_path == "":
			continue
		var node: Node = _runtime_node_from_path(node_path)
		var item: Dictionary = {
			"requested_path": node_path,
			"exists": node != null
		}
		if node == null:
			item["values"] = {}
			item["missing"] = _state_property_names(target.get("properties", []), STATE_MAX_PROPERTIES)
			nodes.append(item)
			continue
		item["path"] = str(node.get_path())
		if include_node:
			item["node"] = _node_summary(node, false)
		var properties: Array = _state_property_names(target.get("properties", []), STATE_MAX_PROPERTIES)
		if properties.is_empty():
			properties = global_properties.duplicate()
		if properties.is_empty():
			properties = _state_default_properties(node)
		var values: Dictionary = {}
		var missing: Array[String] = []
		for property_value: Variant in properties:
			var property_name: String = str(property_value).strip_edges()
			if property_name == "" or values.has(property_name):
				continue
			if _node_has_property(node, property_name):
				values[property_name] = _state_safe_value(node.get(property_name), max_value_depth, max_collection_items, 0)
			else:
				missing.append(property_name)
		item["properties"] = properties
		item["values"] = values
		item["value_count"] = values.size()
		if not missing.is_empty():
			item["missing"] = missing
		total_values += values.size()
		if nodes.is_empty():
			first_values = values.duplicate(true)
			first_missing = missing.duplicate()
		nodes.append(item)
	var response: Dictionary = {
		"request_id": request_id,
		"ok": true,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name(),
		"include_node": include_node,
		"max_value_depth": max_value_depth,
		"max_collection_items": max_collection_items,
		"target_count": targets.size(),
		"node_count": nodes.size(),
		"value_count": total_values,
		"nodes": nodes,
		"values": first_values
	}
	if not first_missing.is_empty():
		response["missing"] = first_missing
	if targets.size() > nodes.size():
		response["targets_truncated"] = true
	return response


func _runtime_find_ui(request: Dictionary) -> Dictionary:
	var request_id: String = str(request.get("request_id", ""))
	var text: String = str(request.get("text", request.get("query", ""))).strip_edges()
	if text == "":
		return _runtime_request_error(request_id, "text is required")
	var exact: bool = _bool_value(request.get("exact", false), false)
	var case_sensitive: bool = _bool_value(request.get("case_sensitive", false), false)
	var include_disabled: bool = _bool_value(request.get("include_disabled", true), true)
	var node_path: String = str(request.get("node_path", "")).strip_edges()
	var max_matches: int = clampi(int(request.get("max_matches", UI_FIND_DEFAULT_MAX_MATCHES)), 1, UI_FIND_MAX_MATCHES)
	var matches: Array[Dictionary] = _find_ui_matches(text, exact, case_sensitive, include_disabled, node_path, max_matches)
	return {
		"request_id": request_id,
		"ok": true,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name(),
		"text": text,
		"exact": exact,
		"case_sensitive": case_sensitive,
		"include_disabled": include_disabled,
		"node_path": node_path,
		"match_count": matches.size(),
		"max_matches": max_matches,
		"matches": matches,
		"truncated": matches.size() >= max_matches
	}


func _runtime_click_text(request: Dictionary) -> Dictionary:
	var request_id: String = str(request.get("request_id", ""))
	var text: String = str(request.get("text", request.get("query", ""))).strip_edges()
	if text == "":
		return _runtime_request_error(request_id, "text is required")
	var exact: bool = _bool_value(request.get("exact", false), false)
	var case_sensitive: bool = _bool_value(request.get("case_sensitive", false), false)
	var node_path: String = str(request.get("node_path", "")).strip_edges()
	var button_index: int = _mouse_button_index(request.get("button_index", request.get("button", MOUSE_BUTTON_LEFT)))
	var matches: Array[Dictionary] = _find_ui_matches(text, exact, case_sensitive, false, node_path, UI_FIND_MAX_MATCHES)
	var selected: Dictionary = {}
	for match_value: Dictionary in matches:
		if match_value.get("clickable", false) == true:
			selected = match_value
			break
	if selected.is_empty():
		return {
			"request_id": request_id,
			"ok": false,
			"captured_at": Time.get_datetime_string_from_system(false, true),
			"message": "no clickable UI text match found",
			"current_scene_path": _current_scene_path(),
			"current_scene_name": _current_scene_name(),
			"text": text,
			"exact": exact,
			"case_sensitive": case_sensitive,
			"node_path": node_path,
			"match_count": matches.size(),
			"matches": matches.slice(0, min(matches.size(), UI_FIND_DEFAULT_MAX_MATCHES))
		}
	var target: Node = _runtime_node_from_path(str(selected.get("path", "")))
	if target == null or not (target is Control):
		return _runtime_request_error(request_id, "selected UI match disappeared before click")
	var target_control: Control = target as Control
	var click_result: Dictionary = _click_control(target_control, button_index)
	return {
		"request_id": request_id,
		"ok": true,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name(),
		"text": text,
		"exact": exact,
		"case_sensitive": case_sensitive,
		"node_path": node_path,
		"match_count": matches.size(),
		"selected": selected,
		"click": click_result
	}


func _runtime_animation_state(request: Dictionary) -> Dictionary:
	var request_id: String = str(request.get("request_id", ""))
	var node_path: String = str(request.get("node_path", "")).strip_edges()
	if node_path == "":
		return _runtime_request_error(request_id, "node_path is required")
	var node: Node = _runtime_node_from_path(node_path)
	if node == null:
		return _runtime_request_error(request_id, "runtime node not found: %s" % node_path)
	var max_items: int = clampi(int(request.get("max_items", ANIMATION_DEFAULT_MAX_ITEMS)), 1, ANIMATION_MAX_ITEMS)
	var include_values: bool = _bool_value(request.get("include_values", true), true)
	var state: Dictionary = {}
	if node is AnimationPlayer:
		var player: AnimationPlayer = node as AnimationPlayer
		state = _animation_player_state(player, max_items)
	elif node is AnimationTree:
		var tree: AnimationTree = node as AnimationTree
		state = _animation_tree_state(tree, max_items, include_values)
	else:
		return _runtime_request_error(request_id, "node is not AnimationPlayer or AnimationTree: %s" % node.get_class())
	state["request_id"] = request_id
	state["ok"] = true
	state["captured_at"] = Time.get_datetime_string_from_system(false, true)
	state["current_scene_path"] = _current_scene_path()
	state["current_scene_name"] = _current_scene_name()
	return state


func _runtime_animation_control(request: Dictionary) -> Dictionary:
	var request_id: String = str(request.get("request_id", ""))
	var node_path: String = str(request.get("node_path", "")).strip_edges()
	var action: String = str(request.get("action", "")).strip_edges().to_lower()
	if node_path == "":
		return _runtime_request_error(request_id, "node_path is required")
	if action == "":
		return _runtime_request_error(request_id, "action is required")
	var node: Node = _runtime_node_from_path(node_path)
	if node == null:
		return _runtime_request_error(request_id, "runtime node not found: %s" % node_path)
	var max_items: int = clampi(int(request.get("max_items", ANIMATION_DEFAULT_MAX_ITEMS)), 1, ANIMATION_MAX_ITEMS)
	var result: Dictionary = {}
	if node is AnimationPlayer:
		var player: AnimationPlayer = node as AnimationPlayer
		result = _animation_player_control(player, request, action, max_items)
	elif node is AnimationTree:
		var tree: AnimationTree = node as AnimationTree
		result = _animation_tree_control(tree, request, action, max_items)
	else:
		return _runtime_request_error(request_id, "node is not AnimationPlayer or AnimationTree: %s" % node.get_class())
	result["request_id"] = request_id
	result["captured_at"] = Time.get_datetime_string_from_system(false, true)
	result["current_scene_path"] = _current_scene_path()
	result["current_scene_name"] = _current_scene_name()
	return result


func _animation_player_state(player: AnimationPlayer, max_items: int) -> Dictionary:
	var animations: Array[Dictionary] = []
	var raw_names: PackedStringArray = player.get_animation_list()
	for animation_name: String in raw_names:
		if animations.size() >= max_items:
			break
		var clip: Animation = player.get_animation(StringName(animation_name))
		var item: Dictionary = {"name": animation_name}
		if clip != null:
			item["length"] = clip.length
			item["loop_mode"] = int(clip.loop_mode)
			item["track_count"] = clip.get_track_count()
		animations.append(item)
	var queued: Array[String] = []
	if player.has_method("get_queue"):
		var queue_value: Variant = player.call("get_queue")
		if typeof(queue_value) == TYPE_PACKED_STRING_ARRAY or typeof(queue_value) == TYPE_ARRAY:
			for queued_value: Variant in queue_value:
				queued.append(str(queued_value))
	var current_animation_name: String = str(player.current_animation)
	var current_position := 0.0
	var current_length := 0.0
	if current_animation_name != "" and player.has_animation(StringName(current_animation_name)):
		current_position = player.current_animation_position
		var current_clip: Animation = player.get_animation(StringName(current_animation_name))
		if current_clip != null:
			current_length = current_clip.length
	return {
		"node_path": str(player.get_path()),
		"node_type": player.get_class(),
		"kind": "AnimationPlayer",
		"animation_count": raw_names.size(),
		"animations": animations,
		"animations_truncated": raw_names.size() > animations.size(),
		"current_animation": current_animation_name,
		"assigned_animation": str(player.assigned_animation),
		"autoplay": str(player.autoplay),
		"is_playing": player.is_playing(),
		"current_position": current_position,
		"current_length": current_length,
		"speed_scale": player.speed_scale,
		"playback_active": player.playback_active,
		"root_node": str(player.root_node),
		"queued": queued
	}


func _animation_tree_state(tree: AnimationTree, max_items: int, include_values: bool) -> Dictionary:
	var parameter_items: Array[Dictionary] = []
	var raw_parameter_count := 0
	for property_value: Variant in tree.get_property_list():
		var property_info: Dictionary = property_value
		var property_name: String = str(property_info.get("name", ""))
		if not property_name.begins_with("parameters/"):
			continue
		raw_parameter_count += 1
		if parameter_items.size() >= max_items:
			continue
		var item: Dictionary = {
			"name": property_name,
			"type": int(property_info.get("type", TYPE_NIL)),
			"type_name": type_string(int(property_info.get("type", TYPE_NIL))),
			"hint": int(property_info.get("hint", 0)),
			"hint_string": str(property_info.get("hint_string", ""))
		}
		if include_values:
			item["value"] = _safe_check_value(tree.get(property_name))
		parameter_items.append(item)
	var root_info: Dictionary = {}
	var tree_root_value: Variant = tree.tree_root
	if tree_root_value is Resource:
		var root_resource: Resource = tree_root_value as Resource
		root_info = {
			"type": root_resource.get_class(),
			"resource_path": root_resource.resource_path
		}
	var playback_info: Dictionary = _animation_tree_playback_state(tree, "parameters/playback")
	return {
		"node_path": str(tree.get_path()),
		"node_type": tree.get_class(),
		"kind": "AnimationTree",
		"active": tree.active,
		"anim_player": str(tree.anim_player),
		"tree_root": root_info,
		"playback": playback_info,
		"parameter_count": raw_parameter_count,
		"parameters": parameter_items,
		"parameters_truncated": raw_parameter_count > parameter_items.size()
	}


func _animation_tree_playback_state(tree: AnimationTree, playback_path: String) -> Dictionary:
	if not _node_has_property(tree, playback_path):
		return {"available": false, "path": playback_path}
	var playback_value: Variant = tree.get(playback_path)
	var playback_object: Object = playback_value as Object
	if playback_object == null:
		return {"available": false, "path": playback_path}
	var info: Dictionary = {
		"available": true,
		"path": playback_path,
		"type": playback_object.get_class()
	}
	if playback_object.has_method("get_current_node"):
		info["current_node"] = str(playback_object.call("get_current_node"))
	if playback_object.has_method("get_travel_path"):
		info["travel_path"] = _safe_check_value(playback_object.call("get_travel_path"))
	return info


func _animation_player_control(player: AnimationPlayer, request: Dictionary, action: String, max_items: int) -> Dictionary:
	match action:
		"play":
			var animation_name: String = str(request.get("animation", request.get("animation_name", ""))).strip_edges()
			if animation_name != "" and not player.has_animation(StringName(animation_name)):
				return _animation_control_error(player, action, "animation not found: %s" % animation_name)
			var custom_blend: float = float(request.get("custom_blend", -1.0))
			var custom_speed: float = float(request.get("custom_speed", 1.0))
			var from_end: bool = _bool_value(request.get("from_end", false), false)
			if animation_name == "":
				player.play()
			else:
				player.play(StringName(animation_name), custom_blend, custom_speed, from_end)
		"stop":
			player.stop(_bool_value(request.get("keep_state", false), false))
		"pause":
			if player.has_method("pause"):
				player.call("pause")
			else:
				player.playback_active = false
		"seek":
			var position: float = float(request.get("time", request.get("position", 0.0)))
			var update: bool = _bool_value(request.get("update", true), true)
			var update_only: bool = _bool_value(request.get("update_only", false), false)
			player.seek(position, update, update_only)
		"set_speed":
			var speed_scale: float = float(request.get("speed", request.get("speed_scale", 1.0)))
			player.speed_scale = speed_scale
		_:
			return _animation_control_error(player, action, "action is not supported for AnimationPlayer")
	var state: Dictionary = _animation_player_state(player, max_items)
	state["ok"] = true
	state["action"] = action
	state["message"] = "runtime animation player action applied"
	return state


func _animation_tree_control(tree: AnimationTree, request: Dictionary, action: String, max_items: int) -> Dictionary:
	match action:
		"tree_active":
			tree.active = _bool_value(request.get("active", true), true)
		"tree_travel":
			var state_name: String = str(request.get("state", request.get("target", request.get("state_name", "")))).strip_edges()
			if state_name == "":
				return _animation_control_error(tree, action, "state is required")
			var playback_path: String = str(request.get("playback_path", "parameters/playback")).strip_edges()
			var playback_value: Variant = tree.get(playback_path)
			var playback_object: Object = playback_value as Object
			if playback_object == null or not playback_object.has_method("travel"):
				return _animation_control_error(tree, action, "AnimationTree playback does not expose travel at %s" % playback_path)
			playback_object.call("travel", state_name)
		"tree_set_parameter":
			var parameter_path: String = _animation_tree_parameter_path(str(request.get("parameter", request.get("property", ""))))
			if parameter_path == "":
				return _animation_control_error(tree, action, "parameter is required")
			if not request.has("value"):
				return _animation_control_error(tree, action, "value is required")
			if not _node_has_property(tree, parameter_path):
				return _animation_control_error(tree, action, "AnimationTree parameter not found: %s" % parameter_path)
			tree.set(parameter_path, _animation_control_value(request.get("value")))
		_:
			return _animation_control_error(tree, action, "action is not supported for AnimationTree")
	var include_values: bool = _bool_value(request.get("include_values", true), true)
	var state: Dictionary = _animation_tree_state(tree, max_items, include_values)
	state["ok"] = true
	state["action"] = action
	state["message"] = "runtime animation tree action applied"
	return state


func _animation_tree_parameter_path(parameter: String) -> String:
	var normalized: String = parameter.strip_edges()
	if normalized == "":
		return ""
	if normalized.begins_with("parameters/"):
		return normalized
	return "parameters/%s" % normalized


func _animation_control_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var value_dictionary: Dictionary = value
		var type_name: String = str(value_dictionary.get("type", "")).strip_edges().to_lower()
		if type_name == "vector2" or (value_dictionary.has("x") and value_dictionary.has("y") and not value_dictionary.has("z")):
			return Vector2(float(value_dictionary.get("x", 0.0)), float(value_dictionary.get("y", 0.0)))
		if type_name == "vector3" or (value_dictionary.has("x") and value_dictionary.has("y") and value_dictionary.has("z")):
			return Vector3(float(value_dictionary.get("x", 0.0)), float(value_dictionary.get("y", 0.0)), float(value_dictionary.get("z", 0.0)))
	return value


func _animation_control_error(node: Node, action: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"action": action,
		"message": message,
		"node_path": str(node.get_path()),
		"node_type": node.get_class()
	}


func _apply_input_event(event: Dictionary, index: int) -> Dictionary:
	var event_type := str(event.get("type", "")).strip_edges().to_lower()
	match event_type:
		"click_node":
			return _apply_click_node(event, index)
		"mouse_button":
			return _apply_mouse_button(event, index)
		"mouse_click":
			return _apply_mouse_click(event, index)
		"mouse_motion":
			return _apply_mouse_motion(event, index)
		"key":
			return _apply_key_event(event, index)
		"action":
			return _apply_action_event(event, index)
	return _input_failure(index, "unsupported input event type: %s" % event_type, event)


func _apply_click_node(event: Dictionary, index: int) -> Dictionary:
	var node_path := str(event.get("node_path", "")).strip_edges()
	if node_path == "":
		return _input_failure(index, "click_node requires node_path", event)
	var node: Node = _runtime_node_from_path(node_path)
	if node == null:
		return _input_failure(index, "node not found: %s" % node_path, event)
	var button_index: int = _mouse_button_index(event.get("button_index", event.get("button", MOUSE_BUTTON_LEFT)))
	if node is Node3D:
		var node3d: Node3D = node as Node3D
		var click3d_result: Dictionary = _click_node3d(node3d, button_index)
		if click3d_result.get("ok", false) != true:
			return _input_failure(index, str(click3d_result.get("message", "click_node 3D target could not be clicked")), event)
		click3d_result["index"] = index
		click3d_result["type"] = "click_node"
		return click3d_result
	if not (node is Control):
		return _input_failure(index, "click_node target must be a Control or Node3D node", event)
	var control: Control = node as Control
	var click_result: Dictionary = _click_control(control, button_index)
	click_result["ok"] = true
	click_result["index"] = index
	click_result["type"] = "click_node"
	return click_result


func _click_control(control: Control, button_index: int) -> Dictionary:
	var rect: Rect2 = control.get_global_rect()
	var position: Vector2 = rect.position + (rect.size * 0.5)
	_send_mouse_motion(position, Vector2.ZERO)
	_send_mouse_button(position, button_index, true)
	_send_mouse_button(position, button_index, false)
	return {
		"node_path": str(control.get_path()),
		"position": _vector2_value(position),
		"button_index": button_index
	}


func _click_node3d(node: Node3D, button_index: int) -> Dictionary:
	var viewport := get_viewport()
	if viewport == null:
		return {"ok": false, "message": "runtime viewport is not available"}
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return {"ok": false, "message": "active Camera3D is not available"}
	var world_position: Vector3 = node.global_position
	if camera.is_position_behind(world_position):
		return {"ok": false, "message": "Node3D target is behind the active Camera3D"}
	var position: Vector2 = camera.unproject_position(world_position)
	var visible_rect: Rect2 = viewport.get_visible_rect()
	if not visible_rect.has_point(position):
		return {"ok": false, "message": "projected Node3D target is outside the runtime viewport"}
	_send_mouse_motion(position, Vector2.ZERO)
	_send_mouse_button(position, button_index, true)
	_send_mouse_button(position, button_index, false)
	return {
		"ok": true,
		"node_path": str(node.get_path()),
		"node_type": node.get_class(),
		"position": _vector2_value(position),
		"world_position": _vector3_value(world_position),
		"button_index": button_index,
		"projection": "active_camera_unproject"
	}


func _apply_mouse_click(event: Dictionary, index: int) -> Dictionary:
	var position: Vector2 = _event_position(event)
	var button_index: int = _mouse_button_index(event.get("button_index", event.get("button", MOUSE_BUTTON_LEFT)))
	_send_mouse_motion(position, Vector2.ZERO)
	_send_mouse_button(position, button_index, true)
	_send_mouse_button(position, button_index, false)
	return {
		"ok": true,
		"index": index,
		"type": "mouse_click",
		"position": _vector2_value(position),
		"button_index": button_index
	}


func _apply_mouse_button(event: Dictionary, index: int) -> Dictionary:
	var position: Vector2 = _event_position(event)
	var button_index: int = _mouse_button_index(event.get("button_index", event.get("button", MOUSE_BUTTON_LEFT)))
	var pressed: bool = _bool_value(event.get("pressed", true), true)
	_send_mouse_button(position, button_index, pressed)
	return {
		"ok": true,
		"index": index,
		"type": "mouse_button",
		"position": _vector2_value(position),
		"button_index": button_index,
		"pressed": pressed
	}


func _apply_mouse_motion(event: Dictionary, index: int) -> Dictionary:
	var position: Vector2 = _event_position(event)
	var relative := Vector2(float(event.get("relative_x", 0.0)), float(event.get("relative_y", 0.0)))
	_send_mouse_motion(position, relative)
	return {
		"ok": true,
		"index": index,
		"type": "mouse_motion",
		"position": _vector2_value(position),
		"relative": _vector2_value(relative)
	}


func _apply_key_event(event: Dictionary, index: int) -> Dictionary:
	var keycode: int = _keycode_from_value(event.get("keycode", event.get("key", 0)))
	if keycode <= 0:
		return _input_failure(index, "key event requires key or keycode", event)
	var pressed: bool = _bool_value(event.get("pressed", true), true)
	var input_event := InputEventKey.new()
	input_event.keycode = keycode
	input_event.physical_keycode = keycode
	input_event.pressed = pressed
	input_event.echo = _bool_value(event.get("echo", false), false)
	Input.parse_input_event(input_event)
	return {
		"ok": true,
		"index": index,
		"type": "key",
		"keycode": keycode,
		"pressed": pressed
	}


func _apply_action_event(event: Dictionary, index: int) -> Dictionary:
	var action := str(event.get("action", "")).strip_edges()
	if action == "":
		return _input_failure(index, "action event requires action", event)
	var pressed: bool = _bool_value(event.get("pressed", true), true)
	var strength := float(event.get("strength", 1.0))
	var input_event := InputEventAction.new()
	input_event.action = action
	input_event.pressed = pressed
	input_event.strength = strength
	Input.parse_input_event(input_event)
	return {
		"ok": true,
		"index": index,
		"type": "action",
		"action": action,
		"pressed": pressed,
		"strength": strength
	}


func _send_mouse_motion(position: Vector2, relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	motion.relative = relative
	Input.parse_input_event(motion)


func _send_mouse_button(position: Vector2, button_index: int, pressed: bool) -> void:
	var button := InputEventMouseButton.new()
	button.position = position
	button.global_position = position
	button.button_index = button_index
	button.pressed = pressed
	Input.parse_input_event(button)


func _runtime_node_from_path(node_path: String) -> Node:
	if node_path == "":
		return null
	if node_path.begins_with("/"):
		return get_node_or_null(NodePath(node_path))
	var root: Window = get_tree().root
	var from_root: Node = root.get_node_or_null(NodePath(node_path))
	if from_root != null:
		return from_root
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return null
	if node_path == str(current_scene.name):
		return current_scene
	var prefix := "%s/" % str(current_scene.name)
	if node_path.begins_with(prefix):
		return root.get_node_or_null(NodePath(node_path))
	return current_scene.get_node_or_null(NodePath(node_path))


func _event_position(event: Dictionary) -> Vector2:
	return Vector2(float(event.get("x", event.get("position_x", 0.0))), float(event.get("y", event.get("position_y", 0.0))))


func _mouse_button_index(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return max(1, int(value))
	var text := str(value).strip_edges().to_lower()
	match text:
		"left":
			return MOUSE_BUTTON_LEFT
		"right":
			return MOUSE_BUTTON_RIGHT
		"middle":
			return MOUSE_BUTTON_MIDDLE
	return MOUSE_BUTTON_LEFT


func _keycode_from_value(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	var text := str(value).strip_edges().to_lower()
	match text:
		"space":
			return KEY_SPACE
		"enter", "return":
			return KEY_ENTER
		"escape", "esc":
			return KEY_ESCAPE
		"tab":
			return KEY_TAB
		"left":
			return KEY_LEFT
		"right":
			return KEY_RIGHT
		"up":
			return KEY_UP
		"down":
			return KEY_DOWN
		"backspace":
			return KEY_BACKSPACE
	if text.length() == 1:
		return text.unicode_at(0)
	return 0


func _input_error(request_id: String, message: String) -> Dictionary:
	return {
		"request_id": request_id,
		"ok": false,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"message": message,
		"event_count": 0,
		"applied_count": 0,
		"failure_count": 1,
		"applied_events": [],
		"failures": [_input_failure(-1, message, {})],
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name()
	}


func _input_failure(index: int, message: String, event: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"index": index,
		"message": message,
		"type": str(event.get("type", "")),
		"node_path": str(event.get("node_path", ""))
	}


func _service_pending_checks() -> void:
	if _pending_checks.is_empty():
		return
	var now_msec: int = Time.get_ticks_msec()
	var completed: Array[String] = []
	for request_id_value: Variant in _pending_checks.keys():
		var request_id: String = str(request_id_value)
		var pending: Dictionary = _pending_checks.get(request_id, {})
		if now_msec < int(pending.get("next_poll_msec", 0)) and now_msec < int(pending.get("deadline_msec", 0)):
			continue
		var request: Dictionary = pending.get("request", {})
		var attempts: int = int(pending.get("attempts", 1)) + 1
		pending["attempts"] = attempts
		var result: Dictionary = _runtime_check_result(request)
		pending["last_result"] = result
		var timed_out: bool = now_msec >= int(pending.get("deadline_msec", 0))
		if result.get("matched", false) == true or result.get("terminal", false) == true or timed_out:
			var response_message: String = str(pending.get("response_message", "wait_response"))
			var mode: String = str(pending.get("mode", "wait"))
			var started_msec: int = int(pending.get("started_msec", now_msec))
			_send_check_response(response_message, _final_check_response(request, result, mode, attempts, started_msec, timed_out))
			completed.append(request_id)
			continue
		var poll_interval_msec: int = int(pending.get("poll_interval_msec", CHECK_DEFAULT_POLL_INTERVAL_MSEC))
		pending["next_poll_msec"] = now_msec + poll_interval_msec
		_pending_checks[request_id] = pending
	for request_id: String in completed:
		_pending_checks.erase(request_id)


func _service_pending_watches() -> void:
	if _pending_watches.is_empty():
		return
	var now_msec: int = Time.get_ticks_msec()
	var completed: Array[String] = []
	for request_id_value: Variant in _pending_watches.keys():
		var request_id: String = str(request_id_value)
		var pending: Dictionary = _pending_watches.get(request_id, {})
		var deadline_msec: int = int(pending.get("deadline_msec", now_msec))
		var next_sample_msec: int = int(pending.get("next_sample_msec", now_msec))
		if now_msec >= next_sample_msec and now_msec < deadline_msec:
			_append_watch_sample(pending, now_msec, "sample")
			pending["next_sample_msec"] = now_msec + int(pending.get("interval_msec", WATCH_DEFAULT_INTERVAL_MSEC))
			_pending_watches[request_id] = pending
			continue
		if now_msec >= deadline_msec:
			var request: Dictionary = pending.get("request", {})
			if _bool_value(request.get("include_final", true), true):
				_append_watch_sample(pending, now_msec, "final")
			EngineDebugger.send_message("%s:watch_response" % MESSAGE_PREFIX, [JSON.stringify(_final_watch_response(pending, now_msec))])
			completed.append(request_id)
	for request_id: String in completed:
		_pending_watches.erase(request_id)


func _append_watch_sample(pending: Dictionary, now_msec: int, phase: String) -> void:
	var request: Dictionary = pending.get("request", {})
	var started_msec: int = int(pending.get("started_msec", now_msec))
	var sample_index: int = int(pending.get("sample_index", 0))
	var sample: Dictionary = _watch_sample(request, now_msec, started_msec, sample_index, phase)
	var samples: Array = pending.get("samples", [])
	samples.append(sample)
	pending["samples"] = samples
	pending["sample_index"] = sample_index + 1
	_collect_watch_property_events(pending, sample)


func _final_watch_response(pending: Dictionary, now_msec: int) -> Dictionary:
	var request: Dictionary = pending.get("request", {})
	var samples: Array = pending.get("samples", [])
	var events: Array = pending.get("events", [])
	var started_msec: int = int(pending.get("started_msec", now_msec))
	return {
		"request_id": str(request.get("request_id", "")),
		"ok": true,
		"schema_version": "gaw.runtime_watch.v0",
		"mode": str(request.get("mode", "watch")),
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"elapsed_msec": max(0, now_msec - started_msec),
		"duration_msec": int(request.get("duration_msec", WATCH_DEFAULT_DURATION_MSEC)),
		"interval_msec": int(request.get("interval_msec", WATCH_DEFAULT_INTERVAL_MSEC)),
		"sample_count": samples.size(),
		"event_count": events.size(),
		"target_count": _watch_request_targets(request).size(),
		"samples": samples,
		"events": events,
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name()
	}


func _watch_sample(request: Dictionary, now_msec: int, started_msec: int, sample_index: int, phase: String) -> Dictionary:
	var targets: Array = _watch_request_targets(request)
	var target_results: Array[Dictionary] = []
	var missing_targets: Array[String] = []
	for target_request_value: Variant in targets:
		if target_results.size() >= WATCH_MAX_TARGETS:
			break
		var target_request: Dictionary = target_request_value
		var requested_path: String = str(target_request.get("node_path", "")).strip_edges()
		var node: Node = _runtime_node_from_path(requested_path)
		var target_result: Dictionary = {
			"requested_path": requested_path,
			"exists": node != null
		}
		if node == null:
			missing_targets.append(requested_path)
			target_results.append(target_result)
			continue
		target_result["node"] = _node_summary(node, _bool_value(target_request.get("include_groups", false), false))
		target_result["node_path"] = str(node.get_path())
		if _bool_value(request.get("include_properties", true), true):
			var property_names: Array = target_request.get("properties", [])
			if property_names.is_empty():
				property_names = request.get("properties", [])
			if property_names.is_empty():
				property_names = _watch_default_properties(node)
			target_result["properties"] = _watch_property_values(node, property_names)
		if _bool_value(request.get("include_signals", true), true) and _bool_value(target_request.get("include_signals", true), true):
			target_result["signals"] = _watch_signal_snapshots(node)
		target_results.append(target_result)
	return {
		"index": sample_index,
		"phase": phase,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"elapsed_msec": max(0, now_msec - started_msec),
		"targets": target_results,
		"missing_targets": missing_targets
	}


func _watch_request_targets(request: Dictionary) -> Array:
	var targets: Array = []
	var raw_targets: Array = []
	if typeof(request.get("targets", [])) == TYPE_ARRAY:
		raw_targets = request.get("targets", [])
	for target_value: Variant in raw_targets:
		if typeof(target_value) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = target_value
		var node_path: String = str(source.get("node_path", source.get("path", ""))).strip_edges()
		if node_path == "":
			continue
		targets.append({
			"node_path": node_path,
			"properties": _watch_property_names(source.get("properties", [])),
			"include_signals": _bool_value(source.get("include_signals", true), true),
			"include_groups": _bool_value(source.get("include_groups", false), false)
		})
	if targets.is_empty():
		var current_scene: Node = get_tree().current_scene
		if current_scene != null:
			targets.append({
				"node_path": str(current_scene.get_path()),
				"properties": _watch_property_names(request.get("properties", [])),
				"include_signals": _bool_value(request.get("include_signals", true), true),
				"include_groups": false
			})
	return targets


func _watch_property_names(value: Variant) -> Array:
	var result: Array = []
	var raw: Array = []
	if typeof(value) == TYPE_ARRAY:
		raw = value
	elif typeof(value) == TYPE_STRING:
		raw = [value]
	for property_value: Variant in raw:
		var property_name := str(property_value).strip_edges()
		if property_name == "" or result.has(property_name):
			continue
		result.append(property_name)
		if result.size() >= WATCH_MAX_PROPERTIES:
			break
	return result


func _state_request_targets(request: Dictionary, global_properties: Array) -> Array:
	var targets: Array = []
	var raw_targets: Array = []
	if typeof(request.get("targets", [])) == TYPE_ARRAY:
		raw_targets = request.get("targets", [])
	for target_value: Variant in raw_targets:
		if targets.size() >= STATE_MAX_TARGETS:
			break
		if typeof(target_value) == TYPE_DICTIONARY:
			var source: Dictionary = target_value
			var node_path: String = str(source.get("node_path", source.get("path", ""))).strip_edges()
			if node_path == "":
				continue
			var properties: Array = _state_property_names(source.get("properties", []), STATE_MAX_PROPERTIES)
			if properties.is_empty():
				properties = global_properties.duplicate()
			targets.append({
				"node_path": node_path,
				"properties": properties
			})
		else:
			var path_value: String = str(target_value).strip_edges()
			if path_value != "":
				targets.append({
					"node_path": path_value,
					"properties": global_properties.duplicate()
				})
	if targets.is_empty():
		var node_path: String = str(request.get("node_path", request.get("path", ""))).strip_edges()
		if node_path != "":
			targets.append({
				"node_path": node_path,
				"properties": global_properties.duplicate()
			})
	if targets.is_empty():
		var current_scene: Node = get_tree().current_scene
		if current_scene != null:
			targets.append({
				"node_path": str(current_scene.get_path()),
				"properties": global_properties.duplicate()
			})
	return targets


func _state_property_names(value: Variant, limit: int) -> Array:
	var result: Array = []
	var raw: Array = []
	if typeof(value) == TYPE_ARRAY:
		raw = value
	elif typeof(value) == TYPE_STRING:
		raw = [value]
	for property_value: Variant in raw:
		var property_name := str(property_value).strip_edges()
		if property_name == "" or result.has(property_name):
			continue
		result.append(property_name)
		if result.size() >= limit:
			break
	return result


func _state_default_properties(node: Node) -> Array:
	var candidates: Array = [
		"state",
		"game_state",
		"board_state",
		"score",
		"left_score",
		"right_score",
		"current_turn",
		"turn",
		"selected_cell",
		"selected_piece",
		"winner",
		"visible",
		"position",
		"global_position",
		"rotation_degrees",
		"scale",
		"size",
		"text",
		"disabled",
		"value",
		"pressed"
	]
	var result: Array = []
	for property_name: String in candidates:
		if _node_has_property(node, property_name):
			result.append(property_name)
			if result.size() >= STATE_MAX_PROPERTIES:
				break
	return result


func _state_safe_value(value: Variant, max_depth: int, max_items: int, depth: int) -> Variant:
	if depth >= max_depth:
		return {
			"truncated": true,
			"reason": "max_depth",
			"type": type_string(typeof(value))
		}
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return value
		TYPE_STRING:
			var text := str(value)
			if text.length() > MAX_TEXT_LENGTH:
				return {
					"text": text.substr(0, MAX_TEXT_LENGTH),
					"truncated": true,
					"length": text.length()
				}
			return text
		TYPE_VECTOR2:
			var vector_2: Vector2 = value
			return _vector2_value(vector_2)
		TYPE_VECTOR3:
			var vector_3: Vector3 = value
			return _vector3_value(vector_3)
		TYPE_VECTOR4:
			var vector_4: Vector4 = value
			return {"x": vector_4.x, "y": vector_4.y, "z": vector_4.z, "w": vector_4.w}
		TYPE_COLOR:
			var color: Color = value
			return {"r": color.r, "g": color.g, "b": color.b, "a": color.a}
		TYPE_ARRAY:
			var source_array: Array = value
			var output_array: Array = []
			var count := 0
			for item: Variant in source_array:
				if count >= max_items:
					break
				output_array.append(_state_safe_value(item, max_depth, max_items, depth + 1))
				count += 1
			if source_array.size() > output_array.size():
				return {
					"items": output_array,
					"truncated": true,
					"count": source_array.size(),
					"returned": output_array.size()
				}
			return output_array
		TYPE_DICTIONARY:
			var source_dictionary: Dictionary = value
			var output_dictionary: Dictionary = {}
			var keys: Array = source_dictionary.keys()
			var count := 0
			for key: Variant in keys:
				if count >= max_items:
					break
				output_dictionary[str(key)] = _state_safe_value(source_dictionary[key], max_depth, max_items, depth + 1)
				count += 1
			if keys.size() > output_dictionary.size():
				output_dictionary["_truncated"] = true
				output_dictionary["_count"] = keys.size()
				output_dictionary["_returned"] = count
			return output_dictionary
	return str(value)


func _watch_default_properties(node: Node) -> Array:
	var candidates: Array = ["visible", "position", "global_position", "rotation", "rotation_degrees", "scale", "size", "text", "disabled", "value", "pressed"]
	var result: Array = []
	for property_name: String in candidates:
		if _node_has_property(node, property_name):
			result.append(property_name)
	return result


func _watch_property_values(node: Node, property_names: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for property_value: Variant in property_names:
		if result.size() >= WATCH_MAX_PROPERTIES:
			break
		var property_name := str(property_value).strip_edges()
		if property_name == "":
			continue
		var exists: bool = _node_has_property(node, property_name)
		var item: Dictionary = {
			"name": property_name,
			"exists": exists
		}
		if exists:
			item["value"] = _safe_check_value(node.get(property_name))
		result.append(item)
	return result


func _watch_signal_snapshots(node: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for signal_value: Variant in node.get_signal_list():
		if result.size() >= WATCH_MAX_SIGNALS:
			break
		var signal_info: Dictionary = signal_value
		var signal_name: String = str(signal_info.get("name", ""))
		if signal_name == "":
			continue
		var connections: Array[Dictionary] = []
		for connection_value: Variant in node.get_signal_connection_list(StringName(signal_name)):
			if connections.size() >= WATCH_MAX_CONNECTIONS_PER_SIGNAL:
				break
			if typeof(connection_value) != TYPE_DICTIONARY:
				continue
			var connection: Dictionary = connection_value
			var callable_value: Variant = connection.get("callable", Callable())
			var method_name := ""
			var target_path := ""
			if typeof(callable_value) == TYPE_CALLABLE:
				var callback: Callable = callable_value
				method_name = callback.get_method()
				var target_object: Object = callback.get_object()
				if target_object is Node:
					var target_node: Node = target_object as Node
					target_path = str(target_node.get_path())
			connections.append({
				"target_path": target_path,
				"method": method_name,
				"flags": int(connection.get("flags", 0))
			})
		result.append({
			"name": signal_name,
			"connection_count": connections.size(),
			"connections": connections
		})
	return result


func _collect_watch_property_events(pending: Dictionary, sample: Dictionary) -> void:
	var events: Array = pending.get("events", [])
	var last_values: Dictionary = pending.get("last_values", {})
	var request: Dictionary = pending.get("request", {})
	var max_events: int = clampi(int(request.get("max_events", WATCH_DEFAULT_MAX_EVENTS)), 1, WATCH_MAX_EVENTS)
	for target_value: Variant in sample.get("targets", []):
		if typeof(target_value) != TYPE_DICTIONARY:
			continue
		var target: Dictionary = target_value
		var node_path := str(target.get("node_path", target.get("requested_path", "")))
		for property_value: Variant in target.get("properties", []):
			if typeof(property_value) != TYPE_DICTIONARY:
				continue
			var property: Dictionary = property_value
			if property.get("exists", false) != true:
				continue
			var property_name := str(property.get("name", ""))
			var key := "%s::%s" % [node_path, property_name]
			var next_value: Variant = property.get("value")
			if last_values.has(key) and not _watch_values_equal(last_values.get(key), next_value):
				if events.size() < max_events:
					events.append({
						"kind": "property_changed",
						"node_path": node_path,
						"property": property_name,
						"old_value": last_values.get(key),
						"new_value": next_value,
						"sample_index": int(sample.get("index", 0)),
						"elapsed_msec": int(sample.get("elapsed_msec", 0))
					})
			last_values[key] = next_value
	pending["events"] = events
	pending["last_values"] = last_values


func _watch_values_equal(left: Variant, right: Variant) -> bool:
	return JSON.stringify(left) == JSON.stringify(right)


func _send_check_response(response_message: String, response: Dictionary) -> void:
	EngineDebugger.send_message("%s:%s" % [MESSAGE_PREFIX, response_message], [JSON.stringify(response)])


func _final_check_response(request: Dictionary, result: Dictionary, mode: String, attempts: int, started_msec: int, timed_out: bool) -> Dictionary:
	var response: Dictionary = result.duplicate(true)
	var elapsed_msec: int = max(0, Time.get_ticks_msec() - started_msec)
	var matched: bool = response.get("matched", false) == true
	response["request_id"] = str(request.get("request_id", ""))
	response["ok"] = matched
	response["mode"] = mode
	response["attempts"] = attempts
	response["elapsed_msec"] = elapsed_msec
	response["timeout_msec"] = int(request.get("timeout_msec", CHECK_DEFAULT_TIMEOUT_MSEC))
	response["timed_out"] = timed_out and not matched
	if matched:
		response["message"] = "runtime %s matched" % mode
	elif response.get("message", "") == "":
		if mode == "assert":
			response["message"] = "runtime assertion failed"
		else:
			response["message"] = "runtime wait timed out"
	return response


func _runtime_check_result(request: Dictionary) -> Dictionary:
	var request_id: String = str(request.get("request_id", ""))
	var condition: String = str(request.get("condition", request.get("assertion", "node_exists"))).strip_edges().to_lower()
	var node_path: String = str(request.get("node_path", "")).strip_edges()
	var result: Dictionary = {
		"request_id": request_id,
		"ok": false,
		"matched": false,
		"terminal": false,
		"condition": condition,
		"node_path": node_path,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name()
	}
	match condition:
		"node_exists":
			return _check_node_exists(result, node_path, true)
		"node_missing":
			return _check_node_exists(result, node_path, false)
		"node_visible":
			return _check_node_visibility(result, node_path, true)
		"node_hidden":
			return _check_node_visibility(result, node_path, false)
		"text_contains", "text_equals", "text_missing":
			return _check_text_condition(result, request, condition, node_path)
		"property_exists", "property_missing", "property_equals", "property_not_equals", "property_contains", "property_gt", "property_gte", "property_lt", "property_lte":
			return _check_property_condition(result, request, node_path, condition)
	result["terminal"] = true
	result["message"] = "unsupported runtime check condition: %s" % condition
	return result


func _check_node_exists(result: Dictionary, node_path: String, should_exist: bool) -> Dictionary:
	if node_path == "":
		result["terminal"] = true
		result["message"] = "node_path is required"
		return result
	var node: Node = _runtime_node_from_path(node_path)
	var exists: bool = node != null
	result["exists"] = exists
	result["matched"] = exists == should_exist
	if node != null:
		result["node"] = _node_summary(node, false)
	return result


func _check_node_visibility(result: Dictionary, node_path: String, should_be_visible: bool) -> Dictionary:
	if node_path == "":
		result["terminal"] = true
		result["message"] = "node_path is required"
		return result
	var node: Node = _runtime_node_from_path(node_path)
	if node == null:
		result["exists"] = false
		return result
	result["exists"] = true
	result["node"] = _node_summary(node, false)
	var visible := false
	if node is CanvasItem:
		var canvas_item: CanvasItem = node as CanvasItem
		visible = canvas_item.is_visible_in_tree()
	elif node is Node3D:
		var node_3d: Node3D = node as Node3D
		visible = node_3d.visible
	else:
		result["terminal"] = true
		result["message"] = "node visibility is only available for CanvasItem or Node3D"
		return result
	result["visible"] = visible
	result["matched"] = visible == should_be_visible
	return result


func _check_text_condition(result: Dictionary, request: Dictionary, condition: String, node_path: String) -> Dictionary:
	var expected_text: String = str(request.get("text", "")).strip_edges()
	if expected_text == "":
		result["terminal"] = true
		result["message"] = "text is required"
		return result
	var case_sensitive: bool = _bool_value(request.get("case_sensitive", true), true)
	result["text"] = expected_text
	result["case_sensitive"] = case_sensitive
	if node_path != "":
		var node: Node = _runtime_node_from_path(node_path)
		if node == null:
			result["exists"] = false
			result["actual_text"] = ""
			return result
		result["exists"] = true
		result["node"] = _node_summary(node, false)
		var node_text: String = _node_text(node)
		result["actual_text"] = node_text
		var text_found: bool = _text_matches(node_text, expected_text, condition, case_sensitive)
		result["matched"] = not text_found if condition == "text_missing" else text_found
		return result
	var matches: Array[Dictionary] = _find_text_matches(expected_text, condition, case_sensitive)
	result["matched"] = matches.is_empty() if condition == "text_missing" else not matches.is_empty()
	result["matches"] = matches
	result["match_count"] = matches.size()
	return result


func _check_property_condition(result: Dictionary, request: Dictionary, node_path: String, condition: String) -> Dictionary:
	if node_path == "":
		result["terminal"] = true
		result["message"] = "node_path is required"
		return result
	var property_name: String = str(request.get("property_name", request.get("property", ""))).strip_edges()
	if property_name == "":
		result["terminal"] = true
		result["message"] = "property_name is required"
		return result
	var expects_value: bool = not ["property_exists", "property_missing"].has(condition)
	if expects_value and not request.has("expected"):
		result["terminal"] = true
		result["message"] = "expected is required"
		return result
	var node: Node = _runtime_node_from_path(node_path)
	result["property_name"] = property_name
	if request.has("expected"):
		result["expected"] = _safe_check_value(request.get("expected"))
	if node == null:
		result["exists"] = false
		return result
	var property_exists: bool = _node_has_property(node, property_name)
	result["exists"] = true
	result["property_exists"] = property_exists
	var actual_value: Variant = node.get(property_name)
	result["exists"] = true
	result["node"] = _node_summary(node, false)
	if property_exists:
		result["actual"] = _safe_check_value(actual_value)
	match condition:
		"property_exists":
			result["matched"] = property_exists
		"property_missing":
			result["matched"] = not property_exists
		"property_equals":
			result["matched"] = property_exists and _values_match(actual_value, request.get("expected"))
		"property_not_equals":
			result["matched"] = property_exists and not _values_match(actual_value, request.get("expected"))
		"property_contains":
			var actual_text := str(actual_value)
			var expected_text := str(request.get("expected"))
			if not _bool_value(request.get("case_sensitive", true), true):
				actual_text = actual_text.to_lower()
				expected_text = expected_text.to_lower()
			result["matched"] = property_exists and actual_text.contains(expected_text)
		"property_gt", "property_gte", "property_lt", "property_lte":
			var numeric_result: Dictionary = _numeric_property_match(actual_value, request.get("expected"), condition)
			if numeric_result.get("ok", false) != true:
				result["terminal"] = true
				result["message"] = str(numeric_result.get("message", "numeric property comparison failed"))
			result["matched"] = property_exists and numeric_result.get("matched", false) == true
	return result


func _find_text_matches(expected_text: String, condition: String, case_sensitive: bool) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var root: Window = get_tree().root
	var queue: Array = [root]
	var visited := 0
	while not queue.is_empty() and visited < CHECK_TEXT_SEARCH_MAX_NODES:
		var node_value: Variant = queue.pop_front()
		var node: Node = node_value as Node
		if node == null:
			continue
		visited += 1
		if not _should_skip_node(node):
			var node_text: String = _node_text(node)
			if node_text != "" and _text_matches(node_text, expected_text, condition, case_sensitive):
				matches.append({
					"path": str(node.get_path()),
					"name": str(node.name),
					"type": node.get_class(),
					"text": _trim_text(node_text)
				})
		for child: Node in node.get_children():
			queue.append(child)
	return matches


func _node_text(node: Node) -> String:
	if node.has_method("get_text"):
		var text_value: Variant = node.call("get_text")
		if typeof(text_value) == TYPE_STRING:
			return str(text_value)
	return ""


func _text_matches(actual_text: String, expected_text: String, condition: String, case_sensitive: bool) -> bool:
	var actual: String = actual_text
	var expected: String = expected_text
	if not case_sensitive:
		actual = actual.to_lower()
		expected = expected.to_lower()
	if condition == "text_equals":
		return actual == expected
	return actual.contains(expected)


func _values_match(actual_value: Variant, expected_value: Variant) -> bool:
	var actual_type: int = typeof(actual_value)
	var expected_type: int = typeof(expected_value)
	if (actual_type == TYPE_INT or actual_type == TYPE_FLOAT) and (expected_type == TYPE_INT or expected_type == TYPE_FLOAT):
		return abs(float(actual_value) - float(expected_value)) < 0.00001
	if actual_type == TYPE_BOOL and expected_type == TYPE_BOOL:
		return bool(actual_value) == bool(expected_value)
	if actual_type == TYPE_STRING or expected_type == TYPE_STRING:
		return str(actual_value) == str(expected_value)
	return actual_value == expected_value


func _node_has_property(node: Object, property_name: String) -> bool:
	if node == null or property_name == "":
		return false
	for property_value: Variant in node.get_property_list():
		var property_info: Dictionary = property_value
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _numeric_property_match(actual_value: Variant, expected_value: Variant, condition: String) -> Dictionary:
	var actual_type: int = typeof(actual_value)
	var expected_type: int = typeof(expected_value)
	if not (actual_type == TYPE_INT or actual_type == TYPE_FLOAT) or not (expected_type == TYPE_INT or expected_type == TYPE_FLOAT):
		return {"ok": false, "matched": false, "message": "numeric property comparison requires numeric actual and expected values"}
	var actual_number := float(actual_value)
	var expected_number := float(expected_value)
	var matched := false
	match condition:
		"property_gt":
			matched = actual_number > expected_number
		"property_gte":
			matched = actual_number >= expected_number
		"property_lt":
			matched = actual_number < expected_number
		"property_lte":
			matched = actual_number <= expected_number
	return {
		"ok": true,
		"matched": matched,
		"actual_number": actual_number,
		"expected_number": expected_number
	}


func _safe_check_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			if typeof(value) == TYPE_STRING:
				return _trim_text(str(value))
			return value
		TYPE_VECTOR2:
			var vector_2: Vector2 = value
			return _vector2_value(vector_2)
		TYPE_VECTOR3:
			var vector_3: Vector3 = value
			return _vector3_value(vector_3)
		TYPE_ARRAY:
			var source_array: Array = value
			var output_array: Array = []
			for item: Variant in source_array:
				output_array.append(_safe_check_value(item))
			return output_array
		TYPE_DICTIONARY:
			var source_dictionary: Dictionary = value
			var output_dictionary: Dictionary = {}
			for key: Variant in source_dictionary.keys():
				output_dictionary[str(key)] = _safe_check_value(source_dictionary[key])
			return output_dictionary
	return str(value)


func _runtime_property_snapshots(node: Node, include_values: bool, max_properties: int) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for property_value: Variant in node.get_property_list():
		if snapshots.size() >= max_properties:
			break
		var property_info: Dictionary = property_value
		var name: String = str(property_info.get("name", ""))
		if name == "":
			continue
		var item: Dictionary = {
			"name": name,
			"type": int(property_info.get("type", TYPE_NIL)),
			"type_name": type_string(int(property_info.get("type", TYPE_NIL))),
			"usage": int(property_info.get("usage", 0)),
			"hint": int(property_info.get("hint", 0)),
			"hint_string": str(property_info.get("hint_string", "")),
			"class_name": str(property_info.get("class_name", ""))
		}
		if include_values:
			item["value"] = _safe_check_value(node.get(name))
		snapshots.append(item)
	return snapshots


func _runtime_signal_snapshots(node: Node, max_signals: int) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for signal_value: Variant in node.get_signal_list():
		if snapshots.size() >= max_signals:
			break
		var signal_info: Dictionary = signal_value
		var args: Array[Dictionary] = []
		for arg_value: Variant in signal_info.get("args", []):
			var arg_info: Dictionary = arg_value
			args.append({
				"name": str(arg_info.get("name", "")),
				"type": int(arg_info.get("type", TYPE_NIL)),
				"type_name": type_string(int(arg_info.get("type", TYPE_NIL))),
				"class_name": str(arg_info.get("class_name", "")),
				"hint": int(arg_info.get("hint", 0)),
				"hint_string": str(arg_info.get("hint_string", ""))
			})
		snapshots.append({
			"name": str(signal_info.get("name", "")),
			"args": args,
			"default_args": signal_info.get("default_args", []),
			"flags": int(signal_info.get("flags", 0))
		})
	return snapshots


func _runtime_node_groups(node: Node) -> Array[String]:
	var groups: Array[String] = []
	for group_value: Variant in node.get_groups():
		groups.append(str(group_value))
	return groups


func _find_ui_matches(text: String, exact: bool, case_sensitive: bool, include_disabled: bool, node_path: String, max_matches: int) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var queue: Array = _ui_search_roots(node_path)
	var visited := 0
	while not queue.is_empty() and visited < UI_FIND_MAX_NODES and matches.size() < max_matches:
		var node_value: Variant = queue.pop_front()
		var node: Node = node_value as Node
		if node == null:
			continue
		visited += 1
		if not _should_skip_node(node):
			var node_text: String = _node_text(node)
			if node_text != "" and _ui_text_matches(node_text, text, exact, case_sensitive):
				var match: Dictionary = _ui_match_summary(node, node_text)
				if include_disabled or match.get("enabled", true) == true:
					matches.append(match)
		for child: Node in node.get_children():
			queue.append(child)
	return matches


func _ui_search_roots(node_path: String) -> Array:
	if node_path != "":
		var requested: Node = _runtime_node_from_path(node_path)
		if requested != null:
			return [requested]
		return []
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		return [current_scene]
	return [get_tree().root]


func _ui_text_matches(actual_text: String, expected_text: String, exact: bool, case_sensitive: bool) -> bool:
	var actual: String = actual_text
	var expected: String = expected_text
	if not case_sensitive:
		actual = actual.to_lower()
		expected = expected.to_lower()
	if exact:
		return actual == expected
	return actual.contains(expected)


func _ui_match_summary(node: Node, text: String) -> Dictionary:
	var enabled := true
	var visible := true
	var clickable := false
	var rect := {}
	if node is CanvasItem:
		var canvas_item: CanvasItem = node as CanvasItem
		visible = canvas_item.is_visible_in_tree()
	if node is Control:
		var control: Control = node as Control
		var global_rect: Rect2 = control.get_global_rect()
		rect = {
			"x": global_rect.position.x,
			"y": global_rect.position.y,
			"width": global_rect.size.x,
			"height": global_rect.size.y
		}
		clickable = visible and global_rect.size.x > 0.0 and global_rect.size.y > 0.0
		if control is BaseButton:
			var button: BaseButton = control as BaseButton
			enabled = not button.disabled
			clickable = clickable and enabled
	return {
		"path": str(node.get_path()),
		"name": str(node.name),
		"type": node.get_class(),
		"text": _trim_text(text),
		"visible": visible,
		"enabled": enabled,
		"clickable": clickable,
		"rect": rect
	}


func _runtime_request_error(request_id: String, message: String) -> Dictionary:
	return {
		"request_id": request_id,
		"ok": false,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"message": message,
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name()
	}


func _node_summary(node: Node, include_groups: bool) -> Dictionary:
	var parent: Node = node.get_parent()
	var parent_path := ""
	if parent != null:
		parent_path = str(parent.get_path())
	var item: Dictionary = {
		"path": str(node.get_path()),
		"name": str(node.name),
		"type": node.get_class(),
		"parent": parent_path,
		"child_count": node.get_child_count(),
		"index": node.get_index(),
		"scene_file_path": node.scene_file_path
	}
	var script_value: Variant = node.get_script()
	if script_value is Script:
		var script: Script = script_value as Script
		if script.resource_path != "":
			item["script_path"] = script.resource_path
	if include_groups:
		var groups: Array = []
		for group_value: Variant in node.get_groups():
			groups.append(str(group_value))
		item["groups"] = groups
	if node is CanvasItem:
		var canvas_item: CanvasItem = node as CanvasItem
		item["visible"] = canvas_item.visible
	if node is Node2D:
		var node_2d: Node2D = node as Node2D
		item["position"] = _vector2_value(node_2d.position)
		item["global_position"] = _vector2_value(node_2d.global_position)
		item["rotation_degrees"] = node_2d.rotation_degrees
		item["scale"] = _vector2_value(node_2d.scale)
	if node is Node3D:
		var node_3d: Node3D = node as Node3D
		item["position"] = _vector3_value(node_3d.position)
		item["global_position"] = _vector3_value(node_3d.global_position)
	if node is Control:
		var control: Control = node as Control
		item["size"] = _vector2_value(control.size)
	if node.has_method("get_text"):
		var text_value: Variant = node.call("get_text")
		if typeof(text_value) == TYPE_STRING:
			item["text"] = _trim_text(str(text_value))
	return item


func _should_skip_node(node: Node) -> bool:
	if node == self:
		return true
	return str(node.name) == "GawWorkbenchRuntimeProbe"


func _probe_status() -> Dictionary:
	return {
		"ok": true,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"node_path": str(get_path()),
		"debugger_active": EngineDebugger.is_active()
	}


func _screenshot_error(request_id: String, message: String) -> Dictionary:
	return {
		"request_id": request_id,
		"ok": false,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"message": message,
		"current_scene_path": _current_scene_path(),
		"current_scene_name": _current_scene_name()
	}


func _safe_file_id(value: String) -> String:
	var trimmed := value.strip_edges()
	if trimmed == "":
		trimmed = "runtime-screenshot-%d" % Time.get_ticks_msec()
	var output := ""
	for index: int in range(0, trimmed.length()):
		var character := trimmed.substr(index, 1)
		if character.is_valid_identifier() or character.is_valid_int() or character == "-":
			output += character
		else:
			output += "_"
	return output


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := int(file.get_length())
	file.close()
	return size


func _cleanup_screenshot_dir(current_path: String, max_files: int, max_bytes: int) -> Dictionary:
	var entries: Array[Dictionary] = _screenshot_entries()
	var before_bytes: int = _entries_size(entries)
	var result: Dictionary = {
		"enabled": true,
		"max_files": max_files,
		"max_bytes": max_bytes,
		"before_files": entries.size(),
		"before_bytes": before_bytes,
		"after_files": entries.size(),
		"after_bytes": before_bytes,
		"deleted_count": 0,
		"deleted_bytes": 0,
		"errors": []
	}
	entries.sort_custom(Callable(self, "_sort_screenshot_entry_oldest"))
	var total_bytes: int = before_bytes
	var file_count: int = entries.size()
	var current_normalized: String = current_path.replace("\\", "/")
	for entry: Dictionary in entries:
		if file_count <= max_files and total_bytes <= max_bytes:
			break
		var path: String = str(entry.get("path", ""))
		if path == current_normalized:
			continue
		var size: int = int(entry.get("size", 0))
		var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if remove_error == OK:
			result["deleted_count"] = int(result.get("deleted_count", 0)) + 1
			result["deleted_bytes"] = int(result.get("deleted_bytes", 0)) + size
			total_bytes = max(0, total_bytes - size)
			file_count = max(0, file_count - 1)
		else:
			var errors: Array = result.get("errors", [])
			errors.append({
				"path": path,
				"error": error_string(remove_error)
			})
			result["errors"] = errors
	var after_entries: Array[Dictionary] = _screenshot_entries()
	result["after_files"] = after_entries.size()
	result["after_bytes"] = _entries_size(after_entries)
	return result


func _screenshot_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(SCREENSHOT_DIR)
	if dir == null:
		return entries
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".png"):
			var path: String = "%s/%s" % [SCREENSHOT_DIR, file_name]
			entries.append({
				"name": file_name,
				"path": path,
				"size": _file_size(path),
				"modified": int(FileAccess.get_modified_time(path))
			})
		file_name = dir.get_next()
	dir.list_dir_end()
	return entries


func _entries_size(entries: Array[Dictionary]) -> int:
	var total := 0
	for entry: Dictionary in entries:
		total += int(entry.get("size", 0))
	return total


func _sort_screenshot_entry_oldest(left: Dictionary, right: Dictionary) -> bool:
	var left_modified := int(left.get("modified", 0))
	var right_modified := int(right.get("modified", 0))
	if left_modified == right_modified:
		return str(left.get("path", "")) < str(right.get("path", ""))
	return left_modified < right_modified


func _current_scene_path() -> String:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return ""
	return current_scene.scene_file_path


func _current_scene_name() -> String:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return ""
	return str(current_scene.name)


func _vector2_value(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _vector3_value(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


func _bool_value(value: Variant, default_value: bool) -> bool:
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


func _trim_text(value: String) -> String:
	if value.length() <= MAX_TEXT_LENGTH:
		return value
	return value.substr(0, MAX_TEXT_LENGTH) + "...[truncated]"
