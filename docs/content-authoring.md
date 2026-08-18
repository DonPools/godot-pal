# 内容创作与设计师 API

## 1. 目标

内容创作系统同时服务使用 Godot 编辑器的人类设计师、通过代码和命令行工作的 AI Agent，以及维护底层系统的程序开发者。

三者使用同一套 Resource、语义 ID、StoryContext 和校验规则。入口包括 Inspector、Content Database Dock、Dock 内 Dialogue Editor、文本 GDScript 和稳定 JSON CLI；所有工具直接操作原始 Resource 或其派生目录。

设计原则：

1. 简单内容不写代码。
2. 复杂剧情使用普通、类型化 GDScript。
3. 静态数据使用 Resource，运行时进度使用 GameRun State。
4. 公共 API 使用领域词汇，不暴露内部 Node 和服务。
5. 一个故事按叙事职责形成一个模块，不按每个触发点创建脚本。
6. 简单事件和 StoryBinding 默认嵌入地图场景，不制造无意义文件。
7. 所有 ID、引用、trigger、stage 和 dialogue block 都可以验证。

## 2. 创作表面

| 内容 | 人类设计师 | AI Agent | 运行时形式 |
|---|---|---|---|
| 角色、物品、法术、状态、怪物 | Inspector + Database Dock | 完整 content CLI | `.tres` Resource |
| 地图、NPC、交互物 | 3D 场景编辑器 | `.tscn` + scene validator | PackedScene/Node3D |
| 对话 | Inspector + Dialogue Editor | `.tres` + validate/apply-json | DialogueDefinition/DialogueBlock |
| 简单交互 | Inspector 内嵌资源 | `.tscn` 配置和模板 | StoryBinding + 内置 StoryEvent |
| 复杂剧情 | GDScript + Inspector | Story API + FakeStoryContext | StoryModule Resource |
| 内容索引 | ContentDatabase + 派生 Dock | catalog/list/show/schema/refs | ContentDatabase 与原始 Resource |

## 3. 内容目录

```text
framework/
├── content/               # Definition、数据库与校验
├── story/                 # 剧情协议与执行器
├── gameplay/              # 战斗、效果与事务
└── presentation/          # 通用角色、地图、交互与对话组件

game/
├── bootstrap/             # 本作入口和组合根
├── presentation/          # 本作标题、菜单等成品界面
└── roadside/
    ├── action_combat_3d/
    │   ├── maps/
    │   ├── characters/
    │   └── props/
    ├── map_generation/
    ├── stories/
    └── tools/

content/
├── content_database.tres
├── actors/
│   └── traveler.tres
├── npcs/
│   └── roadside_shopkeeper.tres
└── maps/
    ├── north_slope_wilds.tres
    ├── roadside_shop.tres
    └── herb_slope.tres
```

Definition 文件名应与 ID 最后一段一致，例如 `content/items/healing_herb.tres` 对应 `item.healing_herb`。

### 剧情文件预算

- 普通对话、商店、宝箱、拾取物、战斗触发和传送：只修改所属地图 `.tscn`，StoryBinding 和内置事件都是 SubResource。
- 复杂故事：通常新增 `story_name.gd` 与 `story_name.tres`；对白较多时再新增一个 `dialogue.tres`。
- 跨地图故事：复用同一个 StoryModule Resource，只修改故事实际出现的地图场景，不为每张地图复制模块。
- 新增全局物品、法术或怪物仍各自创建 Definition；只有需要 ContentDatabase 全局查询的 Definition 才登记到首期手写索引。

地图场景修改是放置触发点的必要工作，不再为每个触发点额外创建脚本或事件资源文件。

## 4. ID 规范

ID 使用小写 `StringName`，由点分隔命名空间，单词使用下划线：

```text
actor.roadside.traveler
map.roadside.shop
map.roadside.herb_slope
map.roadside.north_slope_wilds
item.roadside.fanqing_grass
dialogue.roadside.gathering
story.roadside.gathering
flag.story.roadside.gathering.uprooted.west
herb_patch.west
safe_entry
```

- ID 创建后视为持久 API；重命名通过工具迁移引用。
- 显示名称可以本地化和修改，不影响 ID。
- 存档保存内容 ID，不保存 Resource 路径。
- Map 中的 persistent ID 和 spawn ID 在对应地图内唯一。
- StoryModule 中的 trigger、stage、dialogue block、actor 和 marker 使用语义 ID，不使用 NodePath。

## 5. Definition 基类

所有进入 ContentDatabase 的 RPG Definition 继承 `ContentDefinition`：

```gdscript
class_name ContentDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var tags: Array[StringName]
```

