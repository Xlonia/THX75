# TH75《东方无欲拾食纪 ~Starve Universia~》技术规格书
## —— 标题菜单 / 自定义对战 / 弹幕编辑器（第0期实现 + 全量分期路线）

> 依据：策划文档《东方无欲拾食纪~Starve Universia.txt》（791行）+ 工程现状（Godot 4.7.2 mono，Dialogic 2，Forward+）。
> 本文严格区分【正式设定正文】与【随笔/备注/未来构想】；后者不进入实现规格。
> 所有模糊、二义、缺失点未自行脑补，集中列于《待确认问题列表》（§7），代码注释中以 `待确认#N` 交叉引用。
> 引擎实测：`--import` 全量通过；5 场景 headless 运行零错误；冒烟测试 32 项断言全过（`res://Tests/smoke_test.tscn`）。

---

## 1. 整体架构

### 1.1 场景流（标题画面菜单 = 游戏完整入口）

```
scenes/title_menu.tscn  （主场景，project.godot run/main_scene）
 ├─ 剧情模式  → scenes/story_placeholder.tscn   （占位：点进去但剧情无效）
 ├─ EX关卡    → scenes/ex_placeholder.tscn      （占位：同上）
 ├─ 自定义对战 → scenes/versus_menu.tscn         （选人/配置）
 │                └→ scenes/battle_arena.tscn    （arena_mode="versus"）
 └─ 弹幕编辑器 → scenes/danmaku_editor.tscn
                   └→ scenes/battle_arena.tscn   （arena_mode="preview"，试炼场，可返回编辑器）
```

- 菜单四项为策划指定最低集；标题复用既有资产 `themes/images/tmainUvReimu.png` + `reimu_bgswf.gd`（灵梦横飞动画）。
- 剧情模式/EX 占位场景共用 `placeholder_scene.gd`，按场景文件名区分文案；后续对接 Dialogic（策划原文：未来剧情编辑器对接内置 dialogic 插件——**属未来构想，不在本期实现**）。

### 1.2 Autoload 与数据流

```
GameGlobals (autoload, scripts/game_globals.gd)
 ├─ official_events : Dictionary  ← gameAssetBase/danmaku_event.csv（官方数据）
 ├─ mod_events      : Dictionary  ← res://mods/*.thx + user://mods/*.thx（覆盖层，同名覆盖官方）
 ├─ editor_events   : Array        ← 弹幕编辑器工作集（试炼场优先级最高）
 ├─ versus_* / arena_mode / preview_event_name ：对战与试炼场配置
 └─ goto_scene() ：统一场景路由
```

**事件查询优先级**：`editor_events（仅preview模式） > mod_events > official_events`。

**.thx（=zip）包结构**（照抄策划《弹幕编辑器》章节）：
```
danmaku_event.csv   所有角色的弹幕事件/能力弹幕/符卡弹幕（唯一数值数据源）
danmaku/(事件名).gd 编辑器按参数自动生成的描述/执行文件（默认名 demodanmaku1.gd）
texture/(名).png    弹幕材质（尺寸2的次方、方向朝右、尽量体现灰度）
sonic/ arrange/     wav/ogg、mid（后续音频编辑期实装）
chara_new.csv / chara_cover.csv（后续角色编辑期实装）
```

**“mod直接作为官方数据”双通道**（待确认#3）：
1. 运行时：`.thx` 放入 `mods/` 即生效（mod覆盖官方同名事件）；
2. 开发期：编辑器『导出为官方数据』→ 直接写 `gameAssetBase/danmaku_event.csv` + 材质入 `gameAssetBase/shooting/danmaku16pxs/`，并 `reload_official()` 即时刷新运行时池（注意：导出写 `res://` 仅在工程源码/dev 环境可用，见待确认#20）。

### 1.3 目录结构（本期新增）

