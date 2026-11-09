extends Node
func _ready() -> void:
	for cls in ["Th75BulletHot", "Th75MotionHot", "Th75BulletHashCpp"]:
		print("[ext] %s exists=%s can_instantiate=%s" % [cls,
			ClassDB.class_exists(cls), ClassDB.can_instantiate(cls)])
	get_tree().quit(0)
