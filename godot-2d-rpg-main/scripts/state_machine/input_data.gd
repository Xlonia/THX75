class_name InputAction
extends Resource

@export var action: String ## The action to listen for, as defined in the Input Map.
@export_enum("Pressed", "Released") var mode := "Pressed" ## The input event mode to listen for.
@export var function_name: String ## The name of the function to call on the target node.
@export var function_args: Array = [] ## An array of arguments to pass when calling the function.

func check_input(event: InputEvent, node_ref: Node):
	if mode == "Pressed" and event.is_action_pressed(action) or mode == "Released" and event.is_action_released(action):
		_call_function(node_ref)

func _call_function(node_ref: Node):
	if !node_ref:
		push_warning("No node set in %s" % [get_path()])
		return
	if function_name.is_empty():
		push_warning("No function name set in %s" % [get_path()])
		return
	if !node_ref.has_method(function_name):
		push_warning("No method '%s' in %s" % [function_name, node_ref.get_path()])
		return
	if function_args.size() > 0:
		node_ref.callv(function_name, function_args)
	else:
		node_ref.call(function_name)
