# TH75 技术规格书（第①期版）
## —— 性能改造 / 火力点排布 / 队伍战 / 编辑器重构

> 依据：策划文档 + 作者批复（`gameAssetBase/aiTest/待确认问题批复与额外提示.txt`）+ 新版编辑器文档（`scheme/东方无欲拾食纪-弹幕编辑器-新.txt`）。
> 实测记录：`--import` EXIT=0；五场景 headless 零错误；冒烟测试 35 断言 SMOKE_OK；带窗口 bench（RTX 3050）见 §5。

---

## 0. 批复落实对照表

| 批复# | 内容 | 落实 |
|---|---|---|
| 1 | 分期同意 | ✅ 按原分期 |
| 2 | 着色器路线确认，①期实现 | ✅ DdmGpu 计算着色器（headless自动降级；带窗口跑通管线） |
| 3/5 | 工程环境才显示"导出为官方数据"，否则仅打包导出 | ✅ `_is_project_env()` 写探测，非工程环境菜单项替换为"打包并导出" |
| 4 | 仅CSV | ✅ danmaku_event.csv 唯一数据源（.gd为生成的描述文件） |
| 20 | reload官方数据用途 | ✅ 改为"导出后即时刷新运行时池"（工程内调试用途）；mod 禁用（.disabled）属②期 |
| 7 | P点默认100 | ✅ |
| 8 | 遮罩=15×慢机速度（0.25秒距） | ✅ `Bullet.beyond_mask()` |
| 9 | I类 AP=0 → dmg÷0=FLT_MAX（一发重伤）；光学迷彩min钩子 | ✅ `impale_cap` 变量预留 |
| 10 | 撤离 Pt=2 但 T 仍参与 min(T/60,4) | ✅ 修正公式 |
| 11 | rate: randf()<=rate；pattern真时减一；两命题皆真才释放 | ✅ `_gate()` |
| 12 | 主机保底1，僚机可0；主机=总数/僚机=每侧 | ✅ |
| 13 | 变量命名空间均可接受 | ✅ |
| 14 | 取消CPU像素印章！弹幕=渲染至弹幕图+屏幕的粒子 | ✅ **哈希被弹 + GPU DDM + MultiMesh**（见§5） |
| 15 | repeat=缓冲前多次发射（双发三发） | ✅ `repeat_tick()` |
| 16/17 | Determine 半径执行；determite是笔误 | ✅ |
| 6 | 态势十六点=1d/2d共32点；5d仅巡航 | ✅ 记录（③期AI实装基准） |
| 18 | 调试窗口带实时值（十六点/向量/倾向） | 📋 ②期（角色调试窗口） |
| 19 | 较强杂兵tag→AP10/HP2·2·2；1/5上限去尾 | ✅ `is_elite_private`（决斗外选取UI属②期剧情侧） |

**额外提示落实**：damage_arr消歧义✅（`damage_arr()`）、晚汐Char_Raid=2合法✅（上限检查放宽为非负）、privates.csv✅、Enemy.csv✅（无ID/Team）、sub取代wing✅（旧数据自动迁移）、x/y_offset✅、saturation/hue✅（lightness=隐藏代码）、激光=几何图形+n()遍历换元+单像素线✅、lost_if✅、poi火力点排布✅、杂兵0.3/0.35秒距系绳+256引力✅、termin_point/termin_range/privates_id()/tpp/custom_*✅（PrivateFormation四预设）、编辑器顶栏/标签页/互斥弹幕表达/运算参数引入工具(全角注释)/#拦截/可行性检查✅、getset检测✅（hp/ap setter）、draft.csv清空改造📋（②期撤销系统已先行用快照栈实现）。

---

## 1. 第①期架构变更

### 1.1 性能架构（批复#14 核心）
```
【每帧流水】
① Bullet.update(dt)     运动学+表达式（常量折叠/共享ctx/每帧一次构建）
② BulletHash 重建       每弹O(1)入格 → 被弹解析为圆碰撞（矢量精确，语义=DDM上升沿）
③ DdmGpu.render         印章SSBO → compute shader 弹幕图（AI/调试/预览；可降级）
④ MultiMesh 批量渲染    每材质1个draw call（激光=线段集合）
```
- **CPU 像素印章/包围盒擦除/master 全量重建已全部移除**（0期卡顿根因）。
- GPU DDM 用 `RenderingDevice` + `ddm_clear.glsl`/`ddm_stamps.glsl` 计算着色器（Forward+）。
- headless/无渲染设备自动降级：逻辑完全不受影响（被弹走哈希）。

### 1.2 表达式引擎（三重优化）
1. **常量折叠**：编译期检测未用变量 → 一次求值缓存（0.25μs vs 1.4μs）。
2. **文档函数翻译**：`n(k)→n`、`privates_id()→privates_id`、`getField(t)→field_t`、`log(底,真)→log(真)/log(底)`（手工拼接替换，Godot RegEx.sub 无反向引用）。
3. **共享上下文**：战场每帧按 (事件,side) 构建一次公共字段（field_t/self_*/target_*），弹幕只叠自身变量（t/r0/t_r）——消灭每弹全实体遍历。

### 1.3 数据表（第①期）
- **Characters.csv** 新增7列 poi 表达式：`main_y sub_x sub_y main_poi_x main_poi_y sub_poi_x sub_poi_y`（变量 wpcs/to_c）。
- **privates.csv**：杂兵8种（Name/Normal/Determine/Defend/三语名）。
- **Enemy.csv**：敌角色4名（无 ID/Team——不接受队伍指挥；决斗时分配临时ID）。
- **danmaku_event.csv**：45列（新增 x_offset y_offset saturation hue laser_n_step lost_if；color_render→saturation；wing→sub）。

