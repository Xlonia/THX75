#[compute]
#version 450
// =============================================================
// Hv 派生（0.0.9·策划新三对齐）："快速弹幕警告云(Hr)，是将全局速度热点图
// 的高热度区域按照半径2像素高斯模糊描绘等高线抽象为多个多边形构成的
// 分层设色图"——Hr ← Hv 半径2高斯派生（与 Hd ← Ht 完全对称）。
//   Hv 纹理为 rgba8 彩虹烘焙（上升沿红/下降沿蓝），热度=max(R,B)。
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D src;
layout(set = 0, binding = 1, r8) uniform restrict writeonly image2D dst_hr;

float heat(ivec2 q) {
	q = clamp(q, ivec2(0), ivec2(399));
	vec4 c = imageLoad(src, q);
	return max(c.r, c.b) * 255.0;
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	float wsum = 0.0;
	float sum = 0.0;
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			float w = exp(-float(dx * dx + dy * dy) / 2.0);
			sum += heat(p + ivec2(dx, dy)) * w;
			wsum += w;
		}
	}
	float hr = clamp(sum / wsum, 0.0, 255.0);
	imageStore(dst_hr, p, vec4(hr / 255.0));
}
