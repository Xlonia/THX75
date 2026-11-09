extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -400.0


func _process(delta: float) -> void:
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_vel := Input.get_vector("ui_left", "ui_right","ui_up", "ui_down")
	velocity = input_vel * SPEED


	move_and_slide()
