# 需求与范围

## 1. 产品定位

Godot PAL 是一个面向学习和内容创作的传统单机 RPG 框架。《仙剑奇侠传》一代的本地提取素材是首个真实素材验证对象：第一版把现有 Tile、角色、头像、UI、字体和音频重新组合成两张原创地图和短故事《借来的伞》，以验证 Godot 架构，不以复刻原版地图或完成整部游戏为首版目标。

首个验证片段追求玩家可见内容形成完整闭环，但项目不是原程序兼容工程：

- 不读取原版 opcode、剧情脚本、事件入口或存档。
- `map.lab.inn_hall`、`map.lab.rain_courtyard` 和 `story.lab.borrowed_umbrella` 由 Godot Scene、Resource 和 GDScript 原创建立。
- 后续是否扩展到更多原作场景按框架验证需要决定，不以原作剧情覆盖率作为当前完成度。
- `framework-lab` 离线转换后的 `generated/` 图片、Tile、字体和音频作为工程、地图编辑与普通 CI 的必需资源随仓库维护。
- 原版输入数据和原版存档不进入仓库；维护者在提交或分发派生资源前负责确认相应权利。

## 2. 核心目标

### 可玩与可验证

每个里程碑围绕当前内容片段交付端到端可运行体验，不先建设彼此没有连接的大型子系统。第一版以《借来的伞》验证两地图探索、跨地图剧情、持久状态和素材映射；商店、战斗和角色成长等能力在实际选取对应内容时再进入验收。

### 可创作

设计师能够方便地创建和修改：

- 主角和队员。
- NPC 和地图交互物。
- 物品、装备和商店。
- 法术、状态和效果。
- 怪物、敌人 AI 和战斗遭遇。
- 对话和复杂剧情。
- 地图与出生点。

### 对人类和 AI 友好

- 人类设计师首期通过 Godot Inspector 和场景编辑器工作，内容规模需要时再增加数据库 Dock。
- AI Agent 当前通过文本文件、稳定 JSON 的 `validate/list/show/schema/create` 和自动测试工作；高级引用查询随后按内容规模增加。
- 两者操作同一套内容模型，不维护互相漂移的两份数据库。

### 原版素材与内容解耦

玩法 Resource 使用语义化 ID，不把原版素材编号当作玩法内容 ID；source ID 只负责追踪和重导出。《借来的伞》的本地素材验收绑定提取素材，Godot 内容和规则仍不依赖 MKF、Rust 运行时或原版文件路径。

## 3. 用户类型

### 玩家

在桌面端使用键盘体验传统像素 RPG 的探索、剧情、菜单和战斗。

### 人类设计师

在 Godot 编辑器中搭建地图、放置 NPC、配置内嵌 StoryBinding，并以一个 StoryModule 编写一项完整叙事职责，使用验证面板检查错误。

### AI Agent

在不依赖可视化编辑器的情况下创建、查询、修改和验证内容；运行无窗口测试；得到稳定 JSON 和具体文件/字段诊断。

### 系统程序开发者

维护运行时、内容 schema、Godot EditorPlugin、素材导出器和公共 StoryContext API。

## 4. 功能需求

本章描述框架的目标能力集合。当前已由《借来的伞》《雨夜药房》《断桥伏击》分别验证地图剧情、非战斗 RPG 事务和剧情战斗。

### 4.1 工程与画面

- Godot 4.8 和带静态类型的 GDScript。
- `320 x 200` 内部画面，最近邻整数缩放并保持比例。
- 首期通过 Godot 根 Viewport 和 stretch 设置实现，不增加自定义 SubViewport。
- 桌面端和键盘作为首期平台。
- 工程要求存在有效的 `framework-lab` 素材包；地图场景的 TileSet 直接引用其中的 atlas，manifest 或必需输出缺失视为配置错误。
- 使用 TileMapLayer、CharacterBody2D、Area2D、YSort、AnimationPlayer、Tween 和 Control。

### 4.2 GameScene 流程

- 标题、地图、菜单、商店、战斗和存档页使用独立 GameScene。
- GameSceneStack 支持 `push/pop/replace/reset`。
- `push` 后暂停底层场景，`pop` 时恢复并返回类型化结果。
- 地图切换使用 `replace`，标题或新游戏使用 `reset`。
- Dialogue、确认框和通知使用 Overlay 模态 UI。
- 活动场景和模态 UI 之间不会重复消费输入。

### 4.3 GameRun

