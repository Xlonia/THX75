extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return ["script.validate", "script.open"]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"script.validate":
			_handle_script_validate_command(command)
			return true
		"script.open":
			_handle_script_open_command(command)
			return true
	return false


func _handle_script_validate_command(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var script_path: String = str(args.get("path", args.get("script_path", ""))).strip_edges()
	var timeout_msec: int = clampi(int(args.get("timeout_msec", 5000)), 500, 30000)
	var started_msec: int = Time.get_ticks_msec()
	var details: Dictionary = _dev_details()
	details["action"] = "script.validate"
	details["path"] = script_path
	details["timeout_msec"] = timeout_msec
	details["mutates_scene"] = false
	var diagnostics: Array[Dictionary] = []
	if script_path == "":
		diagnostics.append(_script_diagnostic("", 1, 1, "error", "godot", "missing_path", "path is required"))
		details["diagnostics"] = diagnostics
		details["status"] = "invalid"
		details["valid"] = false
		_ack(command, "ok", "script validation complete", details)
		return
	var script_path_result: Dictionary = _validate_script_resource_path(script_path)
	if script_path_result.get("ok", false) != true:
		diagnostics.append(_script_diagnostic(script_path, 1, 1, "error", "godot", "invalid_path", str(script_path_result.get("message", "script path rejected"))))
		details["diagnostics"] = diagnostics
		details["status"] = "invalid"
		details["valid"] = false
		details["duration_msec"] = Time.get_ticks_msec() - started_msec
		_ack(command, "ok", "script validation complete", details)
		return
	script_path = str(script_path_result.get("path", script_path))
	details["path"] = script_path
	details["absolute_path"] = str(script_path_result.get("absolute_path", ""))
	var loaded_script: Variant = ResourceLoader.load(script_path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
	var snapshot: Dictionary = _debug_snapshot(true)
	var output_diagnostics: Array[Dictionary] = _script_diagnostics_from_output(snapshot, script_path)
	for diagnostic: Dictionary in output_diagnostics:
		diagnostics.append(diagnostic)
	details["cache_mode"] = "ignore"
	if not loaded_script is Script:
		if not _diagnostics_have_severity(diagnostics, "error"):
			diagnostics.append(_script_diagnostic(script_path, 1, 1, "error", "godot", "script_load_failed", "Godot did not load the resource as Script"))
	else:
		var script_resource: Script = loaded_script
		details["script"] = _script_snapshot(script_resource)
	details["valid"] = not _diagnostics_have_severity(diagnostics, "error") and loaded_script is Script
	details["status"] = "valid" if details["valid"] else "invalid"
	details["diagnostics"] = diagnostics
	details["diagnostic_count"] = diagnostics.size()
	details["error_count"] = _diagnostics_count_severity(diagnostics, "error")
	details["warning_count"] = _diagnostics_count_severity(diagnostics, "warning")
	details["duration_msec"] = Time.get_ticks_msec() - started_msec
	var editor_output: Dictionary = _dict(snapshot.get("editor_output", {}))
	details["output_error_count"] = int(editor_output.get("error_count", 0))
	details["output_warning_count"] = int(editor_output.get("warning_count", 0))
	details["editor_output_available"] = editor_output.get("available", false) == true
	_send_request("debug.snapshot", snapshot)
	_refresh_debug_label(snapshot)
	_add_operation("Validate script: %s %s" % [script_path, str(details["status"])])
	_ack(command, "ok", "script validation complete", details)


func _handle_script_open_command(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var script_path: String = str(args.get("path", args.get("script_path", ""))).strip_edges()
	var line: int = maxi(int(args.get("line", 0)), 0)
	var column: int = maxi(int(args.get("column", 0)), 0)
	var focus: bool = _bool(args.get("focus", true), true)
	var details: Dictionary = _dev_details()
	details["action"] = "script.open"
	details["path"] = script_path
	details["line"] = line
	details["column"] = column
	details["focus"] = focus
	details["mutates_scene"] = false
	details["native_godot_api"] = true
	if _editor_interface == null:
		_ack(command, "error", "EditorInterface is unavailable", details)
		return
	if script_path == "":
		_ack(command, "error", "path is required", details)
		return
	var script_path_result: Dictionary = _validate_script_resource_path(script_path)
	if script_path_result.get("ok", false) != true:
		details["path_validation"] = script_path_result
		_ack(command, "error", str(script_path_result.get("message", "script path rejected")), details)
		return
	script_path = str(script_path_result.get("path", script_path))
	details["path"] = script_path
	details["absolute_path"] = str(script_path_result.get("absolute_path", ""))
	var loaded_script: Variant = ResourceLoader.load(script_path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded_script is Script:
		_ack(command, "error", "Godot did not load the resource as Script", details)
		return
	var script_resource: Script = loaded_script
	details["script"] = _script_snapshot(script_resource)
	details["line_applied"] = false
	details["method"] = "edit_resource"
	if _editor_interface.has_method("edit_script"):
		_editor_interface.call("edit_script", script_resource, line, column, focus)
		details["method"] = "edit_script"
		details["line_applied"] = line > 0
	elif _editor_interface.has_method("edit_resource"):
		_editor_interface.call("edit_resource", script_resource)
	else:
		_ack(command, "error", "EditorInterface has no script/resource edit method", details)
		return
	_add_operation("Open script: %s line=%s" % [script_path, str(line)])
	_ack(command, "ok", "script opened", details)



func _script_diagnostic(file_path: String, line: int, column: int, severity: String, source: String, code: String, message: String) -> Dictionary:
	return {
		"file": file_path,
		"line": maxi(line, 1),
		"column": maxi(column, 1),
		"severity": severity,
		"source": source,
		"code": code,
		"message": message
	}


func _script_diagnostics_from_output(snapshot: Dictionary, script_path: String) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	var editor_output: Dictionary = _dict(snapshot.get("editor_output", {}))
	var lines: Array = _array(editor_output.get("lines", []))
	var clean_path: String = script_path.replace("\\", "/")
	var absolute_path: String = ProjectSettings.globalize_path(script_path).replace("\\", "/")
	for line_value: Variant in lines:
		var line: Dictionary = _dict(line_value)
		var text: String = str(line.get("text", ""))
		if not _output_line_mentions_script(text, clean_path, absolute_path):
			continue
		var level: String = str(line.get("level", "")).to_lower()
		var lower_text: String = text.to_lower()
		var severity := "warning"
		if level == "error" or lower_text.contains("error") or lower_text.contains("parse error"):
			severity = "error"
		elif level != "warning" and not lower_text.contains("warning"):
			continue
		var code := "godot_output"
		if lower_text.contains("parse error"):
			code = "godot_parse_error"
		var diagnostic_line: int = _extract_script_line_from_output(text, clean_path, absolute_path)
		var diagnostic_column: int = _extract_output_marker_int(text, "column")
		diagnostics.append(_script_diagnostic(clean_path, diagnostic_line, diagnostic_column, severity, "godot", code, text))
	return diagnostics


func _output_line_mentions_script(text: String, script_path: String, absolute_path: String) -> bool:
	var normalized: String = text.replace("\\", "/").to_lower()
	if script_path != "" and normalized.contains(script_path.to_lower()):
		return true
	if absolute_path != "" and normalized.contains(absolute_path.to_lower()):
		return true
	return false


func _extract_script_line_from_output(text: String, script_path: String, absolute_path: String) -> int:
	var normalized: String = text.replace("\\", "/")
	var candidates: Array[String] = [script_path, absolute_path]
	for candidate: String in candidates:
		if candidate == "":
			continue
		var index: int = normalized.to_lower().find(candidate.to_lower())
		if index < 0:
			continue
		var offset: int = index + candidate.length()
		if offset < normalized.length() and normalized.substr(offset, 1) == ":":
			var parsed: int = _read_positive_int_at(normalized, offset + 1)
			if parsed > 0:
				return parsed
	var line_marker: int = _extract_output_marker_int(text, "line")
	if line_marker > 0:
		return line_marker
	return 1


func _extract_output_marker_int(text: String, marker: String) -> int:
	var lower_text: String = text.to_lower()
	var marker_index: int = lower_text.find(marker.to_lower())
	if marker_index < 0:
		return 0
	return _read_positive_int_at(lower_text, marker_index + marker.length())


func _read_positive_int_at(text: String, start: int) -> int:
	var index: int = start
	while index < text.length():
		var character: String = text.substr(index, 1)
		var codepoint: int = text.unicode_at(index)
		if codepoint >= 48 and codepoint <= 57:
			break
		if character != " " and character != ":" and character != "=" and character != ",":
			return 0
		index += 1
	var digits := ""
	while index < text.length():
		var digit_codepoint: int = text.unicode_at(index)
		if digit_codepoint < 48 or digit_codepoint > 57:
			break
		digits += text.substr(index, 1)
		index += 1
	if digits == "":
		return 0
	return int(digits)


func _diagnostics_have_severity(diagnostics: Array[Dictionary], severity: String) -> bool:
	for diagnostic: Dictionary in diagnostics:
		if str(diagnostic.get("severity", "")) == severity:
			return true
	return false


func _diagnostics_count_severity(diagnostics: Array[Dictionary], severity: String) -> int:
	var count := 0
	for diagnostic: Dictionary in diagnostics:
		if str(diagnostic.get("severity", "")) == severity:
			count += 1
	return count



func _dict(value: Variant) -> Dictionary:
	var result: Variant = _host.call("workbench_dictionary", value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _array(value: Variant) -> Array:
	var result: Variant = _host.call("workbench_array", value)
	if typeof(result) == TYPE_ARRAY:
		return result
	return []


func _bool(value: Variant, default_value: bool) -> bool:
	return bool(_host.call("workbench_bool", value, default_value))


func _dev_details() -> Dictionary:
	var result: Variant = _host.call("dev_details")
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _validate_script_resource_path(script_path: String) -> Dictionary:
	var result: Variant = _host.call("validate_script_resource_path", script_path)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"ok": false, "message": "script path validator did not return a result"}


func _script_snapshot(script_value: Variant) -> Dictionary:
	var result: Variant = _host.call("script_snapshot", script_value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"type": "Variant", "value": str(script_value)}


func _debug_snapshot(include_editor_output: bool) -> Dictionary:
	var result: Variant = _host.call("debug_snapshot", include_editor_output)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _send_request(method: String, params: Dictionary) -> void:
	_host.call("send_request", method, params)


func _refresh_debug_label(snapshot: Dictionary) -> void:
	_host.call("refresh_debug_label", snapshot)


func _add_operation(text: String) -> void:
	_host.call("add_operation", text)


func _ack(command: Dictionary, status: String, message: String, details: Dictionary) -> void:
	_host.call("ack_dev_command", command, status, message, details)
