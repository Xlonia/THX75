#ifndef TH75_MOTION_HOT_H
#define TH75_MOTION_HOT_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class Th75MotionHot : public RefCounted {
	GDCLASS(Th75MotionHot, RefCounted)

private:
	// 查表池：tid → (x[],y[]) 交错 2×n_pts
	LocalVector<PackedFloat64Array> _tables;
	LocalVector<int> _table_pts;

public:
	static void _bind_methods();

	int register_table(const PackedFloat64Array &xy_interleaved, int64_t n_pts);
	// 冻结弹批量：输入（每弹一行 8 值：origin_x, origin_y, dir_x, dir_y,
	// speed, t, rot_c, rot_s）→ 输出 pos_x,pos_y（交错 2n）
	// rot_c/rot_s=cos/sin(rot_angle)（GDScript 预算，避免 C++ 侧 sin/cos 重复）
	PackedFloat64Array step_frozen(const PackedFloat64Array &rows, int64_t n) const;
	// 查表弹批量：每弹一行 9 值：tid, t, origin_x, origin_y, rot_c, rot_s,
	// speed, dt, table_t0 —— dir=表值旋转，pos+=dir*speed*dt（积分语义）
	PackedFloat64Array step_table(const PackedFloat64Array &rows, int64_t n) const;
	int table_count() const { return _tables.size(); }
};

} // namespace godot

#endif
