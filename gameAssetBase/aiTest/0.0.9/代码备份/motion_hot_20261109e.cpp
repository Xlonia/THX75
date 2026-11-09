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
	for (int64_t i = 0; i < n; i++) {
		const double *row = r + i * 8;
		out[i * 2] = row[0] + row[2] * row[4] * row[5];
		out[i * 2 + 1] = row[1] + row[3] * row[4] * row[5];
	}
	return out;
}

PackedFloat64Array Th75MotionHot::step_table(const PackedFloat64Array &rows, int64_t n) const {
	// 每行 9 值：tid, t, ox, oy, rot_c, rot_s, speed, dt, step
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
		double rc = row[4], rs = row[5];
		double rdx = dx * rc - dy * rs;
		double rdy = dx * rs + dy * rc;
		double sp = row[6], dt = row[7];
		out[i * 4] = rdx; out[i * 4 + 1] = rdy;
		out[i * 4 + 2] = row[2] + rdx * sp * dt;
		out[i * 4 + 3] = row[3] + rdy * sp * dt;
	}
	return out;
}

PackedFloat64Array Th75MotionHot::step_wfrozen(const PackedFloat64Array &rows, int64_t n) const {
	PackedFloat64Array out;
	out.resize(n * 2);
	const double *r = rows.ptr();
	for (int64_t i = 0; i < n; i++) {
		const double *row = r + i * 8;
		out[i * 2] = row[2] + row[0] * row[4] * row[5];
		out[i * 2 + 1] = row[3] + row[1] * row[4] * row[5];
	}
	return out;
}

// —— 【0.0.9·审计①-1 完整状态 C++ 接管 20261109】——

int Th75MotionHot::_alloc() {
	if (!_free.empty()) {
		int s = _free.back();
		_free.pop_back();
		return s;
	}
	int s = (int)_ox.size();
	size_t n = (size_t)s + 1;
	_ox.resize(n); _oy.resize(n); _dx.resize(n); _dy.resize(n); _spd.resize(n);
	_t.resize(n); _alive_f.resize(n); _range.resize(n); _radius.resize(n);
	_oob.resize(n); _px.resize(n); _py.resize(n); _alive.resize(n, 0);
	return s;
}

int64_t Th75MotionHot::register_frozen(double ox, double oy, double dx, double dy, double spd,
		double t0, double alive0, double px0, double py0, double range, double radius, int64_t oob_mode) {
	int s = _alloc();
	_ox[s] = ox; _oy[s] = oy; _dx[s] = dx; _dy[s] = dy; _spd[s] = spd;
	_t[s] = t0; _alive_f[s] = alive0; _range[s] = range; _radius[s] = radius;
	_oob[s] = (int)oob_mode;
	// 交接态 pos=GD 当前 pos（首帧死亡判定用"推进前 pos"——与 GD 逐位一致）
	_px[s] = px0;
	_py[s] = py0;
	_alive[s] = 1;
	return s;
}

void Th75MotionHot::set_frozen_alive(int64_t slot, bool alive) {
	if (slot < 0 || slot >= (int64_t)_alive.size()) return;
	if ((_alive[slot] != 0) == alive) return;
	_alive[slot] = alive ? 1 : 0;
	if (!alive) _free.push_back((int)slot);
}

