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
	std::vector<int> _side;      // source_side（Hcs 威胁过滤）
	std::vector<char> _phy;      // is_phy
	std::vector<char> _hid;      // hidden_now（接管弹 pass 已定值折叠=常量）
	std::vector<double> _maskr;  // 【BC·DDM 口径】友伤遮罩半径（15×source 慢机速度；0=法弹不用）
	std::vector<double> _ox2; std::vector<double> _oy2; // 注册原点（beyond 判定）
	std::vector<char> _alive;
	// 【审计 B2】Hcs/Hct 非接管弹快照（每拍 GD 打包一次：x,y,dx,dy,spd,rad,side,phy）
	PackedFloat64Array _hx_rows;
	PackedFloat64Array _bc_rows; // 【BC】非接管弹快照（x,y,r,side,phy,beyond,fin,cz）
	PackedFloat64Array _bc_zones;
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
			double t0, double alive0, double px0, double py0, double range, double radius, int64_t oob_mode,
			int64_t side, bool is_phy, bool hidden, double mask_r);
	// 【0.0.9·审计 B2 Hcs/Hct C++ 化 20261109】
	// 非接管弹（约 5%）每拍由 GD 打包：每行 8 值 x,y,dir_x,dir_y,spd,rad,side,phy
	void hcs_set_extra(const PackedFloat64Array &rows) { _hx_rows = rows; }
	// 单实体 49 点 Hcs/Hct（接管 slot 全量 + 非接管快照）——口径逐条复刻
	// battle_arena._compute_hcs_hct；返回 98 值：hcs[0..48] 后接 hct[0..48]
	PackedFloat32Array hcs_hct(double ex, double ey, double n_spd, double spin, int64_t ent_side) const;
	// 【0.0.9·基础规避 BC（新三 213-218；第⑤问 20261109 双口径）】
	// 非接管弹每帧由 GD 打包一次：每行 8 值 x,y,r,side,phy,beyond,in_field,in_clear
	void bc_set_extra(const PackedFloat64Array &rows) { _bc_rows = rows; }
	// 消弹区（每帧同步：x,y,r…）——DDM 口径下区内的弹不参与（与 DDM 印章跳过同源）
	void bc_set_zones(const PackedFloat64Array &rows) { _bc_zones = rows; }
	// 四个基础规避方向弧（上/下/左/右，各 ±30°）每弧 5 条射线（-30/-15/0/+15/+30°，
	// 长 len=0.1 秒距）；返回 4 值=各弧阻断比例（取 5 条中最大者；0=无弹 1=贴身）。
	// 弹幕判定用显示半径（所见即所判）。
	// mode 0=弹幕本体（本侧物理弹一律威胁——"阻止与物弹角色搭档"对战逻辑用）
	// mode 1=DDM 口径（默认）：本侧法弹与遮罩内物弹不构成威胁（可入友方遮罩组火力组）
	PackedFloat32Array bc_rays(double ex, double ey, double len, int64_t ent_side, int64_t mode) const;
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
