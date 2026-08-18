# 原创素材管线

## 1. 边界

项目只使用 `assets/original/` 下的原创素材。当前正式切片使用固定视角 3D 的模型、纹理、
材质、动画与原创音频；全部生成源和派生文件位于同一原创边界。运行时不读取第三方游戏数据、
外部素材 manifest、source chunk 或旧 `generated/` 输出。

单向流程：

```text
原创设计约束 -> 确定性几何/骨骼/动画生成 -> GLB + manifest -> Godot Import -> wrapper .tscn
```

## 2. 旧 2D 生成记录

旧 2D 基线的主角和 NPC 采用严格 `3 x 4` 图集：每帧 `48 x 64`，每行左步、站立、右步。
这些源图、后处理脚本与 baseline 文档作为迁移证据保留，不进入正式 ContentDatabase、
AssetLibrary、标题或普通 CI 的运行素材集合。

四行依次为：

- `south`：屏幕左下。
- `west`：屏幕左上。
- `north`：屏幕右上。
- `east`：屏幕右下。

`tools/process_isometric_spritesheet.py` 逐格提取主体，移除洋红背景，统一缩放与脚底基线，
再量化为有限色板。

## 3. 旧 2D 地表记录

地表生成源图只提供材质与配色。`tools/process_isometric_environment.py` 丢弃样品菱形的展示
暗边并从材质内部取样，先用 BOX 低通缩小，再以无抖动色板量化、透明 RGB 扩边和逐行
离散遮罩重建严格、无缝的 `64 x 32` alpha 菱形，输出 `256 x 32` 的四格图集：草、旧石路、
硬土与垄田。

松树、双向围栏、小铺和药草拆成独立透明 PNG，保留统一底部中心脚点。药草的完整与
割后状态使用相同地图原点，由 `game/roadside/tools/process_herb_patch.py` 从同一源图确定性提取。
旧 TileMap、碰撞、YSort、spawn、NPC 与互动由 Godot `.tscn` 维护，不使用整张 AI 场景
插画替代地图结构。

程序生成北坡使用另一组同规格原创源表：`north_slope_ground_source.png` 提供湿草、碎石、
泥地、干草和六种地面细节；`north_slope_ecology_source.png` 提供幼松、成松、两种灌木、
两种岩石和倒木。`game/roadside/tools/process_north_slope_ecology.py` 确定性输出：

- `north_slope_ground_8x1.png`：保留原四种地表并增加四种生态地表；
- `north_slope_details_6x1.png`：严格 `64 x 32` 透明 Detail atlas；
- `assets/original/props/ecology/`：固定画布、透明边和底部中心脚点的七种环境物件。

每个需要碰撞的运行图由独立 PackedScene 配置根部碰撞。Biome Resource 只引用这些
PackedScene 和 TileSet，不从源表直接裁图，也不在运行时生成 Texture。

## 4. Godot 导入

- GLB 使用米、+Y 向上、-Z 前向和脚底原点；wrapper scene 保持单位缩放。
- 角色必须具有统一 13 骨骼和 idle/run/attack/cast/hit/death 六组动画。
- 固定摄影机使用 yaw 45 度、elevation 35.264 度和 orthographic size 12。
- 小尺寸纹理使用无损导入；UI 中文使用原生矢量字体。
- `AssetLibrary` 只检查正式切片所需原创素材是否存在。

## 5. 生成记录

具体源图、最终提示、输出文件和处理方式见 `assets/original/README.md`。项目内同时保留生成
源图、严格运行图和最近邻放大预览，方便重新处理与人工验收。

## 6. 验证

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
godot --path . -s res://game/presentation/action_combat_3d/tools/capture_g3_assets.gd
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_g6_formal_slice.gd
```

人工检查角色共享动画、模型脚点、材质、碰撞、固定镜头遮挡和 `640 x 360` 构图。
程序生成地图还要检查 fixed seed plan hash、habitat 分布、人工 anchor 净空、碰撞与导航；
详见 `docs/map-generation.md`。

## 7. 固定视角 3D 正式管线

G3 建立的以下目录已经成为正式运行素材管线：

```text
assets/original/3d/
├── sources/       DCC 源文件与版本说明
├── models/        Godot 运行时导入的 GLB
├── textures/      小尺寸无损纹理
├── materials/     可复用 StandardMaterial3D Resource
└── animations/    共享动画库或可追踪导出
```

- 世界单位使用米，标准人形高度、脚底原点、+Y 向上和面向约定写入素材记录。
- 一个基础人形提供统一骨骼、武器挂点及 idle/run/attack/cast/hit/death 六组动画；第二个变体
  必须证明至少四组动画可重定向复用。
- 环境先制作地面、道路、岩石、松树、灌木、围栏和小型建筑最小模块；固定镜头不可见细节
  不进入预算，同一模块优先通过旋转、尺度和材质变体复用。
- 运行时只引用 GLB、Texture2D、Material 和 PackedScene，不直接引用 DCC 缓存；每项素材记录
  工具版本、单位、轴向、骨骼、导出设置、输出路径、制作工时和许可边界。
- validator 必须检查根节点、Mesh/Material/Texture/Skeleton、必需动画、缩放与外部纹理路径。
- G3 以基础人形、第二变体、一个敌人、一件武器和七类环境模块的实际工时证明了共享骨骼、
  动画与环境模块的复用收益；详细数据见 `docs/baselines/3d-asset-production-g3.md`。
- `fanqing_grass.glb`、`fanqing_grass_cut.glb` 与标题透明头像同样由仓库脚本确定性重建。