- 保存队伍、角色状态、有序背包、金钱、StoryState、简单标记、世界对象状态和当前位置。
- 不保存 Node、Texture、Camera、活动菜单或 Battle Scene 引用。
- 支持新游戏默认值、存档序列化、加载验证和版本迁移。
- 加载失败时保持当前 GameRun 不变。

### 4.4 内容数据库

- Actor、Item、Skill、Enemy、Status、Npc、Shop、BattleEncounter、Dialogue 和 Map 使用 Resource。
- 每条定义包含唯一语义化 ID。
- ContentDatabase 支持按类型和 ID 查询。
- 工具能够检查重复 ID、缺失引用、非法数值、错误类型和循环依赖。
- 首期使用简单、显式的 ContentDatabase Resource；内容增加后再引入自动 catalog。
- 存档保存 ID，静态内容可以使用类型化 Resource 引用。
- StoryModule 和故事私有 Dialogue 不强制登记到手写 ContentDatabase，由 story/map validator 扫描其目录和地图引用。

### 4.5 玩家与探索

- MapGameScene 根据 GameRun 当前队长创建 PlayerCharacter。
- PlayerCharacter 使用 CharacterBody2D、碰撞形状、动画和交互检测。
- PlayerController 可以在剧情、菜单和场景暂停期间禁用。
- 支持四方向或等距四方向移动、朝向和像素步行动画。
- CameraRig 默认跟随玩家，并能在剧情中切换目标。
- 地图使用 TileMapLayer、YSort 和前景层表达碰撞及遮挡。
- MapDefinition/MapGameScene 提供语义化出生点。
- 保存或退出地图时同步当前位置和必要世界状态。

### 4.6 NPC 与交互

- NPC 由可复用的 NpcDefinition 和地图中的 NPC Scene 实例组成。
- 每个需要持久化的地图对象拥有稳定 `persistent_id`。
- Interactable 支持面前确认和 Area2D 进入触发。
- DialogueEvent、ShopEvent、TreasureChestEvent、ItemPickupEvent、BattleTriggerEvent 和 ScenePortalEvent 可以作为内嵌 Resource 只通过 Inspector 配置。
- Interactable 和地图入口通过 StoryBinding 引用 StoryEvent Resource 与 trigger ID。
- 复杂交互使用 StoryModule GDScript；同一模块可以通过多个 trigger 服务多个 NPC 和地图。
- StoryDirector 从触发节点生成只含语义 ID 的 StoryOrigin；一次性事件复用来源实体的 persistent ID，不重复配置。
- StoryContext 提供幂等的 `complete_source_entity()`；它只能完成当前 StoryOrigin 来源，原子更新 WorldState，并立即让来源实体应用自身的完成态表现与交互策略，保证一次性主效果不可重复。
- 一次性宝箱和事件根据 GameRun WorldState/Flags 恢复外观和行为。

### 4.7 StoryContext 与剧情

- StoryEvent 是运行期间只读的 Resource；StoryModule 是复杂故事的主要创作单元。
- StoryModule 直接使用 GDScript 的 `if`、`match`、函数和 `await` 表达控制流。
- StoryContext 提供稳定、类型化、自然命名的高层 API。
- 至少支持：按 block 显示对话、打开商店、开始战斗、原子奖励、模块 stage、简单标记、完成当前来源实体、角色移动和朝向、动画、镜头、等待及地图切换。
- 首期只为真正影响剧情分支的操作定义 DialogueResult、ShopResult、BattleResult 和 RewardResult。
- StoryModule 依赖通过 `@export` 暴露，不直接查找内部服务或修改底层集合。
- 同一时刻只运行一个独占 StoryEvent；StoryDirector 负责控制锁和清理。
- `can_run` 同步且无副作用；binding trigger、module ID、initial/valid stage 必须可校验。
- `travel_to` 是终止操作：当前调用清理后才 replace，新地图初始化完成后再按顺序执行 entry bindings；任一 entry binding 发起 travel 时终止当前地图剩余的入口调用。
- StoryContext 不公开 Node，也不提供通用 Variant entity state 读写后门。
- StoryContext 首期直接委托 GameRun、GameSceneStack、Overlay 和当前地图，不预先建立 Gameplay Service 层。
- 初期只允许在没有活动剧情、战斗和事务菜单时保存。
- 不实现 EventSequence、通用动作数组或剧情 opcode。

### 4.8 对话

- DialogueDefinition 由带稳定 ID 的有序 DialogueBlock 组成；block 包含说话人、文本、头像和简单展示选项。
- 支持逐字显示、立即显示、继续和选项返回值。
- block 和 option ID 唯一且可校验；同一故事的短对白可以嵌入模块，长对白可以独立成一个资源。
- 对话内容使用 UTF-8，允许原版位图字体和替代像素字体。
- 对话只表达谈话内容和选择，不执行给予物品、战斗或地图切换。
- 选择结果由 StoryModule GDScript 处理。

