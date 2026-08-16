# 原创素材管线

## 1. 边界

项目只使用 `assets/original/` 下的原创位图素材。运行时不读取第三方游戏数据、外部素材
manifest、source chunk 或旧 `generated/` 输出。

单向流程：

```text
原创设计约束 -> ImageGen 纯色背景源图 -> 确定性后处理 -> assets/original/ -> Godot Import
```

## 2. 角色

主角和 NPC 采用严格 `3 x 4` 图集：每帧 `24 x 32`，每行左步、站立、右步，运行时
播放站立、左步、站立、右步。

四行依次为：

- `south`：屏幕左下。
- `west`：屏幕左上。
- `north`：屏幕右上。
- `east`：屏幕右下。

`tools/process_isometric_spritesheet.py` 逐格提取主体，移除洋红背景，统一缩放与脚底基线，
再量化为有限色板。

## 3. 地表与环境物件

地表生成源图只提供材质与配色。`tools/process_isometric_environment.py` 重建严格的
`32 x 16` alpha 菱形，输出 `128 x 16` 的四格图集：草、旧石路、硬土与垄田。

松树、双向围栏、小铺和药草拆成独立透明 PNG，保留统一底部中心脚点。药草的完整与
割后状态使用相同地图原点，由 `game/roadside/tools/process_herb_patch.py` 从同一源图确定性提取。
TileMap、碰撞、YSort、spawn、NPC 与互动始终由 Godot `.tscn` 维护，不使用整张 AI 场景
插画替代地图结构。

程序生成北坡使用另一组同规格原创源表：`north_slope_ground_source.png` 提供湿草、碎石、
泥地、干草和六种地面细节；`north_slope_ecology_source.png` 提供幼松、成松、两种灌木、
两种岩石和倒木。`game/roadside/tools/process_north_slope_ecology.py` 确定性输出：

- `north_slope_ground_8x1.png`：保留原四种地表并增加四种生态地表；
- `north_slope_details_6x1.png`：严格 `32 x 16` 透明 Detail atlas；
- `assets/original/props/ecology/`：固定画布、透明边和底部中心脚点的七种环境物件。

每个需要碰撞的运行图由独立 PackedScene 配置根部碰撞。Biome Resource 只引用这些
PackedScene 和 TileSet，不从源表直接裁图，也不在运行时生成 Texture。

## 4. Godot 导入

- 项目全局使用 nearest texture filter。
- PNG 使用无损导入，不生成 MipMap。
- 运行图保持整数尺寸，不在场景中做非整数缩放。
- `AssetLibrary` 只检查正式切片所需原创素材是否存在。

## 5. 生成记录

具体源图、最终提示、输出文件和处理方式见 `assets/original/README.md`。项目内同时保留生成
源图、严格运行图和最近邻放大预览，方便重新处理与人工验收。

## 6. 验证

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
godot --path . -s res://game/roadside/tools/capture_isometric_art_test.gd
```

人工检查角色四斜向、Tile 接缝、透明边、碰撞、树前后遮挡和 `320 x 180` 构图。
程序生成地图还要检查 fixed seed plan hash、habitat 分布、人工 anchor 净空和生成 Prop 的
同层 YSort；详见 `docs/map-generation.md`。
