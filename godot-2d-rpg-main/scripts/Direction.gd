## A resource that defines directional values and their mappings.  
## Provides utility functions for converting between direction names, vectors, and values.
class_name Direction
extends Resource

const DIRECTION = {
	DOWN = "down",
	LEFT = "left",
	RIGHT = "right",
	UP = "up",
}

const DIR_VECTOR = {
	0: Vector2(0, 1),
	1: Vector2(-1, 0),
	2: Vector2(1, 0),
	3: Vector2(0, -1),
}

const DIR_VALUE = {
	Vector2(0, 1): 0, #down
	Vector2(-1, 0): 1, #left
	Vector2(-1, 1): 1, #left
	Vector2(-1, -1): 1, #left
	Vector2(1, 0): 2, #right
	Vector2(1, 1): 2, #right
	Vector2(1, -1): 2, #right
	Vector2(0, -1): 3, #up
}

const DIR_NAME = {
	0: Direction.DIRECTION.DOWN,
	1: Direction.DIRECTION.LEFT,
	2: Direction.DIRECTION.RIGHT,
	3: Direction.DIRECTION.UP,
}

const DIR_BIT = {
	0: 1 << 0,
	1: 1 << 1,
	2: 1 << 2,
	3: 1 << 3,
}

@export_enum(
	DIRECTION.DOWN,
	DIRECTION.LEFT,
	DIRECTION.RIGHT,
	DIRECTION.UP
) var direction

var to_vector := Vector2.ZERO:
	get():
		if direction != null:
			return DIR_VECTOR[direction]
		else:
			return Vector2.ZERO

static func get_vector_value(dir: Vector2):
	return DIR_VALUE[dir.round()]

static func get_value_name(value: int):
	return DIR_NAME[value]

static func get_value_bit(value: int):
	return DIR_BIT[value]
