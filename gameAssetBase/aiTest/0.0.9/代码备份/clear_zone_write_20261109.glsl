#[compute]
#version 450
// =============================================================
// 消弹区标记（0.0.9）：clear_active 期间半径内 clear_zone=255
// ht_step 读到 clear_zone >0 → live=0（跳过加热）
// clear_active 结束后由 GD 侧清零（clear_region 全域写 0）
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict writeonly image2D cz;
layout(push_constant, std430) uniform PC {
	int cx;
	int cy;
	int radius;
	int val; // 255=写入 / 0=清除
} pc;
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	float d = distance(vec2(p), vec2(float(pc.cx), float(pc.cy)));
	if (d <= float(pc.radius)) {
		imageStore(cz, p, vec4(float(pc.val) / 255.0));
	} else if (pc.val > 0) {
		imageStore(cz, p, vec4(0.0));
	}
}