`id` 由模板或创建工具生成。创建后视为持久 API；确需变更时使用 `rename-id` 做可回滚、带审计记录的迁移，不直接手改。

## 6. 核心内容 schema

### ActorDefinition

- `field_model_3d`、基础属性、成长曲线和装备槽。
- 初始装备和初始技能。

ActorDefinition 是角色模板；等级、经验、HP/MP、装备和已学技能属于 ActorState。

### ItemDefinition

- icon、category、price 和 max stack。
- field/battle 可用范围和 target rule。
- `Array[GameEffect]`。
- 可选 EquipmentDefinition。

ItemCategory 至少包含 Consumable、Equipment、KeyItem 和 Material。剧情物品是否可出售或丢弃使用明确字段，不通过价格或 ID 推断。

### SkillDefinition

- MP 消耗、target rule、冷却、施法/生效/恢复秒数、射程与半径。
- `Array[GameEffect]`。
- 可选 3D presentation PackedScene 和 sound。

技能的数值和效果数据化；复杂表现使用 PackedScene/AnimationPlayer，不在 Effect 中操作 UI。

### EnemyDefinition

- CharacterBody3D scene、HP/攻击、移动速度、警戒/攻击/leash 范围和攻击时间线。
- 有限 AI strategy；空间行为由地图中的表现组件执行，规则伤害仍进入 BattleSession。
- 经验、金钱和掉落。

常用 AI 使用少量可配置 Strategy Resource；独特 Boss 使用显式 GDScript Strategy，不建立通用行为表达式语言。

### StatusDefinition

当前有限 schema 使用 `duration_seconds`、`tick_interval_seconds` 和 `periodic_damage`。
BattleSession 在固定规则步长中推进并发出 `STATUS_APPLIED/STATUS_TICK`；状态只属于本场战斗，
不进入 GameRun。周期伤害大于零时，tick interval 不能晚于整个持续时间。

叠加规则、属性修正、图标和更丰富生命周期钩子在真实内容需要时增加。状态始终只影响战斗机械，不触发剧情。

### NpcDefinition

- `field_model_3d` 和内容 tag。

NpcDefinition 描述可复用身份和 3D 表现。位置、StoryBinding、可选 persistent ID 与章节状态
属于地图实例；NpcCharacter3D 只实例化 Definition 的模型，不持有长期状态。

### ShopDefinition

- `Array[ShopEntry]`。
- 买价和卖价策略。
- 是否允许卖出。

ShopEntry 类型化引用 ItemDefinition，并可配置价格覆盖和库存。

### BattleEncounter

- `Array[EncounterEnemy]`、遭遇半径与 leash 半径。
- 音乐、逃跑规则和 `ALL_OR_NOTHING/ALLOW_PARTIAL` 奖励策略。

EncounterEnemy 引用 EnemyDefinition，并配置稳定 instance ID、相对 `Vector3` 出生偏移和等级修正。
instance ID 在单个 Encounter 中唯一；出生偏移必须位于遭遇半径内。

### DialogueDefinition

- `Array[DialogueBlock]`。
- 默认窗口样式。

DialogueBlock 包含稳定 block ID、有序 `Array[DialogueEntry]` 和可选
`Array[DialogueOption]`。DialogueEntry 包含说话人、UTF-8 文本和头像；每个
DialogueOption 包含稳定 option ID 与显示文本。

同一故事的多个谈话片段优先放在一个 DialogueDefinition 的命名 block 中，避免为每次 NPC 对话创建小文件。短对话可以把 DialogueDefinition 嵌入 StoryModule `.tres`，对白较多时再独立为 `dialogue.tres`。使用有序 Array 而不是大型 Dictionary，保证 Inspector 顺序、稳定序列化和逐项校验。

DialogueDefinition 只表达谈话和选择，不执行奖励、战斗、flag 或地图切换；DialogueResult 返回 option ID，由 StoryModule 决定后果。

### MapDefinition

- map scene、default spawn ID、音乐和区域 tag。

地图几何、GridMap、环境模块、NPC 和触发器在具体 `.tscn` 中编辑；MapDefinition 提供数据库
入口。具体地图继承一层 `roadside_map_3d_base.tscn` 复用玩家、固定 Camera3D、WorldRoot
容器、spawn 容器和 HUD，不复制公共骨架，也不在共享脚本中按地图 ID 生成布局。

## 7. GameEffect 创作

《雨夜药房》当前证明需要：

```text
HealEffect
RestoreMpEffect
```

示例：

```text
item.healing_herb
└── HealEffect
    ├── amount: 200
    └── target: selected_ally

skill.fire_bolt
└── DamageEffect
    └── amount: 40
```

