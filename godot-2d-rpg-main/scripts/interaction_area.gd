@tool
extends Area2D
class_name InteractionArea
## Adds a pre-configured Area2D, ready to be set as an interaction_area in a StateInteract.

func _init() -> void:
  monitorable = false
  monitoring = true
  collision_layer = 0
  collision_mask = 8
  z_index = -1
