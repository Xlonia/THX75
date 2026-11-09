@tool
extends EditorDebuggerPlugin

const MAX_EVENTS := 200
const MAX_DATA_DEPTH := 6
const MAX_TEXT_LENGTH := 4000
const CAPTURE_PREFIXES := [
	"output",
	"error",
	"warning",
	"stack_dump",
	"stack_frame_vars",
	"stack_frame_var",
	"gaw_runtime"
]
const RUNTIME_PREFIX := "gaw_runtime"

var _events: Array[Dictionary] = []
var _sequence := 0
var _connected_sessions: Dictionary = {}
var _runtime_request_seq := 0
var _runtime_pending: Dictionary = {}
var _runtime_responses: Dictionary = {}


func _has_capture(capture: String) -> bool:
	return _is_capture_prefix(capture)


func _capture(message: String, data: Array, session_id: int) -> bool:
	var prefix: String = _message_prefix(message)
	if not _is_capture_prefix(prefix):
		return false
	if prefix == RUNTIME_PREFIX:
		_capture_runtime_message(message, data, session_id)
		return true
	_append_event({
		"sequence": _next_sequence(),
		"time": _timestamp(),
		"session_id": session_id,
		"category": _category_for_prefix(prefix),
		"message": _trim_text(message),
		"text": _trim_text(_joined_data_text(data)),
		"data": _safe_array(data, 0)
	})
	if prefix == "stack_dump":
		_request_top_frame_variables(session_id)
	return false


func _setup_session(session_id: int) -> void:
	_connected_sessions[session_id] = true
	var session: EditorDebuggerSession = get_session(session_id)
	if session == null:
		_append_session_event(session_id, "session.setup_unavailable", {})
		return
	_connect_session_signal(session, "started", Callable(self, "_on_session_started").bind(session_id))
	_connect_session_signal(session, "stopped", Callable(self, "_on_session_stopped").bind(session_id))
	_connect_session_signal(session, "continued", Callable(self, "_on_session_continued").bind(session_id))
	_connect_session_signal(session, "breaked", Callable(self, "_on_session_breaked").bind(session_id))
	_append_session_event(session_id, "session.setup", _session_state(session, session_id))


func _breakpoint_set_in_tree(script: Script, line: int, enabled: bool) -> void:
	var script_path := ""
	if script != null:
		script_path = script.resource_path
	_append_event({
		"sequence": _next_sequence(),
		"time": _timestamp(),
		"session_id": -1,
		"category": "debugger",
		"message": "breakpoint.changed",
		"text": "%s:%d enabled=%s" % [script_path, line, str(enabled)],
		"script": script_path,
		"line": line,
		"enabled": enabled
	})


func _breakpoints_cleared_in_tree() -> void:
	_append_event({
		"sequence": _next_sequence(),
		"time": _timestamp(),
		"session_id": -1,
		"category": "debugger",
		"message": "breakpoints.cleared",
		"text": "all breakpoints cleared"
	})


func _goto_script_line(script: Script, line: int) -> void:
	var script_path := ""
	if script != null:
		script_path = script.resource_path
	_append_event({
		"sequence": _next_sequence(),
		"time": _timestamp(),
		"session_id": -1,
		"category": "debugger",
		"message": "debugger.goto_script_line",
		"text": "%s:%d" % [script_path, line],
		"script": script_path,
		"line": line
	})


func get_snapshot(limit: int = 80, since_sequence: int = 0) -> Dictionary:
	var normalized_limit: int = clampi(limit, 1, MAX_EVENTS)
	var selected_events: Array[Dictionary] = []
	for event: Dictionary in _events:
		if int(event.get("sequence", 0)) <= since_sequence:
			continue
		selected_events.append(event.duplicate(true))
	if selected_events.size() > normalized_limit:
		selected_events = selected_events.slice(selected_events.size() - normalized_limit)
	return {
		"sequence": _sequence,
		"captured_at": _timestamp(),
		"total_events": _events.size(),
		"events": selected_events,
		"sessions": _session_snapshots()
	}


