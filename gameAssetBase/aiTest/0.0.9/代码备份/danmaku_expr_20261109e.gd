class_name DanmakuExpr
extends RefCounted

## 【22b 20261031d·C++ 热路径】Th75BulletHot（GDExtension）：编译成功则
## eval 走 C++（2.8 倍）；失败（getChata/_chq_/clamp 等未覆盖函数）回退
## Godot Expression。类未注册（扩展未构建）=自动走原路径。
static var _hot_available: int = -1 ## -1未知 0无 1有
static var hot_enabled := true ## 【对照开关】false=强制回退 GD 路径

var _hot: Object = null
var _no_hot := false ## 【0.0.9】参数类表达式（spawn/repeat/rotate）不走
## C++ 热路径——这些是事件级一次求值，且其 fallback 语义（rotate div=0
## → 单弹）一旦 C++ eval 异常回 0 会把整扇变单弹（作者实测重复故障）
var _hot_idx: PackedInt32Array = [] ## C++ 侧变量下标（vars 全表对齐）
var _hot_vals: PackedFloat64Array = []
## =============================================================
## 表达式求值器 —— 策划文档《运算参数》《外界变量》《弹幕自变量》
## 【第①期新增：常量折叠】编译期检测表达式未使用任何变量 → 只执行一次，
##   之后 execute_dict 直接返回缓存值（静态弹幕/固定颜色零求值开销）。
## 【^→**】文档规定 ^ 为次方，Godot Expression 的 ^ 是按位异或，编译前翻译。
## 出错策略：解析/执行失败 → 告警一次 → 返回 fallback（坏mod不崩游戏）。
## =============================================================

var _text: String = ""
var _vars: PackedStringArray = []
var _expr: Expression = null
var _err_reported := false
var _const_val: float = 0.0
var _is_const := false
## 【性能·20261002】本表达式实际引用的变量下标（编译期确定）：
## execute_dict 只填这些槽位——典型弹幕表达式仅用 0~3 个变量，
## 免去每次全 27 变量表扫描（profiler 实测 execute_dict 为热点）。
var _used_idx: PackedInt32Array = []

## 编译。vars 例：["t","target_x","target_y"]
## 【文档函数翻译】Godot Expression 不支持自定义函数调用，以下在编译期翻译：
##   n(k)→n（遍历换元：值=当前采样坐标；步长由 laser_n_step 列承载）
##   privates_id()→privates_id　getField(t)→field_t
##   log(底,真)→(log(真)/log(底))（Godot log 为自然对数单参）
func compile(text: String, vars: PackedStringArray) -> bool:
	_text = text
	_vars = vars
	_expr = null
	_err_reported = false
	_is_const = false
	var s := _translate(text.strip_edges().replace("^", "**"))
	if s.is_empty():
		return false
	_text = s ## 【20261003】变量扫描/uses_variable 以翻译后文本为准（gettarget(x)→target_x 等）
	var uses_var := false
	for v in vars:
		if _contains_word(s, v):
			uses_var = true
			break
	if not hot_enabled:
		_hot_available = 0
	if _hot_available == -1:
		_hot_available = 1 if ClassDB.class_exists("Th75BulletHot") else 0
	if _hot_available == 1 and not _no_hot:
		var hot: Object = ClassDB.instantiate("Th75BulletHot")
		var herr: String = hot.compile(s.replace("**", "^"), vars)
		if herr == "":
			_hot = hot
			_hot_vals.resize(vars.size())
			_hot_vals.fill(0.0)
			_hot_idx.clear()
			for i2 in vars.size():
				if _contains_word(s, vars[i2]):
					_hot_idx.append(i2)

	## 原路径（含回退）照常编译（恒等性兜底）
	_expr = Expression.new()
	var err := _expr.parse(s, vars)
	if err != OK:
		_report("解析失败: %s" % _expr.get_error_text())
		_expr = null
		return false
	_used_idx.clear()
	for i in vars.size():
		if _contains_word(s, vars[i]):
			_used_idx.append(i)
	if not uses_var:
		## 常量折叠：立即求值一次（失败仅放弃折叠，不算编译错误）
		var cv = _expr.execute([], _expr, false)
		if not _expr.has_execute_failed() and cv != null:
			_const_val = float(cv)
			_is_const = true
	return true

