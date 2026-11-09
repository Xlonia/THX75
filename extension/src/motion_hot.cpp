#include "motion_hot.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>
#include <algorithm>
#include <vector>

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
	_side.resize(n, 0); _phy.resize(n, 0); _hid.resize(n, 0);
	_maskr.resize(n, 0.0); _ox2.resize(n, 0.0); _oy2.resize(n, 0.0);
	return s;
}

int64_t Th75MotionHot::register_frozen(double ox, double oy, double dx, double dy, double spd,
		double t0, double alive0, double px0, double py0, double range, double radius, int64_t oob_mode,
		int64_t side, bool is_phy, bool hidden, double mask_r) {
	int s = _alloc();
	_side[s] = (int)side; _phy[s] = is_phy ? 1 : 0; _hid[s] = hidden ? 1 : 0;
	_maskr[s] = mask_r; _ox2[s] = ox; _oy2[s] = oy;
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
	_side.clear(); _phy.clear(); _hid.clear(); _hx_rows = PackedFloat64Array(); _bc_rows = PackedFloat64Array();
	_dead.clear(); _out.clear(); _live = 0;
}


// —— 【0.0.9·审计 B2 Hcs/Hct C++ 化 20261109】——
// 逐条复刻 battle_arena._compute_hcs_hct（Vector2 运算按 GD f32 舍入；标量 f64）：
//   49 点=三环 48（半径 n_spd×6/12/30，16 等分，spin 偶奇帧带转）+中心
//   候选=非隐/非激光/非本侧法弹/spd>0.05，且 |弹-实体| ≤ R+L（R=n_spd×30，L=min(spd×60,400)）
//   fill=Σ 255×covered/60，covered=min(60, 2√(r²-d²)/max(L/60,0.01))（d=点到 1s 轨迹段距离）
//   hcs=floor(√min(fill,255)×16)；hct=min(255, hcs+(hcs>0?256:0))
// 与 GD 版唯一差异：GD 预筛在弹>512 时均匀步进抽样（纯 GDScript 性能妥协）——C++ 全量
struct HcsCand { float x, y, dx, dy; double len, rad; };

PackedFloat32Array Th75MotionHot::hcs_hct(double ex, double ey, double n_spd, double spin, int64_t ent_side) const {
	PackedFloat32Array out;
	out.resize(98);
	float *o = out.ptrw();
	for (int i = 0; i < 98; i++) o[i] = 0.0f;
	const float exf = (float)ex, eyf = (float)ey;
	const double R = n_spd * 30.0;
	std::vector<HcsCand> cand;
	cand.reserve(64);
	auto consider = [&](double x, double y, double dx, double dy, double spd, double rad, int side, bool phy) {
		if (side == (int)ent_side && !phy) return;
		if (spd <= 0.05) return;
		const double L = std::min(spd * 60.0, 400.0);
		// GD: bl.pos.distance_to(ent.position)（f32）> R + L → 跳过
		const float ddx = (float)x - exf, ddy = (float)y - eyf;
		const float dist = std::sqrt(ddx * ddx + ddy * ddy);
		if ((double)dist > R + L) return;
		cand.push_back({(float)x, (float)y, (float)dx, (float)dy, L, rad});
	};
	for (size_t i = 0; i < _alive.size(); i++) {
		if (!_alive[i] || _hid[i]) continue;
		consider(_px[i], _py[i], _dx[i], _dy[i], _spd[i], _radius[i], _side[i], _phy[i] != 0);
	}
	const int64_t nr = _hx_rows.size() / 8;
	const double *r = _hx_rows.ptr();
	for (int64_t k = 0; k < nr; k++) {
		const double *w = r + k * 8;
		consider(w[0], w[1], w[2], w[3], w[4], w[5], (int)w[6], w[7] > 0.5);
	}
	if (cand.empty()) return out;
	const double PI_ = 3.14159265358979323846;
	const double TAU_ = 6.28318530717958647692;
	for (int pi = 0; pi < 49; pi++) {
		float px, py;
		if (pi < 48) {
			const double rr2 = n_spd * (pi < 16 ? 6.0 : (pi < 32 ? 12.0 : 30.0));
			const double a2 = spin - PI_ / 2.0 + TAU_ * (double)(pi % 16) / 16.0;
			const float cx = (float)std::cos(a2), sy = (float)std::sin(a2);
			const float rf = (float)rr2;
			px = exf + cx * rf;
			py = eyf + sy * rf;
		} else {
			px = exf; py = eyf;
		}
		double fill = 0.0;
		for (const HcsCand &c : cand) {
			const float wx = px - c.x, wy = py - c.y;
			const float dotf = wx * c.dx + wy * c.dy;
			double tproj = (double)dotf;
			if (tproj < 0.0) tproj = 0.0;
			if (tproj > c.len) tproj = c.len;
			const float tf = (float)tproj;
			const float qx = c.x + c.dx * tf, qy = c.y + c.dy * tf;
			const float vx = px - qx, vy = py - qy;
			const double d = (double)std::sqrt(vx * vx + vy * vy);
			if (d >= c.rad) continue;
			double cov = 2.0 * std::sqrt(std::max(0.0, c.rad * c.rad - d * d)) / std::max(c.len / 60.0, 0.01);
			if (cov > 60.0) cov = 60.0;
			fill += 255.0 * cov / 60.0;
		}
		const double h = std::floor(std::sqrt(std::min(fill, 255.0)) * 16.0);
		o[pi] = (float)h;
		o[49 + pi] = (float)std::min(255.0, h + (h > 0.0 ? 256.0 : 0.0));
	}
	return out;
}

