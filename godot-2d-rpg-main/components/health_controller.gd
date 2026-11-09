@icon("res://icons/HealthController.svg")
extends Node2D
## Controls the HP of an entity or any object, draw an health bar and decide what to do when HP reach 0.
class_name HealthController

@export_group("Health")
@export var max_hp := 20 ## If an health_bar is set, this is the value that corresponds to the health_bar completely full.
@export var recovery_time := 1.0 ## The waiting time before changing the HP again.
@export var immortal := false ## Avoids reducing HP.
@export var health_bar: PackedScene ## A PackedScene that displays the HP.
@export_group("States")
@export var on_hp_increase: State ## State to enable when hp increase.
@export var on_hp_decrease: State ## State to enable when hp decrease.
@export var on_hp_0: State ## State to enable when HP reach 0.

var hp_bar: HpBar ## The health_bar instance.

@onready var hp := max_hp:
	set(new_hp):
		hp = new_hp
		hp_changed.emit(hp)

signal hp_changed(value) ## Emitted when HP change.

func _ready():
	_init_health_bar()

func _init_health_bar():
	if health_bar:
		hp_bar = health_bar.instantiate()
		hp_bar.init_hud(self)
		add_child(hp_bar)

func change_hp(value, from = ""):
	var new_hp = hp + value
	if immortal and new_hp < hp:
		return
	recover()
	if new_hp < 0:
		new_hp = 0
	elif new_hp > max_hp:
		new_hp = max_hp
	if new_hp < hp: # Damaged
		print_rich("%s [color=red]damaged[/color] by %s! HP: %s" % [owner.name, from, new_hp])
		if on_hp_decrease:
			on_hp_decrease.enable()
	elif new_hp > hp: # Recovered
		print_rich("%s [color=green]recovered[/color] by %s! HP: %s" % [owner.name, from, new_hp])
		if on_hp_increase:
			on_hp_increase.enable()
	hp = new_hp
	if hp == 0 and on_hp_0:
		on_hp_0.enable()

func recover():
	immortal = true
	await get_tree().create_timer(recovery_time).timeout
	immortal = false