### 4.9 物品、装备和商店

- ItemDefinition 支持名称、说明、图标、价格、分类、使用范围和效果。
- InventoryState 保持获得顺序并支持数量上限和原子变更。
- 装备具有槽位、限制和属性修正。
- ShopDefinition 配置商品、买价/卖价规则和可选库存。
- ShopGameScene 通过 GameSceneStack 打开并返回 ShopResult。
- 宝箱与任务奖励通过 StoryContext 统一处理背包变化、音效和提示，默认使用 `ALL_OR_NOTHING` 原子策略；只有显式选择 `ALLOW_PARTIAL` 的拾取用例可以部分发放。

### 4.10 法术、状态和 GameEffect

- SkillDefinition 支持消耗、目标类型、效果、图标、动画和音效。
- 首次选取需要物品或战斗的后续内容时，GameEffect 只实现该内容需要的 Heal、Damage 和 RestoreMp；《借来的伞》不提前实现 Effect。
- ItemDefinition 和 SkillDefinition 可以组合多个 GameEffect。
- Revive、状态、属性修改和生命周期钩子在真实内容需要时增加。
- GameEffect 不执行剧情控制流。

### 4.11 战斗

- BattleEncounter 配置敌人、背景、音乐、逃跑规则和奖励。
- BattleGameScene 从 GameRun PartyState 创建玩家战斗状态。
- 支持普通攻击、法术、使用物品、防御和逃跑。
- 支持单体/全体目标、行动顺序、伤害、资源消耗、状态、死亡和胜负。
- EnemyDefinition 配置技能、奖励和 AI 策略。
- BattleResolver 负责规则，BattleView 消费 BattleEvent 播放动画。
- 动画加速或跳过不改变规则结果。
- pop BattleGameScene 时将需要保留的 HP/MP、物品消耗和结果写回 GameRun，并返回 BattleResult。
- Victory 提交战斗中的 HP/MP、物品消耗、经验、金钱和掉落；Escaped 只提交 HP/MP 和物品消耗，不完成遭遇也不发放胜利奖励；Defeat 提交 HP/MP 和物品消耗，调用方必须在恢复玩家控制前完成恢复/转移或进入失败流程。
- BattleEncounter 的战斗奖励由 BattleGameScene 在 Victory 时结算；任务奖励仍由 StoryModule 在 BattleResult 返回后显式发放，两者不得重复结算。

### 4.12 存档与音频

- 自有版本化存档，不支持原版 `.rpg`。
- 保存地图、出生点/位置、队伍、角色、背包、金钱、标记和持久世界状态。
- 临时文件完整写入后原子替换目标存档。
- 支持多个本地槽、新游戏和继续。
- 支持场景 BGM、战斗音乐、音效总线、开关和淡入淡出。

### 4.13 人类设计师工具

- 首期使用标准 Inspector 和独立 `.tres`。
- 提供内容模板和统一 validate 命令。
- StoryBinding trigger、Dialogue block/option、地图 spawn/marker 等有限语义引用应尽早提供 Inspector 下拉选择；专用编辑器缺失时仍必须保留文本输入和 validator 诊断。
- Database Dock、专用对话编辑器、反向引用和安全 ID 重命名在内容规模证明需要后实现。

### 4.14 AI Agent 工具

- 当前最小 headless CLI 支持稳定 JSON 的 validate、schema、list、show 和 create，覆盖 Map/Dialogue/Story；validate 扫描两张地图、全部故事 Resource、stage、trigger、Dialogue block 和导出的地图 StoryBinding。
- create 根据类型生成合法 Resource 模板，不要求 Agent 手写 UID，也不隐式维护第二份索引。
- schema 提供当前三种内容的字段、类型、默认值、ID 前缀和创建约束。
- 失败使用非零退出码并输出文件、字段、内容 ID 和修复提示。
- FakeStoryContext 可以注入选择、商店和战斗结果，按 trigger/stage 输出结构化剧情轨迹和 pending travel。
- refs、自动 catalog、JSON round-trip 和迁移工具属于后续阶段。

## 5. 非功能需求

### 可理解性

- 设计师 API 使用完整动词和领域名词。
- 不使用含义模糊的 Dictionary 命令或数字标记。
- 示例代码能够在不理解内部场景树的情况下阅读。

### 可测试性

