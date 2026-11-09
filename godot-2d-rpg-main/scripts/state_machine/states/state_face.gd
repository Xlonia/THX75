## A state that controls the facing direction of an entity.  
## The entity can either face a fixed direction or dynamically face a target position.  
class_name StateFace
extends StateEntity

## The direction the entity should face.
@export var direction: Direction
## If set, the entity will face toward the target position instead of using the specified direction.
@export var target_manager: TargetManager

func enter():
	super.enter()
	if entity and direction:
		entity.facing = direction.to_vector

func physics_update(_delta):
	if entity and target_manager:
		entity.face_towards(target_manager.get_target_position())