Effect 不允许包含 arbitrary GDScript 字符串、剧情条件或场景路径。Revive、Status 和属性修改在真实内容需要时增加；没有事务需求前不建设完整 EffectResolver。

《借来的伞》仍不使用 GameEffect；Heal/RestoreMp 由药房片段证明，Damage 由《断桥伏击》战斗片段证明。

## 8. ContentDatabase

首期 `content_database.tres` 使用类型化数组显式登记需要按 ID 全局查询或进入存档的 RPG Definition，启动时建立 ID Dictionary。ContentDatabase 提供按类型的只读查询和迭代，不在运行时创建永久 Definition。

StoryModule 和只被故事直接引用的私有 DialogueDefinition 不强制登记到手写 ContentDatabase。它们以 `.tres`、地图 StoryBinding 和 ContentDatabase 的 `story_directories` 为真相来源，由 validator 扫描检查。这样创建故事不需要同时修改一个全局注册文件。

当前 ContentCatalog 在需要时从手写 ContentDatabase 与 `story_directories` 扫描结果确定性构建，覆盖 12 类内容。它只驻留内存或作为带 `catalog_version` 的 JSON 导出，不生成需要维护的索引 Resource，因此不是第二份内容真相来源。

## 9. 人类设计师工作流

### Inspector 与 PAL Database Dock

1. 从文件系统创建指定 Resource 类型。
2. 填写 ID、显示字段、图像和规则。
3. 运行 Validate Content。
4. 在地图或其他 Definition 中通过类型化 Resource picker 引用。
5. 在 `PAL Database` Dock 按类型浏览目录、查看反向引用，或把 Resource 打开到 Inspector。
6. 对 DialogueDefinition，可在 Dock 内选择 block/entry、预览、修改说话人与正文并保存；保存目标仍是原 `.tres`。

### Map Generator Dock

1. 打开 `MapGenerationProfile.target_scene_path` 对应的 MapGameScene。
2. 在独立 Map Generator Dock 选择 Profile 和 seed。
3. Preview 只通过 EditorUndoRedo 修改当前场景，不写文件；查看 habitat、道路、Detail、Prop
   指标和 diagnostics。
4. Undo Preview 恢复 Ground/Detail、生成节点和 provenance 元数据的精确快照。
5. Bake 先保存人工编辑，再通过临时场景完整校验并原子替换正式 `.tscn`。
6. 关键 NPC、Portal、资源、StoryMarker 和 StoryBinding 由人类放置；需要再次生成时把它们
   登记为 protected anchor。

## 10. AI Agent CLI

当前 CLI 以 Godot headless 直接扫描和校验同一 Resource：

```sh
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
```

它检查正式原创素材、当前 ContentDatabase 中的地图、TileSet/cell、spawn、persistent ID、
portal 目标、`story_directories` 中全部 StoryModule/DialogueDefinition，以及地图中导出的
StoryBinding。`--json` 保留 `ok/error_count/errors`，并提供带 code、message、file、field
和可选 content_id/source 的 `diagnostics`；成功返回 0，内容错误返回 1，命令用法错误返回
2，写文件失败返回 3。

目录、查询和模板命令：

```sh
godot --headless --path . -s res://tools/content_cli.gd -- catalog --json
godot --headless --path . -s res://tools/content_cli.gd -- list [type] --json
godot --headless --path . -s res://tools/content_cli.gd -- show <type> <id> --json
godot --headless --path . -s res://tools/content_cli.gd -- schema [type] --json
godot --headless --path . -s res://tools/content_cli.gd -- create <type> <id> --path <res://...tres> [type options] --json
godot --headless --path . -s res://tools/content_cli.gd -- refs <id> --json
godot --headless --path . -s res://tools/content_cli.gd -- export-json <res://...json> --json
godot --headless --path . -s res://tools/content_cli.gd -- apply-json <res://...json> --json
godot --headless --path . -s res://tools/content_cli.gd -- rename-id <type> <old-id> <new-id> --json
godot --headless --path . -s res://tools/content_cli.gd -- story-test <story-id> <trigger-id> [stage] [victory|escaped|defeat] --json
```

地图生成使用独立、同样稳定的 JSON CLI：

```sh
godot --headless --path . -s res://tools/map_generator_cli.gd -- plan <profile.tres> [--seed <int>] --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate <profile.tres> [--seed <int>] --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- bake <profile.tres> [--seed <int>] --json
```

`plan/validate` 只读；`bake` 写临时 `.tscn`、重新加载并检查 generator ownership、Tile、anchor、
碰撞净空和人工内容后才替换目标。具体 schema 与工作流见 `docs/map-generation.md`。

