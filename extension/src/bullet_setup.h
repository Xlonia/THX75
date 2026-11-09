#ifndef TH75_BULLET_SETUP_H
#define TH75_BULLET_SETUP_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

namespace godot {

// 【0.0.9 性能①】Bullet.setup C++ 化（策划书 ✰性能优化方面）
// 输入紧凑状态行（每弹一行），输出派生字段——GDScript 侧负责
// 表达式求值（BulletHot 已 C++）与快照查询，本类做纯计算部分：
//   偏移叠加、冻结射线解算、旋转重排、生命周期初值
// 对齐验证：与 GDScript setup 逐字段对照（开关并行期）
class Th75BulletSetup : public RefCounted {
	GDCLASS(Th75BulletSetup, RefCounted)

public:
	static void _bind_methods();

	// 应用 spawn 偏移+冻结射线解算（regular/physical 非 motion 弹）
	// row = [ox, oy, dir_x, dir_y, speed, t, rot_c, rot_s, frozen_ok]
	// 返回 [pos_x, pos_y, dir_x, dir_y, track_speed]
	PackedFloat64Array apply_frozen(const PackedFloat64Array &rows, int64_t n) const;
};

} // namespace godot

#endif
