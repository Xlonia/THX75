extends RefCounted

const ADDON_VERSION := "0.2.0-dev"
const PROTOCOL_VERSION := "gaw.bridge.v0"
const DEFAULT_URL := "ws://127.0.0.1:8765/bridge"

const HANDLER_IDS := [
	"editor.state",
	"scene.tree",
	"selection",
	"debug.snapshot",
	"debug.output_snapshot",
	"debug.output_clear",
	"debug.classdb_lookup",
	"debug.performance_snapshot",
	"script.validate",
	"script.open",
	"editor.read_settings",
	"project.set_setting",
	"editor.set_setting",
	"project.input_action_set",
	"project.input_action_remove",
	"project.autoload_add",
	"project.autoload_remove",
	"scene.create",
	"scene.open",
	"scene.save_as",
	"scene.delete",
	"scene.instance",
	"editor.create_node",
	"editor.set_property",
	"editor.attach_script",
	"editor.rename_node",
	"editor.save_scene",
	"editor.move_node",
	"editor.delete_node",
	"editor.duplicate_node",
	"script.detach",
	"editor.inspect_node",
	"editor.camera_get",
	"editor.camera_set",
	"resource.create",
	"resource.edit",
	"resource.uid_repair",
	"resource.media_metadata",
	"domain.create_preset",
	"domain.configure_collision",
	"domain.assign_material",
	"domain.assign_theme",
	"domain.inspect_node",
	"domain.animation_clip",
	"domain.audio_bus",
	"domain.audio_player",
	"domain.control_setup",
	"domain.find_nodes",
	"domain.scene_dependencies",
	"domain.shader_param",
	"domain.theme_item",
	"domain.tilemap_cells",
	"domain.animation_info",
	"domain.navigation_config",
	"domain.particles_config",
	"domain.scene3d_helper",
	"domain.physics_layers",
	"domain.tileset_info",
	"domain.animation_tree",
	"domain.raycast_config",
	"signal.connect",
	"signal.disconnect",
	"editor.add_node_to_group",
	"editor.remove_node_from_group",
	"editor.batch_operations",
	"runtime.status",
	"runtime.tree",
	"runtime.logs",
	"runtime.screenshot",
	"runtime.compare_screenshots",
	"runtime.input",
	"runtime.inspect_node",
	"runtime.get_node_properties",
	"runtime.state",
	"runtime.find_ui",
	"runtime.click_text",
	"runtime.wait_for",
	"runtime.assert",
	"runtime.animation_state",
	"runtime.animation_control",
	"runtime.watch",
	"runtime.record_events",
	"runtime.play_scene",
	"runtime.stop_scene",
	"workbench.dev_control"
]


static func declared_handlers() -> Array:
	return HANDLER_IDS.duplicate()


static func handler_contract(implemented_commands: Array) -> Dictionary:
	var missing: Array = []
	for handler: String in HANDLER_IDS:
		if not implemented_commands.has(handler):
			missing.append(handler)
	var extra: Array = []
	for command_value: Variant in implemented_commands:
		var command_name: String = str(command_value)
		if not HANDLER_IDS.has(command_name):
			extra.append(command_name)
	return {
		"ok": missing.is_empty(),
		"declared": declared_handlers(),
		"implemented": implemented_commands.duplicate(),
		"missing": missing,
		"extra": extra
	}