func request_runtime_tree(options: Dictionary) -> Dictionary:
	var active_sessions: Array[int] = _active_session_ids()
	if active_sessions.is_empty():
		return {
			"ok": false,
			"message": "no active runtime debugger session",
			"sessions": _session_snapshots()
		}
	_runtime_request_seq += 1
	var request_id := "runtime-tree-%d-%d" % [Time.get_ticks_msec(), _runtime_request_seq]
	var request: Dictionary = options.duplicate(true)
	request["request_id"] = request_id
	for session_id: int in active_sessions:
		var session: EditorDebuggerSession = get_session(session_id)
		if session == null:
			continue
		session.send_message("%s:tree_request" % RUNTIME_PREFIX, [JSON.stringify(request)])
	_runtime_pending[request_id] = {
		"request_id": request_id,
		"sent_at": _timestamp(),
		"session_ids": active_sessions
	}
	return {
		"ok": true,
		"request_id": request_id,
		"session_ids": active_sessions
	}


func request_runtime_screenshot(options: Dictionary) -> Dictionary:
	var active_sessions: Array[int] = _active_session_ids()
	if active_sessions.is_empty():
		return {
			"ok": false,
			"message": "no active runtime debugger session",
			"sessions": _session_snapshots()
		}
	_runtime_request_seq += 1
	var request_id := "runtime-screenshot-%d-%d" % [Time.get_ticks_msec(), _runtime_request_seq]
	var request: Dictionary = options.duplicate(true)
	request["request_id"] = request_id
	for session_id: int in active_sessions:
		var session: EditorDebuggerSession = get_session(session_id)
		if session == null:
			continue
		session.send_message("%s:screenshot_request" % RUNTIME_PREFIX, [JSON.stringify(request)])
	_runtime_pending[request_id] = {
		"request_id": request_id,
		"sent_at": _timestamp(),
		"session_ids": active_sessions
	}
	return {
		"ok": true,
		"request_id": request_id,
		"session_ids": active_sessions
	}


func request_runtime_input(options: Dictionary) -> Dictionary:
	var active_sessions: Array[int] = _active_session_ids()
	if active_sessions.is_empty():
		return {
			"ok": false,
			"message": "no active runtime debugger session",
			"sessions": _session_snapshots()
		}
	_runtime_request_seq += 1
	var request_id := "runtime-input-%d-%d" % [Time.get_ticks_msec(), _runtime_request_seq]
	var request: Dictionary = options.duplicate(true)
	request["request_id"] = request_id
	for session_id: int in active_sessions:
		var session: EditorDebuggerSession = get_session(session_id)
		if session == null:
			continue
		session.send_message("%s:input_request" % RUNTIME_PREFIX, [JSON.stringify(request)])
	_runtime_pending[request_id] = {
		"request_id": request_id,
		"sent_at": _timestamp(),
		"session_ids": active_sessions
	}
	return {
		"ok": true,
		"request_id": request_id,
		"session_ids": active_sessions
	}


func request_runtime_inspect(options: Dictionary) -> Dictionary:
	return _request_runtime_message(options, "inspect_request", "runtime-inspect")


func request_runtime_state(options: Dictionary) -> Dictionary:
	return _request_runtime_message(options, "state_request", "runtime-state")


func request_runtime_ui_find(options: Dictionary) -> Dictionary:
	return _request_runtime_message(options, "ui_find_request", "runtime-ui-find")


func request_runtime_click_text(options: Dictionary) -> Dictionary:
	return _request_runtime_message(options, "click_text_request", "runtime-click-text")


func request_runtime_wait(options: Dictionary) -> Dictionary:
	return _request_runtime_check(options, "wait_request", "runtime-wait")


func request_runtime_assert(options: Dictionary) -> Dictionary:
	return _request_runtime_check(options, "assert_request", "runtime-assert")


func request_runtime_animation_state(options: Dictionary) -> Dictionary:
	return _request_runtime_message(options, "animation_state_request", "runtime-animation-state")


func request_runtime_animation_control(options: Dictionary) -> Dictionary:
	return _request_runtime_message(options, "animation_control_request", "runtime-animation-control")


func request_runtime_watch(options: Dictionary) -> Dictionary:
	return _request_runtime_message(options, "watch_request", "runtime-watch")


func _request_runtime_message(options: Dictionary, message_name: String, request_prefix: String) -> Dictionary:
	var active_sessions: Array[int] = _active_session_ids()
	if active_sessions.is_empty():
		return {
			"ok": false,
			"message": "no active runtime debugger session",
			"sessions": _session_snapshots()
		}
	_runtime_request_seq += 1
	var request_id := "%s-%d-%d" % [request_prefix, Time.get_ticks_msec(), _runtime_request_seq]
	var request: Dictionary = options.duplicate(true)
	request["request_id"] = request_id
	for session_id: int in active_sessions:
		var session: EditorDebuggerSession = get_session(session_id)
		if session == null:
			continue
		session.send_message("%s:%s" % [RUNTIME_PREFIX, message_name], [JSON.stringify(request)])
	_runtime_pending[request_id] = {
		"request_id": request_id,
		"sent_at": _timestamp(),
		"session_ids": active_sessions
	}
	return {
		"ok": true,
		"request_id": request_id,
		"session_ids": active_sessions
	}


