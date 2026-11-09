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

PackedFloat64Array Th75MotionHot::step_wfrozen(const PackedFloat64Array &rows, int64_t n) const {
	PackedFloat64Array out;
	out.resize(n * 2);
	const double *r = rows.ptr();
	for (int64_t i = 0; i < n; i++) {
		const double *row = r + i * 8;
		double dx = row[0], dy = row[1];
		double px = row[2] + dx * row[4] * row[5];
		double py = row[3] + dy * row[4] * row[5];
		out[i * 2] = px;
		out[i * 2 + 1] = py;
	}
	return out;
}

void Th75MotionHot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_frozen", "ox", "oy", "dx", "dy", "spd", "t0"), &Th75MotionHot::register_frozen);
	ClassDB::bind_method(D_METHOD("set_frozen_alive", "slot", "alive"), &Th75MotionHot::set_frozen_alive);
	ClassDB::bind_method(D_METHOD("begin_frame", "dt"), &Th75MotionHot::begin_frame);
	ClassDB::bind_method(D_METHOD("get_frozen_pos"), &Th75MotionHot::get_frozen_pos);
	ClassDB::bind_method(D_METHOD("get_dead"), &Th75MotionHot::get_dead);
	ClassDB::bind_method(D_METHOD("get_dead"), &Th75MotionHot::get_dead);
	ClassDB::bind_method(D_METHOD("register_table", "xy_interleaved", "n_pts"), &Th75MotionHot::register_table);
	ClassDB::bind_method(D_METHOD("step_frozen", "rows", "n"), &Th75MotionHot::step_frozen);
	ClassDB::bind_method(D_METHOD("step_table", "rows", "n"), &Th75MotionHot::step_table);
	ClassDB::bind_method(D_METHOD("step_wfrozen", "rows", "n"), &Th75MotionHot::step_wfrozen);
	ClassDB::bind_method(D_METHOD("table_count"), &Th75MotionHot::table_count);
}

// —— 【0.0.9·Top2 slot 制 frozen 追踪（作者批 20261109）】——
// 注册制：setup 时注册（origin/dir/speed 定值入 C++），每帧 begin_frame
// 推进 t 并算 pos，GD 读回数组赋 bl.pos。零逐帧序列化。
// 生命周期：setup→register / 死亡（出界/航程/消弹/池驱逐）→set_alive(false)

std::vector<double> _f_ox, _f_oy, _f_dx, _f_dy, _f_spd, _f_t, _f_px, _f_py;
static std::vector<double> _f_range, _f_radius;
static std::vector<bool> _f_has_expr, _f_has_repeat;
static std::vector<int> _f_dead;
std::vector<bool> _f_alive;
std::vector<int> _f_free;

int64_t Th75MotionHot::register_frozen(double ox, double oy, double dx, double dy, double spd, double t0,
		double range, double radius, bool has_expr, bool has_repeat) {
	int slot;
	if (!_f_free.empty()) {
		slot = _f_free.back();
		_f_free.pop_back();
	} else {
		slot = (int)_f_ox.size();
		_f_ox.resize(slot + 1); _f_oy.resize(slot + 1);
		_f_dx.resize(slot + 1); _f_dy.resize(slot + 1);
		_f_spd.resize(slot + 1); _f_t.resize(slot + 1);
		_f_px.resize(slot + 1); _f_py.resize(slot + 1);
		_f_alive.resize(slot + 1);
		_f_range.resize(slot + 1); _f_radius.resize(slot + 1);
		_f_has_expr.resize(slot + 1); _f_has_repeat.resize(slot + 1);
	}
	_f_ox[slot] = ox; _f_oy[slot] = oy;
	_f_dx[slot] = dx; _f_dy[slot] = dy;
	_f_spd[slot] = spd; _f_t[slot] = t0;
	_f_range[slot] = range; _f_radius[slot] = radius;
	_f_has_expr[slot] = has_expr; _f_has_repeat[slot] = has_repeat;
	_f_alive[slot] = true;
	_f_px[slot] = ox + dx * spd * t0;
	_f_py[slot] = oy + dy * spd * t0;
	return slot;
}

void Th75MotionHot::set_frozen_alive(int64_t slot, bool alive) {
	if (slot < 0 || slot >= (int64_t)_f_alive.size()) return;
	if (_f_alive[slot] == alive) return;
	_f_alive[slot] = alive;
	if (!alive) _f_free.push_back((int)slot);
}

void Th75MotionHot::begin_frame(double dt) {
	_f_dead.clear();
	for (size_t i = 0; i < _f_alive.size(); i++) {
		if (!_f_alive[i]) continue;
		_f_t[i] += dt;
		_f_px[i] = _f_ox[i] + _f_dx[i] * _f_spd[i] * _f_t[i];
		_f_py[i] = _f_oy[i] + _f_dy[i] * _f_spd[i] * _f_t[i];
		if (i < _f_has_expr.size() && !_f_has_expr[i]) {
			if (_f_t[i] >= _f_range[i]) {
				_f_dead.push_back((int)i); _f_alive[i] = false;
				_f_free.push_back((int)i); continue;
			}
			double r = _f_radius[i];
			if (_f_px[i] < -r || _f_px[i] > 400.0 + r || _f_py[i] < -r || _f_py[i] > 400.0 + r) {
				_f_dead.push_back((int)i); _f_alive[i] = false;
				_f_free.push_back((int)i); continue;
			}
		}
	}
}

PackedInt32Array Th75MotionHot::get_dead() const {
	PackedInt32Array out;
	for (int d : _f_dead) out.push_back(d);
	return out;
}

PackedFloat64Array Th75MotionHot::get_frozen_pos() const {
	PackedFloat64Array out;
	out.resize(_f_px.size() * 2);
	for (size_t i = 0; i < _f_px.size(); i++) {
		out[i * 2] = _f_px[i];
		out[i * 2 + 1] = _f_py[i];
	}
	return out;
}