- `catalog/list/show` 查询 ContentDatabase 中登记的 RPG Definition，以及 `story_directories` 扫描到的 Dialogue/Story。
- `schema` 返回 12 类内容的字段、默认值、ID 前缀和 create 必需选项。
- `create map` 还要求 `--scene`，可选 `--display-name/--default-spawn/--music-source`；创建后由作者显式登记到 ContentDatabase。
- `create dialogue` 可选 `--block/--speaker/--text`，生成至少一个合法 block/entry。
- `create story` 可选 `--script/--dialogue/--initial-stage/--stages`；Shop/Encounter 模板要求一个实际 Item/Enemy 引用。

CLI 稳定契约是：

- JSON 模式输出一个结构稳定的结果文档。
- 成功返回 0，schema/内容错误返回固定非零码。
- 错误逐步补充 code、message、file、content_id、field 和可选 suggestion。
- JSON 字段、枚举字符串和默认值保持稳定。
- create 通过 ResourceSaver 生成合法模板，不要求 Agent 手工生成 ResourceUID 或 ExtResource 编号，也不隐式修改 ContentDatabase。

### Agent 推荐流程

1. 阅读本文件的 schema 和现有 `.tres/.tscn`。
2. 创建或修改内容文件与 StoryModule。
3. 调用 `validate --json` 和相关测试。
4. 执行 Godot 无窗口工程加载检查。

`export-json` 输出的 `properties` 只包含 JSON 可表达、Inspector 可编辑且非内部 Resource 的字段。`apply-json` 禁止修改 `id/script`，先完成全部字段类型转换和 ContentDatabase 校验，再用每文件临时副本整批安装；任何失败都恢复内存与磁盘。ID 变更只能使用 `rename-id`：工具扫描反向引用、精确替换序列化 ID、逐文件回滚，并写迁移审计 JSON。

## 11. StoryContext 公共 API

StoryContext 是设计师脚本允许依赖的主要运行时接口。

### 对话与选择

```gdscript
func show_dialogue(
    dialogue: DialogueDefinition,
    block_id: StringName = &"default"
) -> DialogueResult
```

### 商店与战斗

```gdscript
func open_shop(shop: ShopDefinition) -> ShopResult
func start_battle(encounter: BattleEncounter) -> BattleResult
```

`open_shop` 通过 GameSceneStack push；`start_battle` 不 push BattleGameScene，而是 await 当前
MapGameScene 的唯一 BattleSession。战斗期间互动、保存和事务菜单被禁用。

### 奖励和队伍

```gdscript
func give_item(
    item: ItemDefinition,
    quantity: int = 1,
    policy: RewardPolicy = RewardPolicy.ALL_OR_NOTHING
) -> RewardResult
func item_quantity(item: ItemDefinition) -> int
func deliver_items(
    item: ItemDefinition,
    quantity: int,
    money_reward: int
) -> DeliveryResult
func restore_party() -> void
```

`RewardPolicy.ALL_OR_NOTHING` 是任务奖励和宝箱的默认策略：背包无法容纳全部数量时完全不修改 InventoryState。`RewardPolicy.ALLOW_PARTIAL` 只能由允许部分拾取的内容显式选择；调用方必须处理 changed/rejected quantity，不能在仍有 rejected quantity 时完成来源实体。

`deliver_items` 只有在库存足量时才精确移除材料并增加工钱；失败时库存和金钱都不变。
它用于采集委托等明确交换，不替代商店交易。以上领域操作保持同步。

### 查询和标记

```gdscript
func is_flag_set(flag_id: StringName) -> bool
func get_flag(flag_id: StringName, default_value: Variant = null) -> Variant
func set_flag(flag_id: StringName, value: Variant = true) -> void
func clear_flag(flag_id: StringName) -> void
func get_stage(module: StoryModule) -> StringName
func set_stage(module: StoryModule, stage_id: StringName) -> void
func roll_percent(chance: int) -> bool
```

StoryModule 内部通常写成 `story.get_stage(self)` 和 `story.set_stage(self, &"completed")`。StoryContext 从 module.id 访问 StoryState，并在设置阶段前验证 stage 属于 module.valid_stages，设计师不重复输入 story ID。

故事需要地图 HUD 目标提示时，可以覆盖同步、无副作用的 `get_objective_text(stage_id, map_id)`。目标文本属于 StoryModule 的叙事表现，不写进通用 MapGameScene；没有目标时返回空字符串，地图显示通用操作提示。

