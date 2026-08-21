# 背包、装备与简单技能系统实施计划

> 状态：已完成（2026-08-21）。IES-0 至 IES-5 的状态、事务、战斗、菜单、内容、迁移、测试和
> 文档均已落地；本文同时保留实施前问题、冻结契约与退出门，作为后续回归依据。

## 1. 背景与目标

实施前的纵向切片已经证明了物品数量、原子奖励、野外使用、战斗丹药、单槽法器、装备流派、三个
主动技能、真气、冷却和 v5 存读档。缺口主要不是战斗公式，而是三个系统之间的长期状态语义和
玩家配置入口。实施前缺口为：

- 行囊只有一张混合列表，无法清楚区分消耗品、法器、关键物与材料。
- 战斗物品快捷键隐式使用行囊中第一个可战斗使用的物品，玩家不能确认或配置。
- `ActorState.skill_ids` 同时表示“已经学会”和“三个快捷槽的顺序”，无法支持第四个技能。
- 装备事务可以替换法器，但不能显式卸下，也没有校验角色实际允许的槽位。
- HUD 的三个技能图标按槽位硬编码；一旦允许换技能，图标和技能含义会错位。
- `BattleSession` 检查技能是否可用于战斗，却不检查技能是否属于当前角色的战斗配置。

本计划的目标是建立一个传统单机 RPG 所需的最小闭环：

```text
获得物品 / 学会技能
  -> 在菜单中查看、使用、装备或配置
  -> GameRun 保存语义 ID 与数量
  -> 进入战斗时生成只读战斗配置
  -> BattleSession 校验并执行技能或快捷物品
  -> 退出战斗后只提交允许持久化的结果
```

玩家完成当前五张地图时，应当能够：

- 按分类查看行囊、物品说明、数量、容量和使用限制。
- 在地图菜单中使用消耗品、配置一项战斗快捷物品，并看到明确失败原因。
- 查看当前法器及属性变化，原子装备、替换或卸下法器。
- 查看全部已学技能，把任意三个战斗技能配置到动作栏。
- 保存、读取并恢复装备、已学技能、技能槽与快捷物品。
- 在战斗中只能使用开战时已经配置且合法的技能和物品。

## 2. 非目标

本轮明确不加入：

- 随机词缀、装备品质、强化、镶嵌、耐久、套装和装备掉落光柱。
- 同一 `EquipmentDefinition` 的独立实例、随机数值或实例 UID。
- 技能树、技能点、技能等级、洗点、符文、连招编辑器和被动技能槽。
- 战斗中更换装备、技能或快捷物品。
- 队友战斗 AI、多人同时操作、自动配装和自动技能推荐。
- 重量、物品格旋转、多个同 ID 物品堆栈实例和仓库系统。
- 用标签或脚本表达任意装备条件、技能公式或效果表达式语言。
- 为菜单引入新的 Manager、全局 EventBus、Autoload 或 SubViewport。
- 在没有实际内容前扩展 Revive、长期 Status、ModifyStat 等新 `GameEffect`。

## 3. 已定设计决策

### 3.1 背包模型

- `InventoryState` 继续只保存有序 `item_id -> quantity`，不保存 Resource 或物品实例。
- 一个物品 ID 在行囊中只显示一行；`max_stack` 是该 ID 在行囊中的总数量上限。
- 普通容量按不同物品 ID 计数，不按总件数计数。
- `KEY_ITEM` 不占普通容量，但仍遵守自身 `max_stack`；分类只从 `ItemDefinition` 派生，不写入存档。
- 当前 `max_distinct_items = 12` 继续作为普通容量默认值。是否增加容量属于内容和平衡调整，
  不改变本轮数据结构。
- 获取顺序继续是默认顺序；分类筛选不改写获取顺序。
- 空间不足、超过堆叠上限和非法数量继续返回 `RewardResult`，默认奖励保持
  `ALL_OR_NOTHING`。

