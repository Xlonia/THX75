#[compute]
#version 450
// 【22b 20261103】DDM 区域清除（消弹残影）：矩形区域内像素写 0
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict writeonly image2D ddm;
layout(push_constant, std430) uniform PC {
	ivec2 center;
	int radius;
	int pad;
} pc;

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	ivec2 d = p - pc.center;
	if (abs(d.x) > pc.radius || abs(d.y) > pc.radius) { return; }
	imageStore(ddm, p, vec4(0.0));
}