`roll_percent` 使用 GameRun 的 RandomState。新游戏和测试可以注入种子；种子、内部状态和
抽取次数一并进入存档，因此读档不会重掷已经发生的路径风险。

### 触发来源

```gdscript
var source_entity_id: StringName
var source_actor_id: StringName
func is_source_entity_completed() -> bool
func complete_source_entity() -> void
```

来源 ID 由 StoryDirector 从触发节点生成的 StoryOrigin 快照注入；可能不存在时为空 StringName。`source_entity_id` 是来源地图实例的 map-local `persistent_id`，`source_actor_id` 是其 Actor/Npc Definition ID。StoryContext 不暴露来源 Node。

宝箱、拾取物、敌人和一次性战斗事件直接复用地图对象的 persistent ID，设计师不在事件资源中重复配置。`complete_source_entity()` 只作用于当前 StoryOrigin：它幂等地写入 WorldState，并立即让来源应用自身的完成态，保证一次性主效果不可重复；宝箱仍可提供空箱对白，已清除的敌人则关闭表现、碰撞、交互和自动触发。重新进入地图或加载存档后继续生效。没有合法来源、来源没有 persistent ID 或当前地图无法解析来源时必须产生明确剧情错误。

### 地图角色和表现

```gdscript
func move_actor(actor_id: StringName, marker_id: StringName) -> void
func face_actor(actor_id: StringName, direction: Direction) -> void
func play_actor_animation(actor_id: StringName, animation: StringName) -> void
func set_actor_visible(actor_id: StringName, visible: bool) -> void
func focus_camera(target_id: StringName) -> void
func reset_camera() -> void
func wait_seconds(seconds: float) -> void
```

actor、marker 和 target ID 由当前 MapGameScene 解析；缺失引用是明确剧情错误。

这里的 `actor_id` 是地图实例的语义地址；需要持久化的 NPC 默认直接复用其 `persistent_id`，不再额外配置一份移动专用 ID。`source_actor_id` 则始终表示静态 Actor/Npc Definition ID，两者用途不同。

首期不公开任意 `get_entity_state()/set_entity_state(Variant)`。内置一次性事件通过运行时内部接口更新 WorldState；自定义剧情使用 stage、flag、角色移动、显隐等明确 API。真实出现无法表达的重复用例后，再增加类型化能力。

### 世界切换

```gdscript
func travel_to(map: MapDefinition, spawn_id: StringName = &"") -> void
```

`travel_to` 只记录 pending travel，并使当前 StoryContext 失效；StoryDirector 在当前调用清理完成后执行 replace。它必须是当前 trigger 的最后一个调用，脚本紧接着 `return`。新地图的有序 entry bindings 只在出生和状态恢复完成后依次执行；其中任何一个再次 travel 时停止当前地图剩余的入口调用。

### API 命名约束

- 使用 `show_dialogue`、`start_battle` 等完整动词。
- 不提供 `execute(command)`、`do_action(type, args)` 或 Dictionary 命令。
- 返回结果对象，不用多个含义混杂的 bool/int。
- 交互方法可以 `await`，查询方法不 `await`。
- 新公共方法必须有文档、成功/失败定义、FakeStoryContext 行为和测试。

## 12. 结果对象

当前定义五种会影响剧情分支的结果：

```text
DialogueResult: selected_option_id, skipped
ShopResult: purchases, sales, money_delta
BattleResult: outcome, duration_msec, defeated_enemy_ids, committed, experience_reward,
              money_reward, dropped_items, rejected_dropped_items, state_changes
RewardResult: item_id, requested_quantity, changed_quantity, rejected_quantity
DeliveryResult: outcome, item_id, quantity, money_delta
```

BattleResult 的 outcome 提交规则固定为：Victory 提交 HP/MP、物品消耗、经验、金钱和掉落；
Escaped 只提交 HP/MP 和物品消耗；Defeat 同样提交 HP/MP 和物品消耗，但调用方必须在恢复
玩家控制前恢复/转移队伍或进入明确失败流程。BattleEncounter 奖励只在 Victory 结算，
StoryModule 的任务奖励另行显式发放；重复 commit 返回同一个结果，不重复改变 GameRun。

RewardResult 的失败原因使用枚举，例如 InsufficientQuantity、InventoryFull，而不是需要解析的文本。`ALL_OR_NOTHING` 失败时 changed quantity 为 0、rejected quantity 等于 requested quantity；`ALLOW_PARTIAL` 才允许两者同时非零。其他操作等真实分支需求出现后再增加结果类型。

DeliveryResult 只表达 Invalid、InsufficientItems 或 Completed；Completed 保证物品移除与工钱
增加已经一起提交。

