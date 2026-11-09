@tool
extends StateEntity
## Makes an entity follow a target. The entity won't avoids obstacles. Use a StateNavigation instead.
class_name StateFollow

@export var target_manager: TargetManager
@export var flee := false: ## If true, entity will flee away from the target instead of following it.
	set(value):
		flee = value
		if entity:
			entity.invert_moving_direction = value

func enter():
	super.enter()
	entity.invert_moving_direction = flee

func exit():
	super.exit()
	entity.invert_moving_direction = false

func physics_update(_delta):
	_follow()

func _follow():
	if entity and target_manager:
		entity.move_towards(target_manager.get_target_position())
