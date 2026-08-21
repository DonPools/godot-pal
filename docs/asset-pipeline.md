# 原创素材管线

## 1. 边界

正式内容只使用 `assets/original/3d/`、`assets/original/audio/` 与 `assets/original/ui/`。仓库不保存或读取第三方游戏
提取数据、外部素材 manifest、source chunk、旧 2D 图集或 `generated/` 派生输出。

```text
原创设计约束 -> 确定性模型/骨骼/动画或音频生成 -> manifest/说明 -> Godot Import -> wrapper .tscn
```

## 2. 3D 生产契约

- GLB 使用米、+Y 向上、-Z 前向和脚底原点；wrapper scene 保持单位缩放。
- 角色使用统一 13 骨骼以及 idle/run/attack/cast/hit/death 六组动画。
- 基础人形提供武器挂点；变体和敌人优先复用骨骼与动画轨道。
- 环境以地面、道路、岩石、松树、灌木、围栏、药草和小型建筑模块组合。
- 固定镜头不可见细节不进入预算；同一模块优先通过旋转、尺度和材质变体复用。
- 小尺寸纹理使用无损导入；UI 中文使用原生矢量字体。
- 动作与光标图标使用仓库内原创 SVG，在 `640 x 360` 根 Viewport 中由 TextureRect 原生缩放；
  不把目标帧或整张插画作为运行时 UI。
- 运行时只引用 GLB、Texture2D、Material、PackedScene 与 AudioStream，不引用生成器临时缓存。

地图结构仍由 `.tscn` 表达。GridMap、碰撞、导航、NPC、spawn、Portal、StoryBinding 和
persistent ID 不写入模型文件，也不由运行时素材加载器推断。

## 3. 可重建源与 manifest

`assets/original/3d/sources/generate_lowpoly_assets.py` 生成正式低模集合；
`assets/original/3d/manifest.json` 当前由 generator v5 记录 24 个输出的路径、SHA-256、尺寸、三角面、骨骼、动画、材质、
纹理、单位与轴向。`render_title_portrait.gd` 从正式旅人模型渲染标题透明头像。

generator v5 为所有人形动画写入放松手臂基线，并为四种食炁兽使用独立的较亮石色与多面体
身体/头部轮廓，保证暗色隘口中不闪回绑定姿势且敌人剪影可读。

`assets/original/audio/sources/generate_action_combat_audio.py` 生成地图、战斗、攻击、施法、
闪避、三种 outcome、冲撞/失衡、阵灯两种处理与筑基音频。具体命令和文件说明见 `assets/original/README.md`、
`assets/original/3d/README.md` 与 `assets/original/audio/README.md`。

每次重建必须同时校验：

- manifest 中的哈希、资源数量和模型预算；
- Node3D/Mesh/Material/Texture/Skeleton 与六组必需动画；
- 阻挡环境模块的 CollisionShape3D；
- 正式资源不存在外部路径或缺失导入；
- 角色脚点、武器挂点、动作轮廓和固定镜头遮挡。

## 4. Godot 组合

`ActorDefinition.field_model_3d` 与 `NpcDefinition.field_model_3d` 指向可复用角色模型；敌人通过
`EnemyDefinition.character_scene` 指向包含规则表现组件的 CharacterBody3D wrapper。环境模型
由 `game/presentation/action_combat_3d/environment/` 的 PackedScene 配置碰撞和生成器用途。

`AssetLibrary` 只检查正式切片启动必需素材，完整结构与质量由
`original_3d_asset_validator.gd`、内容校验、地图校验和截图验收共同覆盖。

## 5. 验证

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
./tools/run_tests.sh
godot --path . -s res://game/presentation/action_combat_3d/tools/capture_g3_assets.gd
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_g6_formal_slice.gd
```

人工检查共享动画、模型脚点、材质、碰撞、固定镜头遮挡和 `640 x 360` 构图。程序生成地图
还要检查 fixed seed plan hash、生态分布、人工 anchor 净空、碰撞与导航；详见
`docs/map-generation.md`。素材成本与复用证据见 `docs/baselines/3d-asset-production-g3.md`。
