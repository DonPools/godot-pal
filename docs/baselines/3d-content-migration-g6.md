# G6 固定视角 3D 正式内容迁移验收

日期：2026-08-19

结果：通过。固定视角 3D、地图内实时战斗和三张采药地图成为正式基线；旧 2D 内容只保留
为迁移记录与显式 legacy generator fixture。

## 正式切换

- `map.roadside.north_slope_wilds`、`map.roadside.shop`、`map.roadside.herb_slope` 的
  MapDefinition 已指向 3D 场景，新游戏仍使用原来的语义 map/spawn ID。
- StoryModule、trigger、Dialogue option、persistent ID 与 WorldState 语义保持不变；真实
  GameRoot 测试通过 Portal、两趟采药、留根再生、连根消失、两次交付、菜单与存档。
- `save_version = 4` 保存 Vector3；v2/v3 精确 Vector2 位置清除后回退安全语义 spawn，队伍、
  背包、金钱、剧情、Flags、WorldState 与随机状态继续保留。
- `NpcDefinition`/`NpcCharacter3D` 正式登记店主；Definition 模型、场景 wrapper 与
  StoryInteractable3D actor ID 由内容校验和场景测试共同约束。

## 地图烘焙

| 地图 | seed | cell | prop | plan hash |
|---|---:|---:|---:|---|
| 斜坡小铺 | 250824 | 252 | 10 | `0e9feb04488181654909c0f0e76c0e8cd136f346596dbfb1f66160342982d8be` |
| 北坡药草地 | 240816 | 512 | 30 | `7d0bcff06dd57e26b08a7a9033ba064c277659cdf38bef09bd1f5beb9ca79502` |
| 北坡原野 | 260816 | 2048 | 92 | `4f8c1619d689ae20cf7f506096ecd3e6e50825af0342610abcaf6b7911c5e7f4` |

三个 schema/generator v2 Profile 均为零诊断，全部 gameplay anchor 可达。Baker 保留人工
NPC、建筑、spawn、Portal、药草、StoryBinding 与 persistent ID，只替换带所有权元数据的
GridMap、Detail、环境 Prop、碰撞、导航和边界。

## 素材结论

长期素材量会下降，但不是“所有美术都更便宜”：

- 旧四斜向角色仅一个走路动作需要 12 格；若六个动作每方向三帧，每角色至少 72 个方向帧。
  现在同一 13 骨骼和六组动画覆盖任意地面朝向，第二人形变体和敌人不再复制方向帧。
- 环境模块可旋转、缩放和换材质；三张地图复用同一批地面、松树、灌木、岩石、围栏与建筑，
  地图面积增长主要增加布局数据，而不是增加同等比例的新图。
- 正式药草只增加完整/割后两个 GLB；标题头像由正式旅人 GLB 确定性渲染，不保留第二套角色画法。
- 第一套骨骼、动画、材质、碰撞、导航和导入校验仍是新增固定成本。独特 Boss、复杂布料、
  大量装备外观和高质量特写可能比 2D 更贵，不能用方向复用掩盖这些成本。

G3 的可重建低模集合为 13 个 GLB、约 184KB，完整重建约 0.05 秒、首次 Godot 导入约
2.2 秒；第二人形变体复用全部六组动画轨道。证据见 `3d-asset-production-g3.md`。

## 视觉验收

`capture_g6_formal_slice.gd` 在 `/tmp/godot-pal-g6/` 生成 11 张 `640 x 360 RGBA`：标题、
原野、小铺、店主对白、委托选择、路线选择、药草完整、采法选择、割后、再生和连根消失。
药草四态在同一脚点可辨，3D 地表色值不过曝，角色/NPC/对话没有重叠。

`capture_g4_formal_slice.gd` 在 `/tmp/godot-pal-g4/` 继续生成 7 张 `640 x 360 RGBA`：探索、
警戒、前摇、投射物/障碍、Victory、Escaped 与 Defeat。G4 地图环境光已与三张迁移地图统一。

## 旧实现清理

- 删除 `BattleGameScene` 及 BattleSession 的 `Command/execute/rounds` 临时桥。
- 删除 G1 原型场景、原型规则类和只针对原型的测试；G1 数字与结论保留在 baseline 文档。
- 普通 map generation 测试只运行 3D fixture 与三个正式 Profile；旧 2D 套件通过
  `run_legacy_2d()` 显式调用，不再属于普通 CI。
- AssetLibrary、标题、ContentDatabase 与正式 MapDefinition 不再引用 2D 方向图集或 TileSet。

## 最终验证

以下检查通过，日志没有工程 `SCRIPT ERROR`：

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate res://game/roadside/map_generation/roadside_shop_3d_profile.tres --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate res://game/roadside/map_generation/herb_slope_3d_profile.tres --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate res://game/roadside/map_generation/north_slope_wilds_3d_profile.tres --json
godot --headless --path . -s res://tests/run_tests.gd
```

受限环境中的 editor 命令仍会报告 macOS 系统 CA 和用户目录 editor settings 写入错误；文件
扫描、全局类注册、资源导入和插件加载完成，内容、地图与测试命令均零诊断通过。

发布前仍需用实际手柄复核不同硬件的右摇杆死区与瞄准迟滞；这不改变 BattleSession、内容
schema、存档或地图生产结论。
