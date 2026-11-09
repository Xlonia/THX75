#ifndef TH75_BULLET_HASH_CPP_H
#define TH75_BULLET_HASH_CPP_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/templates/local_vector.hpp>

#include <cmath>

namespace godot {

// 【0.0.9 性能②】弹幕空间哈希 C++ 化
// 32px 格、13×13；行格式 [x, y, r, ref_id, side]
// skip 语义与 GD 版一致：query 时 skip_side 的"非物弹"跳过、物弹双向
class Th75BulletHashCpp : public RefCounted {
	GDCLASS(Th75BulletHashCpp, RefCounted)

private:
	static const int CELL = 32;
	static const int GRID = 13; // 400/32+1
	LocalVector<LocalVector<int64_t>> _cells; // 每格 ref_id 列表
	LocalVector<double> _rx, _ry, _rr; // ref_id → 位置/半径（查询用）
	LocalVector<int> _rside;
	LocalVector<bool> _rphy;

public:
	static void _bind_methods();

	void begin_frame();
	int64_t insert(double x, double y, double r, int64_t ref_id, int side, bool is_phy);
	// 查询：返回 ref_id 列表（调用方映射回 Bullet）
	PackedInt32Array query(double cx, double cy, double r, int skip_side) const;
	int64_t count() const { return (int64_t)_rx.size(); }
};

} // namespace godot

#endif
