@tool
@icon("../icons/StateNavigation.svg")
extends StateEntity
## Makes an entity follow a target using navigation. Requires a NavigationAgent2D.
class_name StateNavigation

@export var navigation_agent: NavigationAgent2D
@export var target_manager: TargetManager

func enter():
	super.enter()
	_update_target.call_deferred()

func _update_target():
	await get_tree().physics_frame
	if target_manager:
		navigation_agent.target_position = target_manager.get_target_position()

func physics_update(_delta):
	_update_target()
	_follow()

func _follow():
	if navigation_agent.is_navigation_finished():
		complete()
		return
	if entity:
		var next_path_position = navigation_agent.get_next_path_position()
		entity.move_towards(next_path_position)
