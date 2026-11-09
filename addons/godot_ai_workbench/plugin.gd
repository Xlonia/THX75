@tool
extends EditorPlugin

const PANEL_SCRIPT_PATH := "res://addons/godot_ai_workbench/panel/workbench_panel.gd"
const DEBUG_PROBE_SCRIPT_PATH := "res://addons/godot_ai_workbench/debug/workbench_debug_probe.gd"
const RUNTIME_PROBE_AUTOLOAD_NAME := "GawWorkbenchRuntimeProbe"
const RUNTIME_PROBE_SCRIPT_PATH := "res://addons/godot_ai_workbench/runtime/workbench_runtime_probe.gd"

var _panel: Control
var _debug_probe: EditorDebuggerPlugin
var _pending_reload_settings: Dictionary = {}

func _enter_tree() -> void:
	set_process(true)
	_ensure_runtime_probe_autoload()
	_mount_debug_probe()
	_mount_panel({})


func _mount_panel(settings: Dictionary) -> void:
	_unmount_panel()
	_request_resource_filesystem_scan()
	var panel_script: GDScript = ResourceLoader.load(PANEL_SCRIPT_PATH, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if panel_script == null:
		_panel = _build_fallback_panel("Panel script could not be loaded.")
	else:
		var candidate: Variant = panel_script.new()
		if candidate is Control:
			_panel = candidate
		else:
			_panel = _build_fallback_panel("Panel script did not create a Control.")
	_panel.name = "Godot AI Workbench"
	if _panel.has_method("setup"):
		_panel.call("setup", get_editor_interface(), _debug_probe, get_undo_redo())
	if _panel.has_signal("workbench_reload_requested"):
		var callback := Callable(self, "_on_panel_reload_requested")
		if not _panel.is_connected("workbench_reload_requested", callback):
			_panel.connect("workbench_reload_requested", callback)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _panel)
	if _panel.has_method("restore_dev_settings"):
		_panel.call_deferred("restore_dev_settings", settings)


func _process(delta: float) -> void:
	if _panel != null and is_instance_valid(_panel):
		if _panel.has_method("service_workbench_bridge"):
			_panel.call("service_workbench_bridge", delta)


func _exit_tree() -> void:
	set_process(false)
	_unmount_panel()
	_unmount_debug_probe()
	_remove_runtime_probe_autoload()


func _unmount_panel() -> void:
	if _panel != null:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null


func _mount_debug_probe() -> void:
	_unmount_debug_probe()
	var probe_script: GDScript = ResourceLoader.load(DEBUG_PROBE_SCRIPT_PATH, "GDScript", ResourceLoader.CACHE_MODE_REPLACE_DEEP) as GDScript
	if probe_script == null:
		return
	var candidate: Variant = probe_script.new()
	if candidate is EditorDebuggerPlugin:
		_debug_probe = candidate
		add_debugger_plugin(_debug_probe)


func _unmount_debug_probe() -> void:
	if _debug_probe != null:
		remove_debugger_plugin(_debug_probe)
		_debug_probe = null


func _ensure_runtime_probe_autoload() -> void:
	var setting_name := "autoload/%s" % RUNTIME_PROBE_AUTOLOAD_NAME
	if ProjectSettings.has_setting(setting_name):
		return
	add_autoload_singleton(RUNTIME_PROBE_AUTOLOAD_NAME, RUNTIME_PROBE_SCRIPT_PATH)


func _remove_runtime_probe_autoload() -> void:
	var setting_name := "autoload/%s" % RUNTIME_PROBE_AUTOLOAD_NAME
	if not ProjectSettings.has_setting(setting_name):
		return
	remove_autoload_singleton(RUNTIME_PROBE_AUTOLOAD_NAME)


func _request_resource_filesystem_scan() -> void:
	var resource_filesystem: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if resource_filesystem == null:
		return
	if resource_filesystem.has_method("scan_sources"):
		resource_filesystem.call("scan_sources")
	elif resource_filesystem.has_method("scan"):
		resource_filesystem.call("scan")


func _on_panel_reload_requested(settings: Dictionary) -> void:
	_pending_reload_settings = settings.duplicate(true)
	call_deferred("_reload_panel_deferred")


func _reload_panel_deferred() -> void:
	var settings: Dictionary = _pending_reload_settings
	_pending_reload_settings = {}
	_mount_debug_probe()
	_mount_panel(settings)


func _on_fallback_reload_pressed() -> void:
	_mount_panel({})


func _build_fallback_panel(message: String) -> Control:
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Godot AI Workbench"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var warning := Label.new()
	warning.text = message
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(warning)
	var reload_button := Button.new()
	reload_button.text = "Reload panel"
	reload_button.pressed.connect(_on_fallback_reload_pressed)
	box.add_child(reload_button)
	return box
