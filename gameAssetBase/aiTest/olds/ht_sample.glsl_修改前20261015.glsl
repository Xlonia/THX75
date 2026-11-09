#[compute]
#version 450
// =============================================================
// 态势十六点采样（10Hz，与 Ht 步进同拍）——②期准备
// 每线程一个采样点：读 Ht 一个纹素 → 输出 0~255 热度（uint）。
// 采样点位置（含"带转"偏移：偶数帧从最上端开始，奇数帧偏1/32圈）
// 由 CPU 预计算写入 spos，着色器不做角度数学（能跳则跳）。
// 输出 vals[i] = 采样点 i 的热度；CPU 回读后按 实体×32 展开。
// =============================================================
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D ht;
layout(set = 0, binding = 1, std430) restrict readonly buffer SP { vec2 spos[]; };
layout(set = 0, binding = 2, std430) restrict writeonly buffer Res { uint vals[]; };

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= spos.length()) { return; }
	ivec2 p = clamp(ivec2(round(spos[i])), ivec2(0), ivec2(399));
	vals[i] = uint(round(imageLoad(ht, p).r * 255.0));
}
