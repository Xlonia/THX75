extends RefCounted


func validate_script_resource_path(script_path: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "message": ""}
	var clean: String = script_path.strip_edges().replace("\\", "/")
	if clean == "":
		result["message"] = "script_path is required"
		return result
	if not clean.begins_with("res://"):
		result["message"] = "script_path must be a res:// project path"
		return result
	var virtual_path: String = clean.substr("res://".length())
	if virtual_path == "" or virtual_path.begins_with("/"):
		result["message"] = "script_path must point to a project file"
		return result
	var parts: PackedStringArray = virtual_path.split("/", false)
	for part: String in parts:
		if part == "..":
			result["message"] = "script_path must not contain parent traversal"
			return result
	if clean.get_extension().to_lower() != "gd":
		result["message"] = "editor.attach_script v0 supports .gd scripts only"
		return result
	var absolute_path: String = ProjectSettings.globalize_path(clean)
	if not FileAccess.file_exists(absolute_path):
		result["message"] = "script file does not exist"
		result["absolute_path"] = absolute_path
		return result
	result["ok"] = true
	result["path"] = clean
	result["absolute_path"] = absolute_path
	return result


func script_compatibility(node: Node, script_resource: Script) -> Dictionary:
	var result: Dictionary = {"ok": false, "message": ""}
	if node == null:
		result["message"] = "node is missing"
		return result
	if script_resource == null:
		result["message"] = "script is missing"
		return result
	var base_type: String = script_base_type(script_resource)
	result["script_base_type"] = base_type
	result["node_class"] = node.get_class()
	if base_type == "":
		result["ok"] = true
		result["message"] = "script base type is not reported by Godot"
		return result
	if node.is_class(base_type):
		result["ok"] = true
		result["message"] = "script base type matches node"
		return result
	result["message"] = "script base type %s is not compatible with node class %s" % [base_type, node.get_class()]
	return result


func script_snapshot(script_value: Variant) -> Dictionary:
	if not script_value is Script:
		return {"type": "Nil", "path": "", "class_name": "", "base_type": ""}
	var script_resource: Script = script_value
	return {
		"type": script_resource.get_class(),
		"path": str(script_resource.resource_path),
		"class_name": script_global_name(script_resource),
		"base_type": script_base_type(script_resource)
	}


func script_base_type(script_resource: Script) -> String:
	if script_resource != null and script_resource.has_method("get_instance_base_type"):
		return str(script_resource.call("get_instance_base_type"))
	return ""


func script_global_name(script_resource: Script) -> String:
	if script_resource != null and script_resource.has_method("get_global_name"):
		return str(script_resource.call("get_global_name"))
	return ""


func scripts_equal(left: Variant, right: Variant) -> bool:
	if left == null and right == null:
		return true
	if not left is Script or not right is Script:
		return false
	var left_script: Script = left
	var right_script: Script = right
	if left_script == right_script:
		return true
	var left_path: String = str(left_script.resource_path)
	var right_path: String = str(right_script.resource_path)
	return left_path != "" and left_path == right_path
