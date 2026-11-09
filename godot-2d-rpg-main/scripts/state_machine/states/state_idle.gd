extends StateEntity
##Stops an entity.
class_name StateIdle

@export var disable_entity := false

func enter():
	super.enter()
	if entity:
		entity.stop()
		entity.disable_entity(disable_entity)

func exit():
	if entity and disable_entity:
		entity.disable_entity(false)
