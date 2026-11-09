@tool
@icon("res://icons/TargetManager.svg")

## Manages target selection and tracking for a node.
class_name TargetManager
extends Node2D

## The ID of the player to set as the target.  
## If greater than 0, the player with this ID will be assigned as the target.
@export var target_player_id := 0:
	set(value):
		target_player_id = value
		notify_property_list_changed()
		if value > 0:
			_init_target.call_deferred()

## The node to follow.
@export var target: Node2D = null:
	set(value):
		if value != target:
			target = value
			target_changed.emit(target)
			target_player_id = 0
			check_target = true
			if is_node_ready() and target:
				print("%s target set to: %s" % [get_parent().name, target])
		notify_property_list_changed()

## Whether to check if the target has been reached.
var check_target := false

## Emitted when the target is changed.
signal target_changed(target: Node2D)

## Emitted when the target is reached.
signal target_reached(target: Node2D)

## Returns the global position of the target if it's valid; otherwise, returns Vector2.ZERO.
func get_target_position():
	return target.global_position if is_instance_valid(target) else Vector2.ZERO

func _ready() -> void:
	_init_target.call_deferred() ## Initialize the target after the node is ready.

## Checks if the target has been reached and emits a signal if so.
func _process(_delta: float) -> void:
	if check_target and _is_target_reached():
		target_reached.emit()
		check_target = false

## Initializes the target.
func _init_target():
	if Engine.is_editor_hint():
		return
	await get_tree().physics_frame
	if target_player_id > 0:
		target = Globals.get_player(target_player_id)
	elif target:
		target = target

## Checks if the node has reached the target position.
func _is_target_reached():
	return global_position.is_equal_approx(get_target_position())

## Validates and updates property visibility in the editor.
func _validate_property(property: Dictionary) -> void:
	if property.name == "target":
		if target_player_id > 0:
			property.usage = PROPERTY_USAGE_NONE ## Hide the target property if player ID is set.
	if property.name == "target_player_id":
		if target != null:
			property.usage = PROPERTY_USAGE_NONE ## Hide the player ID property if a target is manually set.
