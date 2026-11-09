extends RefCounted

var _host


func setup(host) -> void:
	_host = host


func handled_commands() -> Array:
	return ["debug.classdb_lookup", "debug.performance_snapshot"]


func handle(command: Dictionary) -> bool:
	match str(command.get("command", "")):
		"debug.classdb_lookup":
			var lookup: Dictionary = _classdb_lookup(command.get("args", {}))
			var status: String = "ok" if bool(lookup.get("ok", false)) else "error"
			var message: String = str(lookup.get("message", "ClassDB lookup"))
			_host.call("add_operation", "Dev control: ClassDB lookup")
			_host.call("ack_dev_command", command, status, message, lookup)
			return true
		"debug.performance_snapshot":
			var snapshot: Dictionary = _native_performance_snapshot(command.get("args", {}))
			var snapshot_status: String = "ok" if bool(snapshot.get("ok", false)) else "error"
			var snapshot_message: String = str(snapshot.get("message", "Performance snapshot"))
			_host.call("add_operation", "Dev control: performance snapshot")
			_host.call("ack_dev_command", command, snapshot_status, snapshot_message, snapshot)
			return true
	return false


func _classdb_lookup(args: Variant) -> Dictionary:
	var input: Dictionary = {}
	if args is Dictionary:
		input = args
	var target_type: String = str(input.get("class_name", "")).strip_edges()
	var max_items: int = clampi(int(input.get("max_items", 80)), 1, 300)
	var include_inherited: bool = bool(input.get("include_inherited", false))
	if target_type == "":
		return {
			"ok": false,
			"exists": false,
			"message": "class_name is required"
		}
	if not ClassDB.class_exists(target_type):
		return {
			"ok": true,
			"exists": false,
			"class_name": target_type,
			"message": "ClassDB class not found"
		}
	var no_inheritance: bool = not include_inherited
	var methods: Array = ClassDB.class_get_method_list(target_type, no_inheritance)
	var properties: Array = ClassDB.class_get_property_list(target_type, no_inheritance)
	var signals: Array = ClassDB.class_get_signal_list(target_type, no_inheritance)
	var enum_names: PackedStringArray = ClassDB.class_get_enum_list(target_type, no_inheritance)
	var constants: PackedStringArray = ClassDB.class_get_integer_constant_list(target_type, no_inheritance)
	return {
		"ok": true,
		"exists": true,
		"class_name": target_type,
		"parent_class": str(ClassDB.get_parent_class(target_type)),
		"can_instantiate": ClassDB.can_instantiate(target_type),
		"is_node": target_type == "Node" or ClassDB.is_parent_class(target_type, "Node"),
		"is_resource": target_type == "Resource" or ClassDB.is_parent_class(target_type, "Resource"),
		"include_inherited": include_inherited,
		"max_items": max_items,
		"method_count": methods.size(),
		"property_count": properties.size(),
		"signal_count": signals.size(),
		"enum_count": enum_names.size(),
		"constant_count": constants.size(),
		"methods": _trim_method_list(methods, max_items),
		"properties": _trim_property_list(properties, max_items),
		"signals": _trim_signal_list(signals, max_items),
		"enums": _trim_string_list(enum_names, max_items),
		"constants": _trim_string_list(constants, max_items),
		"truncated": methods.size() > max_items or properties.size() > max_items or signals.size() > max_items or enum_names.size() > max_items or constants.size() > max_items,
		"message": "ClassDB lookup ok"
	}


func _trim_method_list(items: Array, max_items: int) -> Array:
	var result: Array = []
	for item: Variant in items:
		if result.size() >= max_items:
			break
		if item is Dictionary:
			var method: Dictionary = item
			result.append({
				"name": str(method.get("name", "")),
				"return": _variant_type_name(method.get("return", {})),
				"args": _trim_argument_list(method.get("args", [])),
				"flags": int(method.get("flags", 0))
			})
	return result