## 文档函数 → Godot Expression 等价文本
## 【20261003·记法大改（作者批复）】gettarget(x)/gettarget(y)/gettarget(d)
##   = 访问目标角色坐标/距离（相对弹幕发射点的定值快照）。
##   旧写法 target_x/target_y/d 保留为等价别名（旧 mod 兼容）。
static func _translate(s: String) -> String:
	if s.is_empty():
		return s
	## 【π 修复 20261027】Godot Expression 无 pi/tau 常量（编译过、执行静默失败取
	## 默认——rotate_range="pi/2" 恒 0 的根因）；词边界预替换为数值字面量。
	## 按作者批复：不做"空=完整圆"的魔法（取消 π 缺省=圆周设定）。
	var out0 := s
	var re_pi := RegEx.new()
	re_pi.compile("(?<![A-Za-z0-9_])pi(?![A-Za-z0-9_])")
	out0 = re_pi.sub(out0, "3.14159265358979", true)
	var re_tau := RegEx.new()
	re_tau.compile("(?<![A-Za-z0-9_])tau(?![A-Za-z0-9_])")
	out0 = re_tau.sub(out0, "6.28318530717959", true)
	s = out0
	## 【P4 修复 20261015】删除残留调试 print——每行表达式求值刷一行 [TR]（10-14 日志 550 行）
	var out := s
	## getchara(v)→self_v（发射者参数）；getfield(v)→field_v（场地参数）
	var re_gc := RegEx.new()
	re_gc.compile("getchara\\(\\s*([A-Za-z_0-9]+)\\s*\\)")
	var mgc := re_gc.search(out)
	var selfmap := {"x": "self_x", "y": "self_y", "ap": "self_ap", "pp": "self_pp", "normal": "self_normal",
		"privates_collapse": "field_privates_collapse", "chara_collapes": "field_chara_collapes",
		"t": "field_t", "phase": "field_phase"} ## 【get 系 20261020】getField 全参数
	while mgc != null:
		var gv: String = mgc.strings[1]
		out = out.substr(0, mgc.get_start()) + selfmap.get(gv, gv) + out.substr(mgc.get_end())
		mgc = re_gc.search(out)
	## 【占位 20261020（批复3：现在做，下批完善全参数）】getFriendly/getEnemy →
	## friendly_/enemy_ 前缀变量（当前 privates_collapse/chara_collapes 四项占位）
	var re_fr := RegEx.new()
	re_fr.compile("getfriendly\\(\\s*(privates_collapse|chara_collapes)\\s*\\)")
	var mfr := re_fr.search(out)
	while mfr != null:
		out = out.substr(0, mfr.get_start()) + "friendly_" + mfr.strings[1] + out.substr(mfr.get_end())
		mfr = re_fr.search(out)
	var re_en := RegEx.new()
	re_en.compile("getenemy\\(\\s*(privates_collapse|chara_collapes)\\s*\\)")
	var men := re_en.search(out)
	while men != null:
		out = out.substr(0, men.get_start()) + "enemy_" + men.strings[1] + out.substr(men.get_end())
		men = re_en.search(out)
	## 【getChata 全量 20261020（作者示例：getChataFriend("AP<<3","random(true)")）】
	## 翻译为 _chq_f_/_chq_e_ 前缀变量；locator/param 原文在事件编译期抽取到
	## chata_queries，运行时按阵营角色逐个求值定位器（非法→默认0）、
	## 多命中随机取一、返回所选角色的参数值；计数器参数直接阵营计数。
	var re_cf := RegEx.new()
	re_cf.compile("getchatafriendly\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)")
	var mcf := re_cf.search(out)
	while mcf != null:
		out = out.substr(0, mcf.get_start()) + "_chq_f_" + mcf.strings[1].replace("'", "") + "_" + mcf.strings[2].replace("'", "") + out.substr(mcf.get_end())
		mcf = re_cf.search(out)
	var re_ce := RegEx.new()
	re_ce.compile("getchataenemy\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)")
	var mce := re_ce.search(out)
	while mce != null:
		out = out.substr(0, mce.get_start()) + "_chq_e_" + mce.strings[1].replace("'", "") + "_" + mce.strings[2].replace("'", "") + out.substr(mce.get_end())
		mce = re_ce.search(out)
	var re_gf := RegEx.new()
	re_gf.compile("getfield\\(\\s*([a-z_]+)\\s*\\)")
	var mgf := re_gf.search(out)
	while mgf != null:
		out = out.substr(0, mgf.get_start()) + "field_" + mgf.strings[1] + out.substr(mgf.get_end())
		mgf = re_gf.search(out)
	## ave(a,b,...) → 平均值翻译（(a+b+...)/n）
	var re_ave := RegEx.new()
	re_ave.compile("ave\\(\\s*([^(\\\\]+)\\s*\\)")
	var mav := re_ave.search(out)
	while mav != null:
		var inner := mav.strings[1]
		var parts := inner.split(",")
		var acc := "("
		for i in parts.size():
			acc += parts[i].strip_edges()
			if i < parts.size() - 1:
				acc += "+"
		acc += ")/" + str(parts.size())
		out = out.substr(0, mav.get_start()) + acc + out.substr(mav.get_end())
		mav = re_ave.search(out)
	var re_gt := RegEx.new()
	re_gt.compile("gettarget\\(\\s*([A-Za-z_0-9]+)\\s*\\)")
	## 【修复 20261024】gettarget(d) 原译 target_d——变量表叫 d → 静默失效；
	## 全参数映射：x/y→target_*，d→d，其余状态参数→target_*（kp/sp 新增）
	## 【修复 20261025b】参数名含下划线/数字（x_copy、dm_smn、1d_ht_aver…）此前
	## 被 [a-z]+ 拒收→gettarget(x_copy) 原样残留→执行期静默失败回退 0（Youshio1
	## 弹幕全程静止的根因）。现扩为词字符；未知名透传（未注册名编译期可见报错）。
	var gtmap := {"x": "target_x", "y": "target_y", "d": "d", "ap": "target_ap",
		"pp": "target_pp", "normal": "target_normal", "hpweapon": "target_hpweapon",
		"hpbody": "target_hpbody", "hpmove": "target_hpmove",
		"kp": "target_kp", "sp": "target_sp",
		"dm_apfrepul": "target_dm_apfrepul", "dm_situate": "target_dm_situate",
		"dm_smn": "target_dm_smn", "dm_sms": "target_dm_sms"}
	var re_shs := RegEx.new()
	re_shs.compile("^([0-9])d_([a-z]+)_(aver|vectsum)$") ## 1d_ht_aver → ht1daver
	var mgt := re_gt.search(out)
	while mgt != null:
		var gk: String = mgt.strings[1]
		var mapped: String = gtmap.get(gk, "")
		if mapped == "":
			var mshs := re_shs.search(gk)
			if mshs != null:
				mapped = mshs.strings[2] + mshs.strings[1] + "d" + mshs.strings[3]
			else:
				mapped = gk ## 透传（未注册名编译期可见报错，不再静默）
		out = out.substr(0, mgt.get_start()) + mapped + out.substr(mgt.get_end())
		mgt = re_gt.search(out)
	var re_n := RegEx.new()
	re_n.compile("(?<![a-zA-Z0-9_])n\\(\\s*[0-9.]+\\s*\\)")
	out = re_n.sub(out, "n", true)
	var re_pid := RegEx.new()
	re_pid.compile("privates_id\\(\\s*\\)")
	out = re_pid.sub(out, "privates_id", true)
	var re_gf_t := RegEx.new()
	re_gf_t.compile("getField\\(\\s*t\\s*\\)")
	out = re_gf_t.sub(out, "field_t", true)
	var re_log := RegEx.new()
	re_log.compile("log\\(\\s*([^(),]+)\\s*,\\s*([^(),]+)\\s*\\)")
	var m := re_log.search(out)
	while m != null:
		## Godot RegEx.sub 不支持 \\1 反向引用插入 → 手工拼接替换
		var rep := "(log(%s)/log(%s))" % [m.strings[2], m.strings[1]]
		out = out.substr(0, m.get_start()) + rep + out.substr(m.get_end())
		m = re_log.search(out)
	return out