// —— 【0.0.9·基础规避 BC（新三 213-218）20261109】——
// 射线-圆求交：O=实体中心，u=单位方向，C/r=弹幕圆（显示半径）；返回首个
// 交点距离 t∈[0,len]，未交=-1。起点在圆内=0（全阻断）。
static double bc_ray_hit(double ox, double oy, double ux, double uy, double len,
		double cx, double cy, double r) {
	const double wx = cx - ox, wy = cy - oy;
	const double ww = wx * wx + wy * wy;
	const double r2 = r * r;
	if (ww <= r2) return 0.0; // 起点已在弹内
	const double tca = wx * ux + wy * uy;
	if (tca < 0.0) return -1.0; // 弹在射线背后
	const double d2 = ww - tca * tca;
	if (d2 > r2) return -1.0;
	const double t0 = tca - std::sqrt(r2 - d2);
	if (t0 > len) return -1.0;
	return t0 < 0.0 ? 0.0 : t0;
}

PackedFloat32Array Th75MotionHot::bc_rays(double ex, double ey, double len, int64_t ent_side, int64_t mode) const {
	PackedFloat32Array out;
	out.resize(4);
	float *o = out.ptrw();
	o[0] = o[1] = o[2] = o[3] = 0.0f;
	if (len <= 0.0) return out;
	struct C { double x, y, r; };
	std::vector<C> cand;
	cand.reserve(32);
	const int64_t nz = _bc_zones.size() / 3;
	const double *zz = _bc_zones.ptr();
	auto consider = [&](double x, double y, double r, int side, bool phy, double beyond, double fin, double cz) {
		if (mode == 0) {
			if (side == (int)ent_side && !phy) return; // 弹幕本体：本侧法弹不威胁
		} else {
			// DDM 成员资格（与印章口径同源）：场内、非消弹区；本侧仅"物理且超遮罩"
			if (!fin || cz) return;
			if (side == (int)ent_side && !(phy && beyond > 0.5)) return;
		}
		const double dx = x - ex, dy = y - ey;
		const double lim = len + r;
		if (dx * dx + dy * dy > lim * lim) return;
		cand.push_back({x, y, r});
	};
	for (size_t i = 0; i < _alive.size(); i++) {
		if (!_alive[i] || _hid[i]) continue;
		const double rr2 = _radius[i];
		const bool fin = _px[i] > -rr2 && _px[i] < 400.0 + rr2 && _py[i] > -rr2 && _py[i] < 400.0 + rr2;
		double cz = 0.0;
		for (int64_t q = 0; q < nz; q++) {
			const double ddx = _px[i] - zz[q * 3], ddy = _py[i] - zz[q * 3 + 1];
			const double rrz = zz[q * 3 + 2] + rr2;
			if (ddx * ddx + ddy * ddy <= rrz * rrz) { cz = 1.0; break; }
		}
		double beyond = 0.0;
		if (_phy[i] && _maskr[i] > 0.0) {
			const double ddx = _px[i] - _ox2[i], ddy = _py[i] - _oy2[i];
			beyond = (ddx * ddx + ddy * ddy > _maskr[i] * _maskr[i]) ? 1.0 : 0.0;
		}
		consider(_px[i], _py[i], rr2, _side[i], _phy[i] != 0, beyond, fin ? 1.0 : 0.0, cz);
	}
	const int64_t nr = _bc_rows.size() / 8;
	const double *rw = _bc_rows.ptr();
	for (int64_t k = 0; k < nr; k++) {
		const double *w = rw + k * 8;
		consider(w[0], w[1], w[2], (int)w[3], w[4] > 0.5, w[5], w[6], w[7]);
	}
	if (cand.empty()) return out;
	const double PI_ = 3.14159265358979323846;
	const double mids[4] = { -PI_ / 2.0, PI_ / 2.0, PI_, 0.0 };
	const double offs[5] = { -PI_ / 6.0, -PI_ / 12.0, 0.0, PI_ / 12.0, PI_ / 6.0 };
	for (int a = 0; a < 4; a++) {
		double worst = 0.0;
		for (int k = 0; k < 5; k++) {
			const double ang = mids[a] + offs[k];
			const double ux = std::cos(ang), uy = std::sin(ang);
			double best_t = -1.0;
			for (const C &c : cand) {
				const double th = bc_ray_hit(ex, ey, ux, uy, len, c.x, c.y, c.r);
				if (th >= 0.0 && (best_t < 0.0 || th < best_t)) best_t = th;
			}
			if (best_t >= 0.0) {
				const double blk = (len - best_t) / len;
				if (blk > worst) worst = blk;
			}
		}
		o[a] = (float)worst;
	}
	return out;
}

void Th75MotionHot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_frozen", "ox", "oy", "dx", "dy", "spd", "t0", "alive0", "px0", "py0", "range", "radius", "oob_mode", "side", "is_phy", "hidden", "mask_r"), &Th75MotionHot::register_frozen);
	ClassDB::bind_method(D_METHOD("hcs_set_extra", "rows"), &Th75MotionHot::hcs_set_extra);
	ClassDB::bind_method(D_METHOD("hcs_hct", "ex", "ey", "n_spd", "spin", "ent_side"), &Th75MotionHot::hcs_hct);
	ClassDB::bind_method(D_METHOD("bc_set_extra", "rows"), &Th75MotionHot::bc_set_extra);
	ClassDB::bind_method(D_METHOD("bc_rays", "ex", "ey", "len", "ent_side", "mode"), &Th75MotionHot::bc_rays);
	ClassDB::bind_method(D_METHOD("bc_set_zones", "rows"), &Th75MotionHot::bc_set_zones);
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
