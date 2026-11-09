#include "bullet_hash_cpp.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void Th75BulletHashCpp::begin_frame() {
	for (auto &c : _cells) {
		c.clear();
	}
	if (_cells.is_empty()) {
		_cells.resize(GRID * GRID);
	}
}

int64_t Th75BulletHashCpp::insert(double x, double y, double r, int64_t ref_id, int side, bool is_phy) {
	int idx = (int)_rx.size();
	_rx.push_back(x);
	_ry.push_back(y);
	_rr.push_back(r);
	_rside.push_back(side);
	_rphy.push_back(is_phy);
	int x0 = (int)floor((x - r) / CELL);
	int x1 = (int)floor((x + r) / CELL);
	int y0 = (int)floor((y - r) / CELL);
	int y1 = (int)floor((y + r) / CELL);
	for (int gy = y0; gy <= y1; gy++) {
		if (gy < 0 || gy >= GRID) continue;
		for (int gx = x0; gx <= x1; gx++) {
			if (gx < 0 || gx >= GRID) continue;
			_cells[gy * GRID + gx].push_back(idx);
		}
	}
	return idx;
}

PackedInt32Array Th75BulletHashCpp::query(double cx, double cy, double r, int skip_side) const {
	PackedInt32Array out;
	int x0 = (int)floor((cx - r - CELL) / CELL);
	int x1 = (int)floor((cx + r + CELL) / CELL);
	int y0 = (int)floor((cy - r - CELL) / CELL);
	int y1 = (int)floor((cy + r + CELL) / CELL);
	for (int gy = y0; gy <= y1; gy++) {
		if (gy < 0 || gy >= GRID) continue;
		for (int gx = x0; gx <= x1; gx++) {
			if (gx < 0 || gx >= GRID) continue;
			for (int idx : _cells[gy * GRID + gx]) {
				double dx = _rx[idx] - cx;
				double dy = _ry[idx] - cy;
				if (dx * dx + dy * dy > (r + _rr[idx]) * (r + _rr[idx])) continue;
				if (_rside[idx] == skip_side && !_rphy[idx]) continue;
				out.push_back(idx);
			}
		}
	}
	return out;
}

void Th75BulletHashCpp::_bind_methods() {
	ClassDB::bind_method(D_METHOD("begin_frame"), &Th75BulletHashCpp::begin_frame);
	ClassDB::bind_method(D_METHOD("insert", "x", "y", "r", "ref_id", "side", "is_phy"), &Th75BulletHashCpp::insert);
	ClassDB::bind_method(D_METHOD("query", "cx", "cy", "r", "skip_side"), &Th75BulletHashCpp::query);
	ClassDB::bind_method(D_METHOD("count"), &Th75BulletHashCpp::count);
}
