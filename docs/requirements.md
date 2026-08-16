# 需求与范围

## 1. 产品定位

本项目是一个面向学习和内容创作的原创传统单机修仙 RPG 框架。当前正式验证片段由
`map.roadside.shop` 与 `map.roadside.herb_slope` 组成：玩家接下两趟采药差事，在路线、
时段和是否留根之间取舍，并观察第二趟的再生或枯竭结果。

项目不读取或维护第三方游戏提取素材、脚本、事件、存档和运行时格式。正式内容与普通
CI 只依赖 `assets/original/` 和 Godot 原生 Scene/Resource。

## 2. 核心目标

### 可玩与可验证

每个里程碑围绕当前内容片段交付端到端可运行体验。第一版原创内容验证等距探索、互动、
遮挡和存档；商店、战斗和成长等通用能力只有在新内容实际需要时才重新登记验收。

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

- 人类设计师通过 Godot Inspector、场景编辑器、Content Database Dock 和 Dock 内 Dialogue Editor 工作。
- AI Agent 通过文本文件、稳定 JSON 的完整内容 CLI 和自动测试工作；支持派生 catalog、反向引用、原子 JSON 应用与可审计 ID 迁移。
- 两者操作同一套内容模型，不维护互相漂移的两份数据库。

### 原创素材与内容解耦

玩法 Resource 使用语义化 ID，视觉和音频直接使用类型化 Texture2D/AudioStream 引用。
生成源图、后处理脚本和运行图彼此可追踪，但生成文件名不进入 GameRun。

## 3. 用户类型

### 玩家

在桌面端使用键盘或手柄体验传统像素 RPG 的探索、剧情、菜单和战斗。

### 人类设计师

在 Godot 编辑器中搭建地图、放置 NPC、配置内嵌 StoryBinding，并以一个 StoryModule 编写一项完整叙事职责，使用验证面板检查错误。

### AI Agent

在不依赖可视化编辑器的情况下创建、查询、修改和验证内容；运行无窗口测试；得到稳定 JSON 和具体文件/字段诊断。

### 系统程序开发者

维护运行时、内容 schema、Godot EditorPlugin、素材导出器和公共 StoryContext API。

## 4. 功能需求

本章描述框架的目标能力集合。当前正式内容验证原创等距地图、选择、采集、原子交付、
有限随机风险、持久地图表现、菜单与存档。

### 4.1 工程与画面

- Godot 4.8 和带静态类型的 GDScript。
- `320 x 180` 内部画面，默认 `960 x 540` 严格 3 倍显示；窗口可缩放并可切换全屏，最近邻放大并保持比例。
- 首期通过 Godot 根 Viewport 和 stretch 设置实现，不增加自定义 SubViewport。
- 桌面端为当前平台，键盘与常见手柄均可用。
- 工程要求存在正式切片所需的原创角色、Tile 与环境物件；缺失时内容校验给出具体路径。
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
- 使用简单、显式的 ContentDatabase Resource；自动 catalog 从它与故事资源确定性派生，不成为第二份真相。
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
- 允许编辑期地图生成器用 seed、生态规则和人工 anchor 产生确定性 MapGameScene 草稿并烘焙
  到正式 `.tscn`；运行时不执行地图生成。
- 地图生成器只拥有 Ground/Detail cell、显式标记的环境节点和边界碰撞，不得改写人工 NPC、
  Portal、StoryBinding、spawn、persistent ID 或剧情物件。
- 生成计划必须验证道路、全部 gameplay anchor、阻挡物 footprint 和保护区，并记录版本、seed、
  plan hash 与结构化诊断。

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
- 对话内容使用 UTF-8，使用原创或可合法分发的替代像素字体。
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
- 当前实证支持单目标、伤害、资源消耗、有限回合状态、死亡和胜负；多人/全体目标随真实内容增加。
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

- 标准 Inspector、独立 `.tres` 和统一 validate 仍是底层入口。
- PAL Database Dock 从现有 Resource 派生目录，支持类型过滤、刷新、Inspector 打开与反向引用预览。
- Dock 内 Dialogue Editor 按 block/entry 预览与编辑原始 DialogueDefinition，保存前运行内容校验。
- 独立 Map Generator Dock 支持 Profile/seed、无保存预览、撤销、校验和原子烘焙；它操作同一
  正式 MapGameScene，不保存第二份地图数据库。
- StoryBinding trigger、Dialogue block/option、地图 spawn/marker 保留文本输入和 validator 诊断，不以编辑器 UI 取代内容契约。

### 4.14 AI Agent 工具

- Headless CLI 支持稳定 JSON 的 `validate/catalog/schema/list/show/create/export-json/apply-json/refs/rename-id/story-test`。
- list/show/schema/create 覆盖 Actor、Item、Equipment、Skill、Status、Enemy、Shop、Encounter、Map、Dialogue 和 Story；create 生成合法 Resource 模板，不要求手写 UID，也不隐式修改 ContentDatabase。
- `export-json` 输出带版本的派生目录；`apply-json` 只接受可编辑的 JSON 字段，先做类型与全库校验，再用临时文件整批安装并失败回滚。
- `refs` 返回 Resource 与地图场景的反向引用；`rename-id` 只替换精确序列化 ID，并生成迁移记录。
- `story-test` 注入 battle outcome，按 trigger/stage 输出结构化剧情轨迹和 pending travel。
- 独立 `map_generator_cli.gd` 提供稳定 JSON 的 `plan/validate/bake`，支持 seed override；只有
  bake 写文件，并在临时场景完整验证后原子替换目标。
