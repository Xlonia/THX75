#[compute]
#version 450
// =============================================================
// 态势十六点采样（10Hz，与 Ht 步进同拍）——②期准备
// 每线程一个采样点：读 Ht 一个纹素 → 输出 0~255 热度（uint）。
// 采样点位置（含"带转"偏移：偶数帧从最上端开始，奇数帧偏1/32圈）
// 由 CPU 预计算写入 spos，着色器不做角度数学（能跳则跳）。
// 输出 vals[i] = 采样点 i 的热度；CPU 回读后按 实体×49 展开。
// 【P1 修复 20261015】push constant 基址：多批采样点可写入同一 spos/
//   vals 大缓冲的不同区段，多侧多图在同一个 compute list 内提交，
//   全批只做一次 buffer_get_data（原先每图各回读一次，tick 帧回读风暴）。
//   单批调用方传 (0,0,n,0) 行为不变。注意 GLSL 内只用 // 注释。
// =============================================================
layout(local_size_x = 64) in;
layout(push_constant, std430) uniform PC {
	uint pts_base;  // 本批采样点在 spos 内的起始下标（vec2 单位）
	uint vals_base; // 本批输出在 vals 内的起始下标（uint 单位）
	uint count;     // 本批采样点数（越界线程直接返回）
	uint pad;
} pc;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D ht;
layout(set = 0, binding = 1, std430) restrict readonly buffer SP { vec2 spos[]; };
layout(set = 0, binding = 2, std430) restrict writeonly buffer Res { uint vals[]; };

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= pc.count) { return; }
	ivec2 p = clamp(ivec2(round(spos[pc.pts_base + i])), ivec2(0), ivec2(399));
	vals[pc.vals_base + i] = uint(round(imageLoad(ht, p).r * 255.0));
}