func _request_runtime_check(options: Dictionary, message_name: String, request_prefix: String) -> Dictionary:
	var active_sessions: Array[int] = _active_session_ids()
	if active_sessions.is_empty():
		return {
			"ok": false,
			"message": "no active runtime debugger session",
			"sessions": _session_snapshots()
		}
	_runtime_request_seq += 1
	var request_id := "%s-%d-%d" % [request_prefix, Time.get_ticks_msec(), _runtime_request_seq]
	var request: Dictionary = options.duplicate(true)
	request["request_id"] = request_id
	for session_id: int in active_sessions:
		var session: EditorDebuggerSession = get_session(session_id)
		if session == null:
			continue
		session.send_message("%s:%s" % [RUNTIME_PREFIX, message_name], [JSON.stringify(request)])
	_runtime_pending[request_id] = {
		"request_id": request_id,
		"sent_at": _timestamp(),
		"session_ids": active_sessions
	}
	return {
		"ok": true,
		"request_id": request_id,
		"session_ids": active_sessions
	}


func runtime_tree_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_screenshot_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_input_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_inspect_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_state_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_ui_find_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_click_text_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_wait_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_assert_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_animation_state_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_animation_control_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func runtime_watch_response(request_id: String) -> Dictionary:
	return _runtime_response_state(request_id)


func _runtime_response_state(request_id: String) -> Dictionary:
	if _runtime_responses.has(request_id):
		var response: Dictionary = _runtime_responses.get(request_id, {})
		return {
			"available": true,
			"pending": false,
			"response": response.duplicate(true)
		}
	if _runtime_pending.has(request_id):
		return {
			"available": false,
			"pending": true,
			"request": _runtime_pending.get(request_id, {}).duplicate(true)
		}
	return {
		"available": false,
		"pending": false,
		"message": "runtime response not found"
	}


func _request_top_frame_variables(session_id: int) -> void:
	var session: EditorDebuggerSession = get_session(session_id)
	if session == null:
		return
	session.send_message("get_stack_frame_vars", [0])


func _on_session_started(session_id: int) -> void:
	_reset_run_history()
	var session: EditorDebuggerSession = get_session(session_id)
	_append_session_event(session_id, "session.started", _session_state(session, session_id))


func _on_session_stopped(session_id: int) -> void:
	var session: EditorDebuggerSession = get_session(session_id)
	_append_session_event(session_id, "session.stopped", _session_state(session, session_id))


func _on_session_continued(session_id: int) -> void:
	var session: EditorDebuggerSession = get_session(session_id)
	_append_session_event(session_id, "session.continued", _session_state(session, session_id))


func _on_session_breaked(can_debug: bool, session_id: int) -> void:
	var session: EditorDebuggerSession = get_session(session_id)
	var state: Dictionary = _session_state(session, session_id)
	state["can_debug"] = can_debug
	_append_session_event(session_id, "session.breaked", state)


func _reset_run_history() -> void:
	_events.clear()
	_runtime_pending.clear()
	_runtime_responses.clear()


func _connect_session_signal(session: EditorDebuggerSession, signal_name: String, callback: Callable) -> void:
	if not session.has_signal(signal_name):
		return
	if not session.is_connected(signal_name, callback):
		session.connect(signal_name, callback)


func _append_session_event(session_id: int, message: String, state: Dictionary) -> void:
	_append_event({
		"sequence": _next_sequence(),
		"time": _timestamp(),
		"session_id": session_id,
		"category": "session",
		"message": message,
		"text": message,
		"state": state
	})


