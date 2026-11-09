#ifndef TH75_BULLET_HOT_H
#define TH75_BULLET_HOT_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class Th75BulletHot : public RefCounted {
	GDCLASS(Th75BulletHot, RefCounted)

private:
	// 逆波兰式（RPN）编译结果
	struct Token {
		enum Kind : uint8_t { NUM, VAR, OP, FUNC1, FUNC2, COND } kind;
		uint8_t op;         // OP: '+','-','*','/','%' FUNC id
		double num;
		uint16_t var_idx;   // VAR: 变量表下标
	};
	PackedVector2Array _rpn; // x=token.kind 压缩？——改用 Array[Token] 平铺：
	// 平铺存储：kind/op 打包 int32，num 存 double 数组，var_idx 存 int 数组
	struct Program {
		PackedInt32Array kinds;   // 0=NUM 1=VAR 2=OP 3=FUNC1 4=FUNC2 5=COND
		PackedInt32Array meta;    // OP: 字符码；FUNC: 函数号；VAR: 下标
		PackedFloat64Array nums;  // NUM 池（f64 全程，免 f32 截断）
		bool ok = false;
	};
	Program _prog;
	int _stride = 0; // 变量数（compile 时记录）
	bool _compile_text(const String &text, const PackedStringArray &vars);
	static double _f1(int id, double a);
	static double _f2(int id, double a, double b);

public:
	static void _bind_methods();

	// 编译：返回错误信息（空=成功）
	String compile(const String &text, const PackedStringArray &vars);
	// 求值：values 与 vars 等长；失败返回 fallback
	double eval(const PackedFloat64Array &values, double fallback) const;
	// 【批量】同表达式对 n 发弹求值：values=行主序 n×vars.size()；
	// 返回长度 n 的结果数组（求值失败的行为 fallback）
	PackedFloat64Array eval_batch(const PackedFloat64Array &values, int64_t n, double fallback) const;
	bool is_ok() const { return _prog.ok; }
	String get_text() const { return _src; }
	String _src;
};

} // namespace godot

#endif // TH75_BULLET_HOT_H
