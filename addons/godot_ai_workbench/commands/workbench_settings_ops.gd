extends RefCounted

var _host
var _editor_interface


func setup(host, editor_interface = null) -> void:
	_host = host
	_editor_interface = editor_interface


func handled_commands() -> Array:
	return [
		"editor.read_settings",
		"project.set_setting",
		"editor.set_setting",
		"project.input_action_set",
		"project.input_action_remove",
		"project.autoload_add",
		"project.autoload_remove"
	]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"editor.read_settings":
			_handle_editor_read_settings(command)
			return true
		"project.set_setting":
			_handle_project_set_setting(command)
			return true
		"editor.set_setting":
			_handle_editor_set_setting(command)
			return true
		"project.input_action_set":
			_handle_input_action_set(command)
			return true
		"project.input_action_remove":
			_handle_input_action_remove(command)
			return true
		"project.autoload_add":
			_handle_autoload_add(command)
			return true
		"project.autoload_remove":
			_handle_autoload_remove(command)
			return true
	return false


func _handle_editor_read_settings(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var names: Array = _string_array(args.get("names", []))
	var prefix: String = str(args.get("prefix", "")).strip_edges()
	var include_values: bool = _bool(args.get("include_values", true), true)
	var max_items: int = clamp(_int(args.get("max_items", 80), 80), 1, 500)
	var details: Dictionary = _read_base_details("editor.read_settings")
	details["native_godot_api"] = true
	details["prefix"] = prefix
	details["requested_names"] = names
	details["include_values"] = include_values
	details["max_items"] = max_items
	var settings: EditorSettings = _editor_settings()
	if settings == null:
		_ack(command, "error", "EditorSettings is unavailable", details)
		return
	var rows: Array = []
	var missing: Array = []
	if names.size() > 0:
		for setting_name: String in names:
			if rows.size() >= max_items:
				break
			var clean_name: String = setting_name.strip_edges()
			var validation: Dictionary = _validate_setting_name(clean_name)
			if validation.get("ok", false) != true:
				missing.append({"name": clean_name, "reason": str(validation.get("message", "invalid setting name"))})
				continue
			if not settings.has_setting(clean_name):
				missing.append({"name": clean_name, "reason": "setting not found"})
				continue
			rows.append(_setting_row(settings, clean_name, include_values))
	else:
		var property_list: Array = settings.get_property_list()
		for property_value: Variant in property_list:
			if rows.size() >= max_items:
				break
			if typeof(property_value) != TYPE_DICTIONARY:
				continue
			var property: Dictionary = property_value
			var setting_name: String = str(property.get("name", ""))
			if setting_name == "":
				continue
			if prefix != "" and not setting_name.begins_with(prefix):
				continue
			if not settings.has_setting(setting_name):
				continue
			rows.append(_setting_row(settings, setting_name, include_values, property))
	details["settings"] = rows
	details["count"] = rows.size()
	details["missing"] = missing
	details["truncated"] = rows.size() >= max_items
	_ack(command, "ok", "editor settings read", details)


func _handle_project_set_setting(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_project: bool = _bool(args.get("save", true), true)
	var setting_name: String = str(args.get("name", "")).strip_edges()
	var has_value: bool = args.has("value")
	var requested_value: Variant = args.get("value", null)
	var details: Dictionary = _write_base_details("project.set_setting")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save"] = save_project
	details["name"] = setting_name
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if not has_value:
		_ack(command, "error", "value is required; pass null to clear a custom setting", details)
		return
	var validation: Dictionary = _validate_setting_name(setting_name)
	if validation.get("ok", false) != true:
		_ack(command, "error", str(validation.get("message", "invalid setting name")), details)
		return
	var existed_before: bool = ProjectSettings.has_setting(setting_name)
	var old_value: Variant = ProjectSettings.get_setting(setting_name, null)
	var new_value: Variant = _coerce_to_existing_type(requested_value, old_value, existed_before)
	details["existed_before"] = existed_before
	details["old_value"] = _variant_snapshot(old_value)
	details["new_value"] = _variant_snapshot(new_value)
	details["would_change"] = not _values_equal(old_value, new_value) or (not existed_before and new_value != null)
	ProjectSettings.set_setting(setting_name, new_value)
	details["applied_value"] = _variant_snapshot(ProjectSettings.get_setting(setting_name, null))
	var save_error: int = OK
	if save_project:
		save_error = ProjectSettings.save()
		details["save_error"] = save_error
		details["saved"] = save_error == OK
		if save_error != OK:
			_ack(command, "error", "ProjectSettings.save failed", details)
			return
	else:
		details["saved"] = false
	details["status"] = "applied"
	_write_audit(details)
	_add_operation("Dev write: project setting %s" % setting_name)
	_ack(command, "ok", "project setting updated", details)


func _handle_editor_set_setting(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var setting_name: String = str(args.get("name", "")).strip_edges()
	var has_value: bool = args.has("value")
	var requested_value: Variant = args.get("value", null)
	var details: Dictionary = _write_base_details("editor.set_setting")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["name"] = setting_name
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	if not has_value:
		_ack(command, "error", "value is required", details)
		return
	var validation: Dictionary = _validate_setting_name(setting_name)
	if validation.get("ok", false) != true:
		_ack(command, "error", str(validation.get("message", "invalid setting name")), details)
		return
	var settings: EditorSettings = _editor_settings()
	if settings == null:
		_ack(command, "error", "EditorSettings is unavailable", details)
		return
	var existed_before: bool = settings.has_setting(setting_name)
	var old_value: Variant = null
	if existed_before:
		old_value = settings.get_setting(setting_name)
	var new_value: Variant = _coerce_to_existing_type(requested_value, old_value, existed_before)
	details["existed_before"] = existed_before
	details["old_value"] = _variant_snapshot(old_value)
	details["new_value"] = _variant_snapshot(new_value)
	details["would_change"] = not _values_equal(old_value, new_value) or (not existed_before and new_value != null)
	settings.set_setting(setting_name, new_value)
	details["applied_value"] = _variant_snapshot(settings.get_setting(setting_name))
	details["saved"] = "editor_managed"
	details["status"] = "applied"
	_write_audit(details)
	_add_operation("Dev write: editor setting %s" % setting_name)
	_ack(command, "ok", "editor setting updated", details)


func _handle_input_action_set(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_project: bool = _bool(args.get("save", true), true)
	var replace_events: bool = _bool(args.get("replace_events", true), true)
	var action_name: String = str(args.get("name", "")).strip_edges()
	var deadzone: float = _float(args.get("deadzone", 0.5), 0.5)
	var details: Dictionary = _write_base_details("project.input_action_set")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save"] = save_project
	details["replace_events"] = replace_events
	details["name"] = action_name
	details["deadzone"] = deadzone
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var validation: Dictionary = _validate_input_action_name(action_name)
	if validation.get("ok", false) != true:
		_ack(command, "error", str(validation.get("message", "invalid input action name")), details)
		return
	var event_plan: Dictionary = _input_events_from_args(args.get("events", []))
	if event_plan.get("ok", false) != true:
		_ack(command, "error", str(event_plan.get("message", "invalid input events")), details)
		return
	var new_events: Array = _array(event_plan.get("events", []))
	var new_event_snapshots: Array = _array(event_plan.get("snapshots", []))
	var existed_before: bool = InputMap.has_action(action_name)
	var old_deadzone: float = 0.5
	var old_event_snapshots: Array = []
	var final_events: Array = []
	if existed_before:
		old_deadzone = InputMap.action_get_deadzone(action_name)
		var old_events: Array = InputMap.action_get_events(action_name)
		old_event_snapshots = _input_event_snapshots(old_events)
		if not replace_events:
			for old_event: Variant in old_events:
				final_events.append(old_event)
	for new_event: Variant in new_events:
		final_events.append(new_event)
	var final_event_snapshots: Array = _input_event_snapshots(final_events)
	details["existed_before"] = existed_before
	details["old_deadzone"] = old_deadzone
	details["old_events"] = old_event_snapshots
	details["new_events"] = new_event_snapshots
	details["final_events"] = final_event_snapshots
	details["would_change"] = (not existed_before) or (abs(old_deadzone - deadzone) > 0.0001) or replace_events or new_events.size() > 0
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, deadzone)
	else:
		InputMap.action_set_deadzone(action_name, deadzone)
	if replace_events:
		InputMap.action_erase_events(action_name)
	for event_value: Variant in new_events:
		if event_value is InputEvent:
			InputMap.action_add_event(action_name, event_value)
	ProjectSettings.set_setting("input/%s" % action_name, {
		"deadzone": deadzone,
		"events": final_events
	})
	var save_error: int = OK
	if save_project:
		save_error = ProjectSettings.save()
		details["save_error"] = save_error
		details["saved"] = save_error == OK
		if save_error != OK:
			_ack(command, "error", "ProjectSettings.save failed", details)
			return
	else:
		details["saved"] = false
	details["status"] = "applied"
	details["applied_events"] = _input_event_snapshots(InputMap.action_get_events(action_name))
	details["applied_deadzone"] = InputMap.action_get_deadzone(action_name)
	_write_audit(details)
	_add_operation("Dev write: input action %s" % action_name)
	_ack(command, "ok", "input action updated", details)


func _handle_input_action_remove(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_project: bool = _bool(args.get("save", true), true)
	var action_name: String = str(args.get("name", "")).strip_edges()
	var details: Dictionary = _write_base_details("project.input_action_remove")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save"] = save_project
	details["name"] = action_name
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var validation: Dictionary = _validate_input_action_name(action_name)
	if validation.get("ok", false) != true:
		_ack(command, "error", str(validation.get("message", "invalid input action name")), details)
		return
	var existed_before: bool = InputMap.has_action(action_name)
	details["existed_before"] = existed_before
	details["setting_name"] = "input/%s" % action_name
	if existed_before:
		details["old_deadzone"] = InputMap.action_get_deadzone(action_name)
		details["old_events"] = _input_event_snapshots(InputMap.action_get_events(action_name))
	details["would_change"] = existed_before or ProjectSettings.has_setting(str(details["setting_name"]))
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	_clear_project_setting(str(details["setting_name"]))
	var save_error: int = OK
	if save_project:
		save_error = ProjectSettings.save()
		details["save_error"] = save_error
		details["saved"] = save_error == OK
		if save_error != OK:
			_ack(command, "error", "ProjectSettings.save failed", details)
			return
	else:
		details["saved"] = false
	details["status"] = "applied"
	details["exists_after"] = InputMap.has_action(action_name)
	_write_audit(details)
	_add_operation("Dev write: remove input action %s" % action_name)
	_ack(command, "ok", "input action removed", details)


func _handle_autoload_add(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_project: bool = _bool(args.get("save", true), true)
	var replace_existing: bool = _bool(args.get("replace", false), false)
	var autoload_name: String = str(args.get("name", "")).strip_edges()
	var resource_path: String = str(args.get("path", "")).strip_edges()
	var singleton: bool = _bool(args.get("singleton", true), true)
	var details: Dictionary = _write_base_details("project.autoload_add")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save"] = save_project
	details["replace"] = replace_existing
	details["name"] = autoload_name
	details["path"] = resource_path
	details["singleton"] = singleton
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var name_validation: Dictionary = _validate_autoload_name(autoload_name)
	if name_validation.get("ok", false) != true:
		_ack(command, "error", str(name_validation.get("message", "invalid autoload name")), details)
		return
	var path_validation: Dictionary = _validate_autoload_path(resource_path)
	if path_validation.get("ok", false) != true:
		_ack(command, "error", str(path_validation.get("message", "invalid autoload path")), details)
		return
	resource_path = str(path_validation.get("path", resource_path))
	var setting_name: String = "autoload/%s" % autoload_name
	var existed_before: bool = ProjectSettings.has_setting(setting_name)
	var old_value: Variant = ProjectSettings.get_setting(setting_name, null)
	var new_value: String = resource_path
	if singleton:
		new_value = "*%s" % resource_path
	details["setting_name"] = setting_name
	details["existed_before"] = existed_before
	details["old_value"] = _variant_snapshot(old_value)
	details["new_value"] = _variant_snapshot(new_value)
	details["would_change"] = not _values_equal(old_value, new_value) or not existed_before
	if existed_before and not replace_existing and not _values_equal(old_value, new_value):
		_ack(command, "error", "autoload already exists; pass replace=true to update it", details)
		return
	ProjectSettings.set_setting(setting_name, new_value)
	var save_error: int = OK
	if save_project:
		save_error = ProjectSettings.save()
		details["save_error"] = save_error
		details["saved"] = save_error == OK
		if save_error != OK:
			_ack(command, "error", "ProjectSettings.save failed", details)
			return
	else:
		details["saved"] = false
	details["status"] = "applied"
	details["applied_value"] = _variant_snapshot(ProjectSettings.get_setting(setting_name, null))
	_write_audit(details)
	_add_operation("Dev write: autoload %s" % autoload_name)
	_ack(command, "ok", "autoload added", details)


func _handle_autoload_remove(command: Dictionary) -> void:
	var args: Dictionary = _dict(command.get("args", {}))
	var save_project: bool = _bool(args.get("save", true), true)
	var autoload_name: String = str(args.get("name", "")).strip_edges()
	var details: Dictionary = _write_base_details("project.autoload_remove")
	details["native_godot_api"] = true
	details["dev_first"] = true
	details["save"] = save_project
	details["name"] = autoload_name
	if not _write_gate_open():
		_ack(command, "error", "write access requires full_control on bridge and addon", details)
		return
	var validation: Dictionary = _validate_autoload_name(autoload_name)
	if validation.get("ok", false) != true:
		_ack(command, "error", str(validation.get("message", "invalid autoload name")), details)
		return
	var setting_name: String = "autoload/%s" % autoload_name
	var existed_before: bool = ProjectSettings.has_setting(setting_name)
	var old_value: Variant = ProjectSettings.get_setting(setting_name, null)
	details["setting_name"] = setting_name
	details["existed_before"] = existed_before
	details["old_value"] = _variant_snapshot(old_value)
	details["would_change"] = existed_before
	_clear_project_setting(setting_name)
	var save_error: int = OK
	if save_project:
		save_error = ProjectSettings.save()
		details["save_error"] = save_error
		details["saved"] = save_error == OK
		if save_error != OK:
			_ack(command, "error", "ProjectSettings.save failed", details)
			return
	else:
		details["saved"] = false
	details["status"] = "applied"
	details["exists_after"] = ProjectSettings.has_setting(setting_name)
	_write_audit(details)
	_add_operation("Dev write: remove autoload %s" % autoload_name)
	_ack(command, "ok", "autoload removed", details)


func _setting_row(settings: EditorSettings, setting_name: String, include_values: bool, property: Dictionary = {}) -> Dictionary:
	var row: Dictionary = {
		"name": setting_name,
		"type": str(property.get("type", "")),
		"hint": str(property.get("hint", "")),
		"hint_string": str(property.get("hint_string", "")),
		"usage": int(property.get("usage", 0))
	}
	if include_values:
		row["value"] = _variant_snapshot(settings.get_setting(setting_name))
	return row


func _editor_settings() -> EditorSettings:
	if _editor_interface == null:
		return null
	var settings: Variant = _editor_interface.get_editor_settings()
	if settings is EditorSettings:
		return settings
	return null


func _validate_setting_name(setting_name: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "message": ""}
	if setting_name == "":
		result["message"] = "setting name is required"
		return result
	if setting_name.length() > 160:
		result["message"] = "setting name is too long"
		return result
	if setting_name.begins_with("/") or setting_name.ends_with("/"):
		result["message"] = "setting name must be a full Godot setting path without leading/trailing slash"
		return result
	if setting_name.contains(".."):
		result["message"] = "setting name must not contain '..'"
		return result
	var blocked: Array[String] = ["\\", "\n", "\r", "\t"]
	for item: String in blocked:
		if setting_name.contains(item):
			result["message"] = "setting name contains a blocked character"
			result["blocked"] = item
			return result
	result["ok"] = true
	result["message"] = "setting name ok"
	return result


func _validate_input_action_name(action_name: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "message": ""}
	if action_name == "":
		result["message"] = "input action name is required"
		return result
	if action_name.length() > 96:
		result["message"] = "input action name is too long"
		return result
	var blocked: Array[String] = ["/", "\\", ":", "\n", "\r", "\t"]
	for item: String in blocked:
		if action_name.contains(item):
			result["message"] = "input action name contains a blocked character"
			result["blocked"] = item
			return result
	result["ok"] = true
	result["message"] = "input action name ok"
	return result


func _validate_autoload_name(autoload_name: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "message": ""}
	if autoload_name == "":
		result["message"] = "autoload name is required"
		return result
	if autoload_name.length() > 80:
		result["message"] = "autoload name is too long"
		return result
	if autoload_name.begins_with("@"):
		result["message"] = "autoload name must not use Godot internal auto-name prefix"
		return result
	var blocked: Array[String] = ["/", "\\", ":", "%", "\n", "\r", "\t", " "]
	for item: String in blocked:
		if autoload_name.contains(item):
			result["message"] = "autoload name contains a blocked character"
			result["blocked"] = item
			return result
	result["ok"] = true
	result["message"] = "autoload name ok"
	return result


func _validate_autoload_path(resource_path: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "message": "", "path": resource_path}
	if resource_path == "":
		result["message"] = "autoload path is required"
		return result
	if not resource_path.begins_with("res://"):
		result["message"] = "autoload path must start with res://"
		return result
	if resource_path.contains(".."):
		result["message"] = "autoload path must not contain '..'"
		return result
	var lower_path: String = resource_path.to_lower()
	if not (lower_path.ends_with(".gd") or lower_path.ends_with(".tscn") or lower_path.ends_with(".scn")):
		result["message"] = "autoload path must point to a GDScript or scene"
		return result
	if not ResourceLoader.exists(resource_path):
		result["message"] = "autoload path does not exist"
		return result
	result["ok"] = true
	result["message"] = "autoload path ok"
	return result


func _input_events_from_args(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "message": "events must be an array"}
	var events: Array = []
	var snapshots: Array = []
	var index := 0
	for event_value: Variant in value:
		var parsed: Dictionary = _input_event_from_dict(event_value)
		if parsed.get("ok", false) != true:
			return {
				"ok": false,
				"message": "event %d rejected: %s" % [index, str(parsed.get("message", "invalid event"))]
			}
		events.append(parsed.get("event", null))
		snapshots.append(parsed.get("snapshot", {}))
		index += 1
	return {"ok": true, "events": events, "snapshots": snapshots}


func _input_event_from_dict(value: Variant) -> Dictionary:
	var event_args: Dictionary = _dict(value)
	if event_args.is_empty():
		return {"ok": false, "message": "event must be an object"}
	var kind: String = str(event_args.get("type", "")).strip_edges().to_lower()
	match kind:
		"key":
			var event := InputEventKey.new()
			event.keycode = _keycode(event_args.get("keycode", 0))
			event.physical_keycode = _keycode(event_args.get("physical_keycode", 0))
			event.ctrl_pressed = _bool(event_args.get("ctrl", false), false)
			event.alt_pressed = _bool(event_args.get("alt", false), false)
			event.shift_pressed = _bool(event_args.get("shift", false), false)
			event.meta_pressed = _bool(event_args.get("meta", false), false)
			if event.keycode == 0 and event.physical_keycode == 0:
				return {"ok": false, "message": "key event requires keycode or physical_keycode"}
			return {"ok": true, "event": event, "snapshot": _input_event_snapshot(event)}
		"mouse_button":
			var event := InputEventMouseButton.new()
			event.button_index = _mouse_button_index(event_args.get("button_index", event_args.get("button", 0)))
			event.ctrl_pressed = _bool(event_args.get("ctrl", false), false)
			event.alt_pressed = _bool(event_args.get("alt", false), false)
			event.shift_pressed = _bool(event_args.get("shift", false), false)
			event.meta_pressed = _bool(event_args.get("meta", false), false)
			if event.button_index <= 0:
				return {"ok": false, "message": "mouse_button event requires button_index"}
			return {"ok": true, "event": event, "snapshot": _input_event_snapshot(event)}
		"joy_button":
			var event := InputEventJoypadButton.new()
			event.button_index = _int(event_args.get("button_index", event_args.get("button", -1)), -1)
			if event.button_index < 0:
				return {"ok": false, "message": "joy_button event requires button_index"}
			return {"ok": true, "event": event, "snapshot": _input_event_snapshot(event)}
		"joy_motion":
			var event := InputEventJoypadMotion.new()
			event.axis = _int(event_args.get("axis", -1), -1)
			event.axis_value = _float(event_args.get("axis_value", 1.0), 1.0)
			if event.axis < 0:
				return {"ok": false, "message": "joy_motion event requires axis"}
			return {"ok": true, "event": event, "snapshot": _input_event_snapshot(event)}
		_:
			return {"ok": false, "message": "unsupported event type"}


func _input_event_snapshots(events: Array) -> Array:
	var snapshots: Array = []
	for event_value: Variant in events:
		if event_value is InputEvent:
			snapshots.append(_input_event_snapshot(event_value))
		else:
			snapshots.append({"type": "Unknown", "value": str(event_value)})
	return snapshots


func _input_event_snapshot(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		return {
			"type": "key",
			"keycode": key_event.keycode,
			"physical_keycode": key_event.physical_keycode,
			"ctrl": key_event.ctrl_pressed,
			"alt": key_event.alt_pressed,
			"shift": key_event.shift_pressed,
			"meta": key_event.meta_pressed
		}
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		return {
			"type": "mouse_button",
			"button_index": mouse_event.button_index,
			"ctrl": mouse_event.ctrl_pressed,
			"alt": mouse_event.alt_pressed,
			"shift": mouse_event.shift_pressed,
			"meta": mouse_event.meta_pressed
		}
	if event is InputEventJoypadButton:
		var joy_button: InputEventJoypadButton = event
		return {"type": "joy_button", "button_index": joy_button.button_index}
	if event is InputEventJoypadMotion:
		var joy_motion: InputEventJoypadMotion = event
		return {"type": "joy_motion", "axis": joy_motion.axis, "axis_value": joy_motion.axis_value}
	return {"type": event.get_class(), "text": event.as_text()}


func _keycode(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	var text: String = str(value).strip_edges()
	if text == "":
		return 0
	if text.is_valid_int():
		return int(text)
	var found: int = OS.find_keycode_from_string(text)
	return found


func _mouse_button_index(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	var text: String = str(value).strip_edges().to_lower()
	match text:
		"left":
			return MOUSE_BUTTON_LEFT
		"right":
			return MOUSE_BUTTON_RIGHT
		"middle":
			return MOUSE_BUTTON_MIDDLE
		"wheel_up":
			return MOUSE_BUTTON_WHEEL_UP
		"wheel_down":
			return MOUSE_BUTTON_WHEEL_DOWN
		_:
			if text.is_valid_int():
				return int(text)
	return 0


func _clear_project_setting(setting_name: String) -> void:
	if ProjectSettings.has_method("clear"):
		ProjectSettings.call("clear", setting_name)
	else:
		ProjectSettings.set_setting(setting_name, null)


func _coerce_to_existing_type(value: Variant, old_value: Variant, existed_before: bool) -> Variant:
	if not existed_before or value == null:
		return value
	match typeof(old_value):
		TYPE_BOOL:
			return _bool(value, bool(old_value))
		TYPE_INT:
			return _int(value, int(old_value))
		TYPE_FLOAT:
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				return float(value)
			return old_value
		TYPE_STRING:
			return str(value)
		TYPE_STRING_NAME:
			return StringName(str(value))
		TYPE_NODE_PATH:
			return NodePath(str(value))
		_:
			return value


func _values_equal(left: Variant, right: Variant) -> bool:
	return var_to_str(left) == var_to_str(right)


func _variant_snapshot(value: Variant) -> Dictionary:
	return {
		"type": _variant_type_name(value),
		"value": _variant_value(value)
	}


func _variant_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a, "html": value.to_html(true)}
		TYPE_STRING_NAME:
			return str(value)
		TYPE_NODE_PATH:
			return str(value)
		_:
			return value


func _variant_type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "Nil"
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "String"
		TYPE_VECTOR2:
			return "Vector2"
		TYPE_VECTOR2I:
			return "Vector2i"
		TYPE_COLOR:
			return "Color"
		TYPE_STRING_NAME:
			return "StringName"
		TYPE_NODE_PATH:
			return "NodePath"
		TYPE_ARRAY:
			return "Array"
		TYPE_DICTIONARY:
			return "Dictionary"
		_:
			return "Variant:%d" % typeof(value)


func _string_array(value: Variant) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item: Variant in value:
		result.append(str(item))
	return result


func _dict(value: Variant) -> Dictionary:
	var result: Variant = _host.call("workbench_dictionary", value)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {}


func _bool(value: Variant, default_value: bool) -> bool:
	return bool(_host.call("workbench_bool", value, default_value))


func _int(value: Variant, default_value: int) -> int:
	return int(_host.call("workbench_int", value, default_value))


func _float(value: Variant, default_value: float) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	var text: String = str(value).strip_edges()
	if text.is_valid_float():
		return float(text)
	return default_value


func _array(value: Variant) -> Array:
	var result: Variant = _host.call("workbench_array", value)
	if typeof(result) == TYPE_ARRAY:
		return result
	return []


func _write_gate_open() -> bool:
	return bool(_host.call("write_gate_open"))


func _read_base_details(action: String) -> Dictionary:
	var result: Variant = _host.call("dev_details")
	if typeof(result) == TYPE_DICTIONARY:
		result["action"] = action
		return result
	return {"action": action}


func _write_base_details(action: String) -> Dictionary:
	var result: Variant = _host.call("write_base_details", action)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"action": action}


func _write_audit(details: Dictionary) -> void:
	_host.call("write_audit", details)


func _add_operation(text: String) -> void:
	_host.call("add_operation", text)


func _ack(command: Dictionary, status: String, message: String, details: Dictionary) -> void:
	_host.call("ack_dev_command", command, status, message, details)
