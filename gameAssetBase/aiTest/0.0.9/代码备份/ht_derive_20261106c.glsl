#[compute]
#version 450
// =============================================================
// Ht 派生（20261028f/1030·策划对齐："根据同一张图(Ht)抽象计算"）
//   dst0 Hd 总结期望云 = Ht 半径2高斯模糊（策划原文；分层设色为表现层）
//   dst1 Ha 全局抽象热点图 = Ht 25x25 区块均值马赛克（策划：256 区块取平均色）
//   （Hp 由 hp_derive 链入：max(Hd, Hp*0.98)）
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D src;
layout(set = 0, binding = 1, r8) uniform restrict writeonly image2D dst_hd;
layout(set = 0, binding = 2, r8) uniform restrict writeonly image2D dst_ha;
// 【0.0.9·作者 20261106】Hd 有记忆存储（作者澄清："Hd 的原图就是 Ht，
// 只不过有记忆存储"）——派生与旧图衰减合成：h = max(模糊(Ht), 旧图×decay)
// （20261028f 曾删记忆路径=Hd 退化为 Ht 模糊副本；decay 取 fam _decays 0.92）
layout(set = 0, binding = 3, r8) uniform restrict readonly image2D old_hd;
const float MEM_DECAY = 0.92; // 记忆衰减（Hd 慢积累；交接方式同 ht_step 的 KEEP/SPREAD——作者可在此自调）


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
	float mem = floor(round(imageLoad(old_hd, p).r * 255.0) * MEM_DECAY);
	hd = max(hd, mem); // 记忆余晖：弹幕走后热区按衰减缓慢消退

	ivec2 b = (p / 25) * 25;
	float asum = 0.0;
	for (int by = 0; by < 25; by++) {
		for (int bx = 0; bx < 25; bx++) {
			asum += px(b + ivec2(bx, by));
		}
	}
	float ha = asum / 625.0;
	imageStore(dst_hd, p, vec4(hd / 255.0));
	imageStore(dst_ha, p, vec4(ha / 255.0));
}