实现关键点：`InventoryState` 不长期持有 `ContentDatabase`。运行时可维护“是否占容量”的派生缓存，
`restore` 在提供数据库时从物品分类重建；存档仍只写 ID、数量、顺序和容量。数据库不可用时使用
保守策略，把未知条目视为占容量，最终仍由 `ContentDatabase.validate_game_run()` 报告未知 ID。

### 3.2 物品动作

第一版支持四种玩家动作：

| 物品类型 | 菜单动作 | 战斗动作 |
|---|---|---|
| Consumable | 使用、设为快捷物品、允许时丢弃 | 仅能使用已配置快捷物品 |
| Equipment | 装备、允许时丢弃 | 不能在战斗中更换 |
| KeyItem | 只读查看 | 由领域事务或 StoryContext 消耗 |
| Material | 只读查看、允许时丢弃 | 不能直接使用 |

`ItemDefinition` 增加明确的 `icon`、`can_discard` 和 `can_sell`。本轮菜单实现丢弃确认；卖出字段进入
schema 和 validator，但卖出事务与商店卖出页等真实商店内容需要时再实现，不能通过 `price > 0`
推断可出售。

丢弃使用独立的原子事务和类型化结果，不让菜单直接调用 `remove_item()`。关键物默认不可丢弃；
剧情内容如需例外，必须在对应定义中明确配置并通过内容校验。

### 3.3 装备模型

- `ActorState.equipment: Dictionary[StringName, StringName]` 保持不变。
- 当前正式内容只开放 `weapon` 一个存档槽位，UI 对玩家显示为“法器”。
- `ActorDefinition` 增加有序 `equipment_slots`，当前旅人配置 `[&"weapon"]`。
- `EquipmentDefinition.slot` 必须属于目标角色的 `equipment_slots`。
- 装备中的物品不同时存在于行囊；换下或卸下后完整返回行囊。
- 换装和卸装都必须原子完成。旧法器无法返回行囊时，角色状态和行囊都不变化。
- 增加最大 HP/MP 的装备不免费补充当前 HP/MP；降低上限时把当前值截断到新上限。
- 数值加成继续由 `CultivationRules` 聚合；特殊战斗机制继续通过有限的
  `BattleBuildModifier -> BattleBuildSnapshot` 进入本场战斗。

本轮不加入角色 ID、境界、性别、门派或标签限制。槽位合法性已经覆盖当前内容的真实限制；更多
限制必须由新装备内容证明需要后，再增加明确类型化字段。

### 3.4 技能模型

`ActorState.skill_ids` 拆分为两个不同概念：

```text
learned_skill_ids: Array[StringName]
battle_skill_ids: Array[StringName]  # 固定三个位置，空位置保存空 StringName
```

规则如下：

- `learned_skill_ids` 按学习顺序保存全部已学技能，不允许重复。
- `battle_skill_ids` 固定恰好三个位置，对应现有三个输入动作。
- 只能把已学、已登记且 `usable_in_battle` 的技能放入战斗槽。
- 同一技能不能同时占据两个槽。
- 把已经配置的技能放到新槽时，旧槽自动清空；目标槽原技能只被移出快捷栏，不会遗忘。
- 新学技能自动填入第一个空槽；三个槽都满时只加入已学列表，不替换玩家配置。
- 冷却、动作阶段和战斗 Status 继续只存在于 `BattleActorState`，不进入 `GameRun` 或存档。
- `SkillDefinition` 增加数据驱动 `icon`；HUD 不再按第几个槽选择固定图标。

学习技能、配置技能槽和清空技能槽都通过领域事务；筑基事务不得再直接向数组 `append()`。

### 3.5 战斗快捷物品

`ActorState` 增加：

```text
battle_item_id: StringName
```

