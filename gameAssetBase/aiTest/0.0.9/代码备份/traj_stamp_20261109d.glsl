#[compute]
#version 450
// =============================================================
// 轨迹期望印章（He/Hr/Hp 共用）：SSBO vec4(x,y,0,0) 逐点写白
// ——与 ddm_stamps 同构；点位由 CPU 按弹幕未来轨迹粗采样计算
// 【0.0.9·陈旧尾部幽灵根治 20261109】守卫改 push constant 本次点数 n
// （原 stamps.data.length()=缓冲容量→向上取整线程读旧点=幽灵热区）
// =============================================================
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, r8) uniform restrict writeonly image2D map_tex;
layout(set = 0, binding = 1, std430) restrict readonly buffer Stamps { vec4 data[]; } stamps;
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
	float r = max(stamps.data[i].z, 3.0); // 【20261103】热区半径（默认3px，上弹幕半径更佳）
	ivec2 lo = ivec2(max(c - vec2(r), vec2(0.0)));
	ivec2 hi = ivec2(min(c + vec2(r), vec2(399.0)));
	for (int y = lo.y; y <= hi.y; y++) {
		for (int x = lo.x; x <= hi.x; x++) {
			vec2 d = vec2(float(x), float(y)) + 0.5 - c;
			if (dot(d, d) <= r * r) {
				imageStore(map_tex, ivec2(x, y), vec4(1.0));
			}
		}
	}
}
