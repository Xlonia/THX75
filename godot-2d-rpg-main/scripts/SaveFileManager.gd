# Save and load the game using the text or binary resource format.
extends Resource
class_name SaveFileManager

@export var nodes_data: Dictionary[String, Variant] = {}
@export var player_data: Dictionary[int, DataPlayer] = {}
@export var game_data: DataGame = null

func write_save_file() -> void:
	ResourceSaver.save(self, get_save_file_path())

static func save_file_exists() -> bool:
	return ResourceLoader.exists(get_save_file_path())

static func load_save_file() -> Resource:
	var save_path := get_save_file_path()
	if ResourceLoader.exists(save_path):
		return ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return SaveFileManager.new()

static func get_save_file_path() -> String:
	# This check allows to save and load a text resource in debug builds and a binary resource in the released project.
	var extension := ".tres" if OS.is_debug_build() else ".res"
	return Const.SAVE_FILE_BASE_PATH + extension