- 配置时要求物品已登记、`usable_in_battle`、当前至少持有一件。
- 使用完最后一件后仍保留该 ID，HUD 显示数量为零；再次获得后无需重新配置。
- 玩家可以在菜单中清空或更换快捷物品。
- 开战时把快捷物品 ID 复制到本场玩家 `BattleActorState`；战斗中不能改变。
- 战斗物品意图必须匹配本场快捷 ID，并继续从 `BattleSession` 的工作背包中原子消耗。

快捷物品属于角色的战斗配置，而不是 `ItemDefinition`、HUD 或 InputMap。当前只有一个队长，未来增加
队员时仍可自然保留每个角色自己的配置。

## 4. 目标状态与所有权

实施后的相关长期状态：

```text
GameRun
├── PartyState
│   └── ActorState[]
│       ├── equipment
│       ├── learned_skill_ids
│       ├── battle_skill_ids[3]
│       └── battle_item_id
└── InventoryState
    ├── ordered item IDs
    ├── quantities
    └── max_distinct_items
```

战斗创建边界：

```text
ActorState + InventoryState + ContentDatabase
  -> BattleSession.create()
     -> BattleActorState.allowed_skill_ids
     -> BattleActorState.battle_item_id
     -> BattleBuildSnapshot
     -> working InventoryState copy
```

所有长期值只保存稳定 ID、整数和数组；`GameRun` 不保存 `SkillDefinition`、`ItemDefinition`、Texture、
活动冷却或菜单选中项。菜单只调用事务并消费结果，不能直接修改 `equipment`、
`learned_skill_ids`、`battle_skill_ids` 或 `battle_item_id`。

## 5. 领域 API 与结果对象

### 5.1 InventoryState

保留现有 `quantity/item_ids/add_item/remove_item/to_dictionary/restore`，增加：

```text
occupied_capacity() -> int
remaining_capacity() -> int
```

容量查询不得要求 UI 自行按分类计算。`add_item`、试算副本和存档恢复必须使用同一容量规则。

### 5.2 EquipmentTransaction

保留 `equip()` 并增加：

```text
unequip(game_run, actor_state, slot, database) -> EquipmentResult
```

`EquipmentResult` 至少区分：

```text
EQUIPPED
UNEQUIPPED
ALREADY_EQUIPPED
SLOT_EMPTY
SLOT_NOT_ALLOWED
INVALID_ACTOR
INVALID_EQUIPMENT
ITEM_UNAVAILABLE
INVENTORY_REJECTED
```

结果继续返回槽位、装上物品 ID 和退回物品 ID。UI 不解析错误字符串。

### 5.3 SkillLearningTransaction

新增独立规则对象：

```text
learn(actor_state, skill, database) -> SkillLearningResult
```

结果至少区分 `LEARNED / ALREADY_LEARNED / INVALID_ACTOR / INVALID_SKILL`，并返回技能 ID、是否自动
进入快捷槽以及槽位索引。`CultivationTransaction` 和未来 StoryContext 高层能力复用该规则，不复制
学习与自动装槽逻辑。

### 5.4 SkillLoadoutTransaction

新增：

```text
assign(actor_state, skill, slot_index, database) -> SkillLoadoutResult
clear(actor_state, slot_index) -> SkillLoadoutResult
```

结果至少区分：

```text
ASSIGNED
CLEARED
UNCHANGED
INVALID_ACTOR
INVALID_SKILL
SKILL_NOT_LEARNED
SKILL_NOT_USABLE_IN_BATTLE
SLOT_OUT_OF_RANGE
```

成功结果返回目标槽、原槽、被替换技能和最终技能 ID，足以让 UI 给出准确反馈。

### 5.5 BattleItemLoadoutTransaction

新增：

```text
assign(game_run, actor_state, item, database) -> BattleItemLoadoutResult
clear(actor_state) -> BattleItemLoadoutResult
```

结果至少区分 `ASSIGNED / CLEARED / UNCHANGED / INVALID_ACTOR / INVALID_ITEM / ITEM_UNAVAILABLE /
ITEM_NOT_USABLE_IN_BATTLE`。

### 5.6 ItemDiscardTransaction