## 13. StoryEvent、StoryModule 与 StoryBinding

### StoryEvent 基类

```gdscript
class_name StoryEvent
extends Resource

func get_trigger_ids() -> Array[StringName]:
    return [&"default"]

func can_run(_trigger_id: StringName, _story: StoryContext) -> bool:
    return true

func run(_trigger_id: StringName, _story: StoryContext) -> void:
    push_error("StoryEvent.run() must be implemented")
```

StoryEvent Resource 运行期间只读。`can_run()` 必须同步、无副作用；返回 false 表示合法地忽略当前触发，未知 trigger 则是校验错误。

### StoryModule 模板

复杂故事通常只创建一个脚本和一个配置 Resource：

StoryModule 基类提供 `id`、`initial_stage`、`valid_stages`、可选 `dialogue` 和只读 `get_objective_text(stage_id, map_id)`。自定义脚本只声明故事需要的额外 Item、Shop、Encounter、Map 等类型化依赖。

```gdscript
class_name RoadsideGatheringStory
extends StoryModule

const TALK_SHOPKEEPER := &"talk_shopkeeper"
const ENTER_SLOPE := &"enter_herb_slope"
const HARVEST_WEST := &"harvest_west"
const LEAVE_ROOT := &"leave_root"
const UPROOT := &"uproot"

@export var herb: ItemDefinition
@export var herb_slope: MapDefinition

func get_trigger_ids() -> Array[StringName]:
    return [TALK_SHOPKEEPER, ENTER_SLOPE, HARVEST_WEST]

func run(trigger_id: StringName, story: StoryContext) -> void:
    match trigger_id:
        TALK_SHOPKEEPER:
            await _talk_shopkeeper(story)
        HARVEST_WEST:
            await _harvest_west(story)

func _talk_shopkeeper(story: StoryContext) -> void:
    var result := await story.show_dialogue(dialogue, &"route_choice")
    if result.selected_option_id == &"safe_route":
        story.set_stage(self, &"trip_one_midday")
        story.travel_to(herb_slope, &"safe_entry")
        return

func _harvest_west(story: StoryContext) -> void:
    var result := await story.show_dialogue(dialogue, &"harvest_choice")
    if result.selected_option_id not in [LEAVE_ROOT, UPROOT]:
        return
    var quantity := 1 if result.selected_option_id == LEAVE_ROOT else 2
    var reward := story.give_item(herb, quantity)
    if not reward.succeeded():
        return
    if result.selected_option_id == UPROOT:
        story.complete_source_entity()
```

正式实现的 `gathering.tres` 设置 `story.roadside.gathering`、两趟有限时段 stage、
`dialogue.roadside.gathering`、返青草和药草坡依赖。小铺店主、药草坡 entry 与三处药丛
使用不同 trigger，但都由同一模块负责；路线随机、原子交付和第二趟表现通过公共 API 与
明确 flag/WorldState 完成。

### StoryBinding

```gdscript
class_name StoryBinding
extends Resource

@export var event: StoryEvent
@export var trigger_id: StringName = &"default"
```

StoryBinding 默认嵌入 `.tscn`，不会产生单独文件。复杂故事引用外部 StoryModule；简单事件把内置 StoryEvent 也嵌入 binding。

### 创作规则

- 内容依赖使用 `@export` 类型化 Resource。
- 控制流使用正常 GDScript。
- 地图实体使用语义 ID，不保存 Node 引用到 GameRun。
- 不直接访问 `/root`、SceneStack、内部 Service 或 GameRun 集合。
- 不在 StoryModule 中实现通用背包、商店或战斗规则。
- `travel_to()` 后立即 `return`，不得继续调用 StoryContext。
- stage 表达故事主进度，彼此独立的线索和世界事实使用 flag。
- 按叙事职责拆分模块；不要按每个 NPC、地图或固定 trigger 数量拆分。
- StoryModule `.tres` 保持只读，所有进度进入 GameRun StoryState/GameFlags。

## 14. 常用 StoryEvent

所有常用零代码事件直接继承 StoryEvent，并实现同一个 trigger 接口；它们通常以 SubResource 嵌入地图场景。

### DialogueEvent

字段：DialogueDefinition、block ID、可选一次性 flag。交互时显示指定 block。

### ShopEvent

字段：欢迎对话、ShopDefinition、结束对话。通过 StoryContext 打开商店。

### TreasureChestEvent

字段：ItemDefinition、数量、打开动画、空箱对话。persistent ID 来自 StoryOrigin；固定使用 `ALL_OR_NOTHING`，Reward 完整成功后才调用来源完成语义并显示打开状态。

### ItemPickupEvent