func _trim_property_list(items: Array, max_items: int) -> Array:
	var result: Array = []
	for item: Variant in items:
		if result.size() >= max_items:
			break
		if item is Dictionary:
			var property_info: Dictionary = item
			result.append({
				"name": str(property_info.get("name", "")),
				"type": int(property_info.get("type", TYPE_NIL)),
				"class_name": str(property_info.get("class_name", "")),
				"hint": int(property_info.get("hint", 0)),
				"hint_string": str(property_info.get("hint_string", "")),
				"usage": int(property_info.get("usage", 0))
			})
	return result


func _trim_signal_list(items: Array, max_items: int) -> Array:
	var result: Array = []
	for item: Variant in items:
		if result.size() >= max_items:
			break
		if item is Dictionary:
			var signal_info: Dictionary = item
			result.append({
				"name": str(signal_info.get("name", "")),
				"args": _trim_argument_list(signal_info.get("args", []))
			})
	return result


func _trim_argument_list(items: Variant) -> Array:
	var result: Array = []
	if not (items is Array):
		return result
	for item: Variant in items:
		if result.size() >= 24:
			break
		if item is Dictionary:
			var argument: Dictionary = item
			result.append({
				"name": str(argument.get("name", "")),
				"type": int(argument.get("type", TYPE_NIL)),
				"class_name": str(argument.get("class_name", "")),
				"hint": int(argument.get("hint", 0)),
				"hint_string": str(argument.get("hint_string", ""))
			})
	return result


func _trim_string_list(items: PackedStringArray, max_items: int) -> Array:
	var result: Array = []
	for item: String in items:
		if result.size() >= max_items:
			break
		result.append(item)
	return result


func _variant_type_name(value: Variant) -> String:
	if value is Dictionary:
		var data: Dictionary = value
		if data.has("class_name") and str(data.get("class_name", "")) != "":
			return str(data.get("class_name", ""))
		return str(data.get("type", TYPE_NIL))
	return str(value)


func _native_performance_snapshot(args: Variant) -> Dictionary:
	var input: Dictionary = {}
	if args is Dictionary:
		input = args
	var category_filter: String = str(input.get("category", "")).strip_edges().to_lower()
	var max_items: int = clampi(int(input.get("max_items", 80)), 1, 120)
	var monitors: Array[Dictionary] = _performance_monitor_rows()
	var filtered: Array[Dictionary] = []
	for monitor: Dictionary in monitors:
		var category: String = str(monitor.get("category", ""))
		if category_filter != "" and category != category_filter:
			continue
		filtered.append(monitor)
	var total_count: int = filtered.size()
	var returned: Array[Dictionary] = []
	for monitor: Dictionary in filtered:
		if returned.size() >= max_items:
			break
		returned.append(monitor)
	return {
		"ok": true,
		"schema_version": "gaw.performance_snapshot.v0",
		"captured_at": Time.get_datetime_string_from_system(false, true),
		"category": category_filter,
		"max_items": max_items,
		"monitor_count": total_count,
		"returned_count": returned.size(),
		"omitted_count": maxi(0, total_count - returned.size()),
		"truncated": returned.size() < total_count,
		"summary": _performance_summary(monitors),
		"monitors": returned,
		"message": "Performance snapshot ok"
	}


func _performance_summary(monitors: Array[Dictionary]) -> Dictionary:
	var by_name: Dictionary = {}
	for monitor: Dictionary in monitors:
		by_name[str(monitor.get("name", ""))] = monitor.get("value", 0.0)
	return {
		"fps": by_name.get("time_fps", 0.0),
		"frame_process_msec": by_name.get("time_process_msec", 0.0),
		"physics_process_msec": by_name.get("time_physics_process_msec", 0.0),
		"static_memory_mb": by_name.get("memory_static_mb", 0.0),
		"object_count": by_name.get("object_count", 0.0),
		"node_count": by_name.get("object_node_count", 0.0),
		"orphan_node_count": by_name.get("object_orphan_node_count", 0.0),
		"render_draw_calls": by_name.get("render_draw_calls_in_frame", 0.0),
		"render_objects": by_name.get("render_objects_in_frame", 0.0),
		"video_memory_mb": by_name.get("render_video_memory_mb", 0.0)
	}