```
scripts/
 ├─ game_globals.gd            autoload 单例
 ├─ chara_db.gd                Characters.csv 解析
 ├─ danmaku/
 │   ├─ danmaku_event_data.gd  事件数据（41列 CSV ⇄ 对象 + 表达式编译）
 │   ├─ danmaku_expr.gd        表达式编译/执行（^→** 翻译）
 │   ├─ danmaku_tex.gd         材质解析（官方库/.thx导入/兜底）
 │   ├─ ddm_field.gd           DDM 伤害弹幕图场（印章式增量更新）
 │   └─ bullet_runtime.gd      弹幕运行时（五类运动学+DDM注册）
 ├─ versus/
 │   ├─ battle_entity.gd       实体（AP/三部位HP/被弹/心情）
 │   ├─ fire_control.gd        火控（轮射/齐射/概率规律门/火力点公式）
 │   ├─ battle_arena.gd        战场主场景脚本
 │   └─ arena_painters.gd      绘制层桥
 └─ ui/
     ├─ title_menu.gd  placeholder_scene.gd  versus_menu.gd  danmaku_editor.gd
scenes/ 上述6个极简tscn（UI全部代码构建）
Tests/smoke_test.gd|tscn       headless 冒烟测试
gameAssetBase/danmaku_event.csv 官方演示事件5条（自机狙/激光/导弹+引爆/环形速度场/散射）
```

---

## 2. 模块拆分