新增：

```text
discard(game_run, item, quantity) -> ItemDiscardResult
```

结果区分非法数量、不可丢弃、数量不足和成功。确认弹窗属于菜单表现层，事务本身保持同步且不持有 UI。

## 6. v6 存档迁移

本轮把 `GameRun.SAVE_VERSION` 从 5 提升到 6。`CONTENT_VERSION` 在内容 ID 没有不兼容变化时保持
不变；新增可选静态字段不单独迫使旧存档失效。

### 6.1 新格式

ActorState 写入：

```json
{
  "equipment": {"weapon": "item.roadside.returning_sword_case"},
  "learned_skill_ids": [
    "skill.roadside.wind_edge",
    "skill.roadside.sweeping_arc"
  ],
  "battle_skill_ids": [
    "skill.roadside.wind_edge",
    "skill.roadside.sweeping_arc",
    ""
  ],
  "battle_item_id": "item.roadside.wound_powder"
}
```

### 6.2 v5 迁移

- 旧 `skill_ids` 按原顺序复制到 `learned_skill_ids`，去重时保留第一次出现的位置。
- 前三个合法战斗技能依次填入 `battle_skill_ids`；不足三个时补空 ID。
- 旧存档没有快捷物品时，从队长行囊获取顺序中选择第一个当前可战斗使用且数量大于零的物品，
  以保持旧版本 Q 键行为；没有则为空。
- `equipment` 和 Inventory 条目格式不变。
- 迁移后必须经过完整 `ContentDatabase.validate_game_run()`；未知、重复、不可战斗技能和非法快捷物品
  不能静默进入新存档。

### 6.3 新游戏

- `ActorDefinition.initial_skills` 全部进入已学列表。
- 其中前三个合法战斗技能按顺序进入战斗槽。
- 当前新游戏没有初始行囊，因此快捷物品为空；第一次获得止血散后由玩家配置，不静默改变选择。
- `initial_equipment` 必须属于角色允许槽位，并继续直接进入 ActorState，不同时放入行囊。

### 6.4 兼容测试

- 保留 v2、v3、v4、v5 fixture 作为只读迁移输入。
- 新增 v6 新游戏和已完成阵灯分支 fixture。
- 覆盖空技能、三技能、超过三技能、重复旧技能、未知技能、非法装备槽和未知快捷物品。
- v5 读取成功后再次保存必须只输出 v6 字段，不保留第二份 `skill_ids` 真相。

## 7. Content schema、CLI 与校验

### 7.1 Definition 变化

```text
ItemDefinition
  + icon: Texture2D
  + can_discard: bool
  + can_sell: bool

SkillDefinition
  + icon: Texture2D

ActorDefinition
  + equipment_slots: Array[StringName]
```

正式内容的六件物品/法器和三项技能补齐原创图标。已有动作 SVG 可分别成为飞剑诀、回风剑环、
归元剑阵和止血散的定义图标；其余物品与法器使用同一有限色板补充原创 SVG，并在
`assets/original/README.md` 记录来源和确定性编辑方式。

### 7.2 ContentDatabase validator

新增或收紧：

- Actor 的装备槽非空、唯一，初始装备槽属于允许槽。
- Equipment 槽位非空；GameRun 中装备的物品槽与角色允许槽同时匹配。
- ActorState 已学技能唯一且全部已登记。
- `battle_skill_ids` 恰好三个、非空项唯一、已学、已登记且允许战斗。
- `battle_item_id` 为空或引用已登记且允许战斗的 ItemDefinition。
- 正式物品和技能图标存在；缺图标时诊断包含定义 ID。
- `can_discard/can_sell` 使用显式字段；关键物不可丢弃的正式内容约束由 validator 固定。
- Inventory 的数量、容量和 key item 容量豁免使用同一规则。

### 7.3 内容 CLI

`schema/create/show/catalog/export-json/apply-json` 同步新增字段；JSON 继续使用稳定字段名和资源引用
路径，不新增第二份目录。`apply-json` 失败仍必须整批回滚。

