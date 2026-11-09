#[compute]
#version 450
// =============================================================
// Ht 步进（0.0.9 热模型 v2 20261104·作者令全新设计）：
//   无独立衰减分支——热度=当帧 DDM 亮度 与 自身+邻域扩散 的合成：
//   h = max( DDM白区亮度, 自身×0.55 + 3×3邻域×0.45摊入 )
//   弹在=热在（DDM 直映）；弹走=几何摊薄快速消散（无尾巴无幻影）
//   大弹群：邻域全白 → 摊入持续 → 恐慌区自然连片
//   小弹：邻域黑 → 摊入≈0 → 就近快速消散
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D ht_prev;
layout(set = 0, binding = 1, r8) uniform restrict writeonly image2D ht_next;
layout(set = 0, binding = 2, r8) uniform restrict readonly image2D ddm_cur;

const float KEEP = 0.35;    // 自身保留比（0.35：弹走后更快消散——作者自调参数）
const float SPREAD = 0.60;  // 邻域摊入比（0.60：扩散更快——作者自调参数）
const float LIVE_GAIN = 1.0; // DDM 白区直映增益

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	float live = imageLoad(ddm_cur, p).r * 255.0 * LIVE_GAIN;
	float own = imageLoad(ht_prev, p).r * 255.0 * KEEP;
	float sum = 0.0;
	float cnt = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) { continue; }
			ivec2 q = p + ivec2(dx, dy);
			if (q.x < 0 || q.x > 399 || q.y < 0 || q.y > 399) { continue; }
			sum += imageLoad(ht_prev, q).r * 255.0 * SPREAD / 8.0;
			cnt += 1.0;
		}
	}
	float h = max(live, own + sum);
	h = floor(min(h, 255.0)); // 【0.0.9·作者令】向下取整——小数不累积，更易归零
	imageStore(ht_next, p, vec4(h / 255.0));
}
