# 山路

这是一个使用 Godot 4.8 开发的原创传统单机修仙 RPG 与内容创作框架。

当前正式可玩切片是“斜坡小铺”：玩家从标题页开始，进入一张 `320 x 180`、斜 45 度
像素地图，使用四个斜向移动，在原创 `32 x 16` 菱形地块上探索，与店主交谈，并验证
碰撞、YSort、菜单、设置和三槽存读档。

内部逻辑画面为 `320 x 180`，默认窗口是严格 3 倍的 `960 x 540`。玩家可以调整窗口
大小或按 F11 切换全屏；画面保持 16:9 和最近邻像素，不对世界素材做平滑拉伸。

## 当前内容

- `actor.roadside.traveler`：普通旅人，`3 x 4` 四斜向像素图集。
- `map.roadside.shop`：草地、旧石路、硬土与垄田组成的斜坡小铺。
- `dialogue.roadside.shopkeeper`：地图内嵌 DialogueEvent 使用的店主日常对白。
- 松树、两个方向的木围栏与小铺均为独立透明精灵，碰撞和遮挡由 `.tscn` 维护。

世界观不会在开场主动讲解。玩家先学习世界中的移动、互动和资源规律，后续内容再从
这些规律的缺口中逐渐显露更大的历史。

## 运行

需要 Godot 4.8：

```sh
godot --path .
```

操作：

- 方向键或左摇杆：四斜向移动。
- Enter、Space 或手柄 A：互动与推进对话。
- M 或手柄 Start：打开菜单。
- F6：从菜单进入保存界面。
- F5/F9：调试保存与读取。
- F11：切换窗口与全屏。

## 验证

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
godot --path . -s res://tools/capture_isometric_art_test.gd
```

最后一个命令在 `/tmp/godot-pal-roadside/` 生成标题、地图、树前后遮挡和店主对话截图。

## 架构边界

```text
ContentDatabase   静态 Resource 定义与索引
GameRun           一次游戏的可序列化状态
GameSceneStack    标题、地图、菜单、商店和战斗流程
StoryEvent        地图内简单交互
StoryModule       未来复杂叙事模块
StoryContext      剧情可调用的稳定高层 API
```

- `.tscn` 负责对象组合、地图布局、碰撞和生命周期。
- Resource 负责静态内容；RefCounted 负责运行状态。
- 地图角色随 MapGameScene 创建和销毁，长期进度只进入 GameRun。
- 当前正式切片用嵌入式 DialogueEvent，不为简单对白添加全局故事模块。
- 不建立 GameSession、GameFlow、通用动作数组或自制剧情 opcode。

## 原创素材

运行素材位于 `assets/original/`，不依赖第三方游戏提取资源。角色、Tile 与环境物件使用
Codex 内置 ImageGen 生成源图，再通过项目脚本确定性处理透明边、尺寸、色板和脚点。
生成提示与处理记录见 [原创素材说明](assets/original/README.md)。

## 文档

- [世界观与叙事原则](docs/worldbuilding.md)
- [需求与范围](docs/requirements.md)
- [运行时架构](docs/architecture.md)
- [内容创作接口](docs/content-authoring.md)
- [原创素材管线](docs/asset-pipeline.md)
- [开发路线](docs/roadmap.md)
- [视觉验收](docs/visual-acceptance.md)
- [开发代理约束](AGENTS.md)
