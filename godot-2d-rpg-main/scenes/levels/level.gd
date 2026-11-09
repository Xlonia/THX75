@tool
extends Node2D
class_name Level

@export_tool_button("Clear Tilemap Layers", "Callable") var clear_action = clear_tilemap_layers

@onready var tilemap_layers: Node2D = %Layers

var destination_name: String ## Used when moving between levels to get the right destination position for the player in the loaded level.
var player_id: int ## Used when moving between levels to save the player facing direction.

func init_scene():
	DataManager.load_level_data()

##internal - Used by SceneManager to pass data between levels.
func get_data():
	var data = {}
	if destination_name:
		data.destination_name = destination_name
	if player_id:
		data.player_id = player_id
	return data

##internal - Used by SceneManager to get data from the outgoing level.
func receive_data(data):
	if data.destination_name:
		destination_name = data.destination_name
	if data.player_id:
		player_id = data.player_id

func clear_tilemap_layers():
	for node in tilemap_layers.get_children():
		if node is TileMapLayer:
			node.clear()
