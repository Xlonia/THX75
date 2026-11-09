extends RefCounted


func find_writable_property_info(node: Node, property_name: String, details: Dictionary) -> Dictionary:
	if _is_blocked_property_name(property_name):
		details["property_error"] = "property is reserved for a later dedicated workflow"
		return {}
	for property_value: Variant in node.get_property_list():
		if typeof(property_value) != TYPE_DICTIONARY:
			continue
		var property_info: Dictionary = property_value
		if str(property_info.get("name", "")) != property_name:
			continue
		var usage: int = int(property_info.get("usage", 0))
		details["property_usage"] = usage
		details["property_hint"] = int(property_info.get("hint", 0))
		details["property_type_id"] = int(property_info.get("type", TYPE_NIL))
		if (usage & PROPERTY_USAGE_READ_ONLY) != 0:
			details["property_error"] = "property is read-only"
			return {}
		if (usage & PROPERTY_USAGE_STORAGE) == 0 and (usage & PROPERTY_USAGE_EDITOR) == 0:
			details["property_error"] = "property is not an inspector/storage property"
			return {}
		return property_info
	details["property_error"] = "property not found"
	return {}


func parse_property_value(raw_value: Variant, property_info: Dictionary, old_value: Variant) -> Dictionary:
	var target_type: int = int(property_info.get("type", typeof(old_value)))
	if target_type == TYPE_NIL:
		target_type = typeof(old_value)
	match target_type:
		TYPE_BOOL:
			return _parse_bool_value(raw_value)
		TYPE_INT:
			return _parse_int_value(raw_value)
		TYPE_FLOAT:
			return _parse_float_value(raw_value)
		TYPE_STRING:
			return {
				"ok": true,
				"value": str(raw_value),
				"type_name": "String"
			}
		TYPE_VECTOR2:
			return _parse_vector2_value(raw_value)
		TYPE_COLOR:
			return _parse_color_value(raw_value)
		_:
			return {
				"ok": false,
				"message": "unsupported Stage 9.2 property type: %s" % variant_type_name(target_type),
				"type_name": variant_type_name(target_type)
			}


