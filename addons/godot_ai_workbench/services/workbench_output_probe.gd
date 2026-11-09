extends RefCounted

var _editor_interface: EditorInterface
var _debug_probe: EditorDebuggerPlugin


func setup(editor_interface: EditorInterface, debug_probe: EditorDebuggerPlugin) -> void:
	_editor_interface = editor_interface
	_debug_probe = debug_probe


func debug_snapshot(include_editor_output: bool, limit: int) -> Dictionary:
	var snapshot: Dictionary = {
		"sequence": 0,
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"total_events": 0,
		"events": [],
		"sessions": [],
		"probe_available": _debug_probe != null
	}
	if _debug_probe != null and _debug_probe.has_method("get_snapshot"):
		var probe_snapshot: Variant = _debug_probe.call("get_snapshot", 80, 0)
		if typeof(probe_snapshot) == TYPE_DICTIONARY:
			var typed_snapshot: Dictionary = probe_snapshot
			snapshot = typed_snapshot
			snapshot["probe_available"] = true
	var events: Array = _as_array(snapshot.get("events", []))
	if not _snapshot_has_event(events, "stack_dump"):
		var stack_snapshot: Dictionary = _debugger_stack_snapshot(limit)
		var frames: Array = _as_array(stack_snapshot.get("frames", []))
		if not frames.is_empty():
			events.append({
				"sequence": int(snapshot.get("sequence", 0)) + 1,
				"time": Time.get_datetime_string_from_system(false, true),
				"session_id": -1,
				"category": "debugger",
				"message": "stack_dump",
				"text": "stack ui frames=%d" % frames.size(),
				"data": frames
			})
			snapshot["events"] = events
			snapshot["total_events"] = maxi(int(snapshot.get("total_events", 0)), events.size())
	if include_editor_output:
		snapshot["editor_output"] = editor_output_snapshot(limit)
	return snapshot


func editor_output_snapshot(limit: int) -> Dictionary:
	var panel_snapshot: Dictionary = _editor_panel_output_snapshot(limit)
	var debugger_snapshot: Dictionary = _debugger_errors_snapshot(limit)
	var source_summaries: Array[Dictionary] = []
	var notes: Array[String] = []
	var combined_lines: Array[Dictionary] = []
	_append_output_source(panel_snapshot, source_summaries, notes, combined_lines, limit)
	_append_output_source(debugger_snapshot, source_summaries, notes, combined_lines, limit)
	var has_editor_ui: bool = panel_snapshot.get("available", false) == true or debugger_snapshot.get("available", false) == true
	if not has_editor_ui:
		var log_snapshot: Dictionary = _project_log_snapshot(limit)
		_append_output_source(log_snapshot, source_summaries, notes, combined_lines, limit)
	var category_counters: Array = _as_array(panel_snapshot.get("category_counters", []))
	var category_counter_total: int = int(panel_snapshot.get("category_counter_total", 0))
	var nonzero_category_counter_count: int = int(panel_snapshot.get("nonzero_category_counter_count", 0))
	var available: bool = has_editor_ui or combined_lines.size() > 0
	var result: Dictionary = {
		"available": available,
		"source": "combined",
		"sources": source_summaries,
		"line_count": combined_lines.size(),
		"error_count": _count_output_level(combined_lines, "error"),
		"warning_count": _count_output_level(combined_lines, "warning"),
		"category_counter_total": category_counter_total,
		"nonzero_category_counter_count": nonzero_category_counter_count,
		"category_counters": category_counters,
		"lines": combined_lines,
		"notes": notes
	}
	if not available:
		result["note"] = _join_values(notes, " ")
	return result


