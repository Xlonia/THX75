#ifndef TH75_MOTION_HOT_H
#define TH75_MOTION_HOT_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <vector>

namespace godot {

// =============================================================
// 【0.0.9·审计①-1 完整状态 C++ 接管 20261109】
// 纯定值弹（frozen 解析式 + 无表达式色/隐身 + 非反射 + 非 repeat 载体）
// 的运动状态**单一写者=C++**：t、存活帧、pos、航程死亡、出界死亡
// 全部在 C++ 内推进与判定；GD 侧该弹整帧跳过 update()。
// 吸取 1102c 教训（GD/C++ 混合双遍式=同帧多消费者错位）：接管弹的
// 上述状态 GD 绝不写，只在 C++ 帧推进后单点读回（pos/t 回填供渲染/
// 哈希/AI 读取）。
// 死亡口径与 GD update() 逐条一致（见 begin_frame 注释）。
// =============================================================
class Th75MotionHot : public RefCounted {
	GDCLASS(Th75MotionHot, RefCounted)

private:
	// 查表池（旧批量接口保留：step_table 等）
	LocalVector<PackedFloat64Array> _tables;
	LocalVector<int> _table_pts;
	// slot 制 SoA（成员——旧版是文件级全局，多实例共享=串台）
	std::vector<double> _ox, _oy, _dx, _dy, _spd;
	std::vector<double> _t;      // 弹 t（与 GD 语义同：每帧 +dt）
	std::vector<double> _alive_f; // 存活帧（GD _alive_frames 同语义）
	std::vector<double> _range;  // range_now（帧）
	std::vector<double> _radius; // draw_radius
	std::vector<int> _oob;       // 0=出界即死 2=不处理（仅 64px 远界兜底）
	std::vector<double> _px, _py;
	std::vector<char> _alive;
	std::vector<int> _free;
	// 本帧结果
	PackedInt32Array _dead;
	PackedFloat64Array _out; // 每活 slot 3 值：slot, px, py（紧凑）
	int64_t _live = 0;

	int _alloc();

public:
	static void _bind_methods();

	int register_table(const PackedFloat64Array &xy_interleaved, int64_t n_pts);
	PackedFloat64Array step_frozen(const PackedFloat64Array &rows, int64_t n) const;
	PackedFloat64Array step_table(const PackedFloat64Array &rows, int64_t n) const;
	PackedFloat64Array step_wfrozen(const PackedFloat64Array &rows, int64_t n) const;
	int table_count() const { return _tables.size(); }

	// 注册（setup 冻结判定之后调用）：t0/alive0=GD 当前 t/_alive_frames
	int64_t register_frozen(double ox, double oy, double dx, double dy, double spd,
			double t0, double alive0, double px0, double py0, double range, double radius, int64_t oob_mode);
	void set_frozen_alive(int64_t slot, bool alive);
	// 推进一帧（dt=1.0 帧）；死亡写 _dead，活弹写 _out（slot,px,py）
	void begin_frame(double dt);
	PackedFloat64Array get_frozen_pos() const { return _out; }
	PackedInt32Array get_dead() const { return _dead; }
	double get_t(int64_t slot) const;
	double get_alive_frames(int64_t slot) const;
	int64_t live_count() const { return _live; }
	void clear_all();
};

} // namespace godot

#endif
