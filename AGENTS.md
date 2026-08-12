# AGENTS.md

本文件适用于整个仓库。开始工作前先阅读本文件、`README.md`，以及 `docs/` 中与任务相关的文档。

## 项目定位

Godot PAL 是一个传统单机 RPG 学习与内容创作框架。《仙剑奇侠传》一代的本地提取素材是首个真实素材验证对象：第一版把现有 Tile、角色、头像、UI、字体和音频重新组合成两张原创地图与短故事《借来的伞》，以验证 Godot 架构、内容创作接口和素材边界。项目当前不承诺复刻原版地图或整部游戏。

首个验证片段追求完整、可重复测试的玩家可见闭环，但不是原程序的二进制、剧情或脚本兼容：

- 不读取、不解释、不翻译原版 opcode、剧情脚本或事件入口。
- `map.lab.inn_hall`、`map.lab.rain_courtyard` 和 `story.lab.borrowed_umbrella` 由 Godot Scene、Resource 与 StoryModule 原创建立。
- 不以兼容原版运行时状态、文件协议或存档为目标。
- Rust-PAL 只用于离线提取本地合法持有的图片、Tile、字体和音频素材。
- `framework-lab` 导出的 `generated/` 是仓库、编辑器和普通 CI 的必需资源，可以随项目维护；原版输入数据和原版存档仍不得提交。
- 维护者在提交或分发 `generated/` 及其截图、录屏前负责确认拥有相应权利；程序化占位素材只作为单项缺失时的防御性表现，不再承担无素材工程模式。

当前技术基线是 Godot 4.8、带静态类型的 GDScript、桌面端、键盘输入和 `320 x 200` 像素画面。

## 统一架构术语

使用以下概念，不再引入同义的 Manager 或 Session：

- `GameRoot`：持久主场景和组合根，拥有场景栈、覆盖 UI、服务与当前 GameRun。
- `GameSceneStack`：通过 `push/pop/replace/reset` 管理标题、地图、菜单、商店和战斗场景；当前活动 GameScene 自然表达游戏流程。
- `GameRun`：一次游戏进度的纯运行时数据，包含队伍、背包、金钱、标记、世界状态和位置。
- `ContentDatabase`：静态 Resource 定义的索引和校验入口。
- `StoryEvent`：无状态 Resource 基类；内置简单交互和复杂剧情使用同一调用协议。
- `StoryModule`：按叙事职责组织复杂剧情的 StoryEvent，一个模块可以响应多个地图 trigger。
- `StoryBinding`：地图中嵌入的 event + trigger ID 配置，把 NPC、区域或地图入口连接到 StoryEvent。
- `StoryContext`：设计师脚本的稳定公共 API，提供对话、商店、战斗、原子奖励、完成当前来源实体、移动、镜头和地图切换等高层用例。
- `StoryState`：以 story ID 保存多阶段剧情当前阶段；简单开关仍使用 GameFlags。
- `GameEffect`：物品、法术和状态使用的有限机械效果 Resource；它不承担剧情控制流。

不要重新引入：

- 同时持有状态、服务、场景和 UI 的 `GameSession` 上帝对象。
- 与 GameSceneStack 重复表达流程的 `GameFlow`。
- `EventSequence/EventAction` 通用剧情解释框架。
- 数字指令、Jump/Loop/Call 等自制剧情 opcode。
- 无边界的全局 EventBus 或大量 Autoload。

## 生命周期与所有权

- 应用级：`GameRoot`、`GameSceneStack`、覆盖 UI、AudioService、SaveService、ContentDatabase。
- 一次游戏：`GameRun` 及其 PartyState、InventoryState、StoryState、GameFlags、WorldState、LocationState。
- 当前地图：MapGameScene、PlayerCharacter、NPC、CameraRig、地图交互对象。
- 一段剧情调用：StoryEvent Resource、StoryContext 和 StoryDirector 的活动调用。
- 一场战斗：BattleGameScene、BattleSession、BattleActorState 和 BattleActorView。
- 一个弹窗：DialogueLayer、ConfirmationDialog 或其他临时 Control。

短生命周期 Node 不得成为长期数据的唯一持有者。GameRun 不保存 Node、Texture、Camera、活动 UI 或战斗场景引用。

## Godot 设计方式