func clear_editor_output(limit: int) -> Dictionary:
	var before: Dictionary = editor_output_snapshot(limit)
	var cleared_controls: Array[Dictionary] = []
	if _editor_interface == null:
		before["cleared"] = false
		before["message"] = "EditorInterface is unavailable."
		return before
	var base_control: Control = _editor_interface.get_base_control()
	if base_control == null:
		before["cleared"] = false
		before["message"] = "Editor base control is unavailable."
		return before
	var clear_result: Dictionary = _clear_editor_log_state(base_control)
	for control_value: Variant in _as_array(clear_result.get("controls", [])):
		cleared_controls.append(_as_dictionary(control_value))
	if clear_result.get("cleared", false) != true:
		var fallback_controls: Array[Dictionary] = _clear_visible_output_controls(base_control)
		cleared_controls.append_array(fallback_controls)
	cleared_controls.append_array(_clear_debugger_error_trees(base_control))
	var after: Dictionary = editor_output_snapshot(limit)
	after["cleared"] = cleared_controls.size() > 0
	after["cleared_count"] = cleared_controls.size()
	after["cleared_controls"] = cleared_controls
	after["clear_strategy"] = str(clear_result.get("strategy", "visible_controls_fallback"))
	after["before_line_count"] = int(before.get("line_count", 0))
	after["before_error_count"] = int(before.get("error_count", 0))
	after["before_warning_count"] = int(before.get("warning_count", 0))
	after["before_category_counter_total"] = int(before.get("category_counter_total", 0))
	after["before_nonzero_category_counter_count"] = int(before.get("nonzero_category_counter_count", 0))
	if cleared_controls.size() == 0:
		after["message"] = "No clearable editor output control was found."
	return {
		"available": after.get("available", false),
		"source": after.get("source", "combined"),
		"sources": after.get("sources", []),
		"line_count": after.get("line_count", 0),
		"error_count": after.get("error_count", 0),
		"warning_count": after.get("warning_count", 0),
		"category_counter_total": after.get("category_counter_total", 0),
		"nonzero_category_counter_count": after.get("nonzero_category_counter_count", 0),
		"category_counters": after.get("category_counters", []),
		"lines": after.get("lines", []),
		"notes": after.get("notes", []),
		"cleared": after.get("cleared", false),
		"cleared_count": after.get("cleared_count", 0),
		"cleared_controls": after.get("cleared_controls", []),
		"clear_strategy": after.get("clear_strategy", ""),
		"before_line_count": after.get("before_line_count", 0),
		"before_error_count": after.get("before_error_count", 0),
		"before_warning_count": after.get("before_warning_count", 0),
		"before_category_counter_total": after.get("before_category_counter_total", 0),
		"before_nonzero_category_counter_count": after.get("before_nonzero_category_counter_count", 0),
		"message": after.get("message", "")
	}


func output_line_mentions_script(text: String, script_path: String, absolute_path: String) -> bool:
	var normalized: String = text.replace("\\", "/").to_lower()
	if script_path != "" and normalized.contains(script_path.to_lower()):
		return true
	if absolute_path != "" and normalized.contains(absolute_path.to_lower()):
		return true
	return false


func extract_script_line_from_output(text: String, script_path: String, absolute_path: String) -> int:
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
			var parsed: int = read_positive_int_at(normalized, offset + 1)
			if parsed > 0:
				return parsed
	var line_marker: int = extract_output_marker_int(text, "line")
	if line_marker > 0:
		return line_marker
	return 1


func extract_output_marker_int(text: String, marker: String) -> int:
	var lower_text: String = text.to_lower()
	var marker_index: int = lower_text.find(marker.to_lower())
	if marker_index < 0:
		return 0
	return read_positive_int_at(lower_text, marker_index + marker.length())


func read_positive_int_at(text: String, start: int) -> int:
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


func count_level(lines: Array, level: String) -> int:
	return _count_output_level(lines, level)


func _editor_panel_output_snapshot(limit: int) -> Dictionary:
	var lines: Array[Dictionary] = []
	if _editor_interface == null:
		return _empty_source("editor_panel_best_effort", lines, "EditorInterface is unavailable.")
	var base_control: Control = _editor_interface.get_base_control()
	if base_control == null:
		return _empty_source("editor_panel_best_effort", lines, "Editor base control is unavailable.")
	var editor_log: Node = _find_editor_log(base_control)
	var category_counters: Array[Dictionary] = _editor_log_category_counters(editor_log)
	var category_counter_total: int = _sum_counter_values(category_counters)
	var nonzero_category_counter_count: int = _count_nonzero_counters(category_counters)
	var output_text: String = _find_editor_output_text(base_control)
	var candidates: Array[Dictionary] = _editor_output_candidate_summaries(base_control, 8)
	if output_text.strip_edges() == "":
		var empty_note: String = "Output panel is empty." if editor_log != null else "Output panel text was not found."
		var empty: Dictionary = _empty_source("editor_panel_best_effort", lines, empty_note)
		empty["available"] = editor_log != null
		empty["candidates"] = candidates
		empty["category_counter_total"] = category_counter_total
		empty["nonzero_category_counter_count"] = nonzero_category_counter_count
		empty["category_counters"] = category_counters
		return empty
	var raw_lines: PackedStringArray = output_text.split("\n", false)
	var start_index := maxi(0, raw_lines.size() - limit)
	for index: int in range(start_index, raw_lines.size()):
		var text: String = raw_lines[index].strip_edges()
		if text == "":
			continue
		lines.append({
			"index": index,
			"level": _infer_output_level(text),
			"text": text
		})
	return {
		"available": true,
		"source": "editor_panel_best_effort",
		"line_count": raw_lines.size(),
		"error_count": _count_output_level(lines, "error"),
		"warning_count": _count_output_level(lines, "warning"),
		"category_counter_total": category_counter_total,
		"nonzero_category_counter_count": nonzero_category_counter_count,
		"category_counters": category_counters,
		"candidates": candidates,
		"lines": lines
	}


