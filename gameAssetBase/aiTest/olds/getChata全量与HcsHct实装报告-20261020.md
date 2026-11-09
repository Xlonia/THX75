# getChata 全量 + Hcs/Hct 实装 + 重命名 报告（2026-10-20 第四批）

**依据**：作者四点——①getChata 文档已完善（示例 `getChataFriend("AP<<3","random(true)")`）；②Hcs/Hct 处理方式在游戏逻辑介绍有述（按文档实装）；③加重命名功能；④.thx 不用过问。绑定问题已解决确认（E2E 回归全绿）。

**全部落地**：SMOKE_OK 105 断言、编辑器加载正常、性能 PASS（物理 1.65ms 中位 / process 1.37ms 中位——Hcs/Hct 优化后无越线）。E2E 绑定链路回归全绿。

## 一、getChata 全量（按文档语义）

- **翻译层**：`getchatafriend(定位器, 参数)` / `getchataenemy(...)` → 编译期抽取为合法占位标识符 `_chq_f_N/_chq_e_N`（定位器/参数原文登记到事件 `chata_queries`）——占位必须是合法标识符（前两轮的字符串直译会产生 `<<` 等非法名）。
- **运行时**（`_eval_chata_query`）：按发射者阵营取候选角色（存活非杂兵非发射器）；定位器命题**以候选角色为 self 上下文**逐个求值（ap/pp/normal/x/y/hpweapon/hpbody/hpmove/kp/sp；未定义变量/执行失败→该角色不命中）；多命中随机取一；返回**所选角色的参数值**（示例：`getchatafriend("AP<3","ap")` 返回 AP 告急角色的 AP）。计数器参数（privates_collapse/chara_collapes）直接返回阵营击破数。`random(true)` 选取器=文档固有的"多命中随机"，无需特判。
- **占位声明**：参数为 `player/fieldid/random(true)` 时返回 0——它们是"角色引用"，数值表达式系统放不下（需实体引用系统，下批）。`randomChara(定位器)` 同理占位。
- 定位器写法：`"AP<<3"` 的 `<<` 按文档原样不支持（`<` 支持）；引号包裹的命题在翻译时剥引号。

## 二、Hcs/Hct 实装（按游戏逻辑介绍）

- **Hcs**（角色 1s 弹幕热点图）：角色 0.5 秒距内威胁弹幕（敌弹+双方物弹）未来 1 秒轨迹的时空分布——分析式求值：每采样点对每条弹幕轨迹算覆盖帧数（点-线段闭式解），填充均值 `sqrt×16 取整`（0~255）。
- **Hct**（s20 图）：Hcs 基础上，采样点位于角色当前 AI 移动方向一侧且 Hcs>0 → +64（钳 255）。
- **采样点**：49 点=三环 48+中心（与态势十六点同构，环半径 0.1/0.2/0.5 秒距；带转随帧）。
- **调度**：每角色 0.2 秒交错（性能红线），候选弹一次预筛（范围 R+轨迹长、上限自然收敛）——首版直算把 process 打到 p90 45ms，优化后 process 1.37ms 中位。
- **接入**：①`dm_apfrepul` 权重表按文档更新为 **Ht1 Hd3 Hcs5 Hct10 He2 Hp3**（分母 24；Hr 移出——文档 APF 斥力不含 Hr）；②`dm_smn=Ht3+Hd1+Hcs8`、`dm_sms=Ht2+Hd1+Hcs4`（中心点值）；③态势变量 `hcs1daver/.../hct5dvectsum` 全部实数（此前占位 0）；④杂兵 AI 的 Hd2/Hcs5 权重——杂兵当前无十六点采样架构（文档：杂兵只用 Hd+Hcs、跳过 RET-SP），列入下批随杂兵 AI 专项。

## 三、重命名功能

弹幕列表按钮行新增「重命名」：改事件名并**自动同步所有引用**——Characters.csv 五个列表列（逐行保存）、时间轴 tick（写回 `gameAssetBase/timelines/<名>.gd`，新增 GameGlobals.save_timeline_gd）、各事件的 inherit/release/clash_ddm 列表字段；随后既有自动落盘写分表。非法名（空/分号/逗号/#/同名）拒绝并提示。

## 四、验证记录

SMOKE_OK 105 断言；flow_e2e 绑定链路回归全绿（同会话/重启/重开编辑器三态出弹）；编辑器加载零解析错；battle_tick_perf：物理 1.65ms 中位、process 1.37ms 中位、VERDICT PASS。修改后快照 12 份存 aiTest `*_修改后20261020d.gd`。

## 五、遗留存照（下批）

1. getChata 定位器的 player/fieldid/random(true) 参数与 randomChara 返回：需实体引用系统（表达式只能回数值）。
2. 杂兵 AI 的 Hd2/Hcs5 权重（杂兵十六点采样架构）。
3. Hct 的"四方向枚举"目前近似为"当前 AI 移动方向单侧判定"——若需严格四方向版本（每方向独立加分图）请示下。
4. Hcs/Hct 尚无可视化（F3 循环可加第 8/9 档，按需）。
