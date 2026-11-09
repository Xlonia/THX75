extends CanvasLayer

@export var anim_label: RichTextLabel
@export var info_label: RichTextLabel

func _ready():
	DataManager.game_saved.connect(_on_game_saved)
	DataManager.game_loaded.connect(_on_game_loaded)
	if info_label:
		info_label.draw.connect(_on_info_label_draw)

func _on_game_saved():
	if info_label:
		info_label.text = "Game saved!"

func _on_game_loaded():
	if info_label:
		info_label.text = "Game loaded!"

func _on_info_label_draw():
	await get_tree().create_timer(2.5).timeout
	info_label.text = ""
