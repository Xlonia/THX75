shader_type canvas_item;
// =============================================================
// 弹幕 HS 上色（作者批复 2026-10-02，第二次纠正后的最终语义）：
//   目标色（实例色）只提供 色相H 与 饱和度S；亮度 L = 纹理像素亮度。
//   合成公式：HSL(h=色H, s=色S, l=纹理亮度)
//   → 白（L=1）上色后仍为白；灰部为主要上色区域；
//   参考东方原作弹幕 / Minecraft 草皮树叶上色。
// 实例色仍从 from_hsv(hue, sat, 1) 传入（shader 内 rgb2hsv 还原 H/S）。
// alpha = 纹理alpha × 实例alpha（不透明度表达式照常生效）。
// =============================================================

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsl2rgb(vec3 hsl) {
	vec3 rgb = clamp(abs(mod(hsl.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return hsl.z + hsl.y * (rgb - 0.5) * (1.0 - abs(2.0 * hsl.z - 1.0));
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float l = dot(tex.rgb, vec3(0.299, 0.587, 0.114)); // 纹理亮度=L
	vec3 hs = rgb2hsv(COLOR.rgb);
	// 【对比度倍乘 20261026】S>1：rgb 偏离 L 的色彩分量放大（对比拉满）；
	// S<=1：常规 HSL 合成（S 趋 0=灰）。倍率由实例色饱和度携带（sat_val/1）。
	float mul = max(hs.y / 0.5, 1.0); // 实例色由 from_hsv(h,s,1) 携带：s>0.5 表示倍乘段
	float s_eff = min(hs.y, 1.0);
	vec3 base = hsl2rgb(vec3(hs.x, s_eff, l));
	COLOR.rgb = clamp(base + (base - vec3(l)) * (mul - 1.0), vec3(0.0), vec3(1.0));
	COLOR.a = tex.a * COLOR.a;
}
