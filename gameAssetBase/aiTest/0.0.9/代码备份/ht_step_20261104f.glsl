#[compute]
#version 450
// =============================================================
// Ht 热力图步进（每侧一张"威胁图"，10Hz，每6物理帧一次）——②期
// 策划《决斗底层→弹幕热力图》三步（顺序照抄原文）：
//   ①扩散：每个像素寻找附近高点，实行半径为1像素的线性衰减
//   ②衰减：本次衰减后的热度 = 0.8h 的去尾整数值
//   ③加热：若此像素位于弹幕图白区，该像素加上64（Ht）
// 【每侧一张（作者批复 2026-10-02）】战场热力图双方各有：
//   side0 的 Ht 只加热 fields[0]（能击中 side0 的弹幕=敌方全部+己方超遮罩物弹），
//   我方法弹对本侧天然为 0（"覆写为0"语义）；实体态势十六点采样本侧图。
// 可调参数（作者手感自调，改这里即可）：DIFFUSION / DECAY / HEAT
// 并发写：每线程只写 ht_next 自己的像素，无需原子操作。
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D ht_prev;
layout(set = 0, binding = 1, r8) uniform restrict writeonly image2D ht_next;
layout(set = 0, binding = 2, r8) uniform restrict readonly image2D ddm;

// =============================================================
// 【密度自适应模型 20261028（作者目标：恐慌区/离散弹速衰/防侥幸）】
//   ①扩散=邻域【均值】×0.10（非 max——多弹彼此填充空隙成密集恐慌区；
//     单弹热不持续→几乎不扩散）
//   ②衰减=基础0.74+密度调制0.20×(3×3均值/255)：密集区≈0.94 自持续，
//     离散弹≈0.74 快消散（角色敢躲单弹、不敢钻弹群）
//   单 pass 3×3（9 读/像素）与旧 max 模型同量级——性能不变
// =============================================================
const float DIFFUSE_K = 0.10;  // 均值扩散系数（慢扩散）
const float DECAY_BASE = 0.74; // 离散弹快速衰减
const float DECAY_DENSE = 0.20; // 密度减免上限（密集区衰减≈0.94）
const float HEAT = 64.0;     // ③加热：Ht += 64（饱和255）

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	float own = round(imageLoad(ht_prev, p).r * 255.0);
	// ①3×3 邻域：均值（扩散源）+ 密度（衰减调制）——一次遍历双用
	float sum = own;
	float cnt = 1.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) { continue; }
			ivec2 q = p + ivec2(dx, dy);
			if (q.x < 0 || q.x > 399 || q.y < 0 || q.y > 399) { continue; }
			sum += round(imageLoad(ht_prev, q).r * 255.0);
			cnt += 1.0;
		}
	}
	float avg = sum / cnt;
	// 扩散：邻域均值 × 系数（密集区互相填充；单弹无邻 → 不扩散）
	float h = max(own, avg * DIFFUSE_K * 2.0);
	// 衰减：基础 + 密度调制（密集区自持续，离散弹速衰）
	float decay = DECAY_BASE + DECAY_DENSE * clamp(avg / 255.0, 0.0, 1.0);
	h = floor(h * decay);
	h = min(h, 200.0); // 【0.0.9·热上限钳制】长期加热群不超 200（消弹后 ≤24 拍消散）
	// ③加热：位于弹幕图白区
	if (imageLoad(ddm, p).r > 0.0) {
		h = min(h + HEAT, 255.0);
	}
	imageStore(ht_next, p, vec4(h / 255.0));
}
