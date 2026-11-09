@icon("../icons/StatePath.svg")
extends StateEntity
##Makes an entity follow a path defined in a Path2D node.
class_name StatePath

@export var path: Path2D
@export var repeats := 0 ## Repeat the path N times. Leave 0 to repeat indefinitely.
@export var distance_threshold := 2.0

@onready var path_curve = path.curve
@onready var current_point_id: int = 0:
	set(value):
		var new_id = value
		if new_id == path_curve.point_count:
			if repeats == 0 or current_repeats < repeats:
				new_id = 0
				current_repeats += 1
			else:
				entity.stop()
			complete()
		current_point_id = new_id

var target_position := Vector2.ZERO
var current_repeats := 1
var can_move := false

func enter():
	super.enter()
	if current_point_id >= path_curve.point_count:
		current_point_id = 0
	_set_target_position()

func update(_delta: float):
	_check_point_reached()

func _set_target_position():
	target_position = path_curve.get_point_position(current_point_id) + path.global_position

func physics_update(_delta: float):
	can_move = is_instance_valid(entity) and current_point_id < path_curve.point_count
	if can_move:
		entity.move_towards(target_position)

func _check_point_reached():
	if !can_move:
		return
	var distance = entity.global_position.distance_to(target_position)
	if distance < distance_threshold:
		current_point_id += 1
		if current_point_id < path_curve.point_count:
			_set_target_position()
