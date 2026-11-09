extends Node
func _ready() -> void:
	var scr := load("res://scripts/danmaku/bullet_runtime.gd")
	if scr == null:
		print("LOAD FAILED")
	else:
		print("LOAD OK")
	var b = scr.new()
	print("new ok=", b != null)
	get_tree().quit(0)
