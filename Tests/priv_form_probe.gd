extends Node
func _ready() -> void:
	await get_tree().process_frame
	print("CharaDB.DATA_BASE=", CharaDB.DATA_BASE)
	print("csv_path=", CharaDB.csv_path(), " exists=", FileAccess.file_exists(CharaDB.csv_path()))
	print("rows=", CharaDB.load_all().size())
	var fm := PrivateFormation.new()
	print("has setup=", fm.has_method("setup"))
	get_tree().quit()
