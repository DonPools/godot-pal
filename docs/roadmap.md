# 开发路线

## 1. 当前状态

项目已从空工程推进到一个可玩的最小垂直切片。`framework-lab` 使用 Rust-PAL 离线提取的现有素材，组成两张原创地图和短故事《借来的伞》：

```text
标题
  -> 听雨客栈·前厅接任务
  -> 听雨客栈·雨院找到蓑衣客并取得旧伞
  -> 返回前厅交付
  -> 故事 completed
```

当前已有 GameRoot、GameSceneStack、GameRun、三张 MapGameScene、玩家/NPC/交互物、StoryModule/StoryContext、DialogueLayer、菜单、商店、Actor/Party/Inventory/Economy、有限 GameEffect、SaveService、ContentDatabase/CLI、Rust exporter 和自动场景测试。

当前限制也很明确：CLI create 仍只覆盖 Map/Dialogue/Story，存档仍是一个测试性 JSON 槽；装备更换、经验成长、状态和战斗尚未实现。《借来的伞》不承担这些系统的验证，《雨夜药房》负责非战斗事务。

## 2. 路线原则

1. 每个阶段交付玩家可见的端到端内容，不堆积互不相连的系统。
2. 新框架能力必须由选定内容证明需要；当前片段不为覆盖清单添加商店或战斗。
3. `.tscn`、`.tres` 和普通类型化 GDScript 是内容真相，不建立剧情 opcode 或万能动作数组。
4. Godot 运行时不解析原版格式；Rust-PAL 只负责离线素材转换。
5. 原版 source ID 只追踪素材，玩法和存档始终使用语义 ID。
6. `generated/` 是仓库、地图编辑和普通 CI 的必需资源；普通 CI 不读取原版输入数据。

## 3. 已建立的验证基线

### G0：运行时骨架 — 已完成

- 320×200 根 Viewport、最近邻纹理和桌面键盘输入。
- 持久 `GameRoot`、Overlay、服务和 `GameSceneStack`。
- `GameSceneStack` 的 reset/replace 基线以及 push/pop API 边界。
- `GameRun` 中的 StoryState、GameFlags、WorldState 和 LocationState。
- 标题页、新游戏入口和必需素材诊断。

验收：Godot 4.8 可无错误加载；新游戏进入前厅；短生命周期地图节点不持有长期进度；没有 GameSession 或 GameFlow。

### G1：最小内容与剧情 API — 已完成当前片段所需子集

- MapDefinition、ContentDatabase 和两个语义地图 ID。
- DialogueDefinition、DialogueBlock、DialogueEntry 与命名 block。
- StoryEvent、StoryModule、StoryBinding、StoryOrigin、StoryContext 和 StoryDirector。
- `story.lab.borrowed_umbrella` 的六个 trigger 与六个 stage。
- FakeStoryContext 的确定性主路径测试。
- `content_cli.gd -- validate --json` 检查地图、story、stage、trigger 和 dialogue。

验收：故事只通过公共 StoryContext 推进；来源完成只能作用于当前 StoryOrigin；未知/重复内容结构由 validator 或测试暴露。

### G2：离线素材和两地图探索 — 已完成

- Rust `pal-godot-exporter` 的 `framework-lab` profile。
- RGBA Tile/角色/UI 图集、头像、BMFont、VOC WAV、RIX/OPL2 WAV 和 SHA-256 manifest。
- `map.lab.inn_hall` 与 `map.lab.rain_courtyard`。
- CharacterBody2D 移动、等距 TileMapLayer、碰撞、YSort、NPC、交互距离和 portal。
- AssetLibrary 的 manifest 加载，以及供场景直接引用的 Tile atlas。

验收：本地 exporter 可重复产生 20 条 manifest asset；仓库中的 `generated/` 可由 Godot 导入；两张地图可往返。

### G3：两地图原创故事 — 已完成

- 前厅 entry 引出掌柜，掌柜启动寻找旧伞主人的请求。
- 雨院 entry 只首次提示；蓑衣客确认旧伞；井边旧伞是一次性来源实体。
- 返回前厅后交付并进入 `completed`。
- 对话期间输入锁定，结束后恢复。
- stage、独立 flag 和 WorldState 各自表达不同事实。

验收：自动场景 smoke test 走完完整主路径；`complete_source_entity()` 立即隐藏旧伞并持久化完成态；地图替换后不会重置剧情。

### G4：存档、音频和视觉 QA — 已完成验证级基线

- SaveService 的版本化 GameRun 字典、临时文件写入与替换。
- F5/F9 测试性存取和加载失败不主动覆盖当前流程的入口检查。
- 场景音乐、交互音效、位图字体、头像、对话窗口和等待图标。
- 320×200 截图脚本和前厅/对话/雨院视觉检查。
- 工程加载、content validate、FakeStoryContext、场景主路径和存档往返回归。

验收：仓库中的 `generated/` 下 Tile、角色帧、透明、头像、字体和音频可用，缺少必需资源时产生明确诊断。

## 4. 下一阶段

### G5：加固当前创作接口 — 已完成

优先把已经证明有用的接口做完整，不立即增加玩法系统：

