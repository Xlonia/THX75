extends StateEntity
##Makes an entity wander around randomly.
class_name StateWander

## The time range (min: x, max: y) for changing the entity's wandering direction.  
## A new direction is chosen after a random duration within this range.  
@export var wander_time_range: = Vector2.ZERO  

var wander_time: float
var direction = Vector2.ZERO

func enter():
	super.enter()
	_wander()

func update(delta: float):
	if wander_time > 0 and not entity.is_blocked:
		wander_time -= delta
	else:
		_wander()

func physics_update(_delta: float):
	entity.move(direction)

func _wander():
	direction = Vector2(randf_range(-1, 1), randf_range(-1 , 1)).normalized()
	wander_time = randf_range(wander_time_range.x, wander_time_range.y)