CLI 测试至少覆盖：

- 创建 item/equipment/skill 时生成合法默认字段。
- 导出并应用 icon、丢弃/出售字段和装备槽。
- 非法装备槽、缺失图标和非法初始技能产生带文件、字段与 ID 的诊断。
- `rename-id` 同时更新已学技能、战斗槽和快捷物品的精确序列化 ID。

## 8. BattleSession 与 HUD 接入

### 8.1 战斗创建

- `BattleSession.create()` 从队长 ActorState 复制三个战斗技能 ID 和快捷物品 ID。
- `BattleActorState` 保存本场允许的技能 ID 与快捷物品 ID，不保存长期 ActorState 引用。
- `BattleBuildSnapshot` 继续只处理装备/道基的战斗 modifier，不吸收技能栏或背包职责。
- 菜单在战斗期间不可打开事务页，因此本场配置在创建后保持稳定。

### 8.2 动作校验

玩家技能意图必须同时满足：

- SkillDefinition 已登记且与数据库中的同 ID 定义一致。
- 技能 ID 存在于来源 BattleActorState 的允许技能列表。
- `usable_in_battle`、目标规则、MP 和冷却合法。

玩家物品意图必须同时满足：

- ItemDefinition 已登记且匹配本场快捷物品 ID。
- `usable_in_battle` 为真。
- 工作背包仍有数量。

未配置、未学会或不属于本场快照的技能返回新增的结构化 `SKILL_UNAVAILABLE`；空定义、未登记定义
或非法动作形态继续返回 `ACTION_INVALID`。物品未配置、已耗尽或工作背包中不存在时继续返回
`ITEM_UNAVAILABLE`。测试只断言枚举和 action ID，不依赖解析中文文本。

### 8.3 输入与 HUD

- 三个技能输入读取 `battle_skill_ids[0..2]`，不再读取已学技能数组顺序。
- 物品输入只请求 `battle_item_id`；没有配置或数量为零时显示明确拒绝。
- HUD 从 SkillDefinition/ItemDefinition 读取图标、名称、消耗和数量。
- 空技能槽显示“未配置”，已学但未配置的技能不出现在战斗 HUD。
- 已配置但耗尽的物品显示原图标与 `×0`，不会改成背包中的另一种物品。
- 原有键鼠、手柄映射和六格布局不变化。

## 9. MenuGameScene 信息架构

继续使用一个由 GameSceneStack `push/pop` 管理的 `MenuGameScene`，内部组合五个 Control 页面：

```text
状态 | 行囊 | 装备 | 法术 | 系统
```

不把页签拆成新的 GameScene，不增加 MenuManager。页签和页面子组件通过 signal 向 MenuGameScene
报告请求，MenuGameScene 调用领域事务并把结果直接刷新回页面。

### 9.1 共通布局

在 `640 x 360` 内采用：

- 顶部：五个页签和当前角色。
- 左侧：分类、物品或技能列表。
- 右侧：图标、说明、规则、属性比较和操作按钮。
- 底部：当前设备按键提示与短结果反馈。

键盘、鼠标和手柄都使用标准 Control focus；不把拖放作为唯一配置方式。切换页签、关闭确认框、
从存读档/设置返回后恢复合理焦点。

### 9.2 状态页

- 显示角色、境界层数、修为、道基、HP/MP、攻击和当前法器。
- 只展示最终派生数值，不在首版展开完整公式。
- 保留当前单队长布局，为未来切换队员预留页面输入，不提前实现队伍管理。

### 9.3 行囊页

- 分类为全部、消耗、法器、关键物、材料。
- 显示普通容量 `已用 / 上限`；关键物明确标注“不占行囊容量”。
- 列表行显示图标、名称和数量；右侧显示说明、可用场景和动作。
- “使用”调用 ItemUseTransaction；当前只有一个角色时默认作用于队长。
- “设为快捷”调用 BattleItemLoadoutTransaction。
- “丢弃”要求数量选择和确认，并调用 ItemDiscardTransaction。
- 关键物或不可丢弃物不显示可执行的丢弃按钮。

