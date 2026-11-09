# Takes care of loading or creating a new save game and provides appropriate
# resources to the user interface and the entity.
extends Node

# We always keep a reference to the SaveFileManager resource here to prevent it from unloading.
var _file: SaveFileManager
# The method name to call on nodes that need to receive data from the save file.
const RECEIVE_DATA_METHOD = "receive_data"
# The method name to call on nodes that need to provide data to the save file.
const GET_DATA_METHOD = "get_data"

signal game_saved
signal game_loaded

func _ready():
	reset_file_data()

func get_file_data():
	return _file

## Called when starting a new game.
func reset_file_data():
	_file = SaveFileManager.new()

## Called when loading a game.
func load_file_data():
	_file = SaveFileManager.load_save_file()

func get_player_data(player_id: int):
	var player_data = get_file_data().player_data if _file else null
	if player_data and player_data.size() >= player_id:
		return player_data[player_id]
	return null

func get_node_data(path: String):
	var nodes_data = get_file_data().nodes_data if _file else null
	if nodes_data and path in nodes_data:
		return nodes_data[path]
	return null

## Used to save nodes state data of the level and players data before removing the level.
func save_level_data():
	_save_nodes_data()

## Used to load nodes state data of the level when entering a level.
func load_level_data():
	_load_nodes_data()

func load_game() -> void:
	print("loading...")
	load_file_data()
	_load_game_data()
	game_loaded.emit()

func save_game() -> void:
	print("saving...")
	_save_game_data()
	_save_nodes_data()
	get_file_data().write_save_file()
	game_saved.emit()

func _load_game_data():
	if !get_file_data().game_data:
		return
	var current_level = Globals.get_current_level()
	if current_level and get_file_data().game_data.level != current_level.scene_file_path or !current_level:
		Globals.load_last_saved_level()

func _load_nodes_data():
	for node: Node in _get_save_nodes():
		if node is not PlayerEntity:
			var node_data = get_node_data(String(node.get_path()))
			if !node_data and node.has_method(GET_DATA_METHOD):
				node_data = node.call(GET_DATA_METHOD)
			if node.has_method(RECEIVE_DATA_METHOD):
				node.call(RECEIVE_DATA_METHOD, node_data)

func _save_nodes_data():
	for node: Node in _get_save_nodes():
		if node != null and node.has_method(GET_DATA_METHOD):
			# Check if the node is a player entity. Player's data is handled differently.
			if node is PlayerEntity:
				var path = node.player_id
				get_file_data().player_data[path] = node.call(GET_DATA_METHOD)
			else:
				var path = String(node.get_path())
				get_file_data().nodes_data[path] = node.call(GET_DATA_METHOD)

func save_player_data(player_id: int, data: Dictionary):
	var player_data: DataPlayer = get_player_data(player_id)
	if player_data:
		for key in data.keys():
			player_data[key] = data[key]

func _save_game_data():
	get_file_data().game_data = _get_game_data()

func _get_game_data():
	var game_data := DataGame.new()
	game_data.level = Globals.get_current_level().scene_file_path
	return game_data

func _get_save_nodes():
	var nodes: Array[Node] = get_tree().get_nodes_in_group(Const.GROUP.SAVE)
	return nodes
