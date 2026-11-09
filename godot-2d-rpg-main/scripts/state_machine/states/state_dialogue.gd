@icon("../icons/StateDialogue.svg")
extends State
##Starts a dialogue from DialogueManager.
class_name StateDialogue

@export var dialogue: DialogueResource ## The dialogue of reference.
@export var title = "" ## The title of the dialogue in the dialogue resource.
@export var pause := true ## Pause the game when dialogue is on screen.

func enter():
	if dialogue:
		get_tree().paused = pause
		DialogueManager.show_dialogue_balloon(dialogue, title)
		await DialogueManager.dialogue_ended
		get_tree().paused = false
		complete()