### 9.4 装备页

- 左侧显示角色允许的槽位，当前只有一个“法器”槽。
- 右侧列出行囊中与该槽匹配的装备。
- 选中候选时比较最大 HP、最大 MP、攻击和特殊战斗说明。
- “装备/替换/卸下”分别调用 EquipmentTransaction。
- 行囊无法收回旧装备时显示具体原因，当前装备和数值保持不变。

### 9.5 法术页

- 左侧显示全部已学技能，按学习顺序排列。
- 右侧显示三个动作槽、技能图标、真气消耗、冷却、目标、范围和说明。
- 选中技能后选择槽位完成配置；已在其他槽时表现为移动。
- 允许清空槽位；不提供遗忘技能。
- 未学技能和内容数据库中的其他技能不显示为灰色技能树节点。

### 9.6 系统页

- 保存、读取、设置和返回标题继续使用现有 GameSceneStack 入口。
- 从子场景返回后刷新状态，但不得丢失当前菜单页签和焦点。

## 10. 实施阶段

阶段编号使用 `IES`（Inventory / Equipment / Skills），不提前占用 R9 之后的产品里程碑编号。
IES-0 至 IES-5 已全部完成；以下工作与退出门保留为当前回归清单。

### IES-0：契约冻结

产出：

- 本计划评审通过。
- 冻结 v6 字段名、三个技能槽、单法器槽、关键物容量豁免和快捷物品所有权。
- 为新增结果对象列出稳定 Outcome 与 JSON/CLI 字段。
- 确认正式物品/技能图标清单及复用/新增方式。

退出门：没有未决定的数据所有权；实现阶段不需要由 UI 临时决定规则。

### IES-1：状态、schema 与 v6 迁移

工作：

- 修改 Item/Equipment/Skill/Actor Definition 与 ContentDatabase validator。
- 修改 ActorState、InventoryState、GameRun 序列化和 v5 -> v6 迁移。
- 更新正式 `.tres` 内容和原创图标引用。
- 更新 CLI schema、show/catalog、JSON 导出/应用和 rename-id。
- 增加状态、validator、CLI 和全部旧版本迁移测试。

退出门：无 UI 和战斗改动时，新游戏与 v2-v5 存档均能生成合法 v6 GameRun；内容 CLI 全部通过。

### IES-2：领域事务

工作：

- 实现卸装、学习技能、技能槽、快捷物品和丢弃事务与结果对象。
- 让新游戏、筑基和未来剧情授予技能统一使用学习规则。
- 补齐失败原子性、自动填空槽、移动技能和装备数值截断测试。

退出门：所有状态变化可在无窗口测试中完成；没有调用方需要直接修改 ActorState 集合。

### IES-3：战斗配置与 HUD

工作：

- BattleSession/BattleActorState 固化技能与物品配置。
- 收紧动作归属校验。
- PlayerCharacter 输入改读战斗槽和快捷物品。
- HUD 改为 Definition 数据驱动图标与数量。
- 更新战斗脚本、截图工具和测试 fixture 的显式配置。

退出门：正常三技能与丹药路径通过；未学、未配置、伪造或耗尽请求均被确定性拒绝；三种 battle outcome
的物品提交规则不回归。

### IES-4：菜单页面

工作：

- 把现有混合菜单组合为状态、行囊、装备、法术和系统页面。
- 实现分类、详情、容量、属性比较、技能配置、快捷物品和丢弃确认。
- 完成键鼠/手柄焦点、返回、空状态和本地化文本。
- 保持保存、读取、设置的 SceneStack 往返。

退出门：玩家无需战斗调试快捷键即可完成物品使用、法器替换/卸下、三技能配置、丹药配置和存读档。

### IES-5：文档、截图与完整回归

