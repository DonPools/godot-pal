# 开发路线

## 当前基线

当前正式基线是固定正交视角 3D 切片“北坡采药”与地图内实时战斗：

```text
标题页
  -> map.roadside.north_slope_wilds（默认 64 x 32 生态原野）
  -> 沿人工 Portal 进入采药内容
  -> map.roadside.shop
  -> 接下采药差事，选择旧路或碎石近坡
  -> map.roadside.herb_slope
  -> 割叶留根或连根采走，按时段返回交付
  -> 第二趟观察再生或永久枯竭
  -> 菜单、设置和三槽存读档
```

项目保留已经验证的 GameRoot、GameSceneStack、GameRun、内容数据库、StoryEvent/
StoryModule、菜单、商店、实时战斗、存档、设置、Dock 与 CLI 等通用框架能力；当前正式内容
登记角色、NPC、物品、技能、状态、敌人、遭遇、四张地图和两个 StoryModule。

## 已完成

### R0：通用运行时

- `640 x 360` Viewport、默认 `1280 x 720` 严格 2 倍可缩放窗口、nearest 世界素材与原生高清 UI。
- GameRoot、GameSceneStack、Overlay 与服务所有权。
- GameRun、队伍、背包、金钱、故事、标记、世界实体和位置存档结构。
- 标题、菜单、设置、三槽存读档与键盘/手柄输入。
- 类型化 StoryContext、常用 StoryEvent、可选 StoryModule 与内容 CLI。

### R1：原创等距美术基线

- `64 x 32` 菱形 TileSet 与四种地表。
- 主角和店主 `48 x 64`、`3 x 4` 四斜向图集。
- 松树、双向围栏和小铺独立透明物件。
- 正式 `map.roadside.shop` 的 TileMap、碰撞、YSort、spawn 和 DialogueEvent。
- ImageGen 源图、确定性后处理脚本和视觉截图流程。
- 移除运行时对第三方提取资源、manifest 与 source ID 的依赖。

### R2：山路采集闭环

- `map.roadside.herb_slope`、三处稳定药草来源和往返 portal。
- DialogueOption 语义选择，以及留根一份/连根两份的明确采集结果。
- 安全旧路固定耗时；碎石近坡使用可注入、可随存档往返的种子随机源。
- 两份返青草与工钱的原子交付，按时十二文、迟到六文。
- 第二趟让留根药丛恢复、连根来源保持完成，并给出无显式善恶值的地方结果。
- FakeStoryContext 轨迹、场景 smoke test 和十三张视觉验收截图。

### R3：程序化生态地图 MVP

- 编辑期 MapGenerationProfile/Biome/Anchor 与确定性 GeneratedMapPlan。
- 海拔、湿度、肥力、灵气、人类干扰、A* 道路、terrain/detail/prop 规则和阻挡 footprint。
- 稳定 JSON 的 `plan/validate/bake` CLI、临时场景校验、原子替换与失败回滚。
- Map Generator Dock 的 seed、Preview、Undo Preview、Validate 和 Bake。
- 湿草、碎石、泥地、干草、六种 Detail Tile、两种松树、两种灌木、两种岩石和倒木原创素材。
- `map.roadside.herb_slope` 固定 seed 的 `32 x 16` baked 地图，保留人工 spawn、Portal、
  三处 persistent 药草和完整两趟 StoryModule。
- `map.roadside.north_slope_wilds` 固定 seed 的 `64 x 32` baked 地图作为新游戏默认入口，
  四向旧路、完整可达生态区域、95 个环境 Prop 和人工小铺 Portal 均通过验证。
- 自动测试覆盖确定性 hash、不同 seed、anchor 可达、人工节点保留、素材尺寸、透明边和失败不写入。

### R4：固定视角 3D 即时战斗基础

- G0 记录 2D 性能、截图与存档基准，并选定固定正交镜头。
- G1 独立灰盒验证键鼠/手柄、普攻、技能、闪避、近远敌人、压力与三种 outcome，方向选择原生 3D。
- G2 将 BattleSession 迁为 `1/60` 固定步实时规则，并覆盖动作、冷却、闪避、投射物、状态、
  多敌人、奖励策略和幂等提交。
- MapGameScene 拥有唯一 BattleSession；StoryContext/StoryDirector 直接 await 地图内结果，
  普通战斗不再 push BattleGameScene。
- Skill/Enemy/Status/Encounter schema、validator 与 CLI 支持实时字段和 3D 场景根检查。
- `save_version = 4` 使用 Vector3；v2/v3 精确二维位置回退语义 spawn，战斗中保存稳定拒绝。

证据见 `docs/baselines/3d-action-combat-g1.md` 与 `docs/3d-action-combat-plan.md`。

### R5：3D 素材与地图生产

- G3 建立确定性 GLB 管线、共享 13 骨骼、六组动画、第二人形变体、敌人、武器与环境模块，
  实际工时证明第二变体与模块复用明显低于首件成本。
- G4 以 `map.roadside.north_slope_pack`、有限敌群、两技能、消耗品、状态、三种 outcome、
  原创音频、CLI 与固定截图形成第一个正式 3D 内容闭环。
- G5 让 schema/generator v2 输出 GridMap 地表、道路、Detail、独立环境 Prop、碰撞、
  NavigationMesh 与边界；Preview/Undo、人工节点保留和失败回滚均有固定测试。

### R6：正式 3D 基线

- 小铺、药草坡、北坡原野按顺序完成 3D 烘焙并保持 Map/story/trigger/persistent/spawn ID。
- 新游戏默认入口与三张 MapDefinition 切换到 3D；完整两趟采药、菜单与 v4 存档通过真实 GameRoot 测试。
- NpcDefinition/NpcCharacter3D、角色 definition 模型注入、标题 3D 派生头像与正式素材清单完成。
- 移除 BattleGameScene 回合桥、Command/execute/rounds 和 G1 原型；2D generator 仅保留显式 legacy fixture。
- G6 截图覆盖标题、三张地图、对话/选项与药草四态；G4 七张战斗图继续作为战斗视觉基准。

详细证据见 `docs/baselines/3d-content-migration-g6.md`。

## 下一阶段

在固定视角 3D 与实时战斗基线之上增加新的玩家可见内容；优先验证一场具有独特地形机制的
Boss 或一段结合探索与战斗后果的剧情，不先扩展随机词缀、无限刷怪和大型装备系统。

## 持续原则

- 新系统必须由一个玩家可见内容闭环证明需要。
- `.tscn`、`.tres` 和类型化 GDScript 是内容真相。
- 内容使用语义 ID，不保存资源路径或 Node 引用到 GameRun。
- 简单内容使用内嵌 StoryEvent，复杂多阶段叙事才增加 StoryModule。
- 原创素材保持提示、源图、后处理和运行图可追踪。
- 每次扩展同时更新内容校验、场景测试、截图和文档。
