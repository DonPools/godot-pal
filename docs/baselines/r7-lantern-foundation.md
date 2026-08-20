# R7 阵灯筑基完成证据

日期：2026-08-20

## 目标

R7 用一个可从北坡原野进入的纵向切片，验证“修仙背景的暗黑式地图内动作战斗”最小闭环：
固定群怪、真气循环、法器构筑、地形 Boss、持久地方选择、境界突破、道基分化与筑基后回测。

## 玩家闭环

```text
炼气七层
  -> 4 / 8 / 9 只固定兽群，普攻回气并积累修为
  -> 4 敌精英，选择回风剑匣或镇岳剑印
  -> 食炁岩兽，冲撞一次性阵柱产生失衡
  -> 修复公共阵灯（灯光 + 捷径）或拆取阵芯剑符（即时装备）
  -> 炼气九层圆满 + 食炁岩心
  -> 锐金或流泉筑基，获得归元剑阵
  -> 12 只幼兽回测构筑
```

## 规则和持久状态证据

- `CultivationRealmDefinition/DaoFoundationDefinition` 进入 ContentDatabase、catalog 和 CLI。
- ActorState 保存 `realm_id/realm_layer/cultivation_points/foundation_id`；SaveService 当前版本为 5，
  v2/v3/v4 的 level/experience 迁移到境界进度。
- CultivationTransaction 原子校验满修为、目标道基和催化物；成功后补满派生 HP/MP 并授予第三技能。
- EquipmentTransaction 原子替换武器，并在旧装备无法退回背包时保持原状态。
- BattleBuildSnapshot 固化装备与道基效果：折返穿透、群攻回气、三击剑波、技能回气/减冷却。
- BattleSession 以 `1/60` 固定步校验 CHARGE、action instance、一次性 pillar ID 与 1.6 秒失衡；
  EnemyActorView 在失衡期间停止移动。
- LanternPassStory 覆盖 Victory/Escaped/Defeat、奖励拒绝、阵灯两种结果、两种道基和最终完成。
- MapDefinition 可声明自己的默认 StoryModule，隘口 HUD 不再误用采药模块。

## 正式原创素材

`assets/original/3d/sources/generate_lowpoly_assets.py` 当前 generator v3 生成 24 条 manifest 记录；
R7 建立、R8 重整色板和晶簇辨识度的资产包括：

- 食炁幼兽、吐石兽、噬灵兽、食炁岩兽；
- 阵柱点亮态与损坏态；
- 阵芯与筑基坛。

Original3DAssetValidator 校验新 GLB 哈希、网格/材质预算、四个 CharacterBody3D wrapper、碰撞、
hurtbox、预警与阵柱两态。音频生成器新增蓄势、撞柱失衡、阵灯修复/拆取和筑基五个 WAV。

## 自动验证

以下命令在本日期的工作树通过：

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
```

编辑器检查只报告受沙箱限制无法保存全局
`~/Library/Application Support/Godot/editor_settings-4.8.tres`；工程扫描、脚本注册和资源加载完成。

内容 CLI 额外验证：

- realm/foundation/actor `create` 成功；actor 缺 realm 和 realm 层费用数量错误稳定失败；
- PackedInt32Array 层费用与道基 aura color 可 export，并以 `change_count: 0` apply；
- `refs realm.qi_refining` 与 `refs foundation.sharp_metal` 返回具体字段；
- `rename-id realm ...` 进入通用迁移器并对不存在 ID 返回结构化 `content_not_found`。

## 视觉验证

```sh
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_r7_lantern_foundation.gd
```

真实 Metal 兼容渲染后端生成 `/tmp/godot-pal-r7/` 十张 `640 x 360` RGBA PNG：

1. 隘口探索；
2. 四怪战斗与真气 HUD；
3. 精英法器选择；
4. Boss 指向玩家的冲撞长条；
5. 阵柱损坏与“破阵·失衡”；
6. 修复后的绿色阵灯和捷径；
7. 拆取后的昏暗阵灯；
8. 锐金金色道基；
9. 流泉蓝色道基；
10. 筑基后十二怪与派生 HP/真气上限。

详细逐图标准见 `docs/visual-acceptance.md`。

## 非目标

R7 没有加入随机词缀、无限刷怪、装备品质、队友 AI、赛季系统、全局天气、通用 Boss 阶段
编辑器或任意剧情 opcode。阵柱不进入 GameRun；活动战斗仍不可保存。
