@icon("../icons/State.svg")
extends Node
##Base class for all states.
class_name State

@export_group("Settings")
@export var delay_start := Vector2.ZERO ## If greater than 0, waits for N seconds before enabling the state, where N is a random value between the minimum (x) and maximum (y) range.
@export var disabled := false ## Set to true to avoid processing this state.
@export_category("Advance")
## States to enable when this state completes (calling the `complete()` method) or when the Await Timer times out.[br]
## In a [i]StateInteract[/i], these are the states activated when the interaction is triggered.
@export var on_completion: Array[State]
@export_group("Await Timer")
@export var delay_completion := Vector2.ZERO ## If greater than 0, waits for N seconds before completing the state, where N is a random value between the minimum (x) and maximum (y) range.

var active := false: ## Indicates whether the state is currently active and being processed by the StateMachine.
	set(value):
		active = value
		if !Engine.is_editor_hint():
			process_mode = PROCESS_MODE_INHERIT if active else PROCESS_MODE_DISABLED
		if active:
			_enter_delayed()

var state_machine: StateMachine:
	set(value):
		state_machine = value
		for state in get_children(true).filter(func(node): return node is State):
			state.state_machine = value

var timer: StateTimer = null


func _enter_tree():
	if disabled:
		active = false

func enable(params = null, sender = null): ## Enables this state.
	if params:
		state_machine.params = params
	state_machine.enable_state(self, sender)
	if delay_completion > Vector2.ZERO:
		await _start_timer(delay_completion).timeout
		_enable_on_completion(params)

func disable(): ## Disables this state.
	if state_machine:
		state_machine.disable_state(self)

func _enter_delayed():
	if delay_start > Vector2.ZERO:
		await _start_timer(delay_start).timeout
	enter()

func _start_timer(t_range: Vector2):
	timer = StateTimer.new(self) if !timer else timer
	return timer.start(t_range)

func enter():
	pass

func exit():
	pass

func update(_delta: float):
	pass

func physics_update(_delta: float):
	pass

func handle_input(_event: InputEvent):
	pass

func complete(params = null):
	if delay_completion == Vector2.ZERO:
		_enable_on_completion(params)

func _enable_on_completion(params):
	for state in on_completion:
		state.enable(state_machine.params if !params else params, self)

class StateTimer:
	var timer: Timer

	func _init(parent: Node):
		timer = Timer.new()
		timer.one_shot = true
		timer.autostart = false
		parent.add_child(timer)

	func start(t_range: Vector2):
		timer.wait_time = randf_range(t_range.x, t_range.y) if t_range.x < t_range.y else t_range.x
		timer.start()
		return timer
