#include "register_types.h"
#include "bullet_hot.h"
#include "motion_hot.h"
#include "bullet_setup.h"
#include "bullet_hash_cpp.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

extern "C" GDExtensionBool GDE_EXPORT th75_extension_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer([](ModuleInitializationLevel p_level) {
		if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
			ClassDB::register_class<Th75BulletHot>();
			ClassDB::register_class<Th75MotionHot>();
			ClassDB::register_class<Th75BulletSetup>();
			ClassDB::register_class<Th75BulletHashCpp>();
		}
	});
	init_obj.register_terminator([](ModuleInitializationLevel p_level) {
		if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		}
	});
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