- 失败使用非零退出码并输出文件、字段、内容 ID 和修复提示。

## 5. 非功能需求

### 可理解性

- 设计师 API 使用完整动词和领域名词。
- 不使用含义模糊的 Dictionary 命令或数字标记。
- 示例代码能够在不理解内部场景树的情况下阅读。

### 可测试性

- GameRun、Inventory、GameEffect、商店和战斗规则可以无窗口测试。
- StoryEvent/StoryModule 可以在 FakeStoryContext 上按 trigger、关键 stage 和结果分支运行。
- SceneStack、输入隔离和 UI 使用场景级 smoke test。
- 地图生成规则可以无窗口测试相同 seed hash、不同 seed、anchor 可达、碰撞净空、人工节点
  保留和失败回滚。
- 普通 CI 只使用仓库中的 `assets/original/`，不读取任何第三方游戏输入或旧派生输出。

### 可诊断性

- 内容错误包含 ID、文件、字段和引用链。
- StoryDirector 显示当前 StoryModule/Event、trigger、来源和等待操作。
- 战斗输出结构化 BattleEvent/规则日志。
- 调试覆盖层显示碰撞、交互区域、地图实体 ID 和 Camera 目标。

### 稳定性

- StoryContext、StoryBinding 及 StoryEvent trigger 契约视为公共 API，破坏性变更需要迁移说明。
- 内容 schema、存档和派生 catalog 格式分别版本化。
- 随机规则可以注入种子。
- 失败的购买、奖励、装备和加载操作保持状态原子性。

### 性能

- `320 x 180` 内部画面目标显示 60 FPS。
- 不在每帧扫描内容目录或加载 Resource。
- ContentDatabase 在启动时建立内存索引，不在每帧扫描目录。
- 像素纹理无过滤、无 MipMap、无有损压缩。

## 6. 首期明确不做

- 在 Godot 运行时解析原版 MKF、opcode、剧情脚本或事件对象流程。
- 对原版脚本进行逐 opcode 翻译，或建立原版事件解释器作为剧情运行时。
- 原版运行时状态、文件协议和 `.rpg` 存档兼容。
- 完整宏大剧情不是当前完成条件；第一版只验收一张可玩的原创等距地图。
- EventSequence、通用可视化剧情语言和万能动作解释器。
- 每个 NPC、地图入口或触发区域各创建一个剧情脚本的工作流。
- 将 Rust `pal-core` 嵌入 Godot。
- 在 GDScript 中解析 MKF、YJ_1、GOP、RLE、VOC 等格式。
- 一开始实现完整 RPG Database Editor；先建立 schema、Inspector 和 CLI。
- 移动端、联网、多人游戏和 Mod SDK。
- 提交第三方游戏提取素材、原版输入数据或原版存档。

## 7. 首个正式片段：斜坡小铺

1. `actor.roadside.traveler` 与店主使用同规格 `3 x 4` 四斜向图集。
2. `map.roadside.shop` 使用严格 `32 x 16` TileSet 和 `18 x 14` Tile 布局，TileMap、碰撞、spawn 和 YSort 保存在 `.tscn`。
3. R1 的店主日常对白使用地图内嵌 DialogueEvent；R2 因多阶段采集闭环改由一个 StoryModule 接管。
4. 玩家能够移动、被松树/小铺/围栏阻挡、在树前后正确排序、打开菜单并存读精确位置。
5. `320 x 180` 视野由玩家 CameraRig 跟随，不通过固定镜头把整张地图缩进一屏。
6. 自动测试覆盖内容索引、素材存在性、四方向帧、地图碰撞、对话输入锁、场景栈和存档往返。
7. 截图固定覆盖标题、地图、树前、树后和店主对话五个状态。

## 8. 第二个正式片段：北坡采药

1. `story.roadside.gathering` 同时响应店主、药草坡入口和三处药草 trigger。
2. 旧石路固定在正午抵达；碎石近坡以可注入种子的随机结果在清早或日斜抵达。
3. 割叶留根获得一份并保留来源；连根采走获得两份并完成当前 StoryOrigin 来源。
4. 每次交付恰好移除两份材料并原子增加工钱；迟到只影响本次工钱，不使用善恶值。
5. 第二趟开始后，留根药丛重新可采，连根完成的 persistent entity 保持消失。
6. GameRun 存档保存 story stage、flag、WorldState、库存、金钱和随机源推进位置。
7. 自动测试覆盖安全/近路、成功/失足、两种采法、迟到/按时交付、再生和存档往返。
8. `map.roadside.herb_slope` 的 `32 x 16` Ground、Detail、道路、栖息地、环境物件和边界
   碰撞由固定 Profile/seed 编辑期烘焙，三处药草、Portal、spawn 和 StoryBinding 保持人工所有。
