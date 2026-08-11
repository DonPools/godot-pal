# Godot PAL

Godot PAL 是一个使用 Godot 原生方式开发的传统单机 RPG 学习与内容创作框架。

当前仓库已有一个可玩的最小垂直切片：使用 Rust-PAL 从用户本地合法持有的数据中离线提取图片、Tile、字体与音频，再由 Godot 将这些现有素材重新组合成两张原创地图和短故事《借来的伞》。这个片段用于验证框架，不复刻原版地图或剧情，也不读取原版 opcode、剧情脚本、事件入口和存档。

## 当前验证片段

两张地图和一个 StoryModule 组成完整的小闭环：

```text
听雨客栈·前厅（map.lab.inn_hall）
  与掌柜交谈，受托寻找旧伞主人
        ↓
听雨客栈·雨院（map.lab.rain_courtyard）
  找到蓑衣客，确认旧伞归属，取走井边旧伞
        ↓
返回前厅，把旧伞交给掌柜，完成故事
```

这个片段已经覆盖：

- `GameRoot`、`GameSceneStack` 与两张 MapGameScene 的 `replace` 切换。
- CharacterBody2D 移动、碰撞、等距 TileMapLayer、YSort、NPC 和交互物。
- `StoryBinding + StoryModule + StoryContext` 的多地图、多 trigger 剧情。
- 命名 Dialogue block、头像、原版位图字体、窗口素材、音乐和音效。
- StoryState、GameFlags、一次性来源完成、WorldState 和测试性存档往返。
- 没有本地版权素材时的程序化占位回退，便于工程 smoke test。

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
- Enter 或 Space：开始游戏、继续对话、与附近对象互动。
- F5：写入测试存档。
- F9：读取测试存档。

## 导出本地素材

素材导出器位于相邻的 Rust-PAL workspace。它只读取视觉、字体和音频白名单，不读取 `SSS.MKF`、`M.MSG`、原版剧情脚本、事件数据或存档。

```sh
cd ../../rust-pal
cargo run -p pal-godot-exporter --offline -- \
  --data data \
  --output ../godot-pal/pal/generated \
  --profile framework-lab \
  --json
```

`framework-lab` 当前导出 RGBA PNG 图集、BMFont `.fnt`、PCM16 WAV 和带 SHA-256 的 `manifest.json`。Godot 启动时验证 profile 并加载 `generated/`；目录不存在或 manifest 不可用时自动使用占位素材。

`generated/` 是本地、可重建且受版权约束的目录，已被 Git 忽略，不得提交或分发。

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

Godot 的场景测试会实际走完“前厅接任务 → 雨院找到蓑衣客 → 完成旧伞来源 → 返回交付”，并检查 StoryState、WorldState、地图切换和存档往返。临时移走 `generated/` 后，同一套测试也必须使用占位素材通过。

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

当前实现有意保持很小：它证明地图、剧情调用、素材映射和持久状态能够连成一个玩家可见闭环；商店、物品、完整角色成长和战斗仍由后续真实内容需求驱动。

## 文档

- [需求与范围](docs/requirements.md)
- [运行时架构](docs/architecture.md)
- [内容创作与设计师 API](docs/content-authoring.md)
- [素材导出管线](docs/asset-pipeline.md)
- [开发路线](docs/roadmap.md)
- [开发代理约束](AGENTS.md)

## 版权说明

本仓库不提供《仙剑奇侠传》的原始数据、图片、音乐、音效、字体或由这些内容生成的资源包。所有原版内容的权利归其各自权利人所有。公开发行前需要替换这些学习素材或取得相应授权。

项目代码的开源许可证尚未确定；在许可证明确前，不应假定代码可以被再分发。