// 逐条复刻 GD Bullet.update() 对纯定值弹的口径（顺序即语义）：
//   ① t += dt；_alive_frames += dt
//   ② _alive_frames > range_now → 死（严格大于）
//   ③ 64+r 远界兜底（非激光恒判；用**推进前**的 pos——GD 此时 pos 尚未更新）
//   ④ oob_mode==0：r 界出界即死（同样用推进前 pos）
//   ⑤ pos = origin + dir*spd*t（_step_regular frozen 分支）
void Th75MotionHot::begin_frame(double dt) {
	_dead.clear();
	_out.clear();
	_live = 0;
	const size_t n = _alive.size();
	_out.resize((int64_t)n * 3);
	double *o = _out.ptrw();
	int64_t k = 0;
	for (size_t i = 0; i < n; i++) {
		if (!_alive[i]) continue;
		_t[i] += dt;
		_alive_f[i] += dt;
		bool dead = _alive_f[i] > _range[i];
		if (!dead) {
			const double r = _radius[i];
			const double hb = 64.0 + r;
			const double x = _px[i], y = _py[i];
			if (x < -hb || x > 400.0 + hb || y < -hb || y > 400.0 + hb) {
				dead = true;
			} else if (_oob[i] == 0 && (x < -r || x > 400.0 + r || y < -r || y > 400.0 + r)) {
				dead = true;
			}
		}
		if (dead) {
			_alive[i] = 0;
			_free.push_back((int)i);
			_dead.push_back((int32_t)i);
			continue;
		}
		// GD Vector2 为 f32：pos = origin + dir * spd * t 按 GD 运算顺序逐步 f32
		// 舍入（(dir*spd)*t 再 +origin）——与 GD 解析式位级一致（A/B 对账前提）
		const float ax = (float)_dx[i] * (float)_spd[i];
		const float ay = (float)_dy[i] * (float)_spd[i];
		const float tf = (float)_t[i];
		const float mx = ax * tf;
		const float my = ay * tf;
		_px[i] = (double)((float)_ox[i] + mx);
		_py[i] = (double)((float)_oy[i] + my);
		o[k * 3] = (double)i;
		o[k * 3 + 1] = _px[i];
		o[k * 3 + 2] = _py[i];
		k++;
	}
	_out.resize(k * 3);
	_live = k;
}

double Th75MotionHot::get_t(int64_t slot) const {
	if (slot < 0 || slot >= (int64_t)_t.size()) return 0.0;
	return _t[slot];
}

double Th75MotionHot::get_alive_frames(int64_t slot) const {
	if (slot < 0 || slot >= (int64_t)_alive_f.size()) return 0.0;
	return _alive_f[slot];
}

void Th75MotionHot::clear_all() {
	_ox.clear(); _oy.clear(); _dx.clear(); _dy.clear(); _spd.clear();
	_t.clear(); _alive_f.clear(); _range.clear(); _radius.clear();
	_oob.clear(); _px.clear(); _py.clear(); _alive.clear(); _free.clear();
	_dead.clear(); _out.clear(); _live = 0;
}

void Th75MotionHot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_frozen", "ox", "oy", "dx", "dy", "spd", "t0", "alive0", "px0", "py0", "range", "radius", "oob_mode"), &Th75MotionHot::register_frozen);
	ClassDB::bind_method(D_METHOD("set_frozen_alive", "slot", "alive"), &Th75MotionHot::set_frozen_alive);
	ClassDB::bind_method(D_METHOD("begin_frame", "dt"), &Th75MotionHot::begin_frame);
	ClassDB::bind_method(D_METHOD("get_frozen_pos"), &Th75MotionHot::get_frozen_pos);
	ClassDB::bind_method(D_METHOD("get_dead"), &Th75MotionHot::get_dead);
	ClassDB::bind_method(D_METHOD("get_t", "slot"), &Th75MotionHot::get_t);
	ClassDB::bind_method(D_METHOD("get_alive_frames", "slot"), &Th75MotionHot::get_alive_frames);
	ClassDB::bind_method(D_METHOD("live_count"), &Th75MotionHot::live_count);
	ClassDB::bind_method(D_METHOD("clear_all"), &Th75MotionHot::clear_all);
	ClassDB::bind_method(D_METHOD("register_table", "xy_interleaved", "n_pts"), &Th75MotionHot::register_table);
	ClassDB::bind_method(D_METHOD("step_frozen", "rows", "n"), &Th75MotionHot::step_frozen);
	ClassDB::bind_method(D_METHOD("step_table", "rows", "n"), &Th75MotionHot::step_table);
	ClassDB::bind_method(D_METHOD("step_wfrozen", "rows", "n"), &Th75MotionHot::step_wfrozen);
	ClassDB::bind_method(D_METHOD("table_count"), &Th75MotionHot::table_count);
}
