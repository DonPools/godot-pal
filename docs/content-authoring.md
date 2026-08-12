# 内容创作与设计师 API

## 1. 目标

内容创作系统同时服务使用 Godot 编辑器的人类设计师、通过代码和命令行工作的 AI Agent，以及维护底层系统的程序开发者。

三者使用同一套 Resource、语义 ID、StoryContext 和校验规则。入口包括 Inspector、PAL Database Dock、Dock 内 Dialogue Editor、文本 GDScript 和稳定 JSON CLI；所有工具直接操作原始 Resource 或其派生目录。

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
| 地图、NPC、交互物 | 2D 场景编辑器 | `.tscn` + scene validator | PackedScene/Node |
| 对话 | Inspector + Dialogue Editor | `.tres` + validate/apply-json | DialogueDefinition/DialogueBlock |
| 简单交互 | Inspector 内嵌资源 | `.tscn` 配置和模板 | StoryBinding + 内置 StoryEvent |
| 复杂剧情 | GDScript + Inspector | Story API + FakeStoryContext | StoryModule Resource |
| 内容索引 | ContentDatabase + 派生 Dock | catalog/list/show/schema/refs | ContentDatabase 与原始 Resource |

## 3. 内容目录

```text
content/
├── content_database.tres
└── maps/
    ├── inn_hall.tres
    └── rain_courtyard.tres

scenes/
├── maps/
│   ├── map_game_scene_base.tscn
│   ├── inn_hall.tscn
│   ├── rain_courtyard.tscn
│   └── tilesets/
│       ├── inn_hall_tileset.tres
│       └── rain_courtyard_tileset.tres
├── actors/
├── npcs/
├── interactions/
├── props/
└── ui/

stories/lab/
├── borrowed_umbrella.gd
├── borrowed_umbrella.tres
└── dialogue.tres
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
actor.li_xiaoyao
actor.zhao_linger
item.po_tian_hammer
skill.ice_heart
status.poison
enemy.miao_warrior
map.lab.inn_hall
map.lab.rain_courtyard
dialogue.lab.borrowed_umbrella
story.lab.borrowed_umbrella
flag.story.lab.borrowed_umbrella.courtyard_seen
entity.lab.rain_courtyard.old_umbrella
spawn.lab.inn_hall.start
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

- portrait、field character scene、battle character scene。
- 基础属性、成长曲线和装备槽。
- 初始装备和初始技能。

ActorDefinition 是角色模板；等级、经验、HP/MP、装备和已学技能属于 ActorState。

### ItemDefinition

- icon、category、price 和 max stack。
- field/battle 可用范围和 target rule。
- `Array[GameEffect]`。
- 可选 EquipmentDefinition。

ItemCategory 至少包含 Consumable、Equipment、KeyItem 和 Material。剧情物品是否可出售或丢弃使用明确字段，不通过价格或 ID 推断。

### SkillDefinition

- icon、资源消耗、target rule 和使用范围。
- `Array[GameEffect]`。
- animation scene 和 sound。

技能的数值和效果数据化；复杂表现使用 PackedScene/AnimationPlayer，不在 Effect 中操作 UI。

### EnemyDefinition

- battle character scene、基础属性和抗性。
- 技能列表和 AI strategy。
- 经验、金钱和掉落。

常用 AI 使用少量可配置 Strategy Resource；独特 Boss 使用显式 GDScript Strategy，不建立通用行为表达式语言。

### StatusDefinition

当前由断桥冷雨内容证明的有限 schema 包含持续回合与周期伤害。`ChillStrikeStrategy` 通过明确 `EnemyAction` 应用状态，BattleSession 在玩家回合开始结算并发出结构化 BattleEvent；状态只属于本场战斗，不进入 GameRun。

叠加规则、属性修正、图标和更丰富生命周期钩子在真实内容需要时增加。状态始终只影响战斗机械，不触发剧情。

### NpcDefinition

- portrait、field character scene 和默认动画。
- 默认移动配置和 tag。

NpcDefinition 描述可复用身份和表现。位置、persistent ID、交互和章节状态属于地图实例。

### ShopDefinition

- `Array[ShopEntry]`。
- 买价和卖价策略。
- 是否允许卖出。

ShopEntry 类型化引用 ItemDefinition，并可配置价格覆盖和库存。

### BattleEncounter

- `Array[EncounterEnemy]`。
- 背景、音乐、逃跑规则和奖励策略。

EncounterEnemy 引用 EnemyDefinition，并配置站位、等级修正和可选实例标签。

### DialogueDefinition

- `Array[DialogueBlock]`。
- 默认窗口样式。

DialogueBlock 包含稳定 block ID 和有序 `Array[DialogueEntry]`。DialogueEntry 包含说话人、UTF-8 文本、头像覆盖、文本速度和可选静态选项；每个选项拥有稳定 option ID。

同一故事的多个谈话片段优先放在一个 DialogueDefinition 的命名 block 中，避免为每次 NPC 对话创建小文件。短对话可以把 DialogueDefinition 嵌入 StoryModule `.tres`，对白较多时再独立为 `dialogue.tres`。使用有序 Array 而不是大型 Dictionary，保证 Inspector 顺序、稳定序列化和逐项校验。

DialogueDefinition 只表达谈话和选择，不执行奖励、战斗、flag 或地图切换；DialogueResult 返回 option ID，由 StoryModule 决定后果。

### MapDefinition

- map scene、default spawn ID、音乐和区域 tag。

地图几何、TileMap、NPC 和触发器在具体 `.tscn` 中编辑；MapDefinition 提供数据库入口。具体地图继承一层 `map_game_scene_base.tscn` 复用玩家、YSort、通用图层、spawn 容器和 HUD，不复制公共骨架，也不在共享脚本中按地图 ID 生成布局。

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

StoryModule 和只被故事直接引用的私有 DialogueDefinition 不强制登记到手写 ContentDatabase。它们以 `.tres`、地图 StoryBinding 和 `stories/` 目录为真相来源，由 validator 扫描检查。这样创建故事不需要同时修改一个全局注册文件。

当前 ContentCatalog 在需要时从手写 ContentDatabase 与 `stories/` 扫描结果确定性构建，覆盖 11 类内容。它只驻留内存或作为带 `catalog_version` 的 JSON 导出，不生成需要维护的索引 Resource，因此不是第二份内容真相来源。

## 9. 人类设计师工作流

### Inspector 与 PAL Database Dock

1. 从文件系统创建指定 Resource 类型。
2. 填写 ID、显示字段、图像和规则。
3. 运行 Validate Content。
4. 在地图或其他 Definition 中通过类型化 Resource picker 引用。
5. 在 `PAL Database` Dock 按类型浏览目录、查看反向引用，或把 Resource 打开到 Inspector。
6. 对 DialogueDefinition，可在 Dock 内选择 block/entry、预览、修改说话人与正文并保存；保存目标仍是原 `.tres`。

## 10. AI Agent CLI

当前 CLI 以 Godot headless 直接扫描和校验同一 Resource：

```sh
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
```

它检查素材 manifest、当前 ContentDatabase 中的地图、TileSet/cell、spawn、persistent ID、portal 目标、`stories/` 中全部 StoryModule/DialogueDefinition，以及地图中导出的 StoryBinding。`--json` 保留 `ok/error_count/errors`，并提供带 code、message、file、field 和可选 content_id/source 的 `diagnostics`；成功返回 0，内容错误返回 1，命令用法错误返回 2，写文件失败返回 3。

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

- `catalog/list/show` 查询 ContentDatabase 中登记的 RPG Definition，以及 `stories/` 扫描到的 Dialogue/Story。
- `schema` 返回 11 类内容的字段、默认值、ID 前缀和 create 必需选项。
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
func confirm(prompt: DialogueDefinition) -> bool
```