## 词边界包含检测（防 "t" 匹配到 "target_x"）
static func _contains_word(s: String, word: String) -> bool:
	var from := 0
	while true:
		var i := s.find(word, from)
		if i < 0:
			return false
		var before_ok := i == 0 or not _is_word_char(s[i - 1])
		var after_i := i + word.length()
		var after_ok := after_i >= s.length() or not _is_word_char(s[after_i])
		if before_ok and after_ok:
			return true
		from = i + 1
	return false

static func _is_word_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"

## 执行。values 与编译期变量名表一一对应；失败/未编译返回 fallback
## 【Godot 4.7 Expression 陷阱】不带 self_instance 的 execute 在表达式含
##   隐式 self 查找时报错——传表达式对象自身作实例即可（不需要真实宿主）。
func execute(values: Array, fallback: float = 0.0) -> float:
	if _is_const:
		return _const_val
	if _expr == null:
		return fallback
	var result = _expr.execute(values, _expr, false)
	if _expr.has_execute_failed() or result == null:
		_report("执行失败: %s" % _expr.get_error_text())
		return fallback
	return float(result)

## 便捷：{变量名: 值} 字典执行
## 【注】Expression 编译期记录的输入下标基于完整变量表，必须全量传参
##   （只传子集会下标错位）——因此只"回填"表达式实际引用的槽位（_used_idx），
##   其余槽位保持 0；复用缓冲数组，避免每次分配。
var _values_buf: Array = []
## 【批复 20261020·越界/非法值规则】
##   合法超范围 → 使用处钳到最近极值；非法（执行失败/NA/类型不兼容）→ 默认值。
##   eval_num：严格数值——布尔等非数值类型视为不兼容取默认（例：color.r 写 true → 0）。
##   eval_prop：命题——布尔真1假0、数值照取（例：rotate_pingpong 写 true → 1）。
var last_failed := false ## 最近一次 eval_num/eval_prop 是否非法（颜色面回退用）

