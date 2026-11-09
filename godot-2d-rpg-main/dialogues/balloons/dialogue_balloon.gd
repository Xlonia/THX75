extends DialogueManagerExampleBalloon
## An extension of the basic dialogue balloon for use with Dialogue Manager.

## The container for the name label.
@onready var name_container: Panel = $Balloon/NameContainer

## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	super.apply_dialogue_line()
	name_container.visible = not dialogue_line.character.is_empty()