### 商店与战斗

```gdscript
func open_shop(shop: ShopDefinition) -> ShopResult
func start_battle(encounter: BattleEncounter) -> BattleResult
```

### 奖励和队伍

```gdscript
func give_item(
    item: ItemDefinition,
    quantity: int = 1,
    policy: RewardPolicy = RewardPolicy.ALL_OR_NOTHING
) -> RewardResult
func take_item(item: ItemDefinition, quantity: int = 1) -> RewardResult
func give_money(amount: int) -> void
func take_money(amount: int) -> bool
func add_party_member(actor: ActorDefinition) -> bool
func remove_party_member(actor: ActorDefinition) -> bool
func restore_party() -> void
```

`RewardPolicy.ALL_OR_NOTHING` 是任务奖励和宝箱的默认策略：背包无法容纳全部数量时完全不修改 InventoryState。`RewardPolicy.ALLOW_PARTIAL` 只能由允许部分拾取的内容显式选择；调用方必须处理 changed/rejected quantity，不能在仍有 rejected quantity 时完成来源实体。

这些高层操作可以显示提示，因此调用方统一允许 `await`。底层纯领域 API 保持同步。

### 查询和标记

```gdscript
func has_item(item: ItemDefinition, quantity: int = 1) -> bool
func is_flag_set(flag_id: StringName) -> bool
func get_flag(flag_id: StringName, default_value: Variant = null) -> Variant
func set_flag(flag_id: StringName, value: Variant = true) -> void
func clear_flag(flag_id: StringName) -> void
func get_stage(module: StoryModule) -> StringName
func set_stage(module: StoryModule, stage_id: StringName) -> void
```

