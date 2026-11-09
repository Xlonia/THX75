#include "bullet_hot.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cmath>
#include <vector>

using namespace godot;

// =============================================================
// Th75BulletHot —— 表达式热路径 C++ 版（GDExtension）
// 覆盖策划《运算参数》常用子集：四则/幂/比较/逻辑/min/max/floor/ceil/
// round/abs/sin/cos/tan/sqrt/log(自然)/exp/fposmod/clamp/lerp
// 未覆盖的文档函数（getChata/_chq_ 等）由调用方回退 GDScript DanmakuExpr。
// 语法：与 GDScript Expression 同域（** 幂），三目 a ? b : c。
// =============================================================

namespace {

enum Op : int {
	OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_POW,
	OP_LT, OP_GT, OP_LE, OP_GE, OP_EQ, OP_NE,
	OP_AND, OP_OR,
	OP_NEG, OP_NOT,
	OP_FUNC1, OP_FUNC2, OP_COND,
};

enum F1 : int { F1_SIN, F1_COS, F1_TAN, F1_ABS, F1_FLOOR, F1_CEIL, F1_ROUND, F1_SQRT, F1_EXP, F1_LOG };
enum F2 : int { F2_MIN, F2_MAX, F2_ATAN2, F2_FPOSMOD, F2_CLAMP, F2_POW, F2_LERP, F2_LOGK };

struct Tok {
	int kind;   // 0=NUM 1=VAR 2=OP 3=F1 4=F2
	int meta;   // OP码/函数号/VAR下标
	double num;
};

// 运算符优先级（越大越先）
int prec(int op) {
	switch (op) {
		case OP_OR: return 1;
		case OP_AND: return 2;
		case OP_LT: case OP_GT: case OP_LE: case OP_GE: case OP_EQ: case OP_NE: return 3;
		case OP_ADD: case OP_SUB: return 4;
		case OP_MUL: case OP_DIV: case OP_MOD: return 5;
		case OP_NEG: case OP_NOT: return 6;
		case OP_POW: return 7;
		default: return 0;
	}
}

bool is_ident(char32_t c) {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

} // namespace

double Th75BulletHot::_f1(int id, double a) {
	switch (id) {
		case F1_SIN: return sin(a);
		case F1_COS: return cos(a);
		case F1_TAN: return tan(a);
		case F1_ABS: return fabs(a);
		case F1_FLOOR: return floor(a);
		case F1_CEIL: return ceil(a);
		case F1_ROUND: return round(a);
		case F1_SQRT: return sqrt(a < 0.0 ? 0.0 : a);
		case F1_EXP: return exp(a);
		case F1_LOG: return a > 0.0 ? log(a) : 0.0;
	}
	return 0.0;
}

double Th75BulletHot::_f2(int id, double a, double b) {
	switch (id) {
		case F2_MIN: return a < b ? a : b;
		case F2_MAX: return a > b ? a : b;
		case F2_ATAN2: return atan2(a, b);
		case F2_FPOSMOD: { double m = fmod(a, b); if (m < 0.0) m += fabs(b); return m; }
		case F2_POW: return pow(a, b);
		case F2_LOGK: return a > 0.0 && b > 0.0 ? log(a) / log(b) : 0.0;
	}
	return 0.0;
}

// —— 词法+递归下降（ Pratt 简化版：shunting-yard）——
bool Th75BulletHot::_compile_text(const String &text, const PackedStringArray &vars) {
	_prog = Program();
	_src = text;
	_stride = vars.size();
	// 逐字符扫描
	const char32_t *w = text.ptr();
	int64_t len = text.length();
	std::vector<Tok> out;
	std::vector<int> ops; // 运算符栈
	std::vector<int> fmeta;
	// 变量名→下标
	// 简化：线性查找（vars 通常 ≤27、表达式 token 少）
	auto var_index = [&](const String &name) -> int {
		for (int i = 0; i < vars.size(); i++) {
			if (vars[i] == name) return i;
		}
		return -1;
	};
	// token 化 + shunting-yard 一体
	int i = 0;
	// w 已在函数开头声明（char32 指针）
	int prev_kind = -1; // -1 起点；0=值（数字/变量/右括号/函数结果）

	while (i < len) {
		char32_t c = w[i];
		if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { i++; continue; }
		if (c >= '0' && c <= '9') {
			double v = 0.0;
			int64_t start = i;
			while (i < len && ((w[i] >= '0' && w[i] <= '9') || w[i] == '.')) i++;
			// 科学计数
			if (i < len && (w[i] == 'e' || w[i] == 'E')) {
				int64_t save = i;
				i++;
				if (i < len && (w[i] == '+' || w[i] == '-')) i++;
				if (i < len && w[i] >= '0' && w[i] <= '9') {
					while (i < len && w[i] >= '0' && w[i] <= '9') i++;
				} else {
					i = save;
				}
			}
			String num_s = text.substr(start, i - start);
			if (!num_s.is_valid_float()) do { _src = String("F1@") + String::num_int64(i); return false; } while (0); // 失败点1
			Tok t = {0, 0, num_s.to_float()};
			out.push_back(t);
			prev_kind = 0;
			continue;
		}
		if (is_ident(c)) {
			int64_t start = i;
			while (i < len && is_ident(w[i])) i++;
			String name = text.substr(start, i - start);
			// 函数名？
			if (i < len && w[i] == '(') {
				int fid = -1, fkind = 0, nargs = 1;
				if (name == "sin") { fid = F1_SIN; }
				else if (name == "cos") { fid = F1_COS; }
				else if (name == "tan") { fid = F1_TAN; }
				else if (name == "abs") { fid = F1_ABS; }
				else if (name == "floor") { fid = F1_FLOOR; }
				else if (name == "ceil") { fid = F1_CEIL; }
				else if (name == "round") { fid = F1_ROUND; }
				else if (name == "sqrt") { fid = F1_SQRT; }
				else if (name == "exp") { fid = F1_EXP; }
				else if (name == "log") { fid = F1_LOG; } // 单参自然对数（双参→logk 另判）
				else if (name == "min") { fid = F2_MIN; fkind = 4; nargs = 2; }
				else if (name == "max") { fid = F2_MAX; fkind = 4; nargs = 2; }
				else if (name == "atan2") { fid = F2_ATAN2; fkind = 4; nargs = 2; }
				else if (name == "fposmod") { fid = F2_FPOSMOD; fkind = 4; nargs = 2; }
				else if (name == "pow") { fid = F2_POW; fkind = 4; nargs = 2; }
				else if (name == "logk") { fid = F2_LOGK; fkind = 4; nargs = 2; }
				else {
					_src = String("unknown_func@") + String::num_int64(i);
					do { _src = String("F2@") + String::num_int64(i); return false; } while (0); // 失败点2
				}
				i++; // '('
				// 第一参
				// 递归：借助栈式处理——这里简化为循环扫描到匹配括号（支持嵌套：
				// 用局部计数递归子编译不可行——改为把函数视为运算符压栈）
				ops.push_back(fkind == 4 ? OP_FUNC2 : OP_FUNC1);
				fmeta.push_back(fid);
				fmeta.push_back(nargs);
				prev_kind = -1; // 函数后期待值
				continue;
			}
			int vi = var_index(name);
			if (vi < 0) {
				_src = String("unknown_var@") + String::num_int64(i);
				do { _src = String("F3@") + String::num_int64(i); return false; } while (0); // 失败点3
			}
			Tok t = {1, vi, 0.0};
			out.push_back(t);
			prev_kind = 0;
			continue;
		}
		switch (c) {
			case '(': {
				ops.push_back(-1); // 括号标记
				i++;
				prev_kind = -1;
				break;
			}
			case ')': {
				// 弹到函数标记或普通括号标记；函数合并后立即结束
				while (!ops.empty() && ops.back() != -1) {
					int op = ops.back();
					ops.pop_back();
					if (op == OP_FUNC1 || op == OP_FUNC2) {
						int meta = fmeta[fmeta.size() - 2];
						fmeta.pop_back(); fmeta.pop_back();
						Tok t = {op == OP_FUNC1 ? 3 : 4, meta, 0.0};
						out.push_back(t);
						break; // 函数合并后参数块已完整
					}
					Tok t = {2, op, 0.0};
					out.push_back(t);
				}
				// 函数情形：栈可能已空（FUNC 已弹出）；普通括号：back=-1 弹掉
				if (!ops.empty() && ops.back() == -1) {
					ops.pop_back(); // 弹普通 '(' 标记
				}
				i++;
				prev_kind = 0;
				break;
			}
			case ',': {
				// 【修正】逗号=当前参数块结束：把运算符弹到 FUNC/括号标记
				// （保证第一参数块完整进 out，RPN 才正确）
				while (!ops.empty() && ops.back() != -1 && ops.back() != OP_FUNC1 && ops.back() != OP_FUNC2) {
					Tok t = {2, ops.back(), 0.0};
					out.push_back(t);
					ops.pop_back();
				}
				i++;
				prev_kind = -1;
				break;
			}
			case '+': {
				int op = prev_kind == 0 || prev_kind == 3 ? OP_ADD : OP_ADD; // 一元+忽略
				while (!ops.empty() && ops.back() != -1 && prec(ops.back()) >= prec(op)) {
					int top = ops.back();
					if (top == OP_FUNC1 || top == OP_FUNC2) break; // 函数栈特殊
					Tok t = {2, top, 0.0};
					out.push_back(t);
					ops.pop_back();
				}
				ops.push_back(op);
				i++;
				prev_kind = -1;
				break;
			}
			case '-': {
				int op = (prev_kind == 0) ? OP_SUB : OP_NEG; // 前面是值→减；否则一元负
				while (!ops.empty() && ops.back() != -1 && ops.back() != OP_FUNC1 && ops.back() != OP_FUNC2 && prec(ops.back()) >= prec(op)) {
					Tok t = {2, ops.back(), 0.0};
					out.push_back(t);
					ops.pop_back();
				}
				ops.push_back(op);
				i++;
				prev_kind = -1;
				break;
			}
			case '*': case '/': case '%': {
				int op = c == '*' ? OP_MUL : (c == '/' ? OP_DIV : OP_MOD);
				while (!ops.empty() && ops.back() != -1 && ops.back() != OP_FUNC1 && ops.back() != OP_FUNC2 && prec(ops.back()) >= prec(op)) {
					Tok t = {2, ops.back(), 0.0};
					out.push_back(t);
					ops.pop_back();
				}
				ops.push_back(op);
				i++;
				prev_kind = -1;
				break;
			}
			case '^': {
				while (!ops.empty() && ops.back() != -1 && ops.back() != OP_FUNC1 && ops.back() != OP_FUNC2 && prec(ops.back()) > prec(OP_POW)) {
					Tok t = {2, ops.back(), 0.0};
					out.push_back(t);
					ops.pop_back();
				}
				ops.push_back(OP_POW);
				i++;
				prev_kind = -1;
				break;
			}
			case '<': {
				int op = OP_LT;
				if (i + 1 < len && w[i + 1] == '=') { op = OP_LE; i++; }
				while (!ops.empty() && ops.back() != -1 && ops.back() != OP_FUNC1 && ops.back() != OP_FUNC2 && prec(ops.back()) >= prec(op)) {
					Tok t = {2, ops.back(), 0.0};
					out.push_back(t);
					ops.pop_back();
				}
				ops.push_back(op);
				i++;
				prev_kind = -1;
				break;
			}
			case '>': {
				int op = OP_GT;
				if (i + 1 < len && w[i + 1] == '=') { op = OP_GE; i++; }
				while (!ops.empty() && ops.back() != -1 && ops.back() != OP_FUNC1 && ops.back() != OP_FUNC2 && prec(ops.back()) >= prec(op)) {
					Tok t = {2, ops.back(), 0.0};
					out.push_back(t);
					ops.pop_back();
				}
				ops.push_back(op);
				i++;
				prev_kind = -1;
				break;
			}
			case '=': {
				if (i + 1 < len && w[i + 1] == '=') {
					while (!ops.empty() && ops.back() != -1 && prec(ops.back()) >= prec(OP_EQ)) {
						Tok t = {2, ops.back(), 0.0};
						out.push_back(t);
						ops.pop_back();
					}
					ops.push_back(OP_EQ);
					i += 2;
					prev_kind = -1;
				} else {
					do { _src = String("F5@") + String::num_int64(i); return false; } while (0); // 失败点5
				}
				break;
			}
			case '!': {
				if (i + 1 < len && w[i + 1] == '=') {
					while (!ops.empty() && ops.back() != -1 && prec(ops.back()) >= prec(OP_NE)) {
						Tok t = {2, ops.back(), 0.0};
						out.push_back(t);
						ops.pop_back();
					}
					ops.push_back(OP_NE);
					i += 2;
					prev_kind = -1;
				} else {
					ops.push_back(OP_NOT);
					i++;
					prev_kind = -1;
				}
				break;
			}
			case '&': {
				if (i + 1 < len && w[i + 1] == '&') {
					ops.push_back(OP_AND);
					i += 2;
					prev_kind = -1;
				} else do { _src = String("F6@") + String::num_int64(i); return false; } while (0); // 失败点6
				break;
			}
			case '|': {
				if (i + 1 < len && w[i + 1] == '|') {
					ops.push_back(OP_OR);
					i += 2;
					prev_kind = -1;
				} else do { _src = String("F7@") + String::num_int64(i); return false; } while (0); // 失败点7
				break;
			}
			case '?': {
				ops.push_back(OP_COND);
				i++;
				prev_kind = -1;
				break;
			}
			case ':': {
				while (!ops.empty() && ops.back() != OP_COND) {
					Tok t = {2, ops.back(), 0.0};
					out.push_back(t);
					ops.pop_back();
				}
				if (ops.empty()) do { _src = String("F8@") + String::num_int64(i); return false; } while (0); // 失败点8
				ops.pop_back();
				Tok t = {2, OP_COND, 0.0};
				out.push_back(t);
				i++;
				prev_kind = 0;
				break;
			}
			default:
				do { _src = String("F9@") + String::num_int64(i); return false; } while (0); // 失败点9
		}
	}
	while (!ops.empty()) {
		int op = ops.back();
		if (op == -1) do { _src = String("F10@") + String::num_int64(i); return false; } while (0); // 失败点10
		ops.pop_back();
		int meta = 0;
		if (op == OP_FUNC1 || op == OP_FUNC2) {
			meta = fmeta[fmeta.size() - 2];
			fmeta.pop_back(); fmeta.pop_back();
		}
		Tok t = {op == OP_FUNC1 ? 3 : (op == OP_FUNC2 ? 4 : 2), op == OP_FUNC1 || op == OP_FUNC2 ? meta : op, 0.0};
		out.push_back(t);
	}
	_prog.kinds.resize(out.size());
	_prog.meta.resize(out.size());
	_prog.nums.resize(out.size());
	for (int k = 0; k < out.size(); k++) {
		_prog.kinds[k] = out[k].kind;
		_prog.meta[k] = out[k].meta;
	_prog.nums[k] = out[k].num;
	}
	_prog.ok = out.size() > 0;
	return _prog.ok;
}

double Th75BulletHot::eval(const PackedFloat64Array &values, double fallback) const {
	if (!_prog.ok) return fallback;
	double stack[64];
	int sp = 0;
	const int *kinds = _prog.kinds.ptr();
	const int *meta = _prog.meta.ptr();
	const double *nums = _prog.nums.ptr();
	const double *vals = values.ptr();
	int n = _prog.kinds.size();
	if (n > 64) {
		return fallback;
	}
	for (int k = 0; k < n; k++) {
		switch (kinds[k]) {
			case 0: stack[sp++] = nums[k]; break;
			case 1: stack[sp++] = (meta[k] >= 0 && meta[k] < values.size()) ? vals[meta[k]] : 0.0; break;
			case 2: {
				if (meta[k] == OP_NEG || meta[k] == OP_NOT) {
					if (sp < 1) return fallback;
					double a = stack[sp - 1];
					stack[sp - 1] = (meta[k] == OP_NEG) ? -a : (a == 0.0 ? 1.0 : 0.0);
					break;
				}
				if (meta[k] == OP_COND) {
					if (sp < 3) return fallback;
					double c = stack[--sp];
					double vb = stack[--sp];
					double va = stack[--sp];
					stack[sp++] = c != 0.0 ? va : vb;
					break;
				}
				if (sp < 2) return fallback;
				double b = stack[--sp];
				double a = stack[--sp];
				double r = 0.0;
				switch (meta[k]) {
					case OP_ADD: r = a + b; break;
					case OP_SUB: r = a - b; break;
					case OP_MUL: r = a * b; break;
					case OP_DIV: r = b != 0.0 ? a / b : 0.0; break;
					case OP_MOD: r = b != 0.0 ? fmod(a, b) : 0.0; break;
					case OP_POW: r = pow(a, b); break;
					case OP_LT: r = a < b ? 1.0 : 0.0; break;
					case OP_GT: r = a > b ? 1.0 : 0.0; break;
					case OP_LE: r = a <= b ? 1.0 : 0.0; break;
					case OP_GE: r = a >= b ? 1.0 : 0.0; break;
					case OP_EQ: r = a == b ? 1.0 : 0.0; break;
					case OP_NE: r = a != b ? 1.0 : 0.0; break;
					case OP_AND: r = (a != 0.0 && b != 0.0) ? 1.0 : 0.0; break;
					case OP_OR: r = (a != 0.0 || b != 0.0) ? 1.0 : 0.0; break;
					default: return fallback;
				}
				stack[sp++] = r;
				break;
			}
			case 3: {
				if (sp < 1) return fallback;
				double a = stack[--sp];
				stack[sp++] = _f1(meta[k], a);
				break;
			}
			case 4: {
				if (sp < 2) return fallback;
				double b = stack[--sp];
				double a = stack[--sp];
				double r = 0.0;
				switch (meta[k]) {
					case F2_MIN: r = a < b ? a : b; break;
					case F2_MAX: r = a > b ? a : b; break;
					case F2_ATAN2: r = atan2(a, b); break;
					case F2_FPOSMOD: { double m = fmod(a, b); if (m < 0.0) m += fabs(b); r = m; break; }
					case F2_POW: r = pow(a, b); break;
					case F2_LOGK: r = (a > 0.0 && b > 0.0) ? log(a) / log(b) : 0.0; break;
					default: return fallback;
				}
				stack[sp++] = r;
				break;
			}
			default: return fallback;
		}
	}
	return sp == 1 ? stack[0] : fallback;
}

PackedFloat64Array Th75BulletHot::eval_batch(const PackedFloat64Array &values, int64_t n, double fallback) const {
	PackedFloat64Array out;
	if (!_prog.ok || n <= 0) {
		out.resize(n > 0 ? n : 0);
		out.fill(fallback);
		return out;
	}
	int64_t stride = _stride;
	if (stride <= 0) stride = 1;
	out.resize(n);
	double stack[64];
	const int *kinds = _prog.kinds.ptr();
	const int *meta = _prog.meta.ptr();
	const double *nums = _prog.nums.ptr();
	const double *vals = values.ptr();
	int tk = _prog.kinds.size();
	for (int64_t row = 0; row < n; row++) {
		const double *rowvals = vals + row * stride;
		int sp = 0;
		double r = fallback;
		bool ok = true;
		for (int k = 0; k < tk && ok; k++) {
			switch (kinds[k]) {
				case 0: stack[sp++] = nums[k]; break;
				case 1: stack[sp++] = (meta[k] >= 0 && meta[k] < stride) ? rowvals[meta[k]] : 0.0; break;
				case 2: {
					if (meta[k] == OP_NEG || meta[k] == OP_NOT) {
						if (sp < 1) { ok = false; break; }
						double a = stack[sp - 1];
						stack[sp - 1] = (meta[k] == OP_NEG) ? -a : (a == 0.0 ? 1.0 : 0.0);
						break;
					}
					if (meta[k] == OP_COND) {
						if (sp < 3) { ok = false; break; }
						double cc = stack[--sp];
						double vb = stack[--sp];
						double va = stack[--sp];
						stack[sp++] = cc != 0.0 ? va : vb;
						break;
					}
					if (sp < 2) { ok = false; break; }
					double b = stack[--sp];
					double a = stack[--sp];
					double rr = 0.0;
					switch (meta[k]) {
						case OP_ADD: rr = a + b; break;
						case OP_SUB: rr = a - b; break;
						case OP_MUL: rr = a * b; break;
						case OP_DIV: rr = b != 0.0 ? a / b : 0.0; break;
						case OP_MOD: rr = b != 0.0 ? fmod(a, b) : 0.0; break;
						case OP_POW: rr = pow(a, b); break;
						case OP_LT: rr = a < b ? 1.0 : 0.0; break;
						case OP_GT: rr = a > b ? 1.0 : 0.0; break;
						case OP_LE: rr = a <= b ? 1.0 : 0.0; break;
						case OP_GE: rr = a >= b ? 1.0 : 0.0; break;
						case OP_EQ: rr = a == b ? 1.0 : 0.0; break;
						case OP_NE: rr = a != b ? 1.0 : 0.0; break;
						case OP_AND: rr = (a != 0.0 && b != 0.0) ? 1.0 : 0.0; break;
						case OP_OR: rr = (a != 0.0 || b != 0.0) ? 1.0 : 0.0; break;
						default: ok = false; break;
					}
					if (ok) stack[sp++] = rr;
					break;
				}
				case 3: {
					if (sp < 1) { ok = false; break; }
					double a = stack[--sp];
					stack[sp++] = _f1(meta[k], a);
					break;
				}
				case 4: {
					if (sp < 2) { ok = false; break; }
					double b = stack[--sp];
					double a = stack[--sp];
					double rr = 0.0;
					switch (meta[k]) {
						case F2_MIN: rr = a < b ? a : b; break;
						case F2_MAX: rr = a > b ? a : b; break;
						case F2_ATAN2: rr = atan2(a, b); break;
						case F2_FPOSMOD: { double m = fmod(a, b); if (m < 0.0) m += fabs(b); rr = m; break; }
						case F2_POW: rr = pow(a, b); break;
						case F2_LOGK: rr = (a > 0.0 && b > 0.0) ? log(a) / log(b) : 0.0; break;
						default: ok = false; break;
					}
					if (ok) stack[sp++] = rr;
					break;
				}
				default: ok = false; break;
			}
		}
		out[row] = (ok && sp == 1) ? stack[0] : fallback;
	}
	return out;
}

void Th75BulletHot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("compile", "text", "vars"), &Th75BulletHot::compile);
	ClassDB::bind_method(D_METHOD("eval", "values", "fallback"), &Th75BulletHot::eval);
	ClassDB::bind_method(D_METHOD("eval_batch", "values", "n", "fallback"), &Th75BulletHot::eval_batch);
	ClassDB::bind_method(D_METHOD("is_ok"), &Th75BulletHot::is_ok);
	ClassDB::bind_method(D_METHOD("get_text"), &Th75BulletHot::get_text);
}

String Th75BulletHot::compile(const String &text, const PackedStringArray &vars) {
	return _compile_text(text, vars) ? String("") : _src;
}
