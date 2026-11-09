@tool
## The HitBox is an Area2D that can be used to detect collisions with HurtBoxes and apply damage to the entities that own them.
class_name HitBox
extends Area2D

@export var hp_change: int = 0 ## Set to change the HP of the entities the HitBox collides with. A positive value will increase the HP, a negative value will decrease it.

func _init() -> void:
  monitorable = true
  monitoring = false
  collision_mask = 0
  z_index = -1
