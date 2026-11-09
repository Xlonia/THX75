#[compute]
#version 450
// DDM 弹幕印章（修4 材质形状加热终版）：
// stamp=vec4(x,y,半径,纹理槽id)。槽>0 → 按纹理 alpha 贴合（阈值0.25）；
// 槽0 → 圆盘兜底。
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, r8) uniform restrict writeonly image2D ddm;
layout(set = 0, binding = 1, std430) restrict readonly buffer Stamps { vec4 data[]; } stamps;
layout(set = 0, binding = 2) uniform texture2DArray texarr_tex;
layout(set = 0, binding = 3) uniform sampler texarr_smp;

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= stamps.data.length()) { return; }
	vec2 c = stamps.data[i].xy;
	float r = max(stamps.data[i].z, 0.5);
	float slot = stamps.data[i].w;
	float r2 = r * r;
	ivec2 lo = ivec2(ceil(c - r));
	ivec2 hi = ivec2(floor(c + r));
	for (int y = max(lo.y, 0); y <= min(hi.y, 399); y++) {
		for (int x = max(lo.x, 0); x <= min(hi.x, 399); x++) {
			vec2 d = vec2(float(x), float(y)) + 0.5 - c;
			if (dot(d, d) > r2) { continue; }
			if (slot > 0.5) {
				vec2 uv = d / r * 0.5 + 0.5;
				float a = textureLod(sampler2DArray(texarr_tex, texarr_smp), vec3(uv, slot - 1.0), 0.0).r;
				if (a < 0.25) { continue; }
			}
			imageStore(ddm, ivec2(x, y), vec4(1.0));
		}
	}
}
