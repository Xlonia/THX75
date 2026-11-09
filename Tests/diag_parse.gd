extends Node
func _ready():
	var s = load("res://scripts/danmaku/family_maps.gd")
	print("fm_parse=", s != null)
	get_tree().quit()