func _capture_runtime_message(message: String, data: Array, session_id: int) -> void:
	var runtime_message := message
	var prefix_text := "%s:" % RUNTIME_PREFIX
	if runtime_message.begins_with(prefix_text):
		runtime_message = runtime_message.substr(prefix_text.length())
	var payload: Dictionary = _runtime_payload(data)
	payload["session_id"] = session_id
	payload["runtime_message"] = runtime_message
	var request_id := str(payload.get("request_id", ""))
	if (runtime_message == "tree_response" or runtime_message == "screenshot_response" or runtime_message == "input_response" or runtime_message == "inspect_response" or runtime_message == "state_response" or runtime_message == "ui_find_response" or runtime_message == "click_text_response" or runtime_message == "wait_response" or runtime_message == "assert_response" or runtime_message == "animation_state_response" or runtime_message == "animation_control_response" or runtime_message == "watch_response") and request_id != "":
		_runtime_responses[request_id] = payload.duplicate(true)
		_runtime_pending.erase(request_id)
	_append_event({
		"sequence": _next_sequence(),
		"time": _timestamp(),
		"session_id": session_id,
		"category": "runtime",
		"message": runtime_message,
		"text": _runtime_event_text(runtime_message, payload),
		"data": [_runtime_event_summary(payload)]
	})


func _runtime_payload(data: Array) -> Dictionary:
	if data.is_empty():
		return {}
	var first: Variant = data[0]
	if typeof(first) == TYPE_DICTIONARY:
		var first_dictionary: Dictionary = first
		return _safe_dictionary(first_dictionary, 0)
	if typeof(first) == TYPE_STRING:
		var parsed: Variant = JSON.parse_string(str(first))
		if typeof(parsed) == TYPE_DICTIONARY:
			var parsed_dictionary: Dictionary = parsed
			return _safe_dictionary(parsed_dictionary, 0)
		return {"raw": _trim_text(str(first))}
	return {"raw": _trim_text(str(first))}


func _active_session_ids() -> Array[int]:
	var active: Array[int] = []
	var ids: Array = _connected_sessions.keys()
	ids.sort()
	for id_value: Variant in ids:
		var session_id := int(id_value)
		var session: EditorDebuggerSession = get_session(session_id)
		if session != null and session.is_active():
			active.append(session_id)
	return active


func _runtime_event_text(message: String, payload: Dictionary) -> String:
	if message == "tree_response":
		return "runtime tree nodes=%d truncated=%s request=%s" % [
			int(payload.get("node_count", 0)),
			str(payload.get("truncated", false)),
			str(payload.get("request_id", ""))
		]
	if message == "screenshot_response":
		if payload.get("ok", false) == true:
			return "runtime screenshot %dx%d request=%s" % [
				int(payload.get("width", 0)),
				int(payload.get("height", 0)),
				str(payload.get("request_id", ""))
			]
		return "runtime screenshot failed request=%s" % str(payload.get("request_id", ""))
	if message == "input_response":
		return "runtime input applied=%d failures=%d request=%s" % [
			int(payload.get("applied_count", 0)),
			int(payload.get("failure_count", 0)),
			str(payload.get("request_id", ""))
		]
	if message == "inspect_response":
		return "runtime inspect node=%s properties=%d request=%s" % [
			str(payload.get("node_path", "")),
			int(payload.get("property_count", 0)),
			str(payload.get("request_id", ""))
		]
	if message == "state_response":
		return "runtime state nodes=%d values=%d request=%s" % [
			int(payload.get("node_count", 0)),
			int(payload.get("value_count", 0)),
			str(payload.get("request_id", ""))
		]
	if message == "ui_find_response":
		return "runtime ui find matches=%d text=%s request=%s" % [
			int(payload.get("match_count", 0)),
			str(payload.get("text", "")),
			str(payload.get("request_id", ""))
		]
	if message == "click_text_response":
		return "runtime click text ok=%s text=%s request=%s" % [
			str(payload.get("ok", false)),
			str(payload.get("text", "")),
			str(payload.get("request_id", ""))
		]
	if message == "wait_response" or message == "assert_response":
		return "runtime %s matched=%s condition=%s request=%s" % [
			"wait" if message == "wait_response" else "assert",
			str(payload.get("matched", false)),
			str(payload.get("condition", "")),
			str(payload.get("request_id", ""))
		]
	if message == "animation_state_response":
		return "runtime animation state node=%s type=%s request=%s" % [
			str(payload.get("node_path", "")),
			str(payload.get("node_type", "")),
			str(payload.get("request_id", ""))
		]
	if message == "animation_control_response":
		return "runtime animation control action=%s ok=%s node=%s request=%s" % [
			str(payload.get("action", "")),
			str(payload.get("ok", false)),
			str(payload.get("node_path", "")),
			str(payload.get("request_id", ""))
		]
	if message == "watch_response":
		return "runtime watch samples=%d events=%d targets=%d request=%s" % [
			int(payload.get("sample_count", 0)),
			int(payload.get("event_count", 0)),
			int(payload.get("target_count", 0)),
			str(payload.get("request_id", ""))
		]
	if message == "probe_ready":
		return "runtime probe ready at %s" % str(payload.get("node_path", ""))
	return message


