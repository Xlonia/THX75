extends Node

@onready var SFX_BUS_ID = AudioServer.get_bus_index("SFX")
@onready var MUSIC_BUS_ID = AudioServer.get_bus_index("Music")

var user_prefs: UserPrefs

var settings_menu_scene: PackedScene = preload("res://scenes/menus/settings_menu.tscn")
var settings_menu = null

@warning_ignore("unused_signal")
signal transfer_start
@warning_ignore("unused_signal")
signal transfer_complete
@warning_ignore("unused_signal")
signal player_added_to_scene(player: PlayerEntity)
@warning_ignore("unused_signal")
signal state_machine_initialized(state_machine: StateMachine)
@warning_ignore("unused_signal")
signal destination_found(destination_path: String)

func _ready():
	user_prefs = UserPrefs.load_or_create()
	AudioServer.set_bus_volume_db(SFX_BUS_ID, linear_to_db(user_prefs.sfx_volume))
	AudioServer.set_bus_mute(SFX_BUS_ID, user_prefs.sfx_volume < .05)
	AudioServer.set_bus_volume_db(MUSIC_BUS_ID, linear_to_db(user_prefs.music_volume))
	AudioServer.set_bus_mute(MUSIC_BUS_ID, user_prefs.music_volume < .05)

func get_selected_language() -> String:
	var s: String = user_prefs.language
	if not s.is_empty():
		return s
	return Const.LANGUAGES[0]

func open_settings_menu():
	if not settings_menu:
		settings_menu = settings_menu_scene.instantiate()
		get_tree().root.add_child(settings_menu)
	else:
		push_warning('settings menu already exists in this scene')

func get_player(id: int):
	var players = get_players()
	var found = players.filter(func(t): return t.player_id == id)
	var player = found[0] if found.size() > 0 else null
	return player

func get_players():
	var players: Array[Node] = get_tree().get_nodes_in_group(Const.GROUP.PLAYER)
	return players

func get_destination(destination_name: String):
	var transfers: Array[Node] = get_tree().get_nodes_in_group(Const.GROUP.DESTINATION)
	var found = transfers.filter(func(t): return t.name == destination_name)
	var destination = found[0] if found.size() > 0 else null
	return destination

func get_current_level():
	var level: Level = get_tree().get_first_node_in_group(Const.GROUP.LEVEL)
	return level

func load_last_saved_level():
	var level_to_load = DataManager.get_file_data().game_data.level
	if level_to_load:
		SceneManager.swap_scenes(level_to_load, get_tree().root, get_current_level(), Const.TRANSITION.FADE_TO_WHITE)

func get_node_inventory(node):
	return node.inventory if node.get("inventory") else null