func _debugger_errors_snapshot(limit: int) -> Dictionary:
	var lines: Array[Dictionary] = []
	if _editor_interface == null:
		return _empty_source("debugger_errors_best_effort", lines, "EditorInterface is unavailable.")
	var base_control: Control = _editor_interface.get_base_control()
	if base_control == null:
		return _empty_source("debugger_errors_best_effort", lines, "Editor base control is unavailable.")
	var debugger_node: Node = _find_node_by_class_name(base_control, "ScriptEditorDebugger", 0, 32)
	if debugger_node == null:
		return _empty_source("debugger_errors_best_effort", lines, "ScriptEditorDebugger node was not found.")
	var trees: Array[Tree] = []
	_collect_debugger_error_trees(debugger_node, trees, 0)
	if trees.is_empty():
		return _empty_source("debugger_errors_best_effort", lines, "Debugger errors tree was not found.")
	var raw_lines: Array[String] = []
	for tree: Tree in trees:
		var root_item: TreeItem = tree.get_root()
		if root_item == null:
			continue
		var column_count: int = clampi(tree.columns, 1, 4)
		_collect_debugger_tree_lines(root_item.get_first_child(), raw_lines, column_count)
	var start_index := maxi(0, raw_lines.size() - limit)
	for index: int in range(start_index, raw_lines.size()):
		var text: String = raw_lines[index].strip_edges()
		if text == "":
			continue
		lines.append({
			"index": index,
			"level": _infer_debugger_output_level(text),
			"text": text
		})
	return {
		"available": true,
		"source": "debugger_errors_best_effort",
		"line_count": raw_lines.size(),
		"error_count": _count_output_level(lines, "error"),
		"warning_count": _count_output_level(lines, "warning"),
		"lines": lines
	}


func _debugger_stack_snapshot(limit: int) -> Dictionary:
	if _editor_interface == null:
		return {"available": false, "source": "debugger_stack_best_effort", "frames": [], "note": "EditorInterface is unavailable."}
	var base_control: Control = _editor_interface.get_base_control()
	if base_control == null:
		return {"available": false, "source": "debugger_stack_best_effort", "frames": [], "note": "Editor base control is unavailable."}
	var debugger_node: Node = _find_node_by_class_name(base_control, "ScriptEditorDebugger", 0, 32)
	if debugger_node == null:
		return {"available": false, "source": "debugger_stack_best_effort", "frames": [], "note": "ScriptEditorDebugger node was not found."}
	var trees: Array[Tree] = []
	_collect_debugger_trees(debugger_node, trees, 0)
	var best_lines: Array[String] = []
	var best_score := -999999
	for tree: Tree in trees:
		var raw_lines: Array[String] = []
		var root_item: TreeItem = tree.get_root()
		if root_item == null:
			continue
		var column_count: int = clampi(tree.columns, 1, 6)
		_collect_debugger_tree_lines(root_item.get_first_child(), raw_lines, column_count)
		var score: int = _stack_tree_score(tree, raw_lines)
		if score > best_score:
			best_score = score
			best_lines = raw_lines
	if best_score <= 0:
		return {"available": false, "source": "debugger_stack_best_effort", "frames": [], "note": "Stack trace tree was not found."}
	var frames: Array[Dictionary] = []
	var start_index := maxi(0, best_lines.size() - limit)
	for index: int in range(start_index, best_lines.size()):
		var frame: Dictionary = _stack_frame_from_text(best_lines[index], frames.size())
		if not frame.is_empty():
			frames.append(frame)
	return {
		"available": not frames.is_empty(),
		"source": "debugger_stack_best_effort",
		"line_count": best_lines.size(),
		"frame_count": frames.size(),
		"frames": frames
	}


func _project_log_snapshot(limit: int) -> Dictionary:
	var attempts: Array[String] = []
	for log_path: String in _project_log_candidate_paths():
		var snapshot: Dictionary = _read_project_log_file(log_path, limit)
		var path_text: String = str(snapshot.get("path", ProjectSettings.globalize_path(log_path)))
		if snapshot.get("available", false) == true:
			if attempts.size() > 0:
				snapshot["note"] = "Read after fallback attempts: %s" % _join_values(attempts, "; ")
			return snapshot
		var note_text: String = str(snapshot.get("note", "unavailable"))
		attempts.append("%s - %s" % [path_text, note_text])
	return {
		"available": false,
		"source": "project_log",
		"line_count": 0,
		"error_count": 0,
		"warning_count": 0,
		"lines": [],
		"note": "No readable project log. Attempts: %s" % _join_values(attempts, "; ")
	}