func _runtime_event_summary(payload: Dictionary) -> Dictionary:
	return {
		"request_id": str(payload.get("request_id", "")),
		"runtime_message": str(payload.get("runtime_message", "")),
		"ok": payload.get("ok", false),
		"node_count": int(payload.get("node_count", 0)),
		"truncated": payload.get("truncated", false),
		"current_scene_path": str(payload.get("current_scene_path", "")),
		"path": str(payload.get("path", "")),
		"width": int(payload.get("width", 0)),
		"height": int(payload.get("height", 0)),
		"event_count": int(payload.get("event_count", 0)),
		"sample_count": int(payload.get("sample_count", 0)),
		"target_count": int(payload.get("target_count", 0)),
		"applied_count": int(payload.get("applied_count", 0)),
		"failure_count": int(payload.get("failure_count", 0)),
		"property_count": int(payload.get("property_count", 0)),
		"match_count": int(payload.get("match_count", 0)),
		"animation_count": int(payload.get("animation_count", 0)),
		"parameter_count": int(payload.get("parameter_count", 0)),
		"matched": payload.get("matched", false),
		"condition": str(payload.get("condition", "")),
		"elapsed_msec": int(payload.get("elapsed_msec", 0)),
		"session_id": int(payload.get("session_id", -1))
	}


func _append_event(event: Dictionary) -> void:
	_events.append(event)
	while _events.size() > MAX_EVENTS:
		_events.remove_at(0)


func _next_sequence() -> int:
	_sequence += 1
	return _sequence


func _session_snapshots() -> Array[Dictionary]:
	var sessions: Array[Dictionary] = []
	var ids: Array = _connected_sessions.keys()
	ids.sort()
	for id_value: Variant in ids:
		var session_id := int(id_value)
		var session: EditorDebuggerSession = get_session(session_id)
		sessions.append(_session_state(session, session_id))
	return sessions


func _session_state(session: EditorDebuggerSession, session_id: int) -> Dictionary:
	if session == null:
		return {
			"id": session_id,
			"active": false,
			"breaked": false,
			"debuggable": false,
			"available": false
		}
	return {
		"id": session_id,
		"active": session.is_active(),
		"breaked": session.is_breaked(),
		"debuggable": session.is_debuggable(),
		"available": true
	}


func _message_prefix(message: String) -> String:
	var separator_index: int = message.find(":")
	if separator_index < 0:
		return message
	return message.substr(0, separator_index)


func _is_capture_prefix(prefix: String) -> bool:
	for known_prefix: String in CAPTURE_PREFIXES:
		if prefix == known_prefix:
			return true
	return false


func _category_for_prefix(prefix: String) -> String:
	match prefix:
		"output":
			return "output"
		"error":
			return "error"
		"warning":
			return "warning"
		_:
			return "debugger"


func _safe_array(values: Array, depth: int) -> Array:
	var output: Array = []
	for value: Variant in values:
		output.append(_safe_variant(value, depth + 1))
	return output


func _safe_dictionary(values: Dictionary, depth: int) -> Dictionary:
	var output: Dictionary = {}
	for key: Variant in values.keys():
		output[str(key)] = _safe_variant(values[key], depth + 1)
	return output


func _safe_variant(value: Variant, depth: int) -> Variant:
	if depth > MAX_DATA_DEPTH:
		return _trim_text(str(value))
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_ARRAY:
			var array_value: Array = value
			return _safe_array(array_value, depth)
		TYPE_DICTIONARY:
			var dictionary_value: Dictionary = value
			return _safe_dictionary(dictionary_value, depth)
		_:
			return _trim_text(str(value))


func _joined_data_text(values: Array) -> String:
	var lines: Array[String] = []
	for value: Variant in values:
		if typeof(value) == TYPE_STRING:
			lines.append(str(value))
		elif typeof(value) == TYPE_ARRAY:
			for nested: Variant in value:
				lines.append(str(nested))
		else:
			lines.append(str(value))
	var output := ""
	for index: int in range(0, lines.size()):
		if index > 0:
			output += "\n"
		output += lines[index]
	return output


func _trim_text(value: String) -> String:
	if value.length() <= MAX_TEXT_LENGTH:
		return value
	return value.substr(0, MAX_TEXT_LENGTH) + "...[truncated]"


func _timestamp() -> String:
	return Time.get_datetime_string_from_system(false, true)
