@tool
## The HurtBox is an Area2D that can be used to detect collisions with HitBoxes and apply damage to the entities that own them.
class_name HurtBox
extends Area2D

@export var health_controller: HealthController ## The HealthController that handles this entity hp.

func _init() -> void:
	monitorable = false
	monitoring = true
	collision_layer = 0
	z_index = -1

func _ready() -> void:
	area_entered.connect(_on_hitbox_entered)

func _on_hitbox_entered(hitbox: HitBox):
	if !hitbox or !health_controller:
		return
	health_controller.change_hp(hitbox.hp_change, hitbox.owner.name)

func _on_entity_action_performed(action: String) -> void:
	process_mode = PROCESS_MODE_DISABLED if action == "jump" else PROCESS_MODE_INHERIT
