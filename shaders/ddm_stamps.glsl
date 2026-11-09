#[compute]
#version 450
// DDM 弹幕印章（修4 材质形状加热终版）：
// stamp=vec4(x,y,半径,纹理槽id)。槽>0 → 按纹理 alpha 贴合（阈值0.25）；
// 槽0 → 圆盘兜底。
// 【0.0.9·陈旧尾部幽灵根治 20261109】守卫原为 stamps.data.length()——那是
// 缓冲容量（16384）而非本帧印章数；dispatch 按 64 向上取整，最多 63 个线程
// 读到以前帧残留的印章→已不存在的弹幕被重新印上 DDM→Ht 加热=作者所见
// 消弹区"诈尸"/零星弹幕突现（自①期起）。改由 push constant 传本帧数量 n。
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, r8) uniform restrict writeonly image2D ddm;
layout(set = 0, binding = 1, std430) restrict readonly buffer Stamps { vec4 data[]; } stamps;
layout(set = 0, binding = 2) uniform texture2DArray texarr_tex;
layout(set = 0, binding = 3) uniform sampler texarr_smp;
layout(push_constant, std430) uniform PC {
	uint n;
	uint pad0;
	uint pad1;
	uint pad2;
} pc;

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= pc.n) { return; }
	vec2 c = stamps.data[i].xy;
	float r = max(stamps.data[i].z, 0.5);
		float slot = floor(stamps.data[i].w + 0.5); // 【20261103·旋转跟随】w=slot+angle_frac（slot 整数部分+角度小数部分）
	float ang = (stamps.data[i].w - slot) * 6.283185307; // 解码角度 [0,TAU)
	float r2 = r * r;
	ivec2 lo = ivec2(ceil(c - r));
	ivec2 hi = ivec2(floor(c + r));
	for (int y = max(lo.y, 0); y <= min(hi.y, 399); y++) {
		for (int x = max(lo.x, 0); x <= min(hi.x, 399); x++) {
			vec2 d = vec2(float(x), float(y)) + 0.5 - c;
			if (dot(d, d) > r2) { continue; }
			if (slot > 0.5) {
				float ca = cos(ang), sa = sin(ang);
				vec2 dr = vec2(d.x * ca + d.y * sa, -d.x * sa + d.y * ca); // 逆旋转到材质系
				vec2 uv = dr / r * 0.5 + 0.5;
				float a = textureLod(sampler2DArray(texarr_tex, texarr_smp), vec3(uv, slot - 1.0), 0.0).r;
				if (a < 0.25) { continue; }
			}
			imageStore(ddm, ivec2(x, y), vec4(1.0));
		}
	}
}
