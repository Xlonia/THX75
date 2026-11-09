#[compute]
#version 450
// =============================================================
// 等高线下采样（0.0.9·策划新三 52-68 行）：
//   400×400 R8 → 50×50 R8（每 thread = 一个 8×8 块 = 等高线一个角点）
//   pre_blur=1：先块中心半径2高斯（Hr 原图未模糊，策划：Hr 等高线同 Hd
//   按"半径2像素高斯模糊描绘等高线"）；pre_blur=0：8px 块平均
//   （Hd 已由 ht_derive 半径2高斯模糊，直接块平均）
//   输出 2500 字节回读（CPU marching squares 的角点）
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D src;
layout(set = 0, binding = 1, r8) uniform restrict writeonly image2D dst;
layout(set = 0, binding = 2) restrict readonly uniform Params {
	float pre_blur;
	float grid_n;   ## 输出网格边长（50/25/16——400/CELL）
	float cell_px;  ## 块边长像素（8/16/24/32）
} prm;

float px(ivec2 q) {
	q = clamp(q, ivec2(0), ivec2(399));
	return round(imageLoad(src, q).r * 255.0);
}

void main() {
	ivec2 b = ivec2(gl_GlobalInvocationID.xy); // 块序 0..grid_n-1
	if (b.x >= int(prm.grid_n) || b.y >= int(prm.grid_n)) { return; }
	float cell = prm.cell_px;
	float v;
	if (prm.pre_blur > 0.5) {
		// 块中心半径2高斯（与 ht_derive 同核 exp(-d²/2)）
		ivec2 c = ivec2(vec2(b) * cell) + ivec2(ivec2(cell * 0.5));
		float wsum = 0.0;
		float sum = 0.0;
		for (int dy = -2; dy <= 2; dy++) {
			for (int dx = -2; dx <= 2; dx++) {
				float w = exp(-float(dx * dx + dy * dy) / 2.0);
				sum += px(c + ivec2(dx, dy)) * w;
				wsum += w;
			}
		}
		v = sum / wsum;
	} else {
		// 8px 块平均
		float s = 0.0;
		int n = int(prm.grid_n);
		int span = 400 / n;
		for (int dy = 0; dy < span; dy++) {
			for (int dx = 0; dx < span; dx++) {
				s += px(b * span + ivec2(dx, dy));
			}
		}
		v = s / float(span * span);
	}
	imageStore(dst, b, vec4(clamp(v, 0.0, 255.0) / 255.0));
}
