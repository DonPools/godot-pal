# 原创素材包

本目录存放原创项目素材，不依赖《仙剑奇侠传》或 Rust-PAL 的输入与派生资源。只有被
ContentDatabase、正式场景或 AssetLibrary 引用的运行图才属于当前可玩内容；早期方向稿
保留生成来源，但不得作为整张运行时地图或隐式内容依赖。

## 生成记录

`maps/yuwan_source.png` 与 `maps/north_slope_source.png` 于 2026-08-13 使用 Codex 内置
ImageGen 生成，随后在项目内以最近邻算法缩放出两张构图验证图：

- `maps/yuwan.png`
- `maps/north_slope.png`

生成提示分别要求原创、固定等距视角、克制的东方修仙日常环境、不含角色、文字、UI、商标、水印或任何既有游戏的可识别素材。

这些图片是早期方向稿，不被当前 ContentDatabase 或正式场景引用，也不得作为整张运行时
地图。当前地图必须由严格菱形 Tile、独立环境精灵和 Godot `.tscn` 中的碰撞、出生点、
NPC 与交互物组成。同批早期角色与头像方向稿同样只保留作原创设计记录。

### 主角四方向精灵

`characters/traveler_walk_3x4_source.png` 于 2026-08-13 使用 Codex 内置 ImageGen 生成，参考此前的普通旅人造型，要求严格输出 `3 x 4` 网格：南、西、北、东四行，每行左步、站立、右步三帧。

生成图先移除纯洋红背景，再逐格保留最大连通主体，统一缩放、脚底对齐并量化为有限色板，最终得到：

- `characters/traveler_walk_3x4.png`：运行时 `72 x 128` spritesheet，单帧 `24 x 32`。
- `characters/traveler_walk_3x4_preview.png`：最近邻放大的静态检查图。
- `characters/traveler_walk_3x4_animation.gif`：四个方向并排的步态检查图。

运行时按“站立、左步、站立、右步”播放每一行；停止移动时固定在站立帧。

### 斜 45 度美术垂直切片

`characters/traveler_isometric_walk_3x4_source.png` 与
`characters/shopkeeper_isometric_walk_3x4_source.png` 于 2026-08-13 使用 Codex
内置 ImageGen 生成。两者都要求原创、固定 `2:1` 等距视角、四行三分之四斜向，
每行左步、站立、右步，并使用纯洋红背景。随后由
`tools/process_isometric_spritesheet.py` 逐格移除色键、统一缩放与脚底基线、量化色板，
生成严格 `72 x 128` 的运行图：

- `characters/traveler_isometric_walk_3x4.png`
- `characters/shopkeeper_isometric_walk_3x4.png`

四行运行语义为：`south` 屏幕左下、`west` 屏幕左上、`north` 屏幕右上、
`east` 屏幕右下。

`tiles/isometric_ground_source.png` 与 `props/isometric_environment_source.png`
同日使用 Codex 内置 ImageGen 生成。最终提示要求原创、克制的乡野修仙日常、固定
`2:1` 等距视角、同一像素密度、纯洋红背景，且不含人物、文字、UI、商标、水印或
任何既有游戏的可识别素材；物件源图只包含松树、两个方向的短围栏和一间朴素小铺。

`tools/process_isometric_environment.py` 使用确定性流程移除洋红背景和色溢、提取最大
连通主体、最近邻缩放、统一脚点并量化色板。地表几何不直接采用生成图轮廓，而是重建
为严格的 `32 x 16` alpha 菱形，输出：

- `tiles/isometric_ground_4x1.png`：`128 x 16` 图集，依次为草、旧石路、硬土、垄田。
- `props/pine_tree.png`
- `props/fence_down_right.png`
- `props/fence_down_left.png`
- `props/roadside_shop.png`

`scenes/visual/isometric_art_test.tscn` 是独立美术验证场景，不登记到正式内容数据库，也
不替换主游戏入口。TileMap、碰撞、NPC、环境物件和 YSort 关系仍由 Godot Scene 维护。

### 北坡返青草

`plants/fanqing_grass_source.png` 于 2026-08-14 使用 Codex 内置 ImageGen 生成。最终提示为：

```text
Use case: stylized-concept
Asset type: source sheet for two 2:1 isometric pixel-art game props
Primary request: create exactly two isolated states of the same original fictional mountain herb called fanqing grass: one healthy rooted clump with five narrow blue-green leaves and tiny pale buds; one freshly harvested rooted clump with short cut stems and the root still visibly left in the soil
Scene/backdrop: flat solid chroma-key magenta background, exact color #FF00FF
Subject: two herb states only, separated widely, same ground footprint and same viewing angle
Style/medium: restrained late-1990s East Asian PC RPG pixel art, crisp hard pixel edges, limited earthy palette, 2:1 isometric three-quarter view, compatible with 32 x 16 diamond ground tiles
Composition/framing: square source canvas; full herb on the left, cut rooted herb on the right; both centered vertically with generous empty magenta space around every edge; no overlap
Lighting/mood: neutral soft daylight, subtle grounded contact shadow contained directly beneath each herb
Constraints: original design only; exactly two objects; no people; no pots; no loose harvested bundle; no scenery; no text; no symbols; no border; no watermark; no antialiased magenta spill; strong readable silhouettes at 16 x 20 pixels after nearest-neighbor downscaling
Avoid: photorealism, painterly blur, excessive detail, perspective mismatch, green background, transparent checkerboard
```

`tools/process_herb_patch.py` 以左右两格切分源图，分别保留最大连通主体、移除洋红色键与
色溢、最近邻缩放、量化为 24 色并对齐底部中心脚点，输出：

- `plants/fanqing_grass.png`：完整植株，`24 x 32`。
- `plants/fanqing_grass_cut.png`：割叶留根状态，`24 x 16`。
- 两张 `_preview.png`：六倍最近邻人工检查图。

连根采走不需要第三张空地贴图；StoryOrigin 完成态直接隐藏并禁用对应地图来源。第二趟
开始时，留根来源重新显示完整植株，连根来源继续由 WorldState 保持完成。
