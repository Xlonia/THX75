#[compute]
#version 450
// =============================================================
// 图族衰减+扩散（He/Hd/Hr/Hp 共用）：decay 与扩散半径由 uniform 控制
//   decay：He/Hr=0.9（快记忆） Hp=0.98（长记忆规律） Hd=0.92
//   blur：Hd 用半径2（策划：半径2高斯模糊）；其余半径1
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D m_prev;
layout(set = 0, binding = 1, r8) uniform restrict writeonly image2D m_next;
layout(set = 0, binding = 2) restrict readonly uniform Params {
	float decay;  // 【密度自适应 20261028】基础衰减（离散区）
	float blur2;  // 1.0=半径2 0.0=半径1
} prm;
const float DIFFUSE_K = 0.10;  // 均值扩散（恐慌区填充）
const float DECAY_DENSE = 0.20; // 密度减免（密集区自持续）

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	float own = round(imageLoad(m_prev, p).r * 255.0);
	// 3×3 均值+密度（密度自适应模型——与 ht_step 同构）
	float sum = own;
	float cnt = 1.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) { continue; }
			ivec2 q = p + ivec2(dx, dy);
			if (q.x < 0 || q.x > 399 || q.y < 0 || q.y > 399) { continue; }
			sum += round(imageLoad(m_prev, q).r * 255.0);
			cnt += 1.0;
		}
	}
	float avg = sum / cnt;
	float h = max(own, avg * DIFFUSE_K * 2.0);
	float decay = prm.decay + DECAY_DENSE * clamp(avg / 255.0, 0.0, 1.0);
	decay = min(decay, 0.985); // Hp 长记忆上限（0.98+0.2 钳制）
	h = floor(h * decay);
	imageStore(m_next, p, vec4(h / 255.0));
}
