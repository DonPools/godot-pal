# 开发路线

## 当前基线

当前正式基线是固定正交视角 3D 的“北坡采药 + 阵灯筑基”纵向切片：

```text
标题页
  -> map.roadside.north_slope_wilds（64 x 32 固定 seed 生态原野）
     -> 小铺 / 药草坡：两趟采药、路线与留根结果
     -> 北坡兽径：三敌即时战斗基线
     -> 阵灯隘口：4 / 8 / 9 / 4 / Boss / 12 固定遭遇
        -> 选择回风剑匣或镇岳剑印
        -> 引食炁岩兽撞上一次性阵柱
        -> 修复公共阵灯或拆取阵芯剑符
        -> 选择锐金或流泉道基，完成筑基回测
  -> 菜单、装备、设置和三槽 v5 存读档
```

正式运行时保留 GameRoot、GameSceneStack、GameRun、ContentDatabase、StoryEvent/StoryModule、
地图内 BattleSession、菜单、商店、存档、设置、Dock 与稳定 JSON CLI。当前内容登记两个境界、
两个道基、一个角色、两个 NPC、六件物品/法器、三项技能、一种状态、六种敌人、七个遭遇、
五张地图与三个 StoryModule。

## 已完成

### R0：通用运行时

- `640 x 360` 根 Viewport、默认严格 2 倍窗口、2 倍/3 倍/全屏设置与 F11 往返。
- GameRoot、GameSceneStack、Overlay、Audio/Save/Settings 服务与三槽存档。
- GameRun、队伍、背包、经济、故事、标记、世界实体、位置和随机状态。
- 类型化 StoryContext、常用 StoryEvent、StoryModule 与内容 CLI。

### R1：原创内容与创作基线

- 建立原创旅人、店主、返青草、小铺和北坡日常方向。
- Actor/Npc/Item/Map/Dialogue/Story 使用语义 ID 与独立 Resource。
- Content Database Dock、Dialogue Editor、反向引用、JSON 导出/应用与 ID 迁移。
- 移除运行时对第三方提取资源、manifest、source ID 与旧验证地图的依赖。

### R2：山路采集闭环

- 三处稳定药草来源、安全/近路、时段、留根/连根与原子交付。
- 第二趟恢复留根药丛并保持连根来源消失，不使用善恶值。
- FakeStoryContext、真实场景、菜单和存档往返测试。

### R3：程序化生态地图 MVP

- 编辑期 Profile/Biome/Anchor、确定性 plan、A* 道路与生态规则。
- `plan/validate/bake` CLI、Preview/Undo、临时场景校验和原子替换。
- 药草坡 `32 x 16` 与北坡原野 `64 x 32` 正式 baked 3D 地图。
- 固定 seed hash、anchor 可达、人工节点保留、碰撞/导航和失败不写入测试。

### R4：固定视角 3D 即时战斗基础

- 移动/瞄准分离、普攻、技能、闪避、物品、近战/远程敌人和三种 outcome。
- BattleSession `1/60` 固定步、动作阶段、投射物、状态、奖励策略与幂等提交。
- MapGameScene 拥有唯一 BattleSession；StoryContext 直接 await 当前地图。
- `save_version = 4` 引入 Vector3，旧二维精确位置回退语义 spawn。

### R5：3D 素材与地图生产

- 确定性 GLB 管线、共享 13 骨骼、六组动画、武器、敌人和环境模块。
- 北坡兽径正式三敌闭环、原创音频与七张 G4 战斗截图。
- schema v2 GridMap、环境 Prop、NavigationMesh 与 3D-only 地图生成器。

### R6：正式 3D 基线

- 小铺、药草坡、北坡原野全部切换到正式 3D，默认入口与两趟采药通过真实 GameRoot。
- NpcDefinition 模型注入、标题 3D 派生头像与正式素材清单。
- 清理旧 2D/回合战斗桥；G6 十一张截图固定标题、三图、选项与药草四态。

### R7：阵灯筑基（完成）

- Realm/Foundation 进入 ContentDatabase、catalog、schema、create、refs、rename-id 与 JSON 往返；
  ActorState 保存境界、层数、修为和道基，`save_version = 5` 迁移旧等级/经验。
