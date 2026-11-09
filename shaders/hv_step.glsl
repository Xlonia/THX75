#[compute]
#version 450
// =============================================================
// Hv 全局速度热点图步进（每侧一张，10Hz）——③期热力图族第二张
// 策划：Hv 是"弹幕图上升与下降沿为热点"的像素遍历图。
//   ①扩散 / ②衰减(0.8h) 与 Ht 相同；③加热：DDM 当前帧 vs 上一帧的
//   差分——上升沿 +64（红相）、下降沿 +64（蓝相）。
// 【彩虹上色（作者批复）】多维=沿类型：上升沿偏红、下降沿偏蓝，
//   热度越高越亮——RGBA 直接烘焙显示色，AI 采样取 max(R,B) 为热度。
// =============================================================
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D hv_prev;
layout(set = 0, binding = 1, rgba8) uniform restrict writeonly image2D hv_next;
layout(set = 0, binding = 2, r8) uniform restrict readonly image2D ddm_cur;
layout(set = 0, binding = 3, r8) uniform restrict readonly image2D ddm_prev;

const float DIFFUSION = 0.5;
const float DECAY = 0.8;
const float HEAT = 64.0;

float heat_of(vec4 c) { return max(c.r, c.b) * 255.0; }

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= 400 || p.y >= 400) { return; }
	vec4 own = imageLoad(hv_prev, p);
	float h = heat_of(own);
	// ①扩散：正交邻域高点（按通道 max——保留红/蓝相）
	vec4 n = own;
	if (p.x > 0)   n = max(n, imageLoad(hv_prev, p + ivec2(-1, 0)));
	if (p.x < 399) n = max(n, imageLoad(hv_prev, p + ivec2(1, 0)));
	if (p.y > 0)   n = max(n, imageLoad(hv_prev, p + ivec2(0, -1)));
	if (p.y < 399) n = max(n, imageLoad(hv_prev, p + ivec2(0, 1)));
	h = max(h, heat_of(n) * DIFFUSION);
	// ②衰减
	h = floor(h * DECAY);
	// ③加热：升降沿（cur vs prev）
	float cur = imageLoad(ddm_cur, p).r * 255.0;
	float prv = imageLoad(ddm_prev, p).r * 255.0;
	float rise = max(cur - prv, 0.0);
	float fall = max(prv - cur, 0.0);
	float r = own.r * 255.0;
	float b = own.b * 255.0;
	if (rise > 0.0) { r = min(r + HEAT, 255.0); }
	if (fall > 0.0) { b = min(b + HEAT, 255.0); }
	if (h > r)  { r = h; }  // 扩散场回填（中性白灰相）
	if (h > b)  { b = h; }
	imageStore(hv_next, p, vec4(r / 255.0, 0.0, b / 255.0, 1.0));
}