字段：ItemDefinition、数量、RewardPolicy。persistent ID 来自 StoryOrigin；默认 `ALL_OR_NOTHING`，获得完整成功后完成并隐藏实例。选择 `ALLOW_PARTIAL` 时，事件自身必须把剩余数量保存到 PersistentEntity state，剩余数量为零后才能完成来源。

### BattleTriggerEvent

字段：BattleEncounter、触发方式、胜利/失败 flag、Defeat 返回地图和 spawn。persistent ID 来自 StoryOrigin；Victory 时完成来源，Escaped 时保持来源可再次触发，Defeat 时恢复队伍并 terminal travel 到配置的安全位置。需要任务 stage、特殊奖励或其他战败流程时使用 StoryModule，不继续扩展 BattleTriggerEvent 字段。

### ScenePortalEvent

字段：MapDefinition、spawn ID、可选过渡样式。通常直接把它嵌入 StoryBinding，不需要自定义脚本。

多步和分支需求加入对应 StoryModule。不要增加包装 Handler，也不要扩展成万能事件数组。

## 15. NPC 和地图创作

### NPC

1. 创建独立 NpcDefinition `.tres`，配置语义 ID 与 `field_model_3d`。
2. 在 MapGameScene3D 的 WorldRoot 下实例化标准 NpcCharacter3D wrapper。
3. 选择 NpcDefinition，并让 StoryInteractable3D 的 actor definition ID 与之保持一致。
4. 需要持久化时设置 map-local persistent ID；普通对话 NPC 可以不设置。
5. 添加内嵌简单 StoryBinding，或引用一个 StoryModule 并选择 trigger ID。
6. 运行 content 与 map validator。

### 地图

1. 组合 `roadside_map_3d_base.tscn`，并创建对应 MapDefinition。
2. 创建 schema v2 MapGenerationProfile/Biome，配置地面模块、环境 PackedScene 和人工 anchor。
3. 添加带语义 ID 的 Marker3D spawn、Portal、StoryMarker 与剧情来源。
4. 放置 NPC、Portal、宝箱和 StoryBinding；需要时按确定顺序配置 MapGameScene `entry_bindings`。
5. 在 MapDefinition 引用 MapGameScene。
6. 运行 map validator 和场景 smoke test。

程序生成地图在步骤 2 前建立类型化 MapGenerationProfile/Biome 和人工 anchor，然后通过
Preview/Bake 生成 Ground、Detail、环境物件与边界。生成物件没有 persistent ID 或
StoryBinding；作者在 baked scene 上完成 NPC、剧情和演出。重新生成只允许清理带
`map_generator_owned` 元数据的内容，不允许按节点名字猜测归属。

新增地图不得修改共享 `map_game_scene_3d.gd` 来添加地图 ID、模块或坐标分支。只有真正跨地图
的生命周期行为进入公共骨架；几何、GridMap、导航、碰撞、实体和绑定留在具体地图场景。

## 16. 当前正式片段：北坡采药

当前正式内容登记一个原创角色、一个 NPC、两种物品、两种技能、一种状态、两种敌人、
一个有限遭遇、四张地图和两个 StoryModule。

### 玩家流程

1. 玩家从标题页进入 `map.roadside.north_slope_wilds`，沿人工 Portal 到达小铺。
2. 在 `map.roadside.shop` 向店主接下采药差事。
3. 选择稳妥旧路或带种子随机风险的碎石近坡，travel 到 `map.roadside.herb_slope`。
4. 三处药草分别选择割叶留根一份或连根挖走两份，每次动作推进有限时段 stage。
5. 回到店主处原子交付两份材料；按时十二文，入夜六文。
6. 第二趟开始后，留根药丛重新可采，连根来源继续由 WorldState 保持完成。
7. 菜单和存档保持精确位置、库存、工钱、剧情、地图来源和随机源推进位置。

### 内容和绑定

```text
game/roadside/stories/gathering.gd
game/roadside/stories/gathering.tres
game/roadside/stories/gathering_dialogue.tres
content/actors/traveler.tres
content/items/fanqing_grass.tres
content/maps/north_slope_wilds.tres
content/maps/roadside_shop.tres
content/maps/herb_slope.tres
content/npcs/roadside_shopkeeper.tres
game/roadside/action_combat_3d/maps/north_slope_wilds_3d.tscn
game/roadside/action_combat_3d/maps/roadside_shop_3d.tscn
game/roadside/action_combat_3d/maps/herb_slope_3d.tscn
game/roadside/action_combat_3d/maps/north_slope_pack.tscn
assets/original/3d/              # 原创 GLB、材质、生成源、manifest 与标题派生图
```