- 已完成：共享一层 `MapGameScene` 场景骨架；前厅和雨院在各自 `.tscn` 保存 TileMap 格子、碰撞、实体和 spawn，不再通过共享脚本硬编码布局。
- 已完成：validator 扫描 `.tscn` 的 TileSet/cell、trigger、portal target、spawn 和 persistent ID。
- 已完成：AssetLibrary 校验 manifest 中每个输出的存在性、类型与哈希，并给出结构化诊断；整包通过后才安装索引。
- 已完成：Content CLI 扫描全部 `stories/` Resource 和地图内嵌 StoryBinding，并提供 `list/show/schema/create` 的最小 Map/Dialogue/Story 支持与稳定 JSON 契约。
- 已完成：SceneStack 的 push/pop 结果、reset/replace、暂停、取消等待者、重入和输入隔离专门测试。
- 已完成：SaveService 的损坏 JSON、未知 schema、未知地图和原子替换失败回滚测试。
- 已完成：`docs/visual-acceptance.md` 固定截图命令、逐图检查项和 2026-08-12 验收记录。

验收：设计师或 AI 能仅凭具体文件/字段诊断修复两地图片段；失败的素材、内容和存档输入不会部分污染当前运行状态。

### G6：原创非战斗片段《雨夜药房》 — 已完成

第三张地图 `map.lab.herbal_room` 形成“获取药品 → 购买 → 打开菜单使用”的玩家可见闭环：

- 已完成：ActorDefinition/ActorState、PartyState、InventoryState 和 EconomyState，全部进入版本化 GameRun 存档。
- 已完成：ItemDefinition、EquipmentDefinition、SkillDefinition 与语义 ID 引用校验。
- 已完成：由草药和药露证明需要的 Heal/RestoreMp；Damage 留给 G7 战斗内容。
- 已完成：MenuGameScene、ShopDefinition/ShopGameScene、ItemUseResult 与 ShopResult。
- 已完成：TreasureChestEvent、ItemPickupEvent、ALL_OR_NOTHING/ALLOW_PARTIAL 领域规则和交易原子性。
- 已完成：药房场景 smoke 走完开箱、拾取、购买、菜单使用、push/pop 和存档往返。

验收：新增能力由独立药房地图证明，没有向《借来的伞》塞入无关宝箱或商店。

### G7：选择一个剧情战斗片段 — 下一阶段

在真实内容需要战斗后实现：

- EnemyDefinition、BattleEncounter 和最小 AI Strategy。
- BattleGameScene、BattleSession、规则状态与表现视图。
- 攻击、法术、物品、防御、逃跑、目标、行动顺序、伤害、死亡和胜负。
- StoryContext `start_battle()`、BattleResult 和 Victory/Escaped/Defeat 提交边界。
- 战斗奖励与 StoryModule 任务奖励的职责分离。

验收：地图剧情 push 战斗，pop 后恢复同一地图并继续当前故事调用；表现加速不改变规则结果。

### G8：内容规模化工具

仅在内容量形成实际维护成本后增加：

- RPG Database Dock 和专用 Dialogue Editor。
- 自动 catalog、反向引用、安全 ID 重命名和迁移。
- `export-json/apply-json/refs/story-test` 等高级 CLI。
- 更多 GameEffect、状态、敌人策略和常用 StoryEvent。
- 手柄、按键配置、文本本地化和正式多槽存档 UI。

不把“完整复刻《仙剑一》”或“兼容全部原版 opcode”设为验收条件。

## 5. 持续工作轨道

| 轨道 | 要求 |
|---|---|
| 运行时所有权 | GameRoot、GameSceneStack、GameRun 和短生命周期 Node 边界清晰 |
| 内容 schema | 一条定义一个 Resource、语义 ID、明确引用和逐步迁移规则 |
| 设计师 API | StoryContext 方法少而稳定，StoryModule 按叙事职责组织 |
| AI Agent | CLI JSON 稳定、错误具体、修改后可自动验证 |
| 素材 | `generated/` 随仓库维护；普通 CI 使用输出但不读取原版输入数据 |
| 测试 | 纯状态、剧情轨迹、场景 smoke、存档和 exporter 分层 |
| 文档 | 需求、架构、创作、素材和路线与实际实现同步 |

## 6. 主要风险

### 验证原型被误认为原作复刻

两张地图和对白都是原创；原版数据只提供本地提取素材。所有 UI、文档和 manifest 都应清楚区分玩法语义 ID 与 source chunk。

### StoryContext 变成上帝对象

StoryContext 是一次剧情调用的 facade，只暴露设计师高频的类型化用例。它不提供通用 Variant state、内部 Node 访问或任意世界实体写入口。

### StoryEvent 重新演变成 opcode

常用事件只表达完整用例。出现条件、分支和多步流程时使用普通 StoryModule GDScript，不添加 Jump/Loop/Call 或动作数组。

### 剧情进度与地图表现漂移

StoryState 表达叙事阶段，GameFlags 表达独立事实，WorldState 表达持久地图实体。一次性来源统一经 `complete_source_entity()` 更新当前表现和持久状态。

### 生成素材与场景引用漂移

地图 TileSet 直接引用 `generated/` atlas。重新导出后必须同时验证 manifest、文件路径、frame 数量、TileSet 和场景截图，避免资源更新后场景仍能加载但映射错误。

### 素材权利与来源

仓库维护 `generated/`，但不维护 Rust-PAL 原版输入数据或原版存档。维护者在提交、共享或公开发行派生素材及截图/录屏前负责确认相应权利和来源。