- GameRun、Inventory、GameEffect、商店和战斗规则可以无窗口测试。
- StoryEvent/StoryModule 可以在 FakeStoryContext 上按 trigger、关键 stage 和结果分支运行。
- SceneStack、输入隔离和 UI 使用场景级 smoke test。
- 普通 CI 使用仓库中的 `generated/` 输出，但不读取原版输入数据。

### 可诊断性

- 内容错误包含 ID、文件、字段和引用链。
- StoryDirector 显示当前 StoryModule/Event、trigger、来源和等待操作。
- 战斗输出结构化 BattleEvent/规则日志。
- 调试覆盖层显示碰撞、交互区域、地图实体 ID 和 Camera 目标。

### 稳定性

- StoryContext、StoryBinding 及 StoryEvent trigger 契约视为公共 API，破坏性变更需要迁移说明。
- 内容 schema 和存档分别版本化；引入自动 catalog 后再单独版本化其格式。
- 随机规则可以注入种子。
- 失败的购买、奖励、装备和加载操作保持状态原子性。

### 性能

- `320 x 200` 内部画面目标显示 60 FPS。
- 不在每帧扫描内容目录或加载 Resource。
- ContentDatabase 在启动时建立内存索引，不在每帧扫描目录。
- 像素纹理无过滤、无 MipMap、无有损压缩。

## 6. 首期明确不做

- 在 Godot 运行时解析原版 MKF、opcode、剧情脚本或事件对象流程。
- 对原版脚本进行逐 opcode 翻译，或建立原版事件解释器作为剧情运行时。
- 原版运行时状态、文件协议和 `.rpg` 存档兼容。
- 完整复刻整部原作不是当前完成条件；第一版只验收两张原创地图和《借来的伞》，后续内容按框架验证需要选择。
- EventSequence、通用可视化剧情语言和万能动作解释器。
- 每个 NPC、地图入口或触发区域各创建一个剧情脚本的工作流。
- 将 Rust `pal-core` 嵌入 Godot。
- 在 GDScript 中解析 MKF、YJ_1、GOP、RLE、VOC 等格式。
- 一开始实现完整 RPG Database Editor；先建立 schema、Inspector 和 CLI。
- 移动端、联网、多人游戏和 Mod SDK。
- 提交原版输入数据、原版存档，或在没有相应权利时公开发行派生素材。

## 7. 首个框架验证片段：《借来的伞》

第一版使用离线提取的《仙剑奇侠传一》视觉和音频素材，组装一个不属于原版剧情的短故事。仓库维护原创 UTF-8 对白、Godot 场景和 `framework-lab` 派生资源，但不附带原版输入数据或存档，也不把商店、背包和战斗纳入当前完成条件。

1. `framework-lab` 从用户合法持有的数据生成两张地图需要的 Tile、角色/NPC、头像、UI、Big5 位图字体、VOC 音效和 RIX/OPL2 音乐；manifest 记录源文件、chunk、输出路径、元数据和 SHA-256。
2. `map.lab.inn_hall`（听雨客栈·前厅）和 `map.lab.rain_courtyard`（听雨客栈·雨院）使用不同 Tile atlas 重新组合布局，`.tscn` 是地图结构、碰撞、NPC、portal、spawn 和交互物的运行时真相来源。
3. 玩家能够在两张地图中移动、碰撞、经过 YSort，并通过 portal 往返；新游戏、地图替换和精确位置恢复均由 GameRoot、GameSceneStack 和 GameRun 协作完成。
4. `story.lab.borrowed_umbrella` 通过前厅 entry、掌柜、安静客人、雨院 entry、蓑衣客和旧伞六个 trigger 推进 `not_started → met_innkeeper → looking_for_owner → owner_found → umbrella_found → completed`。
5. 取得旧伞时，`complete_source_entity()` 同步完成 StoryOrigin、更新 `WorldState` 并隐藏当前交互物；重复进入雨院、重复交谈和地图重新实例化不会重放一次性主效果。
6. 对话使用原创文本以及提取的头像、BMFont、等待图标和音效；场景使用离线合成的 PCM16 音乐。exporter 不读取或输出 `SSS.MKF`、`M.MSG`、地图布局、事件、规则数据库和存档。
7. FakeStoryContext 检查确定性的剧情轨迹；场景 smoke test 实际走完接任务、跨地图、认领旧伞、完成来源和返回交付，并验证输入锁、TileMapLayer、StoryState、GameFlags、WorldState 与存档往返。
8. `generated/` 是地图 TileSet、AssetLibrary 和普通 CI 的必需输入；manifest、atlas 或其他必需输出缺失必须产生明确诊断，不再把无素材占位模式作为工程验收路径。
