## Moves and controls an entity through inputs.
class_name StateInputMove
extends StateEntity

@export var run_speed_increment := 1.5

func physics_update(_delta):
	if entity and entity.input_enabled:
		_handle_inputs()

func _handle_inputs():
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	entity.speed_multiplier = run_speed_increment if Input.get_action_strength("run") > 0 else 1.0
	entity.move(input_dir)
