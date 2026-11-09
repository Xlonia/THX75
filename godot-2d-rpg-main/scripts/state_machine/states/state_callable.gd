@tool
@icon("../icons/StateCallable.svg")
##Call a method by name from any node.
class_name StateCallable
extends State

@export var node: Node ## The target node on which the method will be called.
@export var node_path: String ## An alternative way to reference the target node via a NodePath.
@export var method_name: String ## The name of the method to invoke on the target node.
@export var method_params: Array[Variant] = [] ## An array of parameters to pass when calling the method.
@export var send_statemachine_params := true: ## If true, method calls will include parameters from the state machine.
	set(value):
		send_statemachine_params = value
		notify_property_list_changed()
@export var await_signal_to_complete := "" ## If set, the state will wait for this signal to be emitted on the target node before completing.

func enter():
	if !_check_node():
		return
	if await_signal_to_complete != "":
		if node.has_signal(await_signal_to_complete):
			if !node.is_connected(await_signal_to_complete, complete):
				node.connect(await_signal_to_complete, complete)
		else:
			push_warning("No signal '%s' in %s" % [await_signal_to_complete, node.get_path()])
	else:
		complete.call_deferred()
	_call_method_by_name()

func _check_node():
	if node_path != "":
		node = get_node_or_null(node_path)
		if node == null:
			push_warning("No node found at %s" % [node_path])
			return false
	if node == null:
		push_warning("No node set in %s" % [get_path()])
		return false
	return true

func _call_method_by_name():
	var callable = Callable(node, method_name)
	if is_instance_valid(node) and callable.is_valid():
		print("Calling method %s from %s" % [method_name, node.name])
		if method_params.size() > 0:
			callable.callv.call_deferred(method_params)
		elif send_statemachine_params:
			callable.call.call_deferred(state_machine.params)
		else:
			callable.call.call_deferred()
	else:
		push_warning("%s: Invalid method name" % [get_path()])

func _validate_property(property: Dictionary) -> void:
	if property.name == "method_params":
		if send_statemachine_params:
			property.usage = PROPERTY_USAGE_NONE
	if property.name == "node":
		if !node_path.is_empty():
			property.usage = PROPERTY_USAGE_NONE ## Hide the 'node' property if 'node_path' is set.
	if property.name == "node_path":
		if node != null:
			property.usage = PROPERTY_USAGE_NONE ## Hide the 'node_path' property if 'node' is set.
