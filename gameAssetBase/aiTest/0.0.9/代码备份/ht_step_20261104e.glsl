#[compute]
#version 450
// =============================================================
// Ht 步进（0.0.9 热模型重设计 20261104·作者四原则）：
//   ①恐慌区：DDM 白区（有活弹）像素=恐慌区核心——衰减慢（0.95 自持续）
//   ②边沿快衰：DDM 黑区（无活弹）像素=快衰减（0.45）——恐慌区边沿
//     快速跌落，不产生幻影残留
//   ③双尺度扩散：3×3 强扩散（小弹就近）+5×5 弱扩散（大弹群连片，
//     系数 0.04——远距影响随距离暴跌）
//   ④上限 220：恐慌区饱和留余量
// ⑤单弹避开强度有限：单弹热 64+扩散≈恐慌半径小 ✓（密度自适应保留）
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D ht_prev;
layout(set = 0, binding = 1, r8) uniform restrict writeonly image2D ht_next;
layout(set = 0, binding = 2, r8) uniform restrict readonly image2D ddm_cur;
layout(set = 0, binding = 3, r8) uniform restrict readonly image2D ddm_prev;

const float HEAT = 64.0;
const float DIFFUSE_NEAR = 0.12;   // 3×3 近扩散
const float DIFFUSE_FAR = 0.035;   // 5×5 远扩散（大弹群连片）
const float DECAY_HOT = 0.95;      // 恐慌区（DDM 白）慢衰减=持续恐慌
const float DECAY_COLD = 0.45;     // 非恐慌区快衰减=边沿速跌、无幻影
const float MAX_HEAT = 220.0;

float ddm_at(ivec2 p) {
	if (p.x < 0 || p.x > 399 || p.y < 0 || p.y > 399) { return 0.0; }
	return imageLoad(ddm_cur, clamp(p, ivec2(0), ivec2(399))).r * 255.0;
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	float own = round(imageLoad(ht_prev, p).r * 255.0);
	// ③双尺度扩散：3×3 均值（近）+ 5×5 环均值（远，权重随距离暴跌）
	float sum_near = 0.0;
	float sum_far = 0.0;
	float cnt_near = 0.0;
	float cnt_far = 0.0;
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			if (dx == 0 && dy == 0) { continue; }
			ivec2 q = p + ivec2(dx, dy);
			if (q.x < 0 || q.x > 399 || q.y < 0 || q.y > 399) { continue; }
			float v = round(imageLoad(ht_prev, q).r * 255.0);
			if (max(abs(dx), abs(dy)) <= 1) {
				sum_near += v;
				cnt_near += 1.0;
			} else {
				sum_far += v;
				cnt_far += 1.0;
			}
		}
	}
	float near_avg = sum_near / max(cnt_near, 1.0);
	float far_avg = sum_far / max(cnt_far, 1.0);
	// ③扩散合成：近邻强+远邻弱（大弹群连片=远邻也持续供热）
	float diffuse = max(near_avg * DIFFUSE_NEAR, far_avg * DIFFUSE_FAR * 4.0);
	// ①②热源驱动衰减：DDM 白（当前帧）→恐慌慢衰减；黑→快衰减
	float live = ddm_at(p);
	float decay = live > 32.0 ? DECAY_HOT : DECAY_COLD;
	float h = max(own * decay, diffuse);
	// ③加热：DDM 白区 +64
	if (live > 32.0) {
		h = min(h + HEAT, MAX_HEAT);
	}
	h = min(h, MAX_HEAT);
	imageStore(ht_next, p, vec4(h / 255.0));
}