StoryModule 内部通常写成 `story.get_stage(self)` 和 `story.set_stage(self, &"completed")`。StoryContext 从 module.id 访问 StoryState，并在设置阶段前验证 stage 属于 module.valid_stages，设计师不重复输入 story ID。

故事需要地图 HUD 目标提示时，可以覆盖同步、无副作用的 `get_objective_text(stage_id, map_id)`。目标文本属于 StoryModule 的叙事表现，不写进通用 MapGameScene；没有目标时返回空字符串，地图显示通用操作提示。

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

首期只定义四种会影响剧情分支的结果：

```text
DialogueResult: selected_option_id, skipped
ShopResult: purchases, sales, money_delta
BattleResult: outcome, committed_rewards, rounds, state_changes
RewardResult: item_id, requested_quantity, changed_quantity, rejected_quantity
```

BattleResult 的 outcome 提交规则固定为：Victory 提交 HP/MP、物品消耗、经验、金钱和掉落；Escaped 只提交 HP/MP 和物品消耗；Defeat 同样提交 HP/MP 和物品消耗，但调用方必须在恢复玩家控制前恢复/转移队伍或进入明确失败流程。BattleEncounter 奖励只在 Victory 结算，StoryModule 的任务奖励另行显式发放。

RewardResult 的失败原因使用枚举，例如 InsufficientQuantity、InventoryFull，而不是需要解析的文本。`ALL_OR_NOTHING` 失败时 changed quantity 为 0、rejected quantity 等于 requested quantity；`ALLOW_PARTIAL` 才允许两者同时非零。其他操作等真实分支需求出现后再增加结果类型。

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
class_name BorrowedUmbrellaStory
extends StoryModule

const ENTER_HALL := &"enter_hall"
const TALK_INNKEEPER := &"talk_innkeeper"
const TALK_GUEST := &"talk_guest"
const ENTER_COURTYARD := &"enter_courtyard"
const TALK_TRAVELER := &"talk_traveler"
const TAKE_UMBRELLA := &"take_umbrella"
const COURTYARD_SEEN := &"flag.story.lab.borrowed_umbrella.courtyard_seen"

func get_trigger_ids() -> Array[StringName]:
    return [
        ENTER_HALL,
        TALK_INNKEEPER,
        TALK_GUEST,
        ENTER_COURTYARD,
        TALK_TRAVELER,
        TAKE_UMBRELLA,
    ]

func run(trigger_id: StringName, story: StoryContext) -> void:
    match trigger_id:
        ENTER_HALL:
            await _enter_hall(story)
        TALK_INNKEEPER:
            await _talk_innkeeper(story)
        TALK_GUEST:
            await story.show_dialogue(dialogue, &"quiet_guest")
        ENTER_COURTYARD:
            await _enter_courtyard(story)
        TALK_TRAVELER:
            await _talk_traveler(story)
        TAKE_UMBRELLA:
            await _take_umbrella(story)

