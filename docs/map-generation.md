# 程序化生态地图工具

## 1. 产品边界

地图生成器是编辑期编译工具，不是运行时随机世界系统。它根据带版本、seed 和类型化规则的
`MapGenerationProfile` 生成普通 `MapGameScene3D`，把结果烘焙到正式 `.tscn`；游戏进入地图时
只加载已经保存的 GridMap、环境节点、碰撞和导航，不读取 Profile，也不执行生成算法。

生成器负责：

- 海拔、湿度、肥力、灵气和人类干扰生态场；
- 道路连通、地表分类、低成本 Detail 模块、环境物件、边界碰撞和 NavigationMesh；
- 人工 spawn、portal、剧情空地、资源点和地标周围的保护区；
- 固定 seed 的确定性计划、指标、诊断和原子烘焙。

作者负责：

- 关键 NPC、建筑、Portal、StoryMarker 和 StoryBinding；
- 所有 persistent ID、剧情 trigger 和故事脚本；
- 选择 seed、确认构图，并在生成后完成叙事布置。

当前有三个正式 schema v2 Profile：

- `north_slope_wilds_3d_profile.tres` 生成默认进入的 `map.roadside.north_slope_wilds` `64 x 32`
  环境，保留默认出生点、通往小铺的 Portal 与四向人工路线端点。
- `herb_slope_3d_profile.tres` 生成 `map.roadside.herb_slope` 的 `32 x 16` 环境，保留两处出生点、
  回程 Portal、三处返青草、`story.roadside.gathering` trigger 和已有存档语义。
- `roadside_shop_3d_profile.tres` 生成 `map.roadside.shop` 的 `18 x 14` 环境，保留两处 spawn、
  店主、建筑与剧情交互。

## 2. 内容真相与所有权

提交的 `.tscn` 是运行时和代码审查使用的地图真相。Profile 是可以显式再次执行的编辑配方，
不登记到 ContentDatabase，不被运行时场景引用，也不会在打开地图或 CI 中自动重写场景。

生成器拥有：

- 3D Ground GridMap、Detail 模块和生成环境节点；
- 带 `metadata/map_generator_owned = true` 的节点；
- `NavigationRegion3D` 与 `GeneratedMapBoundary3D`；
- 根节点上的 generator version、seed、plan hash 和 Profile 路径字符串。

其他节点全部视为人工内容。烘焙只清理带所有权元数据的节点，不按名字、类型或 NodePath
猜测归属。生成节点禁止包含 `Interactable`，也不获得 persistent ID 或 StoryBinding。

环境物件直接成为 `WorldRoot` 子节点，固定 Camera3D 统一决定玩家、NPC、药草和人工物件的
空间遮挡。生成器不增加 Interactable 或剧情状态。

## 3. 类型化 Resource

### MapGenerationProfile

- schema version、seed、目标场景、逻辑矩形；
- `MapGenerationBiome`；
- 人工 `MapGenerationAnchor`；
- 四个生态场频率、道路宽度和最大环境节点数。

### MapGenerationBiome

- schema v2 的 terrain/detail `MapGenerationModule3D`；
- road/clearing 模块；
- 有序 `MapGenerationTerrainRule`；
- `MapGenerationDetailRule`；
- `MapGenerationPropRule`。

规则是有限、类型化的 Resource，不接受 Dictionary 命令、表达式字符串或自制 opcode。
3D 模块明确引用已经配置 Mesh/Material/碰撞的 PackedScene；Prop 通过 `scene` 引用环境模块，
并同时声明阻挡 footprint 和导航影响。

### MapGenerationAnchor

锚点可以使用目标场景 NodePath，也可以使用 fallback cell。种类包括 spawn、portal、剧情空地、
资源、地标和路线端点。每个锚点定义净空、是否必须可行走、是否接入道路、可选的四邻域
道路接入方向和是否受保护。

NodePath 只存在于编辑期 Profile，不进入 GameRun 或存档。正式剧情继续使用语义 ID 和
StoryOrigin，而不是引用生成节点。

## 4. 确定性生成阶段

1. 校验 Profile、Mesh 模块、规则、PackedScene、anchor ID、NodePath 和地图范围。
2. 从主 seed 与固定 salt 派生五个 FastNoiseLite 场。
3. 对要求连路的 anchor 生成确定性的最小连接关系，再用四邻域 A* 寻路。
4. 从道路距离推导人类干扰，按有序 terrain rule 分类每个 cell。
5. 按 terrain tag 放置 Detail Mesh 模块。
6. 按生态阈值、密度、最小间距和净空放置环境 PackedScene。
7. 扩张阻挡物的逻辑 footprint，拒绝任何与道路、保护区或既有阻挡重叠的候选。
8. 从道路网络做 flood fill，验证每个 gameplay anchor 可达。
9. 对有序 cell、terrain/detail tag 和 Prop DTO 计算 SHA-256 plan hash。

生成算法不使用全局随机数，不依赖 Dictionary 遍历顺序。相同 Godot、generator version、
Profile 和 seed 必须得到相同 plan hash。升级算法时提升 `GENERATOR_VERSION` 并显式重新验收。

## 5. 人类编辑器流程

