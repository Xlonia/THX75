## This state instantiates a scene and adds it to a parent node.
class_name StateInstantiate
extends State

@export var parent: Node ## The parent node to add the instance to. If not set, the root node will be used.
@export var parent_of_parent := false ## If true, the parent will be the parent of the parent node.
@export var scene: PackedScene ## The scene to instantiate.

func enter():
	if !scene:
		push_warning("Scene not set in %s" % self)
		return
	var instance = scene.instantiate()
	if parent:
		if parent_of_parent:
			parent.get_parent().add_child.call_deferred(instance)
			instance.global_position = parent.global_position
		else:
			parent.add_child.call_deferred(instance)
	else:
		get_tree().root.add_child.call_deferred(instance)
	complete()
