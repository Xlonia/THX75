extends Resource
class_name DataPlayer

@export var position = Vector2.ZERO
@export var facing = Vector2.ZERO
@export var hp: int
@export var max_hp: int
@export var inventory: Array[ContentItem] = []
@export var equipped: int
