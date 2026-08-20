# 山路

这是一个使用 Godot 4.8 开发的原创传统单机修仙 RPG 与内容创作框架。

新游戏默认从固定视角 3D 的“阵灯隘口”开始：沿路清理固定兽群、选择一件改变技能形态的法器、
引食炁岩兽撞上三根阵柱，处理公共阵灯，并从炼气九层突破到锐金或流泉筑基。玩家也可以返回
程序生成的 `64 x 32`“北坡原野”，进入“北坡采药”完成两趟留根采集。五张地图共同覆盖
3D 移动、碰撞、导航、即时战斗、持久选择、装备、菜单和 v5 存读档。

战斗直接发生在当前 3D 地图中：键鼠使用左键情境移动、追击攻击与互动，手柄保持移动与瞄准分离；
普攻命中恢复真气，并使用三个技能、闪避和物品对付有限敌群。法器改变飞剑折返/穿透或群攻回气，道基改变连击剑波或技能周流；
`map.roadside.lantern_pass` 以 4/8/9/4/1/12 的固定遭遇节奏验证群怪、精英选择、阵柱 Boss、
筑基和终局回测。Victory/Escaped/Defeat 与来源结算保持幂等；不做随机词缀或无限刷怪。

北坡原野与药草地都由编辑期生态地图工具使用固定 seed 烘焙：道路、湿润林缘、松林、
碎石坡、地表细节和环境碰撞程序生成；spawn、Portal、三处药草、persistent ID 与
StoryModule 仍由作者维护。游戏运行时只加载普通 `.tscn`，不会随机重建地图。

内部逻辑画面为 `640 x 360`，默认窗口是严格 2 倍的 `1280 x 720`。玩家可以调整窗口
大小、在设置页选择 2 倍/3 倍窗口或按 F11 切换全屏；世界使用低多边形、有限色板与固定
正交摄影机，UI 使用原生布局与清晰矢量文字。根 Viewport 直接同时承载 3D 世界和 Control UI。

当前 R8 成品体验基线采用“传统修仙氛围、暗黑式情境操作、传奇式清晰反馈”：地表物理射线与
导航吸附驱动左键移动，目标切换和战斗镜头保持敌我同屏；命中停顿、受击闪白、剑弧、火花、
残影与敌人前摇提供分层反馈。HUD 使用左下状态、底部六格动作栏、顶部目标血条和右上任务卡，
设置页支持键盘/鼠标/手柄独立重绑、摇杆调校、对话速度与减少闪烁。

## 当前内容

- `actor.roadside.traveler`：使用共享 13 骨骼与六组通用动画的普通旅人。
- `npc.roadside.shopkeeper`：复用同一骨骼与动画的店主定义。
- `map.roadside.north_slope_wilds`：连接采药、兽径和隘口的 `64 x 32` 程序生成生态原野。
- `map.roadside.shop`：草地、旧石路、硬土与垄田组成的斜坡小铺。
- `map.roadside.herb_slope`：三处具有稳定来源 ID 的北坡药草地。
- `map.roadside.lantern_pass`：新游戏默认进入的六段有限遭遇、守灯人、三根阵柱、公共阵灯和筑基坛。
- `item.roadside.fanqing_grass`：可交付换取工钱的返青草材料。
- `story.roadside.gathering`：负责路线、时段、采法、交付和第二趟结果的 StoryModule。
- `map.roadside.north_slope_pack`：地图内实时战斗的有限兽群遭遇。
- `story.roadside.lantern_pass`：负责兽群推进、法器、Boss、阵灯选择、筑基与最终回测。
- `realm.qi_refining` / `realm.foundation_establishment`：炼气九层与筑基三层规则。
- `foundation.sharp_metal` / `foundation.flowing_water`：锐金爆发与流泉循环两种道基。
- 松树、围栏、小铺与完整/割后药草均为可复用 GLB/3D 场景，碰撞与导航由 `.tscn` 维护。

世界观不会在开场主动讲解。玩家先学习世界中的移动、互动和资源规律，后续内容再从
这些规律的缺口中逐渐显露更大的历史。

## 运行

需要 Godot 4.8：

```sh
godot --path .
```

在 Godot 编辑器的“游戏”工作区嵌入运行时，推荐从右上角游戏窗口选项的
`Embedded Window Sizing` 选择 `Fixed Size`。`Stretch to Fit` 会把游戏窗口改成工作区的任意
长宽比，再由工程的 `keep + integer` 规则补黑边，因此窄高工作区中可能出现大面积黑区。

操作：

- 左键：点地移动、点敌人追击普攻、点 NPC/采集物/Portal 自动靠近互动；WASD 或方向键可随时接管移动。
- Shift + 左键：原地攻击；Ctrl + 左键：强制移动，不攻击鼠标下的敌人。
- 鼠标右键、1、2：三个主动技能；第三槽在筑基后获得。Space：闪避；Q：使用战斗丹药。
- Tab 或手柄 R3：在视野和遮挡允许时切换战斗目标。
- 手柄左摇杆移动、右摇杆瞄准；A 普攻/互动，X/Y/RB 三技能，B 闪避，LB 使用丹药。
- Enter 或手柄 A：对话逐字显示时先补全当前句，再次按下推进；靠近对象时仍可用 Enter 互动。
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
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_r7_lantern_foundation.gd
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_ui_baseline.gd
```

四组截图分别写入 `/tmp/godot-pal-g6/`、`/tmp/godot-pal-g4/`、`/tmp/godot-pal-r7/` 与
`/tmp/godot-pal-ui/`；R7
固定覆盖隘口探索、群怪、法器选择、冲撞预警、撞柱失衡、阵灯两种结果、两种道基和最终十二怪回测。

## 架构边界

```text
ContentDatabase   静态 Resource 定义与索引
GameRun           一次游戏的可序列化状态
GameSceneStack    标题、地图、菜单与商店流程
BattleSession     当前地图内一次有限实时遭遇
Realm/Foundation  境界层数、筑基门槛与流派定义
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
- [R8 成品体验改进方案](docs/r8-finished-experience-plan.md)
- [固定视角 3D 即时战斗计划与决策门](docs/3d-action-combat-plan.md)
- [开发代理约束](AGENTS.md)