func _enter_hall(story: StoryContext) -> void:
    if story.get_stage(self) != &"not_started":
        return
    await story.show_dialogue(dialogue, &"opening")
    story.set_stage(self, &"met_innkeeper")

func _talk_innkeeper(story: StoryContext) -> void:
    if story.get_stage(self) in [&"not_started", &"met_innkeeper"]:
        await story.show_dialogue(dialogue, &"innkeeper_request")
        story.set_stage(self, &"looking_for_owner")

func _enter_courtyard(story: StoryContext) -> void:
    if story.get_stage(self) == &"looking_for_owner" and not story.is_flag_set(COURTYARD_SEEN):
        await story.show_dialogue(dialogue, &"courtyard_first")
        story.set_flag(COURTYARD_SEEN)

func _talk_traveler(story: StoryContext) -> void:
    if story.get_stage(self) == &"looking_for_owner":
        await story.show_dialogue(dialogue, &"traveler_reveal")
        story.set_stage(self, &"owner_found")

func _take_umbrella(story: StoryContext) -> void:
    if story.get_stage(self) != &"owner_found":
        return
    await story.show_dialogue(dialogue, &"umbrella_take")
    story.complete_source_entity()
    story.set_stage(self, &"umbrella_found")
```

配套 `borrowed_umbrella.tres` 设置 `story.lab.borrowed_umbrella`、六个有效 stage 和 `dialogue.lab.borrowed_umbrella`。两张地图的 entry、NPC 和旧伞 StoryBinding 都引用同一个模块，并分别选择 trigger ID；这个故事由项目原创，不从原版脚本或事件自动翻译。

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

1. 在 MapGameScene 的 YSortRoot 下实例化标准 NpcCharacter Scene。
2. 选择 NpcDefinition。
3. 设置 map-local persistent ID。
4. 选择移动组件，例如静止、巡逻或随机走动。
5. 添加内嵌简单 StoryBinding，或引用一个 StoryModule 并选择 trigger ID。
6. 运行 map validator。

### 地图

1. 从 `map_game_scene_base.tscn` 创建一层继承场景，并创建对应 MapDefinition。
2. 创建引用 `generated/` atlas 的 TileSet，在具体地图的 TileMapLayer 中绘制并保存布局。
3. 添加带语义 ID 的 SpawnPoint/StoryMarker。
4. 放置 NPC、Portal、宝箱和 StoryBinding；需要时按确定顺序配置 MapGameScene `entry_bindings`。
5. 在 MapDefinition 引用 MapGameScene。
6. 运行 map validator 和场景 smoke test。

新增地图不得修改共享 `map_game_scene.gd` 来添加地图 ID、Tile frame 或坐标分支。只有真正跨地图的生命周期行为进入公共骨架；几何、TileSet、碰撞、实体和绑定留在具体地图场景。

## 16. 首个框架验证片段：《借来的伞》

第一版使用本地提取的现有视觉与音频素材组装两张原创地图，不为了覆盖系统清单增加商店、背包或战斗。后续能力必须在选定真正需要它们的内容时再形成验收。

### 玩家流程

1. `framework-lab` 导出 Tile、角色/NPC 图集、头像、UI、BMFont、音乐与音效。
2. 玩家进入 `map.lab.inn_hall`，从掌柜处接到寻找旧伞主人的请求，通过 portal 前往 `map.lab.rain_courtyard`。
3. 雨院 entry、蓑衣客和井边旧伞与同一个 `BorrowedUmbrellaStory` 交互；取得旧伞后返回前厅交付。
4. 对话、地图替换、音频和输入锁遵守 StoryContext/GameSceneStack 边界；重复交互不会重复推进一次性效果。
5. 重新实例化地图或执行测试性存档往返后，玩家位置、story stage、flags 和旧伞完成态恢复一致。

### 内容和绑定

```text
stories/lab/borrowed_umbrella.gd
stories/lab/borrowed_umbrella.tres
stories/lab/dialogue.tres

content/maps/inn_hall.tres
content/maps/rain_courtyard.tres

