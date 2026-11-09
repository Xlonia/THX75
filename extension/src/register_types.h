#ifndef TH75_EXTENSION_REGISTER_H
#define TH75_EXTENSION_REGISTER_H

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>

using namespace godot;

extern "C" GDExtensionBool GDE_EXPORT th75_extension_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization);

#endif // TH75_EXTENSION_REGISTER_H
