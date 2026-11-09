extends RefCounted

var _socket := WebSocketPeer.new()
var _request_id := 1
var _pending: Dictionary = {}
var _next_reconnect_msec := 0
var _reconnect_attempt := 0
var _current_reconnect_delay_msec := 0


func connect_to_url(url: String) -> Dictionary:
	_close_socket()
	_socket = WebSocketPeer.new()
	_pending.clear()
	var error_code: int = _socket.connect_to_url(url)
	if error_code != OK:
		return {
			"ok": false,
			"error_code": error_code,
			"message": error_string(error_code)
		}
	return {"ok": true, "state": _socket.get_ready_state()}


func poll() -> Dictionary:
	_socket.poll()
	var responses: Array[Dictionary] = []
	var invalid_messages: Array[String] = []
	while _socket.get_available_packet_count() > 0:
		var text: String = _socket.get_packet().get_string_from_utf8()
		var payload: Variant = JSON.parse_string(text)
		if typeof(payload) != TYPE_DICTIONARY:
			invalid_messages.append(text)
			continue
		var response: Dictionary = payload
		var id: String = response_id_key(response.get("id", ""))
		var method: String = str(_pending.get(id, ""))
		_pending.erase(id)
		responses.append({
			"id": id,
			"method": method,
			"payload": response
		})
	return {
		"state": _socket.get_ready_state(),
		"responses": responses,
		"invalid_messages": invalid_messages
	}


func send_request(method: String, params: Dictionary) -> String:
	var id: String = str(_request_id)
	_request_id += 1
	_pending[id] = method
	var payload: Dictionary = {
		"jsonrpc": "2.0",
		"id": id,
		"method": method,
		"params": params
	}
	_socket.send_text(JSON.stringify(payload))
	return id


func close() -> void:
	_close_socket()
	_socket = WebSocketPeer.new()
	_pending.clear()


func clear_pending() -> void:
	_pending.clear()


func reset_reconnect_backoff(initial_delay_msec: int) -> void:
	_reconnect_attempt = 0
	_current_reconnect_delay_msec = initial_delay_msec
	_next_reconnect_msec = 0


func schedule_reconnect(initial_delay_msec: int, max_delay_msec: int) -> Dictionary:
	var now: int = Time.get_ticks_msec()
	if _next_reconnect_msec > now:
		return reconnect_status()
	_current_reconnect_delay_msec = _reconnect_delay_for_attempt(_reconnect_attempt, initial_delay_msec, max_delay_msec)
	_reconnect_attempt += 1
	_next_reconnect_msec = now + _current_reconnect_delay_msec
	return reconnect_status()


func reconnect_due() -> bool:
	return _next_reconnect_msec > 0 and Time.get_ticks_msec() >= _next_reconnect_msec


func clear_reconnect_due() -> void:
	_next_reconnect_msec = 0


func reconnect_status() -> Dictionary:
	var now: int = Time.get_ticks_msec()
	return {
		"next_msec": _next_reconnect_msec,
		"attempt": _reconnect_attempt,
		"attempt_display": max(_reconnect_attempt, 1),
		"current_delay_msec": _current_reconnect_delay_msec,
		"remaining_msec": maxi(0, _next_reconnect_msec - now)
	}


func ready_state() -> int:
	return _socket.get_ready_state()


func pending_count() -> int:
	return _pending.size()


func is_open() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func is_connecting() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING


func is_closed() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED


static func response_id_key(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		return str(int(value))
	return str(value)


func _close_socket() -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.close()


func _reconnect_delay_for_attempt(attempt: int, initial_delay_msec: int, max_delay_msec: int) -> int:
	var delay: int = initial_delay_msec
	for _index: int in range(attempt):
		delay *= 2
		if delay >= max_delay_msec:
			return max_delay_msec
	return delay