scenes/maps/inn_hall.tscn
scenes/maps/rain_courtyard.tscn
generated/                       # 工程与普通 CI 的必需素材
```

| 地图对象 | StoryBinding |
|---|---|
| 前厅 entry | `BorrowedUmbrellaStory / enter_hall` |
| 掌柜实例 | `BorrowedUmbrellaStory / talk_innkeeper` |
| 安静客人实例 | `BorrowedUmbrellaStory / talk_guest` |
| 雨院 entry | `BorrowedUmbrellaStory / enter_courtyard` |
| 蓑衣客实例 | `BorrowedUmbrellaStory / talk_traveler` |
| 旧伞实例 | `BorrowedUmbrellaStory / take_umbrella` |

StoryModule 使用 `not_started/met_innkeeper/looking_for_owner/owner_found/umbrella_found/completed`。旧伞绑定提供 map-local persistent ID `old_umbrella`；剧情和 Dialogue block 由项目维护，不从 SSS/M.MSG 自动生成，也不把原版事件编号当作 trigger ID。

### 验收边界

- 本地人工验收：使用提取素材检查两张原创地图的 Tile、角色帧、透明、YSort、字体、窗口、音乐和音效。
- 自动场景测试：走完接任务、切到雨院、认领与拾取旧伞、切回前厅和交付，并验证输入锁、一次性来源和存档。
- FakeStoryContext：验证关键 trigger、stage、flag、对话块和来源完成轨迹。
- 普通 CI：使用仓库维护的 `generated/` 输出验证同一代码路径，不读取原版输入数据。
- 非当前范围：战斗、商店、完整背包和完整存档 UI；这些能力仍保留在总体架构中，但不阻塞当前验证。

## 17. 剧情测试

FakeStoryContext 实现同一公共 API，但不加载 UI、地图和战斗：

- 记录 dialogue/block、奖励、标记、来源实体完成、移动和 pending travel。
- 由测试预设 DialogueResult、ShopResult 和 BattleResult。
- 输出结构化轨迹。
- 按 StoryModule 的 trigger、关键 stage、选项、Victory/Escaped/Defeat 和奖励接受/拒绝建立测试矩阵。

《借来的伞》的主路径轨迹：

```text
SHOW_DIALOGUE dialogue.lab.borrowed_umbrella opening
SET_STORY_STAGE story.lab.borrowed_umbrella met_innkeeper
SHOW_DIALOGUE dialogue.lab.borrowed_umbrella innkeeper_request
SET_STORY_STAGE story.lab.borrowed_umbrella looking_for_owner
SET_FLAG flag.story.lab.borrowed_umbrella.courtyard_seen
SHOW_DIALOGUE dialogue.lab.borrowed_umbrella traveler_reveal
SET_STORY_STAGE story.lab.borrowed_umbrella owner_found
SHOW_DIALOGUE dialogue.lab.borrowed_umbrella umbrella_take
COMPLETE_SOURCE_ENTITY map.lab.rain_courtyard old_umbrella
SET_STORY_STAGE story.lab.borrowed_umbrella umbrella_found
SHOW_DIALOGUE dialogue.lab.borrowed_umbrella innkeeper_finish
SET_STORY_STAGE story.lab.borrowed_umbrella completed
```

轨迹只用于测试和诊断，不是运行时指令格式，也不能作为剧情存储格式。

固定测试至少覆盖：首次与重复进入两张地图、各关键 stage 下与掌柜/蓑衣客/旧伞交互、对话期间输入锁、未知 trigger 诊断、地图替换、来源完成，以及玩家位置、StoryState、GameFlags 和 WorldState 的存档往返。BattleResult 与奖励拒绝属于后续选中对应内容后的独立测试矩阵。

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
- 禁止绝对 `/root` 路径和列入黑名单的内部 API。

## 19. API 版本和迁移

- StoryContext 维护公开 API 版本。
- 方法重命名先提供弃用期和自动迁移脚本。
- Content schema 变更提升 schema version；引入 JSON round-trip 后再提供对应迁移。
- save、content schema 与派生 catalog 分别版本化；`rename-id` 迁移记录还会在 SaveService 加载旧槽时精确迁移序列化内容 ID，再执行完整内容校验。
- CLI JSON 契约变化记录在 changelog，避免无意义字段重排。
