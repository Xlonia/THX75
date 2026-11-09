shader_type canvas_item;
// =============================================================
// 热力图显示上色（0.0.9·Hd/Hr 青蓝显示修复 20261106）
//   R8 单通道纹理只有 R 有值（G/B=0）——modulate 蓝青会被乘成
//   极暗红=作者实测"Hd/Hr 都不能显示"。本 shader 把灰度读出后
//   重映射到 tint 颜色（策划：热力图显示颜色红色系；调试原图另色青蓝）。
// =============================================================
uniform vec4 tint : source_color = vec4(0.35, 0.65, 1.0, 0.45);

void fragment() {
	float g = texture(TEXTURE, UV).r;
	COLOR = vec4(tint.rgb * g, tint.a * (0.25 + 0.75 * g));
}
