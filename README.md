# 山路

这是一个使用 Godot 4.8 开发的原创传统单机修仙 RPG 与内容创作框架。

当前默认从固定视角 3D、程序生成的 `64 x 32`“北坡原野”开始，玩家可以沿贯穿湿地、松林与碎石坡的
旧路探索，再由人工 Portal 进入“北坡采药”切片：从斜坡小铺接下两趟采药差事，在安全
旧路与有随机风险的碎石近坡之间选择，决定割叶留根或连根挖走，并在第二趟看到药丛再生
或永久消失。三张地图覆盖 3D 移动、碰撞、导航、交互、菜单和存读档。

战斗直接发生在当前 3D 地图中：玩家移动与瞄准分离，使用普通攻击、两个主动技能、闪避和
物品对付有限敌群。`map.roadside.north_slope_pack` 验证近战/远程敌人、前摇、投射物、
状态、Victory/Escaped/Defeat，以及幂等的遭遇结算；不做随机词缀或无限刷怪。

北坡原野与药草地都由编辑期生态地图工具使用固定 seed 烘焙：道路、湿润林缘、松林、
碎石坡、地表细节和环境碰撞程序生成；spawn、Portal、三处药草、persistent ID 与
StoryModule 仍由作者维护。游戏运行时只加载普通 `.tscn`，不会随机重建地图。

内部逻辑画面为 `640 x 360`，默认窗口是严格 2 倍的 `1280 x 720`。玩家可以调整窗口
大小或按 F11 切换全屏；世界使用低多边形、有限色板与固定正交摄影机，UI 使用原生布局
与清晰矢量文字。根 Viewport 直接同时承载 3D 世界和 Control UI。

## 当前内容

- `actor.roadside.traveler`：使用共享 13 骨骼与六组通用动画的普通旅人。
- `npc.roadside.shopkeeper`：复用同一骨骼与动画的店主定义。
- `map.roadside.north_slope_wilds`：默认进入的 `64 x 32` 程序生成生态原野。
- `map.roadside.shop`：草地、旧石路、硬土与垄田组成的斜坡小铺。
- `map.roadside.herb_slope`：三处具有稳定来源 ID 的北坡药草地。
- `item.roadside.fanqing_grass`：可交付换取工钱的返青草材料。
- `story.roadside.gathering`：负责路线、时段、采法、交付和第二趟结果的 StoryModule。
- `map.roadside.north_slope_pack`：地图内实时战斗的有限兽群遭遇。
- 松树、围栏、小铺与完整/割后药草均为可复用 GLB/3D 场景，碰撞与导航由 `.tscn` 维护。

世界观不会在开场主动讲解。玩家先学习世界中的移动、互动和资源规律，后续内容再从
这些规律的缺口中逐渐显露更大的历史。

## 运行

需要 Godot 4.8：

```sh
godot --path .
```

操作：

- WASD、方向键或左摇杆：地面移动。
- 鼠标或右摇杆：瞄准；鼠标左键/手柄 A：普通攻击。
- Q/鼠标右键/手柄 Y 与 E/手柄 X：两个主动技能。
- Space/手柄 B：闪避；R/右肩键：使用战斗物品。
- Enter 或手柄 A：探索互动与推进对话。
- 方向键或左摇杆：在对话选项间移动；Enter/A 确认。
- M 或手柄 Start：打开菜单。
- F6：从菜单进入保存界面。
- F5/F9：调试保存与读取。
- F11：切换窗口与全屏。

## 验证

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate res://game/roadside/map_generation/roadside_shop_3d_profile.tres --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate res://game/roadside/map_generation/herb_slope_3d_profile.tres --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate res://game/roadside/map_generation/north_slope_wilds_3d_profile.tres --json
godot --headless --path . -s res://tests/run_tests.gd
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_g6_formal_slice.gd
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_g4_formal_slice.gd
```

两个截图命令分别在 `/tmp/godot-pal-g6/` 生成标题、三张地图、剧情选项与药草四态，在
`/tmp/godot-pal-g4/` 生成探索、警戒、前摇、投射物与三种战斗结果。

## 架构边界

```text
ContentDatabase   静态 Resource 定义与索引
GameRun           一次游戏的可序列化状态
GameSceneStack    标题、地图、菜单与商店流程
BattleSession     当前地图内一次有限实时遭遇
StoryEvent        地图内简单交互
StoryModule       多地图、多阶段叙事职责
StoryContext      剧情可调用的稳定高层 API
```

- `.tscn` 负责对象组合、地图布局、碰撞和生命周期。
- Resource 负责静态内容；RefCounted 负责运行状态。
- 地图角色随 MapGameScene 创建和销毁，长期进度只进入 GameRun。
- 当前采药闭环由一个 StoryModule 响应店主、地图入口和三处药草 trigger。
- 不建立 GameSession、GameFlow、通用动作数组或自制剧情 opcode。

## 原创素材

运行素材位于 `assets/original/`，不依赖第三方游戏提取资源。正式 3D 角色、药草与环境模块
由仓库脚本确定性生成 GLB，记录统一单位、轴向、共享骨骼、动画、三角面、哈希和导入约束；
原创音频同样保留生成记录。详见 [原创素材说明](assets/original/README.md)。

## 文档

- [世界观与叙事原则](docs/worldbuilding.md)
- [需求与范围](docs/requirements.md)
- [运行时架构](docs/architecture.md)
- [内容创作接口](docs/content-authoring.md)
- [原创素材管线](docs/asset-pipeline.md)
- [程序化生态地图工具](docs/map-generation.md)
- [开发路线](docs/roadmap.md)
- [视觉验收](docs/visual-acceptance.md)
- [固定视角 3D 即时战斗计划与决策门](docs/3d-action-combat-plan.md)
- [开发代理约束](AGENTS.md)
