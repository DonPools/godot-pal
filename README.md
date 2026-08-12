# Godot PAL

Godot PAL 是一个使用 Godot 原生方式开发的传统单机 RPG 学习与内容创作框架。

当前仓库已有一个可玩的最小垂直切片：使用 Rust-PAL 从用户本地合法持有的数据中离线提取图片、Tile、字体与音频，再由 Godot 将这些现有素材重新组合成两张原创地图和短故事《借来的伞》。这个片段用于验证框架，不复刻原版地图或剧情，也不读取原版 opcode、剧情脚本、事件入口和存档。

## 当前验证片段

《借来的伞》两张地图和一个 StoryModule 组成剧情闭环；独立的《雨夜药房》片段提供第三张地图：

```text
听雨客栈·前厅（map.lab.inn_hall）
  与掌柜交谈，受托寻找旧伞主人
		↓
听雨客栈·雨院（map.lab.rain_courtyard）
  找到蓑衣客，确认旧伞归属，取走井边旧伞
		↓
返回前厅，把旧伞交给掌柜，完成故事

听雨客栈·药房（map.lab.herbal_room）
  开药箱与拾取药露 → 购买药品 → 在行囊中使用

听雨客栈·断桥（map.lab.broken_bridge）
  遭遇匪徒 → 攻击/技能/物品/防御/逃跑 → 剧情按结果续接
```

这个片段已经覆盖：

- `GameRoot`、`GameSceneStack` 与两张 MapGameScene 的 `replace` 切换。
- CharacterBody2D 移动、碰撞、等距 TileMapLayer、YSort、NPC 和交互物。
- `StoryBinding + StoryModule + StoryContext` 的多地图、多 trigger 剧情。
- 命名 Dialogue block、头像、原版位图字体、窗口素材、音乐和音效。
- StoryState、GameFlags、一次性来源完成、WorldState 和带失败回滚的正式三槽存档。
- 共享 `MapGameScene` 骨架、场景内可编辑的 TileMap 布局，以及直接引用 `generated/` atlas 的 TileSet。
- manifest 文件存在性、类型与 SHA-256 校验，以及 11 类内容的 catalog、查询、创建、引用、JSON 应用与迁移 CLI。
- Actor/Party/Inventory/Economy、Heal/RestoreMp、菜单、商店与原子奖励/交易。
- Enemy/BattleEncounter、BattleSession/BattleGameScene、Damage 与 Victory/Escaped/Defeat 提交边界。
- PAL Database Dock、可保存的 Dialogue Editor、雨寒状态、第二种敌人策略与常用零代码事件。
- 键盘重绑、手柄默认映射、中英 UI、音乐/音效开关与三槽存读档界面。

故事内容使用语义 ID，例如：

```text
map.lab.inn_hall
map.lab.rain_courtyard
story.lab.borrowed_umbrella
dialogue.lab.borrowed_umbrella
flag.story.lab.borrowed_umbrella.courtyard_seen
```

素材 manifest 中的 `GOP.MKF:10`、`MGO.MKF:2` 等 source 信息只用于追踪提取来源，不进入玩法 ID 或存档协议。

## 运行

需要 Godot 4.8。在本目录执行：

```sh
godot --editor --path .
```

也可以直接运行项目：

```sh
godot --path .
```

操作方式：

- 方向键：等距四方向移动。
- Enter 或 Space / 手柄 A：继续对话、确认、与附近对象互动。
- M / 手柄 Start：打开或关闭行囊菜单。
- F6：从行囊打开保存界面；标题页可以读取存档和打开设置。
- F5：写入测试存档。
- F9：读取测试存档。

## 素材资源与重新导出

素材导出器位于相邻的 Rust-PAL workspace。它只读取视觉、字体和音频白名单，不读取 `SSS.MKF`、`M.MSG`、原版剧情脚本、事件数据或存档。

```sh
cd ../../rust-pal
cargo run -p pal-godot-exporter --offline -- \
  --data data \
  --output ../godot-pal/pal/generated \
  --profile framework-lab \
  --json
```

`framework-lab` 当前导出 RGBA PNG 图集、BMFont `.fnt`、PCM16 WAV 和带 SHA-256 的 `manifest.json`。`generated/` 是当前工程、地图 TileSet 和普通 CI 的必需资源；缺失或 manifest 不可用属于工程配置错误。

当前仓库维护 `generated/` 输出，以上命令用于从有权使用的输入重新生成和更新它。提交或分发这些资源前，维护者需要自行确认拥有相应权利。

## 验证

Godot 工程、内容和场景回归：

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
```

Rust exporter：

```sh
cd ../../rust-pal
cargo test -p pal-godot-exporter --offline
cargo clippy -p pal-godot-exporter --offline -- -D warnings
```

Godot 的场景测试会实际走完“前厅接任务 → 雨院找到蓑衣客 → 完成旧伞来源 → 返回交付”，并检查 TileMap 场景数据、StoryState、WorldState、地图切换和存档往返。内容校验还会检查 TileSet、spawn、persistent ID、trigger 和 portal 目标。

内容 CLI 支持稳定 JSON 的派生目录、查询、模板、引用和批量工作流：

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
godot --headless --path . -s res://tools/content_cli.gd -- story-test <story-id> <trigger-id> [stage] [outcome] --json
```

支持的类型为 Actor、Item、Equipment、Skill、Status、Enemy、Shop、Encounter、Map、Dialogue 和 Story。模板创建后仍需显式登记或引用；自动 catalog 只从现有 Resource 派生，不是第二份内容真相。详细契约见内容创作文档。

## 架构边界

```text
ContentDatabase   静态 Resource 定义与索引
GameRun           一次游戏的可序列化状态
GameSceneStack    标题、地图、菜单、商店和战斗流程
StoryModule       普通类型化 GDScript 编写的复杂剧情
StoryContext      剧情可调用的稳定高层 API
```

- `.tscn` 负责对象组合和生命周期，Resource 负责静态内容，RefCounted 负责运行状态。
- 当前地图的 PlayerCharacter、NPC 与交互物随 MapGameScene 创建和销毁。
- 对话是 Overlay 模态 UI；地图切换由 GameSceneStack 管理。
- StoryModule 不访问内部场景路径和服务，也不直接修改 GameRun 集合。
- 不建立 GameSession、GameFlow、EventSequence、自制 opcode 或原版脚本兼容层。

当前实现以《借来的伞》《雨夜药房》《断桥伏击》分别证明地图剧情、非战斗事务和剧情战斗。

## 文档

- [需求与范围](docs/requirements.md)
- [运行时架构](docs/architecture.md)
- [内容创作与设计师 API](docs/content-authoring.md)
- [素材导出管线](docs/asset-pipeline.md)
- [开发路线](docs/roadmap.md)
- [视觉验收记录](docs/visual-acceptance.md)
- [开发代理约束](AGENTS.md)

## 版权说明

本仓库不包含《仙剑奇侠传》的原始输入数据或原版存档，但当前维护 `framework-lab` 导出的图片、字体和音频资源。所有原版内容的权利归其各自权利人所有；使用或分发这些派生资源前必须确认拥有相应授权。

项目代码的开源许可证尚未确定；在许可证明确前，不应假定代码可以被再分发。