启用的 `Content Tools` 插件同时提供独立 `Map Generator` Dock：

1. 打开 Profile 的 target scene。
2. 在 Dock 选择 `MapGenerationProfile`，输入或生成 seed。
3. 点击 `Preview`；工具通过 EditorUndoRedo 在当前场景显示结果，但不保存。
4. 检查 cell、道路、物件、habitat 指标与诊断。
5. 点击 `Undo Preview` 回到精确快照，或点击 `Bake`。
6. Bake 先保存人工修改，再写临时 `.tscn`、重新加载、完整验证并原子替换目标。
7. 完成人工 NPC、StoryMarker、StoryBinding 和演出布置；需要再次生成时先把关键节点登记为
   protected anchor。

Bake 失败时正式场景保持不变。工具不支持悄悄修正冲突约束；无法满足的规则必须通过
code/message/file/field/id 诊断暴露。

## 6. Headless CLI

```sh
godot --headless --path . -s res://tools/map_generator_cli.gd -- \
  plan res://game/roadside/map_generation/north_slope_wilds_3d_profile.tres --json

godot --headless --path . -s res://tools/map_generator_cli.gd -- \
  validate res://game/roadside/map_generation/north_slope_wilds_3d_profile.tres --json

godot --headless --path . -s res://tools/map_generator_cli.gd -- \
  bake res://game/roadside/map_generation/north_slope_wilds_3d_profile.tres --json
```

三条命令都支持可选 `--seed <int>`。稳定 JSON 包含 contract/generator version、命令、Profile、
目标场景、seed、plan hash、anchor cell、habitat/道路/物件指标和 diagnostics。成功返回 0，
生成或内容错误返回 1，命令用法错误返回 2。

`plan` 和 `validate` 不写文件。`bake` 只在计划、临时场景和 baked scene validator 全部成功后
替换目标，并在替换失败时恢复备份。

## 7. 测试与验收

自动测试固定覆盖：

- 同 seed 同 hash，不同 seed 不同 hash；
- `32 x 16` 共 512 个 ground cell，`64 x 32` 共 2048 个 ground cell；
- 多种 habitat、道路、Detail 模块和 Prop；
- 道路与所有 gameplay anchor 可达；
- 阻挡 footprint 不覆盖道路或保护区；
- 人工 NodePath、位置、trigger、Portal 和 persistent ID 在烘焙后不变；
- 临时烘焙可重新加载，非法计划不修改目标字节；
- 原创 GLB/prop 的 Mesh、Material、碰撞、单位与导入边界；
- 正式采药两趟、菜单和存档回归。

视觉验收使用 G6 十一张 `640 x 360` 截图，额外检查湿润林缘、碎石坡、松林、旧路、生成
碰撞、导航、锚点净空和 Camera 边界。Profile 调整后必须重新 bake、运行全部校验并重拍。

MVP 性能门槛：`32 x 16` 计划生成低于 500 ms，包含临时重载的 bake 低于 2 秒，单图生成的
独立环境 Node 不超过 120；纯地表细节优先合入 GridMap/批量模块。generator v3 的正式 hash
为：小铺 `da4f7f6d8fd0fe5a7bfa6587e6a84d472522a457081ddbeb87b419432cf03915`
（252 cell/10 prop），药草坡 `b430c6ce06cd716e64c9b97ff8a6e8d1ea1861ffedda14770cda8977b3e43fdd`
（512/30），北坡原野 `0c84f5e1050250c8b225c441ed59431cb3843f0d1e857bf867b94c4bb3ca6939`
（2048/92）。

## 8. MVP 之后

局部区域锁定、批量 seed 缩略图、生态热力图、局部重生成、动物槽位和粗粒度区域生态状态
均不属于当前工具。只有新内容证明需要时，才在 GameRun 增加可序列化生态状态；不能把
编辑期 Profile、Noise、Node 或 Texture 放入 GameRun。

## 9. 3D-only 边界

地图生成 schema 固定为 v2、generator 当前为 v3，只输出 `MapGameScene3D`。旧 schema v1、
TileMap baker、2D Profile 和 atlas tile DTO 已移除；新增 Profile 不再配置 `target_mode`。

Profile 使用 `map_origin/map_size` 表达逻辑格，使用 `cell_size_3d/world_origin_3d` 把格中心
确定性映射到 `WorldRoot` 的 XZ 平面。Biome 的 `terrain_modules/detail_modules` 以有限 Mesh
模块表达地表与细节；大型 Prop 通过 PropRule 的 `scene` 独立实例化。terrain module 必须含
Mesh 与碰撞，blocking Prop 必须含 Mesh 与碰撞；非阻挡 Prop 的物理层在 bake 时关闭，避免
表现、物理和逻辑导航互相矛盾。

3D bake 只拥有带 `map_generator_owned` 元数据的地面、道路、Detail、环境节点、碰撞、导航区域
和生成边界，不改写人工 NPC、spawn、Portal、StoryBinding、persistent ID 或剧情资源。临时场景
重载、完整验证、原子替换和失败回滚契约保持不变；generator version 与 golden plan hash 必须
显式提升，不能让运行时执行生成器。固定 G5 fixture 与验收结果见
`docs/baselines/3d-map-generation-g5.md`。