- 新游戏从炼气七层开始；修为逐层推进并在炼气九层圆满封顶，突破事务原子消耗食炁岩心，
  进入筑基一层、授予归元剑阵并补满派生 HP/MP。
- 普攻命中回气、第三技能、回风剑匣折返穿透、镇岳剑印群攻回气、锐金三击剑波与流泉技能周流
  均通过 BattleBuildSnapshot 和有限类型化 modifier 实现。
- 菜单显示境界/修为/派生属性并使用 EquipmentTransaction 原子换装。
- `map.roadside.lantern_pass`、守灯人、三种小兽、食炁岩兽、六个固定遭遇和完整 LanternPassStory
  接入北坡原野；法器、Boss 催化物、修复/拆取、筑基与最终回测均有持久来源和分支测试。
- Boss 冲撞在固定步中可重放；地图只提交接触候选，BattleSession 校验 action instance、一次性阵柱
  与 1.6 秒失衡。长条预警、损坏阵柱和“破阵·失衡”反馈在固定镜头内可辨。
- 修复阵灯开放持久捷径并点亮区域；拆取发放阵芯剑符并保持昏暗。选择不写善恶值，回访和读档
  恢复路线、灯光、来源与守灯人对白。
- 食炁兽、Boss、阵柱亮/损态、阵芯和筑基坛进入确定性 GLB v2 manifest；蓄势、撞柱、修复、
  拆取和筑基音效可确定性重建。
- R7 十张真实 Metal 截图覆盖探索、群怪、精英法器、冲撞、失衡、阵灯两态、两种道基和十二怪回测。

证据见 `docs/baselines/r7-lantern-foundation.md` 与 `docs/visual-acceptance.md`。

### R8：成品体验改造（完成）

- 键鼠改为真实地表/敌人/互动碰撞拾取，NavigationServer 吸附落点；不可达、卡死、互动和目标
  分别使用世界阵纹与 HUD 短反馈。Tab/R3 通过方向锥、距离和遮挡循环目标。
- 19 个动作支持键盘、鼠标、手柄按钮/摇杆轴独立重绑；移动/瞄准死区、灵敏度、对话速度和
  减少闪烁进入 SettingsService v3 持久化。
- CombatFeedback3D 提供局部命中停顿、受击闪白/红、剑弧、火花与闪避残影；近战范围和远程/
  冲撞方向使用世界前摇。辅助模式保留动作信息但关闭闪白并缩短停顿。
- HUD 收敛为左下体力/真气、底部六格动作栏、顶部目标/首领血条与右上任务卡；键鼠和手柄只显示
  当前设备提示，拒绝原因不再依赖玩家猜测。
- 标题页改为旅人氛围区与纵向主菜单；对话采用可调逐字显示、补全/推进两段输入；设置页加入完整
  输入和辅助功能入口。
- 角色、敌人、晶簇、环境色板、轮廓和灯光完成第一轮统一；固定镜头加入目标构图偏置与树木/屋檐
  遮挡淡出，阵灯长路补齐人工环境节奏和原创木牌。
- G4 增至八张战斗截图，UI 基线增至六张；自动测试覆盖物理导航、目标切换、反馈、遮挡恢复、
  多设备绑定、辅助功能和对话补全。

完整范围、取舍和验收门见 `docs/r8-finished-experience-plan.md`。

## 下一决策门

R8 基线完成后，用当前切片回答两个问题：玩家是否愿意围绕真气循环持续调整法器/道基，以及
持久地方结果是否值得回访。只有玩家测试证据支持时，才从下列方向选择一个短切片：

- 扩展一个新境界与对应世界门槛；或
- 增加一张能让阵灯结果产生后续路线差异的地图。

下一阶段仍不默认加入随机词缀、无限刷怪、装备品质、队友 AI、赛季系统、全局天气或通用 Boss 阶段编辑器。

## 持续原则

- 新系统必须由一个玩家可见内容闭环证明需要。
- `.tscn`、`.tres` 和类型化 GDScript 是内容真相。
- 存档只保存语义 ID 与运行状态，不保存 Node、Resource 路径或活动战斗。
- 简单内容使用内嵌 StoryEvent，复杂多阶段叙事使用单一职责 StoryModule。
- 原创素材保持生成源、确定性脚本、manifest、导入边界和截图可追踪。
- 每次扩展同时更新内容校验、规则/剧情/场景测试、截图和文档。
