# AGENTS.md

本文件适用于整个仓库。开始工作前先阅读本文件、`README.md`，以及 `docs/` 中与任务相关的文档。

## 项目定位

本项目是一个原创传统单机修仙 RPG 学习与内容创作框架。当前默认从固定视角 3D 的
`map.roadside.lantern_pass`“阵灯筑基”纵向切片开始，再连接程序生成的
`map.roadside.north_slope_wilds` `64 x 32` 生态地图、`map.roadside.shop` 与
`map.roadside.herb_slope` 的两趟采药内容，以及 `map.roadside.north_slope_pack` 的实时战斗基线。
五张地图使用原创旅人、NPC、药草、食炁兽、地表与环境模块，验证 3D 移动、碰撞、
导航、路线风险、留根采集、群怪、法器构筑、阵柱 Boss、持久阵灯选择、境界突破、菜单和 v6 存读档。

仓库不再使用或维护《仙剑奇侠传》提取素材、Rust-PAL 导出结果、旧验证地图与旧故事。
`generated/`、原版 source ID 和 `framework-lab` manifest 不得重新成为运行时依赖。后续素材
直接保存在 `assets/original/`，生成源图、提示与确定性后处理方式记录在素材说明中。

当前技术基线是 Godot 4.8、带静态类型的 GDScript、桌面端、键盘与手柄输入，以及
`640 x 360` 根 Viewport 中的固定正交视角低多边形 3D 画面与原生 Control UI。

## 统一架构术语

使用以下概念，不再引入同义的 Manager 或 Session：

- `GameRoot`：持久主场景和组合根，拥有场景栈、覆盖 UI、服务与当前 GameRun。
- `GameSceneStack`：通过 `push/pop/replace/reset` 管理标题、地图、菜单、商店和存档场景；普通战斗由当前地图内的 BattleSession 表达。
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
- 一场战斗：当前 MapGameScene、BattleSession、BattleActorState 和 BattleActorView。
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

地图、菜单、商店和存档页由 GameSceneStack 管理；普通战斗由当前 MapGameScene 拥有：

- `push`：暂停当前场景并进入新场景，例如菜单或商店。
- `pop`：返回结果并恢复前一个场景。
- `replace`：切换地图。
- `reset`：清空栈并进入标题或新游戏入口。

`StoryContext.start_battle()` 直接 await 当前 MapGameScene；战斗期间 StoryDirector 保留剧情
调用所有权，地图只开放移动和战斗输入，禁止互动、保存和事务菜单。

Dialogue 是 Overlay 中的模态 UI，不需要成为完整 GameScene。Cutscene 是地图内的 StoryModule trigger，不需要单独的全局模式枚举。

整个游戏直接使用 Godot 根 Viewport 的 `640 x 360`、`viewport` stretch 和 `keep` aspect；
默认窗口为严格 2 倍的 `1280 x 720`，允许调整窗口尺寸并以 F11 切换全屏。3D 世界使用固定
yaw/pitch 的正交摄影机、有限色板与清晰轮廓，UI 以原生字号渲染清晰矢量文字；没有额外
渲染需求前不要增加自定义 SubViewport。

## 玩家与角色

必须区分：

- `ActorDefinition`：角色静态 Resource。
- `ActorState`：GameRun 中的境界、层数、修为、道基、HP/MP、装备和技能。
- `PlayerCharacter`：当前地图中的 CharacterBody3D 化身。
- `PlayerController`：可启停的输入组件。
- `BattleActorState/BattleActorView`：一场战斗中的规则状态和表现。

PlayerCharacter 每次进入地图时创建并绑定队长 ActorState，离开地图时销毁；不要把 Player 做成 Autoload 或跨地图 reparent。地图中的位置在保存或退出边界同步到 GameRun。CameraRig 独立于 Player，便于剧情镜头切换。

## 内容数据库

每条内容定义使用独立 `.tres`：

- ActorDefinition
- CultivationRealmDefinition
- DaoFoundationDefinition
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

需要全局按 ID 查询或进入存档的 RPG Definition 保持一条定义一个文件。首期允许使用一个简单、显式的 ContentDatabase Resource；只有手工登记产生实际维护负担后才引入自动 catalog，自动生成文件不得成为第二份内容真相来源。StoryModule 和故事私有 Dialogue 不强制登记到手写数据库，由 validator 扫描 ContentDatabase 配置的 `story_directories` 和地图 binding。

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
- 小尺寸纹理关闭有损压缩；低多边形材质、模型单位、轴向、脚点与动画名称保持可验证。
- 优先使用 GridMap、CharacterBody3D、Area3D、NavigationRegion3D、AnimationPlayer、Tween 和 Control。

## 设计师与 AI Agent 工具

人类设计师使用标准 Inspector、Content Database Dock 和 Dock 内的 Dialogue Editor；Dock 的目录与反向引用由 Resource 派生，不保存第二份数据库。AI Agent 使用稳定 headless CLI。

当前已实现 `validate/catalog/list/show/schema/create/export-json/apply-json/refs/rename-id/story-test`；所有命令支持稳定 JSON，内容类型覆盖 Realm/Foundation/Actor/Npc/Item/Equipment/Skill/Status/Enemy/Shop/Encounter/Map/Dialogue/Story：

