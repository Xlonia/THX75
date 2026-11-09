#[compute]
#version 450
// =============================================================
// 消弹抑制衰减（0.0.9）：suppress 每拍 ×0.9（60 帧后≈0=抑制约 1 秒）
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, r8) uniform restrict image2D sup;
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	float v = imageLoad(sup, p).r * 255.0;
	if (v > 0.5) {
		imageStore(sup, p, vec4(floor(v * 0.9) / 255.0));
	}
}
