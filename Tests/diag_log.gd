extends Node
func _ready() -> void:
	var e := DanmakuExpr.new()
	var ok := e.compile("log(2,8)", PackedStringArray([]))
	print("ok=", ok)
	if ok:
		print("val=", e.execute([], -1.0))
	## 直接看翻译产物
	var re := RegEx.new()
	re.compile("log\\(\\s*([^(),]+)\\s*,\\s*([^(),]+)\\s*\\)")
	var m := re.search("log(2,8)")
	print("match=", m)
	if m:
		print("translated=", re.sub("log(2,8)", "(log(\\2)/log(\\1))", true))
	var e2 := Expression.new()
	var err := e2.parse("(log(8)/log(2))", [])
	print("direct parse err=", err, " val=", e2.execute([], e2, false))
	get_tree().quit(0)
