#[compute]
#version 450
// =============================================================
// Ha 全局抽象热点图（0.0.9·审计 B4 20261109）：Ht 25x25 区块均值马赛克
//   （策划：256 区块取平均色）。一个线程负责一个区块：求 625 像素之和
//   并写回整块——原实现在 ht_derive 内每个像素各自重算本块之和
//   （每派发 1 亿次图像读），本 pass 总计 16 万读 + 16 万写。
//   像素值先 round 成 0..255 整数再累加（与原实现同口径），整数和在 f32
//   内精确（上限 625x255=159375 < 2^24）→ 求和顺序无关，输出逐位不变。
// =============================================================
layout(local_size_x = 16, local_size_y = 16) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D src;
layout(set = 0, binding = 1, r8) uniform restrict writeonly image2D dst_ha;

void main() {
	ivec2 blk = ivec2(gl_GlobalInvocationID.xy); // 区块序 0..15
	if (blk.x >= 16 || blk.y >= 16) { return; }
	ivec2 b = blk * 25;
	float asum = 0.0;
	for (int by = 0; by < 25; by++) {
		for (int bx = 0; bx < 25; bx++) {
			asum += round(imageLoad(src, b + ivec2(bx, by)).r * 255.0);
		}
	}
	vec4 v = vec4((asum / 625.0) / 255.0);
	for (int by = 0; by < 25; by++) {
		for (int bx = 0; bx < 25; bx++) {
			imageStore(dst_ha, b + ivec2(bx, by), v);
		}
	}
}
