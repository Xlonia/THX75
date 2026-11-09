class_name CheckPropValue
extends Check

@export var prop_name := ""
@export var prop_value := ""

func check(on: Node = null) -> bool:
	var prop = on.get(prop_name)
	return prop == str_to_var(prop_value)
