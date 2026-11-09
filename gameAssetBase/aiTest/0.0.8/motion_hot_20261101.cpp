#include "motion_hot.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

int Th75MotionHot::register_table(const PackedFloat64Array &xy_interleaved, int64_t n_pts) {
	_tables.push_back(xy_interleaved);
	_table_pts.push_back((int)n_pts);
	return _tables.size() - 1;
}

PackedFloat64Array Th75MotionHot::step_frozen(const PackedFloat64Array &rows, int64_t n) const {
	// 每行 8 值：ox, oy, dx, dy, s, t, rot_c, rot_s
	PackedFloat64Array out;
	out.resize(n * 2);
	const double *r = rows.ptr();
	// 定值弹幕：pos = origin + dir*s*t（dir 已含旋转——rot 恒 0 传入即可）
	for (int64_t i = 0; i < n; i++) {
		const double *row = r + i * 8;
		double dx = row[2], dy = row[3];
		double s = row[4], t = row[5];
		double px = row[0] + dx * s * t;
		double py = row[1] + dy * s * t;
		out[i * 2] = px;
		out[i * 2 + 1] = py;
	}
	return out;
}

PackedFloat64Array Th75MotionHot::step_table(const PackedFloat64Array &rows, int64_t n) const {
	// 每行 9 值：tid, t, ox, oy, rot_c, rot_s, speed, dt, step
	// dir = 表[t/step] 旋转 rot；pos += dir*speed*dt（x_copy 帧控积分语义）
	PackedFloat64Array out;
	out.resize(n * 4); // dir_x, dir_y, pos_x, pos_y
	const double *r = rows.ptr();
	for (int64_t i = 0; i < n; i++) {
		const double *row = r + i * 9;
		int tid = (int)row[0];
		if (tid < 0 || tid >= (int)_tables.size()) {
			out[i * 4] = 0; out[i * 4 + 1] = 0; out[i * 4 + 2] = row[2]; out[i * 4 + 3] = row[3];
			continue;
		}
		const PackedFloat64Array &tbl = _tables[tid];
		int n_pts = _table_pts[tid];
		double tq = row[1] / (row[8] > 0.0 ? row[8] : 1.0);
		if (tq < 0.0) tq = 0.0;
		if (tq > (double)(n_pts - 1)) tq = (double)(n_pts - 1);
		int i0 = (int)tq;
		double fr = tq - (double)i0;
		int i1 = i0 + 1 < n_pts ? i0 + 1 : n_pts - 1;
		double wx = tbl[i0 * 2] + (tbl[i1 * 2] - tbl[i0 * 2]) * fr;
		double wy = tbl[i0 * 2 + 1] + (tbl[i1 * 2 + 1] - tbl[i0 * 2 + 1]) * fr;
		double len = sqrt(wx * wx + wy * wy);
		double dx = 0.0, dy = 0.0;
		if (len > 0.0001) {
			dx = wx / len; dy = wy / len;
		}
		// 旋转 rot_angle（rot_c=cos, rot_s=sin）
		double rc = row[4], rs = row[5];
		double rdx = dx * rc - dy * rs;
		double rdy = dx * rs + dy * rc;
		double sp = row[6], dt = row[7];
		double px = row[2] + rdx * sp * dt;
		double py = row[3] + rdy * sp * dt;
		out[i * 4] = rdx; out[i * 4 + 1] = rdy;
		out[i * 4 + 2] = px; out[i * 4 + 3] = py;
	}
	return out;
}

void Th75MotionHot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_table", "xy_interleaved", "n_pts"), &Th75MotionHot::register_table);
	ClassDB::bind_method(D_METHOD("step_frozen", "rows", "n"), &Th75MotionHot::step_frozen);
	ClassDB::bind_method(D_METHOD("step_table", "rows", "n"), &Th75MotionHot::step_table);
	ClassDB::bind_method(D_METHOD("table_count"), &Th75MotionHot::table_count);
}
