extends Node
## 临时诊断：找出哪个事件字段编译报 self 错误
func _ready() -> void:
	var text := FileAccess.get_file_as_string("res://gameAssetBase/danmaku_event.csv")
	var events := DanmakuEventData.parse_csv_text(text)
	print("events=", events.size())
	for ev in events:
		var errs := ev.compile()
		print(ev.event_name, " errs=", errs)
	print("DONE")
	get_tree().quit(0)
