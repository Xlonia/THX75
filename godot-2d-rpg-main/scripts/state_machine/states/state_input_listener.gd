@icon("../icons/StateInputListener.svg")
## This state listens for input actions and calls a method on a target node when the input is detected.
class_name StateInputListener
extends State

@export var node_ref: Node ## The target node on which the method will be called.
@export var input_actions: Array[InputAction] = [] ## An array of input actions to listen for.

func handle_input(event: InputEvent):
	if !event.is_action_type():
		return
	for input_data in input_actions:
		input_data.check_input(event, node_ref)