| # | 模块 | 文件 | 职责 | 分期 |
|---|------|------|------|------|
| 1 | 全局单例 | scripts/game_globals.gd | 事件池/mod加载/对战配置/路由 | 0期✅ |
| 2 | 角色数据库 | scripts/chara_db.gd | Characters.csv→字典行（26角色） | 0期✅ |
| 3 | 事件数据 | scripts/danmaku/danmaku_event_data.gd | 41列CSV⇄对象、表达式编译、引号CSV | 0期✅ |
| 4 | 表达式引擎 | scripts/danmaku/danmaku_expr.gd | 文档运算语法（^=次方）→Godot Expression | 0期✅ |
| 5 | 材质系统 | scripts/danmaku/danmaku_tex.gd | 官方库扫描/运行时导入/兜底白圆 | 0期✅ |
| 6 | DDM弹幕图场 | scripts/danmaku/ddm_field.gd | 伤害|模式 键控多图、印章增量、圆盘探测 | 0期✅（GPU迁移见§5） |
| 7 | 弹幕运行时 | scripts/danmaku/bullet_runtime.gd | 五类tag运动学、pass/alpha、物弹遮罩、引爆链 | 0期✅ |
| 8 | 战斗实体 | scripts/versus/battle_entity.gd | AP/HP三部位、被弹四类、0.5s免疫、心情 | 0期✅ |
| 9 | 火控 | scripts/versus/fire_control.gd | Mpcs/Spcs公式、轮射/齐射计时器、rate/pattern门 | 0期✅ |
| 10 | 战场 | scripts/versus/battle_arena.gd | 主循环8步、被弹上升沿结算、阶段/胜负、HUD | 0期✅（简化项见§4.10） |
| 11 | 弹幕编辑器 | scripts/ui/danmaku_editor.gd | 41参数表单、.thx存读、官方导出、试炼场 | 0期✅ |
| 12 | 标题/选人/占位UI | scripts/ui/*.gd | 菜单、选人、占位 | 0期✅ |
| 13 | 冒烟测试 | Tests/smoke_test.gd | CSV/表达式/.thx/DDM/被弹/公式 32断言 | 0期✅ |
| 14 | 队伍编排/增援/杂兵 | — | 33实体上限、增援队列5形状、250池 | ②期 |
| 15 | 战场四阶段完整判定 | — | 远距/短兵/破阵/撤离 全条件 | ②期 |
| 16 | 符卡/P点经济 | — | 16张携带/5接收/掉落32P/击破5P等 | ②期 |
| 17 | 态势卡环形缓冲区抽卡 | — | 祖玛式补卡、正态分布S/P参数 | ③期 |
| 18 | 战术卡检测 | — | 16~25号卡遍历、At/10*Ct>1 | ③期 |
| 19 | 热力图族8种 | — | Ht/Hv/Hd/Hr/Hcs/Hct/He/Hp 像素遍历图 | ③期（GPU） |
| 20 | 态势十六点/APF/RET/R-ETA | — | 48采样、斥力权重表、RET-C/RET-SP | ③期 |
| 21 | 剧情模式/Dialogic | — | 对接 dialogic | 未来（作者声明暂不做） |

---

## 3. 常量枚举数据表

### 3.1 弹幕类 tag（文档《弹幕释放类型》）
| 常量 | 值 | 语义 |
|---|---|---|
| TAG_REGULAR | IsDanmakuRegular | 一般直线类：pos=origin+normalize(x,y)·speed·t |
| TAG_PHYSICAL | IsDanmakuPhysical | 物理类：v=(x,y表达式)·speed乘数，逐帧积分 |
| TAG_FUNCTED | IsDanmakuFuncted | 轨道类：forward+=speed·dt；pos=origin+dir·forward+垂直·func |
| TAG_LASER | IsDanmakuLaser | 瞬时类：预警[0,alarm]伤害-1，生效(alarm,range]；伤害=min(16,dmg) |
| TAG_NODES | Nodes | 点向类：目标追踪/转向角/失锁/引爆与中途事件（节点实现，性能敏感） |

### 3.2 攻击模式 dmg_mode（文档《攻击模式》）
| 值 | 语义 | 结算 |
|---|---|---|
| N | 一般 | 先扣AP再扣HP；AP剩1仍可防御一次被弹 |
| I | 穿透类 | 与剩余AP呈反比削减，最少1；ap=0直击HP（口径见待确认#9） |
| S | 碎甲类 | 无视结界；瘫痪部位 dmg 秒（1攻击力=1秒=60帧），暂不伤AP/HP |

### 3.3 火力槽 slot（文档《角色弹幕设定》）
`main`武器首要 / `sub`武器次要 / `rest`其余武器 / `wing`僚机 / `skill`能力时间轴 / `spell`符卡时间轴。
时间轴事件 `timeline_frame≥0`；火控循环事件 `-1`。（首要/次要占比进位/去尾分配属②期）

### 3.4 danmaku_event.csv 列（41列，= 编辑器表单字段）
```
event_name owner slot timeline_frame tag
texture color color_render alpha pass
repeat_time repeat_freq range is_abs_coord
dmg dmg_mode dmg_allow_moderate rate pattern
danmaku_size_muti is_phy is_cannon
speed x y func
alarm alarm_shader_alpha
targe targe_offsetx targe_offsety
acc turn_arg speed_max lost_max lost_min
explode_condit release_condit explode release can_destroy
```
- `rate`/`pattern` 空缺=不启用门（`rate_specified`/`pattern_specified` 内部标记）。
- `range` 为 GDScript 保留字上下文，运行时字段名 `range_frames`，CSV 列名不变。
- `func` 同理，运行时字段名 `func_expr`。
- `targe` 拼写保持文档原文（非 target）。

### 3.5 实体数值表（文档《被弹》，照抄）
| 项 | 自机 | 核心成员 | 杂兵 | 较强杂兵 |
|---|---|---|---|---|
| AP（结界） | 50 | 25 | 5 | 10 |
| HP 武器/僚机/机动 | 10/20/10 | 3/5/3 | 1/1/1 | 2/2/2 |
| 判定圆弧 | 上120°=武器，下120°=机动，左右60°=僚机；结界被剥后判定点四分 | |||
| 免疫 | 被弹结算后 0.5 秒（30帧）跳过一切被弹判定 | |||
| 满目疮痍 | 三部位HP全归零 | |||

### 3.6 火力点公式常量（文档《火控》，[[x]]=去尾）
```
Mpcs = [[ [ min(Pp/100,6,Pt) + min(T/60,4) ] × 0.5·Wm ]]
Spcs = [[ [ min(Pp/100,6,Pt) + 1 ] × 0.5·Wm ]]        （单侧僚机）
撤离阶段：忽略T，Pt=2；主机否则：T<60→3，[60,180)→4，否则→7
                          僚机否则：T<60→1，[60,180)→4，否则→7
（短兵/破阵是否共用时间轴档位 → 待确认#10）
```
缓冲时间：`Main_Cd`/`Sub_Cd`（CSV，单位0.1秒=1tick）。轮射=按ID每tick每部位解锁1点；齐射=缓冲取两者最大值全员同放；计时器允许超限立即释放（防切换哑火）；部位HP=0→计时器全锁定。

### 3.7 概率/规律门（文档《火控》原文算例）
- rate：`rate_roll ≥ rate` 才释放（第0期 rate_roll=randf()∈[0,1]，待确认#11）。
- pattern：每tick `pattern_roll += pattern`；`≥1` → 释放并 `-1`（例：0.8→0.8,1.6释放→0.6,1.4释放→0.4,…）。
- 两者同填按 AND（待确认#11）。

### 3.8 表达式变量表（第0期扁平集；完整命名空间见待确认#13）
| 变量 | 语义（文档出处） |
|---|---|
| t / t_r | 弹幕自变量·时间(帧) / 预警期进度 t_r=t/alarm（文档算例 alarm150 第90帧=0.6） |
| rate_roll / pattern_roll | 弹幕自变量·概率骰子/规律时序结果 |
| r0 / r1 | 【本实现扩展】弹幕独立随机相位（0~TAU），供环形/散射做相位差 |
| self_x/y/ap/pp/normal | getChara() 子集：发射者坐标/AP/P点/慢机速度 |
| target_x/y/ap/pp/normal | getTarget() 子集：目标相对弹幕起点坐标（is_abs_coord=真时为绝对坐标） |
| target_hpweapon/hpbody/hpmove | 目标三部位HP |
| field_t / field_phase | getField() 子集：决斗帧数 / 阶段1~4 |

运算语法（文档《运算参数》）：`+ - * /`、`^`=次方（**本实现将 ^ 翻译为 Godot 的 `**`，因 Godot 的 ^ 是异或**）、`abs/min/max/log(x,y)`、括号`() `、以及 Godot 原生全部运算。

### 3.9 官方色板（文档《通用弹幕事件参数·颜色》）
`#b50321`俄赤尼安红 `#eeb30b`桂花金 `#3bff40`伊岗绿 `#3bc5ff`鲜青 `#3644e8`漪蓝 `#981cff`桂正紫晶紫

### 3.10 材质库清单（gameAssetBase/shooting/danmaku16pxs/，16px）
`tama0 tama1 ammos0 knife lasermidpx2 torpedo wasserdrop spell0 spells45`（大小写不敏感解析；材质方向朝右）

### 3.11 战场操作键位（第0期）
方向键/WASD 移动（慢机）｜V 轮射↔齐射｜F3 DDM调试图｜Esc 暂停(界面暂停=双方冻结)/结算后返回｜R 结算后重试。
（完整机控键位表——G/B/X/C/Tab/E/预设点等——属①期，见§6）

---

## 4. 模块详细规格（摘要；逐行运算流程注释见各 .gd 文件头）

### 4.1 DanmakuExpr（表达式引擎）
- `compile(text, vars)`：`^`→`**` 翻译 → `Expression.parse`；空串=未填写（调用方走默认值）。
- `execute(values, fallback)` / `execute_dict(ctx)`：失败仅告警一次并返回 fallback（坏mod不崩游戏）；命题结果自动转 0/1。

### 4.2 DanmakuEventData（事件数据）
- 41列 CSV ⇄ 对象往返（冒烟测试断言逐字段）；带引号转义的 CSV 拆分/转义。
- `compile()` 编译 alpha/pass/speed/x/y/func/explode_condit/release_condit 8 个表达式，错误数组返回给编辑器状态栏。
- `laser_damage(t)`：`t≤alarm → -1`；否则 `min(16,dmg)`（照抄文档 alar_on 算式）。

### 4.3 DdmField（DDM 场；一方一实例）
- 图键 `"伤害|模式"`（1DDM_N、3DDM_I…）；非法伤害（≤0，假弹幕/预警）注册但**不参与被弹结算**（=DDMU 语义）。
- 增量印章：每弹幕每帧 擦除上帧包围盒→盖新戳；`master` 合成图懒重建（调试/AI）。
- `probe_disc`：判定圆内白点探测，返回 [接触?, 命中角数组]（角用于部位四分）。
- **场的归属语义**：`fields[side]` = “能击中 side 方实体的弹幕” = 敌方全部 + 己方物弹（超遮罩部分）。实体被弹结算读 `fields[自身side]`（对应文档“战场双方都有一张弹幕图”）。

### 4.4 Bullet（弹幕运行时）
- delta 帧步进（`dt=delta*60`），掉帧自动补/跳（文档“异常帧”）。
- `pass` 命题为真：不注册任何弹幕图、不渲染，但继续运行（照抄文档）。
- 物弹：注册双方场；发射源遮罩半径 `15×发射者慢机速度` 内不注册友方场（待确认#8）。
- 点向类：turn_arg 限角转向、acc 沿航向加速、speed_max 封顶、远/近失锁转直线、`explode_condit` 真→执行 `explode` 事件并消亡、`release_condit` 真（需重新武装）→ 执行 `release` 不消亡；`can_destroy` 被可击中本方的场白点命中即消亡；递归深度上限 3（性能护栏）。
- 瞬时类：渲染为线（预警期 0.3×宽 细线）；`alarm_shader_alpha` 控制预警期透明度。

### 4.5 BattleEntity（实体）
- `take_hit(dmg, type, hit_angle)`：部位判定（角→上120°/下120°/左右60°）→ N/I/S 结算 → 30帧免疫 → 满目疮痍检测。
- 穿透(I)：`ap>0 → hp-=max(1,dmg*ap/100)`；`ap=0 → hp-=dmg`（待确认#9）。
- 机动折损：慢机×0.2、无快机；武器损坏：主武器失效；僚机损坏：僚机失效（火控对应部位计时器全锁定）。
- 心情（0期两档）：AP≥半=自信，否则冷静；完整心情8态+tag分层属③期。

### 4.6 FireControl（火控）
- 每 0.1s tick；轮射锁定/逐tick解锁/超限立即释放；齐射最大缓冲全员同放；部位HP=0锁定。
- 火力点重建：每5秒或P点/阶段变化（重建重置计时器——与文档“计时器允许超限”的完整互操作属①期精修，见待确认#15）。
- 事件池：主机=main∪rest槽，僚机=wing槽（②期接入首要/次要占比）。
- 0产出保底：Mpcs/Spcs 至少1（待确认#12）。

### 4.7 battle_arena（战场主循环，每物理帧8步）
```
①输入→我方移动 ②敌AI(0期简化:保持距离+正弦环绕) ③实体tick(免疫/瘫痪倒计时)
④火控tick ⑤弹幕update(delta帧) ⑥被弹结算 ⑦阶段/胜负 ⑧HUD
```
- 被弹结算：每实体读 `fields[side]`，按伤害**降序**遍历DDM；**上升沿**（上帧未接触本帧接触）才结算→同帧多弹幕只算最高伤害；持续接触不断结算。
- 部位优先级：侧身(僚机)→头部(武器)→尾部(机动)（照抄文档）。
- 阶段（0期简化）：有角色满目疮痍→撤离(4)；完整四阶段判定属②期。
- 渲染：`world`节点按 SCALE 放大（SCALE=[[(窗口高-110)/400]]≥1 的整数缩放，对齐文档渲染规格公式思路）；三层绘制桥（实体圈/弹幕/DDM调试）。

### 4.8 弹幕编辑器（danmaku_editor）
- 左栏：事件列表（新增/复制/删除）+ 文件按钮（新建/读取/保存.thx、导入材质、载入官方CSV、导出为官方数据）。
- 右栏：41字段表单（分节：元数据/通用参数/分类型参数；表达式字段带“空=默认值”提示；gate字段空=不启用）+ 试炼场预览 + 状态栏（编译错误/操作反馈）。
- 保存.thx：CSV(数据源) + danmaku/(事件名).gd(自动生成描述文件) + texture/；读取反向解析。
- 导出官方：写 `gameAssetBase/danmaku_event.csv` + 材质拷入官方库 + `GameGlobals.reload_official()` 即时生效。
- 试炼场：`_collect_form()→compile()→editor_events→arena_mode="preview"` 进入战场；顶部发射器每0.5s随机x发射选中事件；Esc返回编辑器（工作集保留）。

### 4.9 versus_menu（选人）
- 角色池=Characters.csv 全26行（Name+NameZH+关键参数展示）；配置我方/敌方/开局P点(默认100,待确认#7)/发射模式。

### 4.10 本期简化声明（非最终行为）
| 项 | 0期行为 | 目标（分期） |
|---|---|---|
| 敌AI | 保持距离+正弦环绕 | 态势/战术卡AI+热力图族（③） |
| 战场阶段 | 仅撤离简化判定 | 四阶段完整条件（②） |
| 队伍 | 1v1 | 33实体+增援+杂兵（②） |
| 符卡/P点经济 | 未实装（P点仅作公式输入） | 全量经济规则（②） |
| repeat_time/freq | 数据保留，行为未实装 | 弹幕事件重复节拍（①/③） |
| 实体渲染 | 判定圈+结界圈占位 | 立绘/朝向/服饰（美术期） |

---

## 5. 性能与 GPU 渲染方案（作者重点关注项）

### 5.1 现状（0期，CPU）
| 环节 | 复杂度 | 实测 |
|---|---|---|
| DDM增量印章 | 每弹 O(πr²)≈200~800px | headless 360帧零错误；数百弹稳定 |
| 被弹探测 | 每实体 O(πr²) 小圆 | 同上 |
| 弹幕绘制 | `_draw` 批量 | 数百sprite无压力 |
| 表达式 | 每弹每帧 ~2-6 次 Expression.execute | 编译一次，执行开销可控 |

### 5.2 迁移路线（③期热力图族为硬需求）
- **像素遍历图（Ht/Hv/Hd/Hr/Hp，10~20fps，400×400×8张）**：每张每帧 1.6M 像素 × 扩散/衰减/加热三次遍历 —— CPU 不可行，**必须 GPU**。方案：`RenderingDevice` + GLSL ComputeShader（Forward+ 已启用，无兼容障碍），ping-pong 双纹理（RD_TEXTURE_USAGE_STORAGE_BIT），衰减`0.8h去尾`/扩散`半径1线性`/加热`+64(Ht/He)`全部在片内完成。
- **DDM 合成与态势十六点采样**：随像素遍历图一并进 compute pass；CPU 仅 readback 每实体 32~48 个采样值（`texture_rd_get` 小区域或 SSBO 回读）。
- **弹幕渲染**：>2000 发时迁 `MultiMesh`（实例化）或 GPUParticles2D；注意——文档原文“其它弹幕均为Godot粒子”，但 GPUParticles 无法低成本逐粒读取位置做 DDM 注册，故 0 期用自定义 `_draw`（偏差已记待确认#14 附注）。
- **回读节流**：热力图→AI 决策数据 10fps 更新即可，与渲染帧解耦。

### 5.3 已预留的迁移接口
`DdmField` 的 stamp/erase/probe 全部为纯函数式接口；`Bullet._restamp/_unstamp_all` 集中注册；战场主循环步骤⑥独立成函数——迁 GPU 时仅替换 DdmField 实现为 RD 后端，上层不动。

---

## 6. 分期路线图

| 期 | 内容 | 关键依赖 |
|---|---|---|
| **0期（本次交付）** | 标题菜单/占位、自定义对战(1v1)、弹幕编辑器+.thx+官方导出+试炼场、DDM被弹结算、火控轮射齐射、五类弹幕、表达式引擎 | — |
| ①期 | 完整机控键位（G/B/X/C/Tab/E/预设点）、角色朝向侧判定、repeat节拍、次要/首要火力点占比、快机/巡航 | 待确认#10/13/15 |
| ②期 | 战场四阶段完整判定、队伍33实体+增援队列5形状、杂兵收编/万岁冲锋、符卡P点经济、撤退/投降/胜负全规则 | 待确认#1 |
| ③期 | 态势卡环形缓冲区、战术卡、心情8态、热力图族8种(GPU compute)、态势十六点/APF/RET-C/RET-SP/R-ETA | 待确认#2/6 |
| 未来 | 剧情编辑器(Dialogic)、sonic/arrange、chara_new/cover | 作者排期 |

---

## 7. 待确认问题列表（逐条提问；代码注释 `待确认#N` 对应）

**分期与范围**
1. 自定义对战首版按“分阶段”推进（现0期=弹幕核心+DDM+火控+1v1；②期阶段/增援/经济；③期AI+热力图）——是否认可此分期？还是要求一次性全量实装后再开放入口？
2. 像素遍历图/热力图族/态势十六点采样迁 `RenderingDevice` 计算着色器（Forward+已启用）——技术路线是否确认？（0期DDM为CPU增量印章，接口已隔离可平滑迁移；备选：双SubViewport片元着色器ping-pong，实现更简单但带宽高）

**mod与编辑器工作流**
3. “mod直接作为官方数据”采用双通道：运行时 mods/ 加载 .thx + 编辑器『导出为官方数据』写回 gameAssetBase/——是否符合预期？
4. danmaku/(事件名).gd 定位为“编辑器按参数自动生成的描述/执行文件”，CSV 行为唯一数值数据源——是否正确？
5. 导出官方数据写 `res://gameAssetBase/` 仅在工程源码（dev）环境可用（导出包内 res:// 只读）——正式发行版是否改为导出至 user:// 后提示手动拷贝？
20. （并入#3/#5）编辑器导出后 `reload_official()` 即时刷新运行时池——是否需要在游戏内提供“重载官方数据”入口？

**数值口径**
7. 决斗开始 P 点初始值文档未定义（仅有上限500与溢出规则）——0期默认100（选人界面可改），正式值？
8. 物弹发射源遮罩半径：文档《决斗底层》=“25场地像素”，《弹幕编辑器》=“15×getChara(normal)”，两处不一致——取哪个？（0期实现取 15×慢机速度）
9. 穿透类(I)公式：算例“AP剩10 挨3攻击 扣0.3 算作1”推出 `dmg×AP/100` 基线100，但自机AP上限仅50、核心25（穿透伤害几乎恒为最小值1）；“被剥甲后一发就重伤”的精确语义（HP扣多少？）——请给出最终公式与被剥甲分支。
10. 火力点公式 Pt 阶段基数：文档只给 撤离2 / T<60 / [60,180) / 否则7 四档——短兵/破阵阶段是否直接沿用时间轴档位（0期如此实现）？
11. rate 语义：`rate_roll≥rate` 中 rate_roll 取值范围（0期 randf()∈[0,1]，rate=0.5 即50%）；rate 与 pattern 同填时按“与”处理——是否正确？
12. 火力点公式产出 0 时的行为（低P点+撤离阶段可能为0）——0期强制每侧至少1个火力点，是否可接受？

**表达式与变量**
13. 外界变量命名空间：文档为 getChara()/getTarget()/getField()/getFriendly()/getEnemy()/getChataFriendly(,) 与 1d/2d/5d_(弹幕图)_aver/vectsum 系列——①期起按命名空间函数+热力图变量全集实装，0期扁平变量集（self_*/target_*/field_*）作为过渡是否可接受？r0/r1 随机相位为0期扩展变量，保留否？

