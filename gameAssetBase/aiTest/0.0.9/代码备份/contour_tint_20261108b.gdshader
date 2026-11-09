shader_type canvas_item;
// =============================================================
// 等高面色图显示（0.0.9·审计 Top1 20261108）：50×50 值图 → 16 层阶梯设色
// （替代 draw_colored_polygon 实时三角化——proc 省 4-5ms 最大单项）
// 层色 ramp 与 _contour_level_color 同款：低层暗红→高层亮黄白
// =============================================================
void fragment() {
	float g = texture(TEXTURE, UV).r;
	float lv = floor(g * 15.999) / 15.0; // 层 id 0..1 归一
	COLOR = vec4(1.0, 0.18 + 0.72 * lv, 0.18 + 0.72 * lv, 0.42 + 0.4 * lv) * step(0.001, g);
}