func _project_log_candidate_paths() -> Array[String]:
	var paths: Array[String] = ["user://logs/godot.log"]
	var rotated_names: Array[String] = []
	var logs_dir: DirAccess = DirAccess.open("user://logs")
	if logs_dir != null:
		logs_dir.list_dir_begin()
		while true:
			var file_name: String = logs_dir.get_next()
			if file_name == "":
				break
			if logs_dir.current_is_dir():
				continue
			if file_name.begins_with("godot") and file_name.ends_with(".log") and file_name != "godot.log":
				rotated_names.append(file_name)
		logs_dir.list_dir_end()
	rotated_names.sort()
	rotated_names.reverse()
	for file_name: String in rotated_names:
		paths.append("user://logs/%s" % file_name)
	return paths


func _read_project_log_file(log_path: String, limit: int) -> Dictionary:
	var lines: Array[Dictionary] = []
	if not FileAccess.file_exists(log_path):
		return {
			"available": false,
			"source": "project_log",
			"path": ProjectSettings.globalize_path(log_path),
			"line_count": 0,
			"error_count": 0,
			"warning_count": 0,
			"lines": lines,
			"note": "Project log file is not available."
		}
	var file: FileAccess = FileAccess.open(log_path, FileAccess.READ)
	var open_error: int = FileAccess.get_open_error()
	var display_path: String = ProjectSettings.globalize_path(log_path)
	if file == null and display_path != "" and display_path != log_path and FileAccess.file_exists(display_path):
		file = FileAccess.open(display_path, FileAccess.READ)
		open_error = FileAccess.get_open_error()
	if file == null:
		return {
			"available": false,
			"source": "project_log",
			"path": display_path,
			"line_count": 0,
			"error_count": 0,
			"warning_count": 0,
			"lines": lines,
			"note": "Project log file could not be opened (error=%d)." % int(open_error)
		}
	var total_lines := 0
	while not file.eof_reached():
		var text: String = file.get_line().strip_edges()
		total_lines += 1
		if text == "":
			continue
		lines.append({
			"index": total_lines - 1,
			"level": _infer_output_level(text),
			"text": text
		})
		while lines.size() > limit:
			lines.remove_at(0)
	return {
		"available": true,
		"source": "project_log",
		"path": display_path,
		"line_count": total_lines,
		"error_count": _count_output_level(lines, "error"),
		"warning_count": _count_output_level(lines, "warning"),
		"lines": lines
	}


func _append_output_source(snapshot: Dictionary, source_summaries: Array[Dictionary], notes: Array[String], combined_lines: Array[Dictionary], limit: int) -> void:
	var source_name: String = str(snapshot.get("source", "unknown"))
	var available: bool = snapshot.get("available", false) == true
	var summary: Dictionary = {
		"source": source_name,
		"available": available,
		"line_count": int(snapshot.get("line_count", 0)),
		"error_count": int(snapshot.get("error_count", 0)),
		"warning_count": int(snapshot.get("warning_count", 0))
	}
	if snapshot.has("category_counter_total"):
		summary["category_counter_total"] = int(snapshot.get("category_counter_total", 0))
	if snapshot.has("nonzero_category_counter_count"):
		summary["nonzero_category_counter_count"] = int(snapshot.get("nonzero_category_counter_count", 0))
	if snapshot.has("path"):
		summary["path"] = str(snapshot.get("path", ""))
	if snapshot.has("note"):
		var note: String = str(snapshot.get("note", ""))
		summary["note"] = note
		if note != "":
			notes.append("%s: %s" % [source_name, note])
	source_summaries.append(summary)
	if not available:
		return
	var source_lines: Array = _as_array(snapshot.get("lines", []))
	for line_value: Variant in source_lines:
		var line: Dictionary = _as_dictionary(line_value).duplicate(true)
		line["source"] = source_name
		if snapshot.has("path"):
			line["path"] = str(snapshot.get("path", ""))
		combined_lines.append(line)
		while combined_lines.size() > limit:
			combined_lines.remove_at(0)


func _count_output_level(lines: Array, level: String) -> int:
	var count := 0
	for line_value: Variant in lines:
		var line: Dictionary = _as_dictionary(line_value)
		if str(line.get("level", "")) == level:
			count += 1
	return count


func _find_editor_log(root: Node) -> Node:
	if root == null:
		return null
	return _find_node_by_class_name(root, "EditorLog", 0, 32)