| 地图对象 | StoryBinding |
|---|---|
| 北坡原野小铺入口 | `ScenePortalEvent / map.roadside.shop / default` |
| 店主 | `story.roadside.gathering / talk_shopkeeper` |
| 药草坡 entry | `story.roadside.gathering / enter_herb_slope` |
| 三处返青草 | `story.roadside.gathering / harvest_west / harvest_centre / harvest_east` |
| 回程围栏 | `ScenePortalEvent / map.roadside.shop / from_slope` |

StoryState 只保存主进度与离散时段；每趟每处是否采过使用布尔 flag，连根造成的永久完成态
只写当前 StoryOrigin 的 WorldState，不开放任意实体状态接口。

### 验收边界

- 人工验收：检查固定正交镜头、3D 角色/NPC、选项布局、战斗前摇/投射物，以及药草完整/割后/再生/消失状态。
- 自动场景测试：验证四张地图、默认入口、完整两趟轨迹、实时战斗三种结果、随机分支、原子交付、菜单和存档。
- 普通 CI：只使用仓库维护的 `assets/original/`。
- 非当前内容：随机词缀、无限刷怪、队友战斗 AI 与装备外观组合。

## 17. 剧情测试

FakeStoryContext 实现同一公共 API，但不加载 UI、地图和战斗：

- 记录 dialogue/block、奖励、标记、来源实体完成、移动和 pending travel。
- 由测试预设 DialogueResult、ShopResult、BattleResult、DeliveryResult 和随机抽取结果。
- 输出结构化轨迹。
- 按 StoryModule 的 trigger、关键 stage、选项、Victory/Escaped/Defeat 和奖励接受/拒绝建立测试矩阵。

当前采集 StoryModule 的测试轨迹类似：

```text
SHOW_DIALOGUE dialogue.roadside.gathering route_choice
ROLL_PERCENT 50 true
SET_STORY_STAGE story.roadside.gathering trip_one_early
GIVE_ITEM item.roadside.fanqing_grass 1
COMPLETE_SOURCE_ENTITY map.roadside.herb_slope herb_patch.centre
```

轨迹只用于测试和诊断，不是运行时指令格式，也不能作为剧情存储格式。

当前固定测试覆盖：四张正式 3D 地图、模型注入、碰撞、导航、DialogueOption、完整两趟
StoryModule、路径成功/失足、两种采法、两档工钱、地图表现、菜单和存档往返。

## 18. 校验规则

### 通用

- ID 格式、唯一性和文件名约定。
- 必填字段、类型、引用和数值范围。
- ContentDatabase 中登记的 ID 唯一且引用有效。

### RPG 数据

- Item/Skill Effect 目标兼容。
- 装备槽和限制合法。
- ShopEntry 不重复且价格合法。
- Encounter 至少有一个敌人，站位和标签唯一。
- Enemy AI 引用的技能可用。

### 地图和剧情

- MapDefinition 与 Scene 匹配。
- spawn、persistent entity、actor 和 marker ID 唯一。
- Portal 目标地图和 spawn 存在。
- StoryBinding 的 event 非空，trigger 存在于 event.get_trigger_ids()。
- StoryModule ID 全局唯一，initial stage 属于 valid stages，stage 和 trigger 不重复。
- Dialogue block ID 和同一 block 内 option ID 唯一。
- 地图 entry bindings 顺序稳定，只在地图初始化完成后运行，目标地图和 spawn 合法。
- StoryEvent/StoryModule 导出依赖完整，简单一次性事件和调用来源完成 API 的 binding 具有有效 persistent StoryOrigin 来源。
- RewardPolicy 与配置型事件兼容；宝箱固定 `ALL_OR_NOTHING`，部分拾取必须能够保存剩余数量。StoryModule 的任务奖励原子性由 story test 覆盖。
- MapGenerationProfile 的 Tile/Prop/anchor 引用合法；固定 seed 计划完整，所有 gameplay
  anchor 可达，阻挡 footprint 不覆盖道路/保护区，生成节点不包含 Interactable。
- 禁止绝对 `/root` 路径和列入黑名单的内部 API。

## 19. API 版本和迁移

- StoryContext 维护公开 API 版本。
- 方法重命名先提供弃用期和自动迁移脚本。
- Content schema 变更提升 schema version；引入 JSON round-trip 后再提供对应迁移。
- save、content schema 与派生 catalog 分别版本化；`rename-id` 迁移记录还会在 SaveService 加载旧槽时精确迁移序列化内容 ID，再执行完整内容校验。
- CLI JSON 契约变化记录在 changelog，避免无意义字段重排。
