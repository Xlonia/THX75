extends Node
## kit 探针 wrapper（th75 侧）：脚本直实例化内核探针（tscn ext_resource
## 内核绝对路径在宿主失效——历史坑）；探针内部自用 kpath，双工程兼容
@export var probe_script: GDScript
func _ready() -> void:
	var n := Node.new()
	n.set_script(probe_script)
	add_child(n)
