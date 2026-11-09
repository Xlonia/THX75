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
	// 【0.0.9·所见即所判】圆形判定（与蓝色消弹圈显示一致）——原方形
	vec2 d = vec2(p - pc.center) + 0.5;
	if (dot(d, d) > float(pc.radius * pc.radius)) { return; }
	imageStore(ddm, p, vec4(0.0));
}