```sh
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tools/content_cli.gd -- catalog --json
godot --headless --path . -s res://tools/content_cli.gd -- list [type] --json
godot --headless --path . -s res://tools/content_cli.gd -- show <type> <id> --json
godot --headless --path . -s res://tools/content_cli.gd -- schema [type] --json
godot --headless --path . -s res://tools/content_cli.gd -- create <type> <id> --path <res://...tres> [type options] --json
godot --headless --path . -s res://tools/content_cli.gd -- refs <id> --json
godot --headless --path . -s res://tools/content_cli.gd -- export-json <res://...json> --json
godot --headless --path . -s res://tools/content_cli.gd -- apply-json <res://...json> --json
godot --headless --path . -s res://tools/content_cli.gd -- rename-id <type> <old-id> <new-id> --json
godot --headless --path . -s res://tools/content_cli.gd -- story-test <story-id> <trigger-id> [stage] [outcome] --json
```

编辑期生态地图工具使用独立稳定 CLI；`plan/validate` 只读，`bake` 只在临时场景重新加载和
全部校验通过后原子替换目标：

```sh
godot --headless --path . -s res://tools/map_generator_cli.gd -- plan <profile.tres> [--seed <int>] --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate <profile.tres> [--seed <int>] --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- bake <profile.tres> [--seed <int>] --json
```

地图生成器只拥有 Ground/Detail cell、带 `map_generator_owned` 元数据的环境节点和生成边界；
不得改写人工 NPC、spawn、Portal、StoryBinding、persistent ID 或剧情资源。Profile 不登记
ContentDatabase、不进入 GameRun，也不成为运行时依赖。完整契约见 `docs/map-generation.md`。

`apply-json` 必须整批校验、使用临时文件并在失败时回滚；`rename-id` 只替换精确序列化 ID 并写迁移记录。CLI 必须继续支持机器可读 JSON、稳定字段、非零失败码和包含文件/字段/ID 的诊断。

## 素材管线

原创素材保存在 `assets/original/`。正式 3D 资产由仓库脚本确定性生成与导出，统一使用米、
+Y 向上、-Z 前向和脚底原点；角色共用 13 骨骼以及 idle/run/attack/cast/hit/death 六组动画。
`manifest.json` 记录 GLB 哈希、三角面、骨骼、动画、材质与导入边界。

运行时只直接引用原创 GLB、Texture2D、Material、PackedScene 与 AudioStream Resource，不接受
原版 source chunk、外部素材 manifest 或整张场景插画作为地图结构。`.tscn` 继续维护
GridMap、碰撞、导航、实体和 StoryBinding。

## 验证

基础工程检查：

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate res://game/roadside/map_generation/roadside_shop_3d_profile.tres --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate res://game/roadside/map_generation/herb_slope_3d_profile.tres --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate res://game/roadside/map_generation/north_slope_wilds_3d_profile.tres --json
```

新增功能按层验证：

- Resource schema、ID、引用和 ContentDatabase 校验。
- GameSceneStack 的 push/pop/replace/reset 与返回值。
- GameRun 的新游戏、修改和存档往返。
- PlayerCharacter 创建、移动、交互、暂停和地图恢复。
- StoryModule 使用 FakeStoryContext 覆盖 trigger、关键 stage、选择、Victory/Escaped/Defeat、奖励拒绝、来源完成和 pending travel 的剧情轨迹测试。
- 物品、法术、GameEffect、商店、奖励原子性和战斗 outcome 提交规则测试。
- `map.roadside.north_slope_wilds` 固定覆盖 `64 x 32` baked 3D 地表、长路线、生态密度、默认出生点、人工 Portal、Camera、导航和边界碰撞。
- `map.roadside.shop` 与 `map.roadside.herb_slope` 固定覆盖原创 3D 模块、spawn、移动、碰撞、导航、DialogueOption、采集选择、原子交付、第二趟地图状态、菜单和存档恢复。
- `map.roadside.lantern_pass` 固定覆盖六段有限遭遇、真气循环、两件法器、两种道基、CHARGE
  action instance、三根一次性阵柱、失衡、阵灯修复/拆取、捷径、回访和 v6 存档恢复。
- 固定 seed 地图生成覆盖 plan hash、生态分类、全部 gameplay anchor 可达、阻挡 footprint、
  人工节点保留、失败不写入和正式 baked scene；运行时不得执行生成器。
- 不为当前验证片段添加随机词缀、无限刷怪、装备品质、队友 AI、赛季或通用 Boss 阶段编辑器。
- 场景输入隔离、固定镜头遮挡和 UI smoke test。
- `docs/visual-acceptance.md` 中的标题、地图、树前后遮挡与对话截图检查。
- 普通 CI 只使用仓库中的 `assets/original/`，不读取任何原版输入数据。

## 文档维护

- 产品目标和范围：`docs/requirements.md`
- 运行时与所有权：`docs/architecture.md`
- 人类设计师和 AI Agent 接口：`docs/content-authoring.md`
- 程序化生态地图：`docs/map-generation.md`
- 本地素材提取：`docs/asset-pipeline.md`
- 里程碑：`docs/roadmap.md`

架构术语、公共 StoryContext API 或内容 schema 变化时，必须同步相应文档。

## 完成标准

- Godot 工程可无错误加载，新增脚本无解析错误。
- 新功能遵守 GameSceneStack/GameRun/Resource/StoryBinding/StoryContext 边界。
- 没有重新引入 GameFlow、GameSession、EventSequence 或原版 opcode 兼容层。
- 设计师内容可通过 Inspector 或 CLI 创建、检查和验证。
- 测试覆盖新增规则、失败边界和引用错误。
- 未提交第三方游戏提取素材、原版输入数据或原版存档；原创素材具有生成和处理记录。
- 文档和实现保持一致。
