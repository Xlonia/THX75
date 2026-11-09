#[compute]
#version 450
// =============================================================
// Hp 敌角色攻击规律图（20261030·作者批复：不再是像素遍历图/弹幕注册，
// 改 10Hz 类 Hd 型分层期望云）：Hp = max(Hd, Hp_prev * 0.98)
//   ——Hd 是"本次期望"，慢衰减自记忆承载"规律总结"（Anime 性质）
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D hd_src;
layout(set = 0, binding = 1, r8) uniform restrict readonly image2D hp_prev;
layout(set = 0, binding = 2, r8) uniform restrict writeonly image2D hp_next;

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	float hd = round(imageLoad(hd_src, p).r * 255.0);
	float prev = round(imageLoad(hp_prev, p).r * 255.0);
	float hp = max(hd, floor(prev * 0.98));
	imageStore(hp_next, p, vec4(hp / 255.0));
}