**弹幕行为**
14. 瞬时类激光长度公式：文档未明示（仅“航程”概念），0期取 `长度=speed×range`——是否符合预期？另：文档“其它弹幕均为Godot粒子”与DDM逐弹注册的需求冲突（GPUParticles无法低成本读粒子位置），0期用自定义批量绘制替代——渲染层后续迁 MultiMesh/GPUParticles 是否可接受？
15. repeat_time/repeat_freq（弹幕重复时间/频率）与火控缓冲时间的层级关系：文档仅明确火炮类据此生成“重复频率为0的弹幕粒子节点”——①期实装时按“事件自身节拍独立于火控tick”理解是否正确？

**数据表**
16. 判定点“约4像素”描述 vs CSV Determine/Defend 数值（1~5）——已按 CSV 像素半径执行，确认即可。
17. 文档列名 Determite vs CSV 表头 Determine——已按 CSV，确认即可。

**AI与③期前置**
6. 态势十六点：文档一处写“0.1/0.2秒距32点”，另一处写“0.1/0.2/0.5秒距三个尺度、每串16点、默认1d+2d共32点”——5d 是否属于态势十六点？32点组成以哪个描述为准？
18. 心情参数表（S/P）与《心情》章节描述一致性已核对无冲突，③期按参数表实装——如有修订请提出。
19. ②期队伍上限33实体（8角色+25杂兵渲染上限、250池、1/5较强杂兵AP/HP翻倍为10与2/2/2）——“较强杂兵”的选取与数值翻倍确认。

---

*生成于第0期交付；实测记录：`--import` EXIT=0；smoke_test 32断言 SMOKE_OK；title/versus/editor/story/ex/battle_arena 六场景 headless EXIT=0 零错误。*