func eval_num(ctx: Dictionary, dflt: float = 0.0) -> float:
	last_failed = false
	if _is_const:
		return _const_val
	if _expr == null:
		return dflt
	_fill_buf(ctx)
	var result = _expr.execute(_values_buf, _expr, false)
	if _expr.has_execute_failed() or result == null:
		last_failed = true
		return dflt
	if typeof(result) != TYPE_FLOAT and typeof(result) != TYPE_INT:
		last_failed = true ## 恒真命题等非数值 → 不兼容，取默认
		return dflt
	var fv := float(result)
	if is_nan(fv) or is_inf(fv):
		last_failed = true ## 【20261025f】NaN/INF（如 /t_copy 在 0 处 0/0）=非法→默认
		return dflt
	return fv

func eval_prop(ctx: Dictionary, dflt: float = 0.0) -> float:
	if _is_const:
		return _const_val
	if _expr == null:
		return dflt
	_fill_buf(ctx)
	var result = _expr.execute(_values_buf, _expr, false)
	if _expr.has_execute_failed() or result == null:
		return dflt
	if typeof(result) == TYPE_BOOL:
		return 1.0 if result else 0.0
	if typeof(result) == TYPE_FLOAT or typeof(result) == TYPE_INT:
		return float(result)
	return dflt

func _fill_buf(ctx: Dictionary) -> void:
	if _values_buf.size() != _vars.size():
		_values_buf.resize(_vars.size())
		_values_buf.fill(0.0)
	for idx in _used_idx:
		var name: String = _vars[idx]
		if ctx.has(name):
			_values_buf[idx] = ctx[name]

func execute_dict(ctx: Dictionary, fallback: float = 0.0) -> float:
	if _is_const:
		return _const_val
	if _hot != null:
		## 【C++ 热路径】回填实际引用槽位（与 Godot 路径同语义）
		for idx in _hot_idx:
			var name: String = _vars[idx]
			_hot_vals[idx] = float(ctx.get(name, 0.0)) if ctx.has(name) else 0.0
		return _hot.eval(_hot_vals, fallback)
	if _expr == null:
		return fallback
	if _values_buf.size() != _vars.size():
		_values_buf.resize(_vars.size())
		_values_buf.fill(0.0)
	for idx in _used_idx:
		var name: String = _vars[idx]
		if ctx.has(name):
			_values_buf[idx] = ctx[name]
	return execute(_values_buf, fallback)

func _report(msg: String) -> void:
	if _err_reported:
		return
	_err_reported = true
	push_warning("[DanmakuExpr] 表达式「%s」%s" % [_text, msg])

func is_empty() -> bool:
	return _text.strip_edges().is_empty()

## 【0.0.9·审计①-0】常量折叠结果外露（事件编译期把纯算式字段降为定值）
func is_constant() -> bool:
	return _is_const

func const_value() -> float:
	return _const_val

func uses_variable(v: String) -> bool:
	return _contains_word(_text, v)