- `.tscn` 负责对象组合和生命周期。
- `Resource` 负责静态定义和设计师可编辑内容。
- `RefCounted` 负责 GameRun 中的可序列化运行状态与纯规则对象。
- `Node` 负责场景树、输入、动画、音频和异步表现。
- 子节点通过 signal 向上报告请求；拥有者通过直接方法向下控制。
- 需要返回值的操作使用直接调用和 `await`，纯通知才使用 signal。
- 优先组合小组件，避免深层节点继承树。
- 只有真正跨场景的对象才放入 GameRoot；默认不使用 Autoload。

地图、菜单、商店和战斗由 GameSceneStack 管理：

- `push`：暂停当前场景并进入新场景，例如菜单或战斗。
- `pop`：返回结果并恢复前一个场景。
- `replace`：切换地图。
- `reset`：清空栈并进入标题或新游戏入口。

Dialogue 是 Overlay 中的模态 UI，不需要成为完整 GameScene。Cutscene 是地图内的 StoryModule trigger，不需要单独的全局模式枚举。

整个游戏首期直接使用 Godot 根 Viewport 的 `320 x 200`、`viewport` stretch 和 `keep` aspect；没有世界/UI 双分辨率需求前不要增加自定义 SubViewport。

## 玩家与角色

必须区分：

- `ActorDefinition`：角色静态 Resource。
- `ActorState`：GameRun 中的等级、HP/MP、装备和技能。
- `PlayerCharacter`：当前地图中的 CharacterBody2D 化身。
- `PlayerController`：可启停的输入组件。
- `BattleActorState/BattleActorView`：一场战斗中的规则状态和表现。

PlayerCharacter 每次进入地图时创建并绑定队长 ActorState，离开地图时销毁；不要把 Player 做成 Autoload 或跨地图 reparent。地图中的位置在保存或退出边界同步到 GameRun。CameraRig 独立于 Player，便于剧情镜头切换。

## 内容数据库

每条内容定义使用独立 `.tres`：

- ActorDefinition
- ItemDefinition
- SkillDefinition
- EnemyDefinition
- StatusDefinition
- NpcDefinition
- ShopDefinition
- BattleEncounter
- DialogueDefinition
- MapDefinition

所有内容使用稳定、语义化、带命名空间的 `StringName` ID，例如：

```text
actor.li_xiaoyao
actor.zhao_linger
item.po_tian_hammer
skill.ice_heart
enemy.miao_warrior
shop.yuhang.village
encounter.yuhang.miao_warriors
story.yuhang.inn_opening
map.yuhang.inn
```

Definition 是静态模板；State 保存当前存档值。存档使用 ID，不序列化资源路径、NodePath 或 ResourceUID。静态 Definition 之间可以使用类型化 Resource 引用，ContentDatabase 必须验证引用和重复 ID。

需要全局按 ID 查询或进入存档的 RPG Definition 保持一条定义一个文件。首期允许使用一个简单、显式的 ContentDatabase Resource；只有手工登记产生实际维护负担后才引入自动 catalog，自动生成文件不得成为第二份内容真相来源。StoryModule 和故事私有 Dialogue 不强制登记到手写数据库，由 validator 扫描 `stories/` 和地图 binding。

## 设计师剧情 API

复杂剧情直接继承 `StoryModule`，依赖通过 `@export` 暴露，并只通过 `StoryContext` 调用游戏能力。一个模块通过多个 trigger 服务同一故事涉及的 NPC、区域和地图入口。

推荐形式：

```gdscript
class_name BorrowedUmbrellaStory
extends StoryModule

func get_trigger_ids() -> Array[StringName]:
    return [&"enter_hall", &"talk_innkeeper", &"talk_traveler", &"take_umbrella"]

func run(trigger_id: StringName, story: StoryContext) -> void:
    match trigger_id:
        &"enter_hall":
            if story.get_stage(self) == &"not_started":
                await story.show_dialogue(dialogue, &"opening")
                story.set_stage(self, &"met_innkeeper")
        &"talk_traveler":
            if story.get_stage(self) == &"looking_for_owner":
                await story.show_dialogue(dialogue, &"traveler_reveal")
                story.set_stage(self, &"owner_found")
        &"take_umbrella":
            if story.get_stage(self) == &"owner_found":
                await story.show_dialogue(dialogue, &"umbrella_take")
                story.complete_source_entity()
                story.set_stage(self, &"umbrella_found")
```

