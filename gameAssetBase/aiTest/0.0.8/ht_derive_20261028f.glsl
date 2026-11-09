#[compute]
#version 450
// =============================================================
// Ht 派生（20261028f·策划对齐："根据同一张图(Ht)抽象计算"）
//   Hd 总结期望云 = Ht 半径2高斯模糊（策划原文；分层设色为表现层）
//   （Ha 马赛克/Hp 慢积累同族派生——Ha 待表现层纹理，Hp 保留弹幕注册）
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D src;
layout(set = 0, binding = 1, r8) uniform restrict writeonly image2D dst;

float px(ivec2 q) {
	q = clamp(q, ivec2(0), ivec2(399));
	return round(imageLoad(src, q).r * 255.0);
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	float wsum = 0.0;
	float sum = 0.0;
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			float w = exp(-float(dx * dx + dy * dy) / 2.0);
			sum += px(p + ivec2(dx, dy)) * w;
			wsum += w;
		}
	}
	float hd = clamp(sum / wsum, 0.0, 255.0);
	imageStore(dst, p, vec4(hd / 255.0));
}
