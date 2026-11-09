## This state animates a property of a Node2D using a Tween.
class_name StateTween
extends State

@export var object: Node2D ## The object to animate.
@export var tweens: Array[TweenData] ## The tweens to apply.
@export var parallel := true ## If true, the tweens will be applied in parallel.
@export var loops := 1 ## The number of times the tween will be repeated.

var available_tweens: Array[TweenData]

func enter():
	if not object:
		return
	available_tweens = tweens.filter(func(t): return !t.disabled)
	for t in available_tweens:
		t.init_value = str_to_var(t.start_value) if !t.start_value.is_empty() else object.get(t.property)
		t.target_value = t.init_value + str_to_var(t.end_value)
	var tween: Tween = create_tween().set_parallel(parallel).set_loops(loops)
	tween.finished.connect(complete)
	for t in available_tweens:
		tween.tween_method(
			func(v): object.set(t.property, lerp(t.init_value, t.target_value, t.curve.sample_baked(v))),
			0.0, 1.0, t.duration).set_delay(t.delay)

func exit():
	for t in available_tweens:
		if t.reset_value_at_end:
			object.set(t.property, t.init_value)
