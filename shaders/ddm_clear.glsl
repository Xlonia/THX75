#[compute]
#version 450
// DDM 清底：每帧把 400×400 单通道图清零（每线程一像素）
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict writeonly image2D ddm;

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	imageStore(ddm, p, vec4(0.0));
}