StoryEvent/StoryModule 中禁止：

- 访问 `/root/...` 或任意内部服务节点路径。
- 直接操作 GameSceneStack、DialogueLayer 或 BattleGameScene。
- 直接修改 GameRun 内部集合，绕过 StoryContext/领域 API。
- 隐藏依赖的 `load()`/`preload()`；设计内容优先通过 `@export` 引用。
- 创建通用动作数组来代替正常 GDScript 控制流。
- 修改 StoryEvent Resource 自身保存运行进度，或在 `travel_to()` 后继续调用 StoryContext。
- 通过通用 Variant entity state 接口绕过明确的 stage、flag 和地图表现 API。

StoryContext 是稳定公共接口。方法使用完整自然的动词、类型化参数和结果对象；不要使用 `exec()`、`cmd()`、Dictionary 命令或含义不明的 bool 返回值。对话通过 `show_dialogue(dialogue, block_id)` 使用命名 block，模块进度通过 `get_stage(self)/set_stage(self, stage_id)` 访问。

`travel_to()` 是终止操作：它只登记 pending travel，当前 trigger 随即 return；StoryDirector 清理旧调用后 replace 地图，新地图恢复完成后按顺序运行 entry bindings，其中再次 travel 会中止当前地图剩余入口调用。宝箱、拾取物和一次性战斗事件从 StoryOrigin 取得触发实体已有的 persistent ID，不让设计师重复填写。

自定义 StoryModule 通过幂等的 `complete_source_entity()` 完成 StoryOrigin 来源，并同时更新 WorldState、让当前来源应用自身的完成态，保证一次性主效果不可重复；它不能接受任意 entity ID，也不能成为通用世界状态写入口。任务和宝箱物品奖励默认使用 `RewardPolicy.ALL_OR_NOTHING`，只有显式的部分拾取使用 `ALLOW_PARTIAL` 并持久化剩余数量。

StoryModule 的 `can_run()` 必须同步且无副作用。validator 必须检查 binding trigger、module ID、initial/valid stage、Dialogue block/option ID、来源 persistent ID、RewardPolicy 和有序地图 entry bindings；未知 trigger 是内容错误，不等同于 can_run 返回 false。

## 常用 StoryEvent

简单内容优先配置而不是写脚本：

- `DialogueEvent`
- `ShopEvent`
- `TreasureChestEvent`
- `ItemPickupEvent`
- `BattleTriggerEvent`
- `ScenePortalEvent`

它们都直接继承 StoryEvent，并作为 StoryBinding 中的嵌入 SubResource 由 StoryDirector 执行，不额外创建文件。TreasureChestEvent 固定原子奖励；ItemPickupEvent 只有在能保存剩余数量时才允许部分获取；BattleTriggerEvent 在 Victory 完成来源、Escaped 保留来源，Defeat 恢复队伍并 travel 到配置的安全位置。复杂条件和多步剧情加入对应 StoryModule，不增加包装 Handler 或通用动作数组。

## GameEffect 边界

当前《雨夜药房》实现 Heal/RestoreMp，《断桥伏击》实现 Damage。Revive、Status 和 ModifyStat 在真实内容需要时增加。

- 不在 GameEffect 中做剧情跳转、地图切换或对话。
- 效果应用接收明确的 EffectContext、来源和目标。
- ItemDefinition 和 SkillDefinition 可以组合多个效果。
- 特殊机制优先用类型化新 Effect；确有一次性复杂逻辑时使用显式自定义策略脚本，不加入万能表达式语言。

## GDScript 与资源约束

- 使用静态类型；公共 API、非直观算法和状态转换写简洁注释。
- 文件和变量使用 `snake_case`，类名使用 `PascalCase`，signal 使用已发生事件的语义命名。
- StoryContext 的交互操作统一可 `await`；纯查询和即时状态修改保持同步。
- 输入由活动 GameScene 或 PlayerController 处理；领域状态不轮询 Input。
- 随机规则使用可注入种子的随机源。
- 像素纹理关闭 Filter、MipMap 和有损压缩。
- 优先使用 TileMapLayer、CharacterBody2D、Area2D、YSort、AnimationPlayer、Tween 和 Control。

## 设计师与 AI Agent 工具