工作：

- 同步 README、requirements、architecture、content-authoring、roadmap 和 visual-acceptance。
- 更新内容数量或图标资产说明，但不宣称新增玩法内容。
- 扩充 UI 截图，覆盖分类行囊、装备比较、技能槽和手柄焦点。
- 执行工程、内容、地图、测试与截图回归。

退出门：完成标准全部满足，并且不存在旧 `skill_ids` 运行时读写、HUD 固定技能图标或“第一个可用
丹药”回退逻辑。

## 11. 测试矩阵

### 11.1 Inventory

- 获得新普通物品占一个容量，叠加同 ID 不再占容量。
- 普通容量已满时拒绝新普通物品，不部分改变顺序或数量。
- 关键物在普通容量已满时仍可按 `max_stack` 获得。
- ALL_OR_NOTHING 与 ALLOW_PARTIAL 在堆叠边界保持现有语义。
- 使用、丢弃、交付、购买、装备退回和战斗提交后顺序与数量正确。
- 不能丢弃关键物或显式不可丢弃物。

### 11.2 Equipment

- 装备空槽、替换同槽、重复装备、卸下空槽。
- 目标角色不允许该槽时完整拒绝。
- 新法器不在行囊时完整拒绝。
- 旧法器无法退回行囊时完整拒绝。
- 增减 HP/MP/攻击后派生值正确，当前 HP/MP 只在超过新上限时截断。
- 装备 modifier 只在下一场 BattleBuildSnapshot 创建时生效。

### 11.3 Skills

- 学习新技能、重复学习、无效定义和未登记定义。
- 自动填入第一个空槽，槽满时不覆盖。
- 配置未学技能、非战斗技能、越界槽位全部拒绝。
- 已配置技能移动到另一槽时不重复，目标原技能保留已学状态。
- 清空技能槽不遗忘技能。
- 筑基授予归元剑阵后旧两技能顺序稳定，第三槽自动填入。

### 11.4 Battle item

- 配置合法丹药、未持有物品、不可战斗物品和清空快捷槽。
- 耗尽后快捷 ID 保留、数量为零、动作被拒绝。
- 再获得同物品后无需重配即可使用。
- Victory/Escaped/Defeat 继续只按既有规则提交工作背包消耗。

### 11.5 Battle integrity

- 三个槽分别映射正确 Definition、图标、消耗和冷却。
- 未配置技能即使传入合法 SkillDefinition 也被拒绝。
- 同 ID 但非数据库定义的 Resource 被拒绝。
- 战斗开始后修改长期 ActorState 不影响当前 BattleActorState 快照。
- 装备/技能菜单在活动战斗期间不可进入。

### 11.6 Save and content

- v2-v5 迁移、新 v6 往返、三槽空值和快捷物品往返。
- ContentDatabase 拒绝重复已学技能、重复战斗槽、非法装备槽和未知快捷物品。
- CLI list/show/schema/create/export/apply/refs/rename-id 覆盖新增字段。
- 存档摘要不因新增字段失败；旧合法地图、故事、世界和随机状态不变化。

### 11.7 UI smoke

- `640 x 360` 中文和英文文本不越界。
- 空行囊、空装备槽、少于三个技能、无快捷物品均有明确空状态。
- 键盘、鼠标和手柄可完成全部动作；焦点不会落入隐藏页面。
- 丢弃确认取消不改变状态。
- 从设置、保存和读取返回时恢复页面与焦点。

## 12. 预计主要文件影响

状态与内容：

- `framework/state/inventory_state.gd`
- `framework/state/actor_state.gd`
- `framework/state/game_run.gd`
- `framework/services/save_service.gd`
- `framework/content/item_definition.gd`
- `framework/content/equipment_definition.gd`
- `framework/content/skill_definition.gd`
- `framework/content/actor_definition.gd`
- `framework/content/content_database.gd`
- `content/**/*.tres`

规则与战斗：