func _clear_editor_log_state(root: Node) -> Dictionary:
	var editor_log: Node = _find_editor_log(root)
	if editor_log == null:
		return {"cleared": false, "strategy": "editor_log_not_found", "controls": []}
	if editor_log.has_method("_clear_request"):
		editor_log.call("_clear_request")
		return {
			"cleared": true,
			"strategy": "editor_log_clear_request",
			"controls": [{
				"kind": editor_log.get_class(),
				"path": _node_debug_path(editor_log),
				"strategy": "editor_log_clear_request"
			}]
		}
	if editor_log.has_method("clear"):
		editor_log.call("clear")
		return {
			"cleared": true,
			"strategy": "editor_log_clear_method",
			"controls": [{
				"kind": editor_log.get_class(),
				"path": _node_debug_path(editor_log),
				"strategy": "editor_log_clear_method"
			}]
		}
	var clear_button: BaseButton = _find_editor_log_clear_button(editor_log, 0)
	if clear_button != null:
		clear_button.emit_signal("pressed")
		return {
			"cleared": true,
			"strategy": "editor_log_clear_button",
			"controls": [{
				"kind": clear_button.get_class(),
				"path": _node_debug_path(clear_button),
				"strategy": "editor_log_clear_button"
			}]
		}
	return {
		"cleared": false,
		"strategy": "editor_log_clear_unavailable",
		"controls": [],
		"button_candidates": _editor_log_button_candidates(editor_log)
	}


func _find_editor_log_clear_button(node: Node, depth: int) -> BaseButton:
	if node == null or depth > 16:
		return null
	if node is BaseButton:
		var button: BaseButton = node
		if _is_editor_log_clear_button(button):
			return button
	for child: Node in node.get_children():
		var found: BaseButton = _find_editor_log_clear_button(child, depth + 1)
		if found != null:
			return found
	return null


func _is_editor_log_clear_button(button: BaseButton) -> bool:
	var label_text: String = _button_text(button).to_lower()
	var tooltip_text: String = _control_tooltip_text(button).to_lower()
	var name_text: String = str(button.name).to_lower()
	if label_text.contains("clear") or tooltip_text.contains("clear output") or tooltip_text == "clear" or name_text.contains("clear"):
		return true
	var shortcut_text: String = _button_shortcut_text(button).to_lower()
	if shortcut_text.contains("clear_output") or shortcut_text.contains("clear output"):
		return true
	return false


func _button_text(button: BaseButton) -> String:
	if button is Button:
		return (button as Button).text.strip_edges()
	return ""


func _button_shortcut_text(button: BaseButton) -> String:
	var shortcut_value: Variant = button.get("shortcut")
	if shortcut_value == null:
		return ""
	return str(shortcut_value)


func _editor_log_button_candidates(editor_log: Node) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	_collect_editor_log_button_candidates(editor_log, output, 0)
	return output


func _collect_editor_log_button_candidates(node: Node, output: Array[Dictionary], depth: int) -> void:
	if node == null or depth > 20:
		return
	if node is BaseButton:
		var button: BaseButton = node
		output.append({
			"kind": button.get_class(),
			"name": str(button.name),
			"path": _node_debug_path(button),
			"text": _button_text(button),
			"tooltip": _control_tooltip_text(button),
			"toggle_mode": button.toggle_mode,
			"button_pressed": button.button_pressed,
			"shortcut": _button_shortcut_text(button)
		})
	for child: Node in node.get_children():
		_collect_editor_log_button_candidates(child, output, depth + 1)


func _find_largest_text_control_text(root: Node) -> String:
	var text_controls: Array[Dictionary] = []
	_collect_text_controls(root, text_controls, 0)
	var best_text := ""
	var best_length := -1
	for item: Dictionary in text_controls:
		var text: String = str(item.get("text", ""))
		if text.length() > best_length:
			best_length = text.length()
			best_text = text
	return best_text


func _collect_text_controls(node: Node, output: Array[Dictionary], depth: int) -> void:
	if node == null or depth > 20:
		return
	var text: String = _text_control_contents(node)
	if text.strip_edges() != "":
		output.append({
			"kind": node.get_class(),
			"path": _node_debug_path(node),
			"text": text
		})
	for child: Node in node.get_children():
		_collect_text_controls(child, output, depth + 1)


func _text_control_contents(node: Node) -> String:
	if node is RichTextLabel:
		var rich_label: RichTextLabel = node
		return rich_label.get_parsed_text()
	if node is TextEdit:
		var text_edit: TextEdit = node
		return text_edit.text
	if node is ItemList:
		var item_list: ItemList = node
		var lines: Array[String] = []
		for index: int in range(0, item_list.get_item_count()):
			lines.append(item_list.get_item_text(index))
		return _join_values(lines, "\n")
	return ""


