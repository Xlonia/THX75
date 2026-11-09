class_name CheckDirection
extends Check

@export_flags(
	Direction.DIRECTION.DOWN,
	Direction.DIRECTION.LEFT,
	Direction.DIRECTION.RIGHT,
	Direction.DIRECTION.UP
) var direction ## Check if the entity is facing the right direction.

func check(on = null) -> bool:
	if on is not CharacterEntity:
		return true
	var dir_value = Direction.get_vector_value(on.facing)
	var dir_bit = Direction.get_value_bit(dir_value)
	if direction and direction > 0 and (direction & dir_bit) == 0:
		return false
	else:
		return true
