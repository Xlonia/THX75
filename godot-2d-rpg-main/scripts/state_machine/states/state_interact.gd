@tool
@icon("../icons/StateInteract.svg")
extends State
## Handle entity interactions.
class_name StateInteract

@export var interaction_area: InteractionArea: ## Interaction will trigger only if entity is inside this area.
	set(value):
		interaction_area = value
		update_configuration_warnings()
@export var on_leaving: Array[State] ## States to enable on exiting the area.
@export var action_trigger := "" ## The input action (as in the Input Map) that will trigger the interaction. Leave empty to trigger on area entered.
@export_enum("Pressed", "Released") var action_mode := "Pressed" ## Determines the action mode for the input action.
@export_category("Conditions")
@export var conditions: Array[Check] = []: ## A list of conditions to met in order to trigger the interaction.
	set(value):
		conditions = value
		notify_property_list_changed()
@export var on_condition_not_met: Dictionary[String, State] = {} ## Provide a state to enable if a certain condition is not met. Use the condition's resource_name as key of the Dictionary.
@export_category("Settings")
@export var one_shot := true ## If true, it can be interacted only once. Useful for chests or pickable items.
@export var reset_delay := 0.2 ## Determines after how many seconds the interactable can be triggered again. It works only if [member one_shot] is disabled.
@export_flags("Area:4", "Body:8", "Area and Body:12") var check = 4 ## Determines which elements the [member interaction_area] should check: only other areas, only bodies, or both.

var entity: CharacterEntity
var interacting := false

func _ready() -> void:
	if interaction_area:
		if check == 4 or check == 12:
			interaction_area.area_entered.connect(func(_area): _set_entity(_area.get_parent()))
			interaction_area.area_exited.connect(func(_area): _reset_entity())
		if check == 8 or check == 12:
			interaction_area.body_entered.connect(func(_body): _set_entity(_body))
			interaction_area.body_exited.connect(func(_body): _reset_entity())

func enter():
	_reset_interaction()
	if interaction_area:
		var areas: Array[Area2D] = interaction_area.get_overlapping_areas()
		for a in areas:
			_set_entity(a.get_parent())

func exit():
	_reset_entity()

func _set_entity(node):
	if node is CharacterEntity:
		entity = node
		_try_to_interact()

func _reset_entity():
	if active and not interacting:
		_do_leaving()
	entity = null

func update(_delta):
	if not entity or action_trigger.is_empty():
		return
	if entity.input_enabled:
		if action_mode == "Pressed" and Input.is_action_just_pressed(action_trigger) or action_mode == "Released" and Input.is_action_just_released(action_trigger):
			_try_to_interact()

func _try_to_interact():
	if _can_interact():
		_do_interaction()

func _can_interact() -> bool:
	if not is_instance_valid(entity) or interacting or not active:
		return false
	if not action_trigger.is_empty() and not Input.is_action_pressed(action_trigger):
		return false
	for condition: Check in conditions.filter(func(_check: Check): return !_check.disabled):
		if !condition.check(entity): # Condition not met
			if on_condition_not_met.has(condition.resource_name):
				on_condition_not_met[condition.resource_name].enable()
			return false
	return true

func _do_interaction():
	interacting = true
	if is_instance_valid(entity) and state_machine.debug:
		print(entity.name, " interacted with ", get_path())
	complete({"entity": entity})
	if !one_shot:
		_reset_interaction()

func _do_leaving():
	for state in on_leaving:
		interacting = true
		state.enable()
	if !one_shot:
		_reset_interaction()

func _reset_interaction():
	interacting = true
	if is_inside_tree():
		await get_tree().create_timer(reset_delay).timeout
	interacting = false

func _validate_property(property: Dictionary) -> void:
	if property.name == "on_condition_not_met":
		if conditions.size() == 0:
			property.usage = PROPERTY_USAGE_NONE

func _get_configuration_warnings() -> PackedStringArray:
	if !interaction_area:
		return ["Set an InteractionArea to make the interaction working."]
	return []
