#[compute]
#version 450
// =============================================================
// 消弹抑制写入（0.0.9）：半径内 suppress=255（ht_step 读到即归零）
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict writeonly image2D sup;
layout(push_constant, std430) uniform PC {
	int cx;
	int cy;
	int radius;
	int pad;
} pc;
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	float d = distance(vec2(p), vec2(pc.cx, pc.cy));
	if (d <= float(pc.radius)) {
		imageStore(sup, p, vec4(1.0));
	}
}