func _editor_log_category_counters(editor_log: Node) -> Array[Dictionary]:
	var counters: Array[Dictionary] = []
	if editor_log == null:
		return counters
	_collect_editor_log_counter_controls(editor_log, counters, 0)
	return counters


func _collect_editor_log_counter_controls(node: Node, output: Array[Dictionary], depth: int) -> void:
	if node == null or depth > 20:
		return
	var counter_text: String = _counter_text_for_node(node)
	if counter_text != "" and counter_text.is_valid_int():
		var value: int = int(counter_text)
		output.append({
			"kind": node.get_class(),
			"name": str(node.name),
			"path": _node_debug_path(node),
			"text": counter_text,
			"value": value,
			"tooltip": _control_tooltip_text(node)
		})
	for child: Node in node.get_children():
		_collect_editor_log_counter_controls(child, output, depth + 1)


func _counter_text_for_node(node: Node) -> String:
	if node is Button:
		var button: Button = node
		return button.text.strip_edges()
	if node is Label:
		var label: Label = node
		return label.text.strip_edges()
	return ""


func _control_tooltip_text(node: Node) -> String:
	if node is Control:
		var control: Control = node
		return control.tooltip_text
	return ""


func _sum_counter_values(counters: Array[Dictionary]) -> int:
	var total := 0
	for counter: Dictionary in counters:
		total += int(counter.get("value", 0))
	return total


func _count_nonzero_counters(counters: Array[Dictionary]) -> int:
	var count := 0
	for counter: Dictionary in counters:
		if int(counter.get("value", 0)) != 0:
			count += 1
	return count


func _clear_visible_output_controls(root: Node) -> Array[Dictionary]:
	var cleared_controls: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	_collect_editor_output_candidates(root, candidates, 0)
	var visited: Dictionary = {}
	for candidate: Dictionary in candidates:
		var node_value: Variant = candidate.get("node", null)
		if not node_value is Node:
			continue
		var node: Node = node_value
		var key: String = str(node.get_instance_id())
		if visited.has(key):
			continue
		visited[key] = true
		if _clear_output_candidate_node(node):
			cleared_controls.append({
				"kind": node.get_class(),
				"path": _node_debug_path(node),
				"score": int(candidate.get("score", 0)),
				"strategy": "visible_control"
			})
	return cleared_controls


func _clear_debugger_error_trees(root: Node) -> Array[Dictionary]:
	var cleared_controls: Array[Dictionary] = []
	var debugger_node: Node = _find_node_by_class_name(root, "ScriptEditorDebugger", 0, 32)
	if debugger_node == null:
		return cleared_controls
	var trees: Array[Tree] = []
	_collect_debugger_error_trees(debugger_node, trees, 0)
	for tree: Tree in trees:
		tree.clear()
		cleared_controls.append({
			"kind": tree.get_class(),
			"path": _node_debug_path(tree),
			"strategy": "debugger_error_tree_clear"
		})
	return cleared_controls


func _clear_output_candidate_node(node: Node) -> bool:
	if node is RichTextLabel:
		(node as RichTextLabel).clear()
		return true
	if node is TextEdit:
		(node as TextEdit).clear()
		return true
	if node is ItemList:
		(node as ItemList).clear()
		return true
	return false


func _find_editor_output_text(root: Node) -> String:
	var editor_log: Node = _find_editor_log(root)
	if editor_log != null:
		var editor_log_text: String = _find_largest_text_control_text(editor_log)
		if editor_log_text.strip_edges() != "":
			return editor_log_text
	var candidates: Array[Dictionary] = []
	_collect_editor_output_candidates(root, candidates, 0)
	var best_text := ""
	var best_score := -1
	for candidate: Dictionary in candidates:
		var score: int = int(candidate.get("score", 0))
		var text: String = str(candidate.get("text", ""))
		if text.strip_edges() == "":
			continue
		if score > best_score:
			best_score = score
			best_text = text
	return best_text


