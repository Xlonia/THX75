#[compute]
#version 450
// DDM 弹幕印章（20261102 修4：材质形状加热）：
// stamp=vec4(x,y,半径,纹理槽id)。槽>0 → 按纹理 alpha 贴合形状；
// 槽0 → 圆盘填充（旧行为，兜底/无纹理）。并发写同值无需原子。
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, r8) uniform restrict writeonly image2D ddm;
layout(set = 0, binding = 1, std430) restrict readonly buffer Stamps { vec4 data[]; } stamps;
layout(set = 0, binding = 2) uniform sampler2DArray texarr;

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= stamps.data.length()) { return; }
	vec2 c = stamps.data[i].xy;
	float r = max(stamps.data[i].z, 0.5);
	float slot = stamps.data[i].w;
	float r2 = r * r;
	ivec2 lo = ivec2(ceil(c - r));
	ivec2 hi = ivec2(floor(c + r));
	bool textured = slot > 0.5;
	for (int y = max(lo.y, 0); y <= min(hi.y, 399); y++) {
		for (int x = max(lo.x, 0); x <= min(hi.x, 399); x++) {
			vec2 d = vec2(float(x), float(y)) + 0.5 - c;
			if (dot(d, d) > r2) { continue; }
			if (textured) {
				// 弹幕局部坐标：dir 朝右的材质，u=沿弹径向（这里用场向：
				// stamp 无旋转信息——用径向投影近似：u=沿 (c→p) 方向？不——
				// 材质方向朝右=弹行进方向。印章无方向 → 以 [0,1]² 圆内映射
				// （圆内贴图，方向性损失可接受：DDM 只判白黑）
				vec2 uv = d / r * 0.5 + 0.5;
				float a = textureLod(texarr, vec3(uv, slot - 1.0), 0.0).r; ## 槽1=层0
				if (a < 0.5) { continue; }
			}
			imageStore(ddm, ivec2(x, y), vec4(1.0));
		}
	}
}
