extends Node
func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ev := GameGlobals.get_event("demo_aimed")
	print("[gd] demo_aimed=%s x=%s" % [str(ev != null), str(ev.x) if ev != null else "?"])
	print("[gd] official count=%d" % GameGlobals.official_events.size())
	print("[gd] mod demo_aimed=%s" % str(GameGlobals.mod_events.has("demo_aimed")))
	get_tree().quit(0)