func _editor_output_candidate_summaries(root: Node, limit: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	_collect_editor_output_candidates(root, candidates, 0)
	var summaries: Array[Dictionary] = []
	var used: Dictionary = {}
	while summaries.size() < limit and summaries.size() < candidates.size():
		var best_index := -1
		var best_score := -999999
		for index: int in range(0, candidates.size()):
			if used.has(index):
				continue
			var candidate_score := int(candidates[index].get("score", 0))
			if candidate_score > best_score:
				best_score = candidate_score
				best_index = index
		if best_index < 0:
			break
		used[best_index] = true
		var candidate: Dictionary = candidates[best_index]
		var text: String = str(candidate.get("text", "")).strip_edges()
		summaries.append({
			"score": int(candidate.get("score", 0)),
			"kind": str(candidate.get("kind", "")),
			"path": str(candidate.get("path", "")),
			"line_count": int(candidate.get("line_count", 0)),
			"sample": text.substr(0, mini(180, text.length()))
		})
	return summaries


func _collect_editor_output_candidates(node: Node, candidates: Array[Dictionary], depth: int) -> void:
	if depth > 28:
		return
	var text: String = _output_candidate_text(node)
	if text.strip_edges() != "":
		var score: int = _output_candidate_score(node, text)
		if score > 0:
			candidates.append({
				"node": node,
				"kind": node.get_class(),
				"path": _node_debug_path(node),
				"text": text,
				"score": score,
				"line_count": text.split("\n", false).size()
			})
	for child: Node in node.get_children():
		_collect_editor_output_candidates(child, candidates, depth + 1)


func _find_node_by_class_name(node: Node, target_class: String, depth: int, max_depth: int) -> Node:
	if node == null or depth > max_depth:
		return null
	if node.get_class() == target_class:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_node_by_class_name(child, target_class, depth + 1, max_depth)
		if found != null:
			return found
	return null


func _collect_debugger_error_trees(node: Node, output: Array[Tree], depth: int) -> void:
	if node == null or depth > 24:
		return
	if node is Tree and _has_named_ancestor(node, "error", 8):
		output.append(node as Tree)
		return
	for child: Node in node.get_children():
		_collect_debugger_error_trees(child, output, depth + 1)


func _collect_debugger_trees(node: Node, output: Array[Tree], depth: int) -> void:
	if node == null or depth > 24:
		return
	if node is Tree:
		output.append(node as Tree)
	for child: Node in node.get_children():
		_collect_debugger_trees(child, output, depth + 1)


func _has_named_ancestor(node: Node, marker: String, max_depth: int) -> bool:
	var current: Node = node
	var depth := 0
	while current != null and depth < max_depth:
		if str(current.name).to_lower().contains(marker):
			return true
		current = current.get_parent()
		depth += 1
	return false


func _collect_debugger_tree_lines(item: TreeItem, output: Array[String], column_count: int) -> void:
	var current: TreeItem = item
	while current != null:
		var text: String = _debugger_tree_item_text(current, column_count)
		if text != "":
			output.append(text)
		var child: TreeItem = current.get_first_child()
		if child != null:
			_collect_debugger_tree_lines(child, output, column_count)
		current = current.get_next()


func _debugger_tree_item_text(item: TreeItem, column_count: int) -> String:
	var parts: Array[String] = []
	for column: int in range(0, column_count):
		var text: String = item.get_text(column).strip_edges()
		if text != "":
			parts.append(text)
	return _join_values(parts, " ")


func _stack_tree_score(tree: Tree, lines: Array[String]) -> int:
	var score := 0
	if _has_named_ancestor(tree, "stack", 10):
		score += 100
	for line: String in lines:
		var lower_line: String = line.to_lower()
		if lower_line.contains("res://") and (lower_line.contains(".gd") or lower_line.contains(".cs")):
			score += 60
		if lower_line.contains("function") or lower_line.contains("_ready") or lower_line.contains("_process"):
			score += 10
		if lower_line.contains("error") and not lower_line.contains("res://"):
			score -= 10
	return score


func _stack_frame_from_text(text: String, index: int) -> Dictionary:
	var trimmed: String = text.strip_edges()
	if trimmed == "":
		return {}
	var lower_text: String = trimmed.to_lower()
	var path_start: int = lower_text.find("res://")
	if path_start < 0:
		return {
			"id": index,
			"raw": trimmed
		}
	var path_end: int = _script_path_end(trimmed, path_start)
	if path_end <= path_start:
		return {
			"id": index,
			"raw": trimmed
		}
	var file_path: String = trimmed.substr(path_start, path_end - path_start)
	var line_number := 0
	if path_end < trimmed.length():
		line_number = read_positive_int_at(trimmed, path_end)
	return {
		"id": index,
		"file": file_path,
		"line": line_number,
		"function": _stack_function_from_text(trimmed),
		"raw": trimmed
	}


func _script_path_end(text: String, start: int) -> int:
	var markers: Array[String] = [".gdshader", ".gd", ".cs"]
	var best := -1
	var best_length := 0
	var lower_text: String = text.to_lower()
	for marker: String in markers:
		var found: int = lower_text.find(marker, start)
		if found >= 0 and (best < 0 or found < best):
			best = found
			best_length = marker.length()
	if best < 0:
		return -1
	return best + best_length


func _stack_function_from_text(text: String) -> String:
	var markers: Array[String] = ["function ", "func ", " in "]
	var lower_text: String = text.to_lower()
	for marker: String in markers:
		var index: int = lower_text.find(marker)
		if index < 0:
			continue
		var value: String = text.substr(index + marker.length()).strip_edges()
		value = value.replace("\"", "").replace("'", "")
		if value.length() > 120:
			value = value.substr(0, 120)
		return value
	return ""


func _snapshot_has_event(events: Array, message_name: String) -> bool:
	for value: Variant in events:
		var event: Dictionary = _as_dictionary(value)
		if str(event.get("message", "")) == message_name:
			return true
	return false


func _output_candidate_text(node: Node) -> String:
	if node is RichTextLabel:
		var rich_label: RichTextLabel = node
		return rich_label.get_parsed_text()
	if node is TextEdit:
		var text_edit: TextEdit = node
		return text_edit.text
	if node is ItemList:
		var item_list: ItemList = node
		var lines: Array[String] = []
		for index: int in range(0, item_list.get_item_count()):
			lines.append(item_list.get_item_text(index))
		return _join_values(lines, "\n")
	if node is Label:
		var label: Label = node
		return label.text
	return ""


func _output_candidate_score(node: Node, text: String) -> int:
	var score := 0
	var lower_text: String = text.to_lower()
	var line_count: int = text.split("\n", false).size()
	var has_output_error: bool = (
		lower_text.begins_with("error:")
		or lower_text.begins_with("e ")
		or lower_text.contains("\nerror:")
		or lower_text.contains("\ne ")
		or lower_text.contains(" error: res://")
		or lower_text.contains(" error: scene/")
		or lower_text.contains("parse error")
	)
	var has_output_warning: bool = (
		lower_text.begins_with("warning:")
		or lower_text.begins_with("w ")
		or lower_text.contains("\nwarning:")
		or lower_text.contains("\nw ")
		or lower_text.contains(" warning: res://")
	)
	var has_output_marker: bool = (
		has_output_error
		or has_output_warning
		or lower_text.contains("godot ai workbench:")
		or lower_text.contains("debug adapter server")
		or lower_text.contains("gdscript language server")
	)
	if not has_output_marker:
		return -1000
	if node is Label and line_count <= 1 and not lower_text.contains("godot ai workbench:"):
		return -1000
	if has_output_error:
		score += 220
	if has_output_warning:
		score += 140
	if lower_text.contains("godot ai workbench:"):
		score += 120
	if lower_text.contains("debug adapter server") or lower_text.contains("gdscript language server"):
		score += 90
	score += mini(line_count, 30)
	if line_count <= 1 and lower_text.contains("error:") and not has_output_error:
		score -= 180
	if lower_text.begins_with("class ") and line_count <= 2:
		score -= 120
	var current: Node = node
	var depth := 0
	while current != null and depth < 12:
		var node_name := str(current.name).to_lower()
		if node_name.contains("output"):
			score += 45
		if node_name.contains("log"):
			score += 25
		if node_name.contains("debug"):
			score += 8
		if node_name.contains("inspector") or node_name.contains("documentation") or node_name.contains("help"):
			score -= 25
		current = current.get_parent()
		depth += 1
	return score


func _node_debug_path(node: Node) -> String:
	var names: Array[String] = []
	var current: Node = node
	var depth := 0
	while current != null and depth < 16:
		names.push_front(str(current.name))
		current = current.get_parent()
		depth += 1
	return _join_values(names, "/")


func _infer_output_level(text: String) -> String:
	var lower := text.to_lower().strip_edges()
	if lower.contains(" error") or lower.begins_with("error") or lower.begins_with("e ") or lower.begins_with("e\t") or lower.contains("parse error"):
		return "error"
	if lower.contains(" warning") or lower.begins_with("warning") or lower.begins_with("w ") or lower.begins_with("w\t") or lower.contains("invalid uid"):
		return "warning"
	return "info"


func _infer_debugger_output_level(text: String) -> String:
	var lower := text.to_lower().strip_edges()
	if lower.begins_with("<c++ source>") or lower.begins_with("at:"):
		return "info"
	if lower.contains(" @ ") and not lower.contains("res://"):
		return "info"
	return "error"


func _empty_source(source_name: String, lines: Array[Dictionary], note: String) -> Dictionary:
	return {
		"available": false,
		"source": source_name,
		"line_count": 0,
		"error_count": 0,
		"warning_count": 0,
		"lines": lines,
		"note": note
	}


func _join_values(values: Array, separator: String) -> String:
	var output := ""
	var index := 0
	for value: Variant in values:
		if index > 0:
			output += separator
		output += str(value)
		index += 1
	return output


func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