- `framework/gameplay/rules/equipment_transaction.gd`
- 新增学习、技能配置、快捷物品和丢弃事务/结果脚本
- `framework/gameplay/rules/cultivation_rules.gd`
- `framework/gameplay/rules/cultivation_transaction.gd`
- `framework/gameplay/battle/battle_session.gd`
- `framework/gameplay/battle/battle_actor_state.gd`
- `framework/presentation/action_combat_3d/player_character_3d.gd`
- `framework/presentation/action_combat_3d/map_hud_3d.gd`

菜单、工具与验证：

- `game/presentation/menu/menu_game_scene.gd`
- `game/presentation/menu/menu_game_scene.tscn`
- 可按页面拆分 `game/presentation/menu/components/` 下的小型 Control 组件
- `tools/content_cli.gd`
- `tests/run_tests.gd` 与 save fixtures
- UI/R7/R9 截图工具中直接访问旧 `skill_ids` 的部分
- README 与相关 `docs/`

这是一份影响面清单，不要求一次提交同时修改全部文件。实现按 IES 阶段保持可回归的小步提交。

## 13. 风险与控制

| 风险 | 控制方式 |
|---|---|
| 已学技能与快捷槽迁移后顺序变化 | v5 fixture 固定原顺序和前三槽结果 |
| 关键物容量豁免产生两套容量算法 | 容量只由 InventoryState 公共查询与增减方法计算 |
| UI 直接修改 ActorState 导致规则分叉 | 页面只能调用事务并消费类型化结果 |
| HUD 仍按槽位使用固定图标 | SkillDefinition/ItemDefinition 成为图标真相，测试三个槽互换 |
| 战斗可使用未配置技能 | BattleActorState 保存允许 ID，BattleSession 在扣 MP 前验证 |
| 卸装时行囊已满导致物品丢失 | 使用 InventoryState 试算副本，成功后一次提交 |
| v6 迁移破坏旧故事或世界状态 | 只迁移 Actor 技能/快捷物品字段，其他子状态逐字段回归 |
| 菜单在 640 x 360 信息过载 | 固定左右布局、分页、真实中英文截图与手柄焦点门 |
| 计划扩张为装备/技能编辑器 | 坚持一个法器槽、三个主动槽和有限 Definition 字段 |

## 14. 完成定义

- Godot 工程无解析错误，ContentDatabase 和全部正式内容通过校验。
- v2-v5 存档可迁移为 v6，v6 保存和读取保持装备、技能和快捷物品一致。
- 背包分类、容量、使用、快捷物品和丢弃规则通过无窗口测试。
- 法器可装备、替换和卸下；失败边界全部原子。
- 已学技能和三个战斗槽完全分离，筑基授予技能沿统一事务完成。
- BattleSession 拒绝未配置技能和非快捷物品，不依赖 UI 作为唯一防线。
- HUD 图标、名称、消耗、冷却和数量由内容定义与当前配置驱动。
- 菜单五页在键鼠和手柄下可完整使用，空状态、确认和 SceneStack 往返正确。
- CLI、Content Database Dock、JSON 往返、引用和 ID 迁移支持新增 schema。
- README、requirements、architecture、content-authoring、roadmap、visual-acceptance 与实现一致。
- 没有引入 GameSession、GameFlow、通用动作数组、全局 EventBus 或装备/技能表达式语言。
- 没有加入本计划非目标中的随机装备、技能树或内容规模扩张。

## 15. 已确认决策

IES-1 开始前确认并在实现中保持了三件事：

1. “法器”是否继续使用存档槽 ID `weapon`。本计划建议保留，避免无价值的 ID 迁移。
2. 关键物不占普通容量是否作为正式规则。本计划按“是”编写。
3. 丢弃是否进入第一版菜单。本计划按“是，但关键物默认禁止”编写。

后续若改变其中任何一项，需要单独评估存档迁移、容量规则、事务结果与菜单交互，不通过局部 UI
改动静默改变领域契约。
