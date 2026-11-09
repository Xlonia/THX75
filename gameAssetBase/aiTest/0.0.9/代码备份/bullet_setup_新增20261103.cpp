#include "bullet_setup.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;

PackedFloat64Array Th75BulletSetup::apply_frozen(const PackedFloat64Array &rows, int64_t n) const {
	// 每行 9 值 → 输出每行 5 值（pos_x, pos_y, dir_x, dir_y, track_speed）
	PackedFloat64Array out;
	out.resize(n * 5);
	const double *r = rows.ptr();
	for (int64_t i = 0; i < n; i++) {
		const double *row = r + i * 9;
		double ox = row[0], oy = row[1];
		double dx = row[2], dy = row[3];
		double s = row[4], t = row[5];
		double ok = row[8];
		double spd = ok > 0.5 ? s : 0.0;
		double ddx = ok > 0.5 ? dx : 0.0;
		double ddy = ok > 0.5 ? dy : 0.0;
		double px = ox + ddx * spd * t;
		double py = oy + ddy * spd * t;
		out[i * 5] = px;
		out[i * 5 + 1] = py;
		out[i * 5 + 2] = ddx;
		out[i * 5 + 3] = ddy;
		out[i * 5 + 4] = spd;
	}
	return out;
}

void Th75BulletSetup::_bind_methods() {
	ClassDB::bind_method(D_METHOD("apply_frozen", "rows", "n"), &Th75BulletSetup::apply_frozen);
}
