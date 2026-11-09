extends StateEntity
##Applies an inpulse to an entity.
class_name StateImpulse

@export var impulse_force := 300.0
@export var impulse_duration := 0.1

func enter():
  super.enter()
  entity.add_impulse(impulse_force)
  await get_tree().create_timer(impulse_duration).timeout
  entity.stop()
  complete()