首期人类设计师使用标准 Inspector，并为 StoryBinding trigger、Dialogue block/option、地图 spawn/marker 提供轻量语义选择器和对白可读预览。AI Agent 使用最小 headless CLI；Database Dock、完整 Dialogue Editor、自动 catalog 和 JSON apply 工具只有在内容规模产生明确痛点后再实现。

当前已实现 `validate/list/show/schema/create`；所有命令支持稳定 JSON，`create` 当前覆盖 Map/Dialogue/Story 模板：

```sh
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tools/content_cli.gd -- list [map|dialogue|story] --json
godot --headless --path . -s res://tools/content_cli.gd -- show <map|dialogue|story> <id> --json
godot --headless --path . -s res://tools/content_cli.gd -- schema [map|dialogue|story] --json
godot --headless --path . -s res://tools/content_cli.gd -- create <type> <id> --path <res://...tres> [type options] --json
```

高级引用查询、JSON round-trip、自动 catalog 和迁移命令属于后续阶段。CLI 必须继续支持机器可读 JSON、稳定字段、非零失败码和包含文件/字段/ID 的诊断。

## 素材管线

单向数据流：

```text
原版数据 -> Rust pal-assets -> pal-godot-exporter -> generated/ -> Godot Import
```

当前 `framework-lab` profile 只导出两张原创验证地图需要的 RGBA PNG 图集、BMFont、PCM16 WAV 和 source manifest，不导出剧情文本、脚本、事件、规则数据库、地图布局或存档。导出素材中的 source ID 只用于追踪来源，不能成为玩法内容 ID。

`generated/` 随当前项目维护，具体地图 TileSet 可以直接引用其中的 atlas。重新导出后必须同时检查 manifest、Godot 导入结果、场景 TileSet 和视觉回归。

修改 `../../rust-pal` 前先阅读该仓库的 `AGENTS.md`、`README.md` 和相关格式文档，并保留已有未提交改动。

## 验证

基础工程检查：

```sh
godot --headless --editor --path . --quit
```

新增功能按层验证：

- Resource schema、ID、引用和 ContentDatabase 校验。
- GameSceneStack 的 push/pop/replace/reset 与返回值。
- GameRun 的新游戏、修改和存档往返。
- PlayerCharacter 创建、移动、交互、暂停和地图恢复。
- StoryModule 使用 FakeStoryContext 覆盖 trigger、关键 stage、选择、Victory/Escaped/Defeat、奖励拒绝、来源完成和 pending travel 的剧情轨迹测试。
- 物品、法术、GameEffect、商店、奖励原子性和战斗 outcome 提交规则测试。
- 《借来的伞》固定覆盖两张地图的素材映射、spawn、移动/碰撞/YSort、掌柜/客人/蓑衣客 bindings、跨地图 entry trigger、对话输入锁、stage 重复交互、一次性旧伞来源和测试性存档恢复。
- 不为当前验证片段添加商店、背包、战斗等尚未证明需要的系统；这些系统在选定包含对应玩法的内容后再做验收。
- 场景输入隔离、YSort/前景遮挡和 UI smoke test。
- `docs/visual-acceptance.md` 中固定的八张截图与文字检查。
- 普通 CI 使用仓库中的 `generated/`，不读取原版输入数据；exporter 在 Rust-PAL workspace 单独验证可重复导出。

## 文档维护

- 产品目标和范围：`docs/requirements.md`
- 运行时与所有权：`docs/architecture.md`
- 人类设计师和 AI Agent 接口：`docs/content-authoring.md`
- 本地素材提取：`docs/asset-pipeline.md`
- 里程碑：`docs/roadmap.md`

架构术语、公共 StoryContext API 或内容 schema 变化时，必须同步相应文档。

## 完成标准

- Godot 工程可无错误加载，新增脚本无解析错误。
- 新功能遵守 GameSceneStack/GameRun/Resource/StoryBinding/StoryContext 边界。
- 没有重新引入 GameFlow、GameSession、EventSequence 或原版 opcode 兼容层。
- 设计师内容可通过 Inspector 或 CLI 创建、检查和验证。
- 测试覆盖新增规则、失败边界和引用错误。
- 未提交原版输入数据或存档；`generated/` 的变更具有可追踪 manifest，并已确认相应使用与分发权利。
- 文档和实现保持一致。