func variant_snapshot(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return {"type": variant_type_name(typeof(value)), "value": value}
		TYPE_VECTOR2:
			var vector: Vector2 = value
			return {"type": "Vector2", "value": {"x": vector.x, "y": vector.y}}
		TYPE_COLOR:
			var color: Color = value
			return {
				"type": "Color",
				"value": {"r": color.r, "g": color.g, "b": color.b, "a": color.a, "html": "#%s" % color.to_html(true)}
			}
		TYPE_ARRAY:
			var array_values: Array = []
			for item: Variant in _as_array(value):
				array_values.append(variant_snapshot(item))
			return {"type": "Array", "value": array_values}
		TYPE_DICTIONARY:
			var dictionary_values: Dictionary = {}
			var dictionary: Dictionary = _as_dictionary(value)
			for key: Variant in dictionary.keys():
				dictionary_values[str(key)] = variant_snapshot(dictionary[key])
			return {"type": "Dictionary", "value": dictionary_values}
		_:
			return {"type": variant_type_name(typeof(value)), "value": str(value)}


func variants_equal(left: Variant, right: Variant) -> bool:
	var left_type: int = typeof(left)
	var right_type: int = typeof(right)
	if left_type == TYPE_INT and right_type == TYPE_FLOAT:
		return abs(float(left) - float(right)) <= 0.00001
	if left_type == TYPE_FLOAT and right_type == TYPE_INT:
		return abs(float(left) - float(right)) <= 0.00001
	if left_type != right_type:
		return false
	match left_type:
		TYPE_FLOAT:
			return abs(float(left) - float(right)) <= 0.00001
		TYPE_VECTOR2:
			var left_vector: Vector2 = left
			var right_vector: Vector2 = right
			return left_vector.distance_to(right_vector) <= 0.00001
		TYPE_COLOR:
			var left_color: Color = left
			var right_color: Color = right
			return (
				abs(left_color.r - right_color.r) <= 0.00001
				and abs(left_color.g - right_color.g) <= 0.00001
				and abs(left_color.b - right_color.b) <= 0.00001
				and abs(left_color.a - right_color.a) <= 0.00001
			)
		_:
			return left == right


func property_type_name(property_info: Dictionary, old_value: Variant) -> String:
	var target_type: int = int(property_info.get("type", typeof(old_value)))
	if target_type == TYPE_NIL:
		target_type = typeof(old_value)
	return variant_type_name(target_type)


func variant_type_name(type_id: int) -> String:
	match type_id:
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
		TYPE_COLOR:
			return "Color"
		TYPE_ARRAY:
			return "Array"
		TYPE_DICTIONARY:
			return "Dictionary"
		_:
			return "Variant(%d)" % type_id


func _is_blocked_property_name(property_name: String) -> bool:
	var blocked: Array[String] = [
		"name",
		"owner",
		"script",
		"scene_file_path",
		"unique_name_in_owner"
	]
	return blocked.has(property_name)


func _parse_bool_value(raw_value: Variant) -> Dictionary:
	match typeof(raw_value):
		TYPE_BOOL:
			return {"ok": true, "value": raw_value == true, "type_name": "bool"}
		TYPE_INT:
			return {"ok": true, "value": int(raw_value) != 0, "type_name": "bool"}
		TYPE_FLOAT:
			return {"ok": true, "value": float(raw_value) != 0.0, "type_name": "bool"}
		TYPE_STRING:
			var text: String = str(raw_value).strip_edges().to_lower()
			if text == "true" or text == "1" or text == "yes":
				return {"ok": true, "value": true, "type_name": "bool"}
			if text == "false" or text == "0" or text == "no":
				return {"ok": true, "value": false, "type_name": "bool"}
	return {"ok": false, "message": "expected bool-compatible value", "type_name": "bool"}


func _parse_int_value(raw_value: Variant) -> Dictionary:
	var parsed: Dictionary = _number_from_variant(raw_value)
	if parsed.get("ok", false) != true:
		parsed["type_name"] = "int"
		return parsed
	var number: float = float(parsed.get("value", 0.0))
	var rounded: float = round(number)
	if abs(number - rounded) > 0.00001:
		return {"ok": false, "message": "expected integer value", "type_name": "int"}
	return {"ok": true, "value": int(rounded), "type_name": "int"}


func _parse_float_value(raw_value: Variant) -> Dictionary:
	var parsed: Dictionary = _number_from_variant(raw_value)
	if parsed.get("ok", false) != true:
		parsed["type_name"] = "float"
		return parsed
	return {"ok": true, "value": float(parsed.get("value", 0.0)), "type_name": "float"}


func _parse_vector2_value(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) == TYPE_VECTOR2:
		return {"ok": true, "value": raw_value, "type_name": "Vector2"}
	var x_value: Dictionary = {}
	var y_value: Dictionary = {}
	if typeof(raw_value) == TYPE_ARRAY:
		var values: Array = _as_array(raw_value)
		if values.size() != 2:
			return {"ok": false, "message": "Vector2 array must contain exactly 2 numbers", "type_name": "Vector2"}
		x_value = _number_from_variant(values[0])
		y_value = _number_from_variant(values[1])
	elif typeof(raw_value) == TYPE_DICTIONARY:
		var data: Dictionary = _as_dictionary(raw_value)
		x_value = _number_from_variant(data.get("x"))
		y_value = _number_from_variant(data.get("y"))
	elif typeof(raw_value) == TYPE_STRING:
		var list_result: Dictionary = _parse_float_list_text(str(raw_value), 2, 2)
		if list_result.get("ok", false) != true:
			list_result["type_name"] = "Vector2"
			return list_result
		var list_values: Array = _as_array(list_result.get("values", []))
		return {"ok": true, "value": Vector2(float(list_values[0]), float(list_values[1])), "type_name": "Vector2"}
	else:
		return {"ok": false, "message": "expected Vector2 as array, object or string", "type_name": "Vector2"}
	if x_value.get("ok", false) != true or y_value.get("ok", false) != true:
		return {"ok": false, "message": "Vector2 components must be numbers", "type_name": "Vector2"}
	return {"ok": true, "value": Vector2(float(x_value.get("value", 0.0)), float(y_value.get("value", 0.0))), "type_name": "Vector2"}


func _parse_color_value(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) == TYPE_COLOR:
		return {"ok": true, "value": raw_value, "type_name": "Color"}
	if typeof(raw_value) == TYPE_STRING:
		var color_text: String = str(raw_value).strip_edges()
		if color_text.begins_with("#"):
			return _parse_color_hex(color_text)
		var list_result: Dictionary = _parse_float_list_text(color_text, 3, 4)
		if list_result.get("ok", false) != true:
			list_result["type_name"] = "Color"
			return list_result
		var list_values: Array = _as_array(list_result.get("values", []))
		var alpha := 1.0
		if list_values.size() == 4:
			alpha = _normalize_color_component(float(list_values[3]))
		return {
			"ok": true,
			"value": Color(
				_normalize_color_component(float(list_values[0])),
				_normalize_color_component(float(list_values[1])),
				_normalize_color_component(float(list_values[2])),
				alpha
			),
			"type_name": "Color"
		}
	var components: Array = []
	if typeof(raw_value) == TYPE_ARRAY:
		components = _as_array(raw_value)
	elif typeof(raw_value) == TYPE_DICTIONARY:
		var data: Dictionary = _as_dictionary(raw_value)
		components = [data.get("r"), data.get("g"), data.get("b"), data.get("a", 1.0)]
	else:
		return {"ok": false, "message": "expected Color as hex string, array or object", "type_name": "Color"}
	if components.size() != 3 and components.size() != 4:
		return {"ok": false, "message": "Color value must contain 3 or 4 components", "type_name": "Color"}
	var parsed_components: Array[float] = []
	for component: Variant in components:
		var parsed: Dictionary = _number_from_variant(component)
		if parsed.get("ok", false) != true:
			return {"ok": false, "message": "Color components must be numbers", "type_name": "Color"}
		parsed_components.append(_normalize_color_component(float(parsed.get("value", 0.0))))
	if parsed_components.size() == 3:
		parsed_components.append(1.0)
	return {
		"ok": true,
		"value": Color(parsed_components[0], parsed_components[1], parsed_components[2], parsed_components[3]),
		"type_name": "Color"
	}


func _parse_float_list_text(text: String, min_count: int, max_count: int) -> Dictionary:
	var clean: String = text.strip_edges()
	clean = clean.replace("Vector2", "").replace("Color", "").replace("(", "").replace(")", "")
	var parts: PackedStringArray = clean.split(",", false)
	if parts.size() < min_count or parts.size() > max_count:
		return {"ok": false, "message": "expected %d-%d numeric components" % [min_count, max_count]}
	var values: Array[float] = []
	for part: String in parts:
		var parsed: Dictionary = _number_from_variant(part.strip_edges())
		if parsed.get("ok", false) != true:
			return {"ok": false, "message": "all components must be numbers"}
		values.append(float(parsed.get("value", 0.0)))
	return {"ok": true, "values": values}


func _parse_color_hex(text: String) -> Dictionary:
	var clean: String = text.strip_edges()
	if clean.begins_with("#"):
		clean = clean.substr(1)
	if clean.length() != 6 and clean.length() != 8:
		return {"ok": false, "message": "Color hex must be #RRGGBB or #RRGGBBAA", "type_name": "Color"}
	var red: Dictionary = _hex_byte(clean.substr(0, 2))
	var green: Dictionary = _hex_byte(clean.substr(2, 2))
	var blue: Dictionary = _hex_byte(clean.substr(4, 2))
	var alpha_value := 255
	if clean.length() == 8:
		var alpha: Dictionary = _hex_byte(clean.substr(6, 2))
		if alpha.get("ok", false) != true:
			return {"ok": false, "message": "invalid Color alpha hex", "type_name": "Color"}
		alpha_value = int(alpha.get("value", 255))
	if red.get("ok", false) != true or green.get("ok", false) != true or blue.get("ok", false) != true:
		return {"ok": false, "message": "invalid Color hex", "type_name": "Color"}
	return {
		"ok": true,
		"value": Color(
			float(red.get("value", 0)) / 255.0,
			float(green.get("value", 0)) / 255.0,
			float(blue.get("value", 0)) / 255.0,
			float(alpha_value) / 255.0
		),
		"type_name": "Color"
	}


func _hex_byte(text: String) -> Dictionary:
	var high: int = _hex_digit_value(text.substr(0, 1))
	var low: int = _hex_digit_value(text.substr(1, 1))
	if high < 0 or low < 0:
		return {"ok": false}
	return {"ok": true, "value": high * 16 + low}


func _hex_digit_value(text: String) -> int:
	var lower: String = text.to_lower()
	var digits := "0123456789abcdef"
	return digits.find(lower)


func _number_from_variant(raw_value: Variant) -> Dictionary:
	match typeof(raw_value):
		TYPE_INT:
			return {"ok": true, "value": float(int(raw_value))}
		TYPE_FLOAT:
			return {"ok": true, "value": float(raw_value)}
		TYPE_STRING:
			var text: String = str(raw_value).strip_edges()
			if text.is_valid_float():
				return {"ok": true, "value": text.to_float()}
	return {"ok": false, "message": "expected numeric value"}


func _normalize_color_component(value: float) -> float:
	var normalized := value
	if normalized > 1.0:
		normalized = normalized / 255.0
	return clampf(normalized, 0.0, 1.0)


func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
