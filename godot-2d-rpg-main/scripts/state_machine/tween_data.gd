class_name TweenData
extends Resource

@export var curve: Curve = null ## The curve to use.
@export var duration := 1.0 ## The duration of the tween.
@export var delay := 0.0 ## The delay before starting the tween.
@export var property := "" ## The property to animate.
@export var start_value := "" ## The start value of the property. If not set, the current value of the property will be used.
@export var end_value := "" ## The end value of the property.
@export var reset_value_at_end := true ## If true, the property will be reset to its initial value at the end of the tween.
@export var disabled := false ## If true, the tween will not be applied.

var init_value
var target_value