func _performance_monitor_rows() -> Array[Dictionary]:
	return [
		_monitor_row("time", "time_fps", Performance.TIME_FPS, 1.0, ""),
		_monitor_row("time", "time_process_msec", Performance.TIME_PROCESS, 1000.0, "ms"),
		_monitor_row("time", "time_physics_process_msec", Performance.TIME_PHYSICS_PROCESS, 1000.0, "ms"),
		_monitor_row("time", "time_navigation_process_msec", Performance.TIME_NAVIGATION_PROCESS, 1000.0, "ms"),
		_monitor_row("memory", "memory_static_bytes", Performance.MEMORY_STATIC, 1.0, "bytes"),
		_monitor_row("memory", "memory_static_mb", Performance.MEMORY_STATIC, 1.0 / 1048576.0, "mb"),
		_monitor_row("memory", "memory_static_peak_bytes", Performance.MEMORY_STATIC_MAX, 1.0, "bytes"),
		_monitor_row("memory", "memory_static_peak_mb", Performance.MEMORY_STATIC_MAX, 1.0 / 1048576.0, "mb"),
		_monitor_row("object", "object_count", Performance.OBJECT_COUNT, 1.0, ""),
		_monitor_row("object", "object_resource_count", Performance.OBJECT_RESOURCE_COUNT, 1.0, ""),
		_monitor_row("object", "object_node_count", Performance.OBJECT_NODE_COUNT, 1.0, ""),
		_monitor_row("object", "object_orphan_node_count", Performance.OBJECT_ORPHAN_NODE_COUNT, 1.0, ""),
		_monitor_row("render", "render_objects_in_frame", Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, 1.0, ""),
		_monitor_row("render", "render_primitives_in_frame", Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME, 1.0, ""),
		_monitor_row("render", "render_draw_calls_in_frame", Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, 1.0, ""),
		_monitor_row("render", "render_video_memory_bytes", Performance.RENDER_VIDEO_MEM_USED, 1.0, "bytes"),
		_monitor_row("render", "render_video_memory_mb", Performance.RENDER_VIDEO_MEM_USED, 1.0 / 1048576.0, "mb"),
		_monitor_row("physics_2d", "physics_2d_active_objects", Performance.PHYSICS_2D_ACTIVE_OBJECTS, 1.0, ""),
		_monitor_row("physics_2d", "physics_2d_collision_pairs", Performance.PHYSICS_2D_COLLISION_PAIRS, 1.0, ""),
		_monitor_row("physics_2d", "physics_2d_island_count", Performance.PHYSICS_2D_ISLAND_COUNT, 1.0, ""),
		_monitor_row("physics_3d", "physics_3d_active_objects", Performance.PHYSICS_3D_ACTIVE_OBJECTS, 1.0, ""),
		_monitor_row("physics_3d", "physics_3d_collision_pairs", Performance.PHYSICS_3D_COLLISION_PAIRS, 1.0, ""),
		_monitor_row("physics_3d", "physics_3d_island_count", Performance.PHYSICS_3D_ISLAND_COUNT, 1.0, ""),
		_monitor_row("navigation", "navigation_active_maps", Performance.NAVIGATION_ACTIVE_MAPS, 1.0, ""),
		_monitor_row("navigation", "navigation_region_count", Performance.NAVIGATION_REGION_COUNT, 1.0, ""),
		_monitor_row("navigation", "navigation_agent_count", Performance.NAVIGATION_AGENT_COUNT, 1.0, "")
	]


func _monitor_row(category: String, name: String, monitor_id: int, scale: float, unit: String) -> Dictionary:
	return {
		"category": category,
		"name": name,
		"value": Performance.get_monitor(monitor_id) * scale,
		"unit": unit
	}