### 1.4 火力点排布 poi（作者公式）
```
主机首点 = 朝向×(慢机×6 + main_y)          【0.1秒距 + 修改值】
僚机首点 = 侧向×(慢机×12 + sub_x) + 背向×sub_y 【0.2秒距 + 修改值】
第k点 = 首点 + Σ_{k'=1..k-1} poi向量(k')    【poi x=该侧朝向，y=角色背向】
每6帧按 wpcs 从小到大更新（快慢机切换的"收回"动画）
wpcs=侧面从里到外序号（奇数含中点，中点x恒0）
```
表达式求值走常量折叠（`(to_c+1)*wpcs` 等仅算术式高效）。

### 1.5 队伍战（demo 目标达成）
- 每侧 5 角色（第1位=自机/领队）+ 每角色5杂兵（privates.csv 循环取材）→ 5×5=25/侧。
- 杂兵：相对角色坐标跟随 + PrivateFormation 排布（扇形/线列/蝶翼/潮汐公转四预设，作者公式原文实装）+ 0.3秒距系绳 + 0.35秒距圆4px内向256引力。
- 杂兵AI（①期简化）：仅跟随排布（场地热力图AI属③期，批复#19）。
- 敌方池：Enemy.csv（空数据回退 Characters.csv）。

### 1.6 编辑器（批复设计案）
- 顶栏：文件/编辑(撤销重做快照栈)/帮助；工程环境检测控制"导出为官方数据"可见性。
- 标签页：通用参数 / 颜色(HSL) / 弹幕表达（tag互斥，行进类型在此切换）/ 使用者（引用查询）。
- 运算/参数引入工具浮窗：搜索+全角注释插入（`log(“底数”,“真数")`）+ 提示替换。
- #字符实时拦截；可行性检查（全表达式编译报告）。
- 试炼场预览保持（Esc 返回编辑器，工作集保留）。

---

## 2. 模块清单变更

新增：`DdmGpu`（GPU弹幕图）、`BulletHash`（空间哈希被弹）、`PrivateFormation`（杂兵排布）。
重写：`Bullet`（哈希接口/激光几何/lost_if/repeat/共享ctx）、`FireControl`（poi/批复公式）、`BattleEntity`（getset/杂兵/Kind枚举）、`battle_arena`（队伍战/GPU/MultiMesh）、`danmaku_editor`（设计案）、`DanmakuExpr`（折叠/翻译）、`DanmakuEventData`（45列）、`CharaDB`（三表+poi）、`versus_menu`（队伍选人5×2）。
测试：`smoke_test`（35断言）、`bench`（带窗口性能）、`micro_bench`（微基准）、`diag_*`（诊断）。

---

## 5. 性能实测（RTX 3050 Laptop，1280×960 窗口）

| 弹幕数 | physics均值 | 峰值 | 预算 |
|---|---|---|---|
| 100 | 2.4ms | 8.7ms | 16.7ms ✅ |
| 500 | 6.5ms | 9.7ms | ✅ |
| 1000 | 13.4ms | 21.3ms | ✅（接近满载） |
| 2000 | 26.4ms | 48.4ms | ⚠️ 超预算 |
| 4000 | 48.3ms | 86.6ms | ⚠️ |

- **对比0期：百弹从 86.5ms → 2.4ms（36倍）**。demo 日常密度（≤1000）60fps 稳定。
- 微基准：Expression 1.4μs/次（折叠后0.25μs）；哈希 clear×60=331μs。
- 剩余瓶颈（2000+）：Expression 解释执行。②期方案：①表达式分频求值（低频字段 pass/alpha 每6帧）②常见模式（纯t一次多项式）预编译为闭包表 ③极端密度下 Expression→GDScript bytecode 编译。
- GPU DDM：管线已在带窗口环境跑通（RTX 3050 检测正常）；着色器导入修复（.glsl+RDShaderFile）。

---

## 7. 待确认问题列表（第①期新增/遗留）

1. **poi 修改值表达式**：main_y/sub_x/sub_y 在 CSV 中为数值或表达式——①期按字面数值读取（`_num_db`），完整表达式求值（含 wpcs/to_c 变量的 main_poi 系列）已实现 poi 步进部分；**main_y/sub_x/sub_y 本身含变量时**是否也按表达式求值？（现仅 poi 向量按表达式）
2. **火力点挂弹分配**：①期主机=main∪rest 槽全部事件、僚机=sub 槽全部事件——首要/次要占比（main_para_rat 等）分配属②期，确认排期？
3. **杂兵发射弹幕**：①期杂兵仅有判定/结界/跟随，不发射弹幕（原文"杂兵参与队伍扛血与附加弹幕"）——杂兵弹幕事件挂载格式（privates.csv 加槽位列？还是复用 danmaku_event.csv 的 owner=杂兵名）？
4. **bench 场景**：目标"数千弹幕"当前 2000+ 超预算——是否接受②期的分频求值+闭包表优化路线，或需要①期内立即做到 4000@60？（后者需把高频表达式迁移到 C# / GDExtension）
5. **编辑器设计案细节**：浮窗-弹幕显示（1:1预览/缩放/全屏）与时间轴（能力/符卡排演）UI 属②期，确认排期？
6. **draft.csv 改造**：作者要求"记录玩家未保存修改+部分还原"——①期撤销已用内存快照栈实现，draft.csv 持久化格式（哪些字段算"已修改"？）需作者给格式样例。
7. **角色材质**：shooting/charas/MarisaA.PNG 等已存在——①期战场仍用判定圈占位渲染，角色精灵/头像/立绘接入编辑器素材库属②期，确认？

---

*第①期交付实测：`--import` EXIT=0；五场景 headless EXIT=0 零错误；smoke 35断言 SMOKE_OK；bench 带窗口完成（RTX 3050）。*