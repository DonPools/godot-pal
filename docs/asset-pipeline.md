# 本地素材提取管线

## 1. 目标与边界

Godot 运行时只消费普通 PNG、BMFont、WAV 和 JSON，不解析 MKF，也不依赖 Rust-PAL。素材始终沿单一方向流动：

```text
用户本地合法持有的原版数据
  -> Rust pal-assets 解码
  -> pal-godot-exporter 离线转换
  -> Godot 项目的 generated/
  -> Godot Import 与 AssetLibrary
```

当前管线服务 `framework-lab`：用现有素材组装听雨客栈前厅、雨院和原创短故事《借来的伞》。它不复刻原版地图或剧情。

明确禁止：

- 在 Godot 运行时读取 MKF、YJ_1、GOP、RLE、VOC 或 RIX。
- 导出或解释 `SSS.MKF`、`M.MSG`、opcode、事件入口、规则数据库和原版存档。
- 把原版 source chunk 当作 Map、Actor、Story 等玩法 ID。
- 将原版输入数据或原版存档提交到仓库；`generated/` 可以随项目维护，但提交和分发前必须确认相应权利。

## 2. 当前 exporter

exporter 位于 Rust-PAL workspace：

```text
../../rust-pal/pal-godot-exporter/
├── Cargo.toml
└── src/main.rs
```

当前只有一个 profile：`framework-lab`。输入白名单为：

| 输入 | 当前用途 |
|---|---|
| `PAT.MKF` | 白天 palette 0 |
| `GOP.MKF` | 两组地图 Tile sprite |
| `MGO.MKF` | 玩家和 NPC field character sprite |
| `RGM.MKF` | 对话头像 |
| `DATA.MKF` | 对话窗口与等待图标 |
| `WOR16.ASC`、`WOR16.FON` | Big5 字符映射和 16×15 位图字形 |
| `VOC.MKF` | 两个交互音效 |
| `MUS.MKF` | 一首 RIX/OPL2 场景音乐 |

输入文件都记录 SHA-256。profile 不读取 `MAP.MKF`，两张地图的布局、spawn、碰撞、portal、NPC 与 StoryBinding 全部由 Godot `.tscn` 原创维护。

## 3. 运行命令

从 Rust-PAL workspace 根目录执行：

```sh
cargo run -p pal-godot-exporter --offline -- \
  --data data \
  --output ../godot-pal/pal/generated \
  --profile framework-lab \
  --json
```

当前 CLI 只实现：

- `--data <directory>`：包含白名单输入的目录。
- `--output <directory>`：输出目录。
- `--profile framework-lab`：必须显式给出且只能使用该值。
- `--json`：成功或失败时输出机器可读摘要。

尚未实现 `category`、`reference-map`、`full-assets`、`--check` 或 `--manifest-only`，在真实工作流产生需求前不预设这些接口。

exporter 先写入同级 `.tmp` 目录，全部产物和 manifest 成功后才替换既有输出。成功 JSON 形如：

```json
{"ok":true,"profile":"framework-lab","asset_count":20,"manifest":"manifest.json"}
```

## 4. 当前输出

```text
generated/
├── manifest.json
├── textures/
│   ├── palettes/pat_000_day.png
│   ├── tiles/gop_0010/atlas.png
│   ├── tiles/gop_0012/atlas.png
│   ├── characters/mgo_*/atlas.png
│   ├── portraits/rgm_*.png
│   └── ui/data_*/atlas.png
├── fonts/
│   ├── pal_bitmap_16.png
│   └── pal_bitmap_16.fnt
└── audio/
    ├── sfx/voc_*.wav
    └── music/mus_0031.wav
```

共 20 条 manifest asset：1 个 palette、2 个 Tile atlas、5 个角色 atlas、5 个头像、2 个 UI atlas、2 个字体文件、2 个音效和 1 首音乐。当前仓库同时维护这些输出和 Godot 的相邻 `.import` 描述文件；`.import` 不是 exporter 产物。

## 5. Manifest 契约

顶层结构：

```json
{
  "schema_version": 1,
  "source_variant": "dos_zh",
  "export_profile": "framework-lab",
  "exporter_version": "0.1.0",
  "source_hashes": {
    "GOP.MKF": "..."
  },
  "assets": []
}
```

每条 asset 包含：

- `kind`：如 `tile_atlas`、`field_character_atlas`、`portrait`、`bitmap_font`、`sound_effect` 或 `music`。
- `source.file`、可选 `source.chunk` 和 `source.palette`：仅用于追踪与重导出。
- `path`：相对于 `generated/` 的确定性输出路径。
- `sha256`：输出文件内容哈希。
- `metadata`：图集 cell、帧、pivot、音频采样率等类型相关元数据。

Godot 内容使用 `map.lab.inn_hall`、`map.lab.rain_courtyard` 和 `story.lab.borrowed_umbrella` 等语义 ID。manifest 中的 `GOP.MKF:10` 或 `MGO.MKF:2` 不得进入玩法状态和存档。

## 6. 图片与图集

- 原始索引色图像通过选定 palette 转换为无损 RGBA PNG，透明语义由 `pal-assets` 解码器统一处理。
- Tile、角色和 UI 按固定列数打入 atlas；manifest 保存 cell size、atlas 坐标、原帧尺寸和 bottom-center pivot。
- field character 若至少有 12 帧，会记录四方向、每方向三帧和步行循环提示。
- Tile metadata 记录 `logical_tile_size: [32, 16]` 和 texture origin；Godot 运行时据此创建 TileSet Atlas Source。
- 项目全局关闭 Canvas 纹理过滤；不得对像素素材做有损压缩、MipMap 或插值缩放。

`.tscn` 是场景布局真相。exporter 只提供可选择的素材 atlas，不能覆盖设计师维护的碰撞、遮挡、spawn、persistent ID 或 StoryBinding。

## 7. 字体

exporter 使用 `WOR16.ASC` 的 Big5 编码表，把 `WOR16.FON` 中可映射的 16×15 字形转换为 Unicode BMFont：

- `pal_bitmap_16.png` 是白色透明字形 atlas。
- `pal_bitmap_16.fnt` 是 Godot 可导入的文本 BMFont descriptor。
- DialogueDefinition 始终保存项目原创的 UTF-8 文本。
- 无法由原版字库覆盖的字符由 Godot fallback font 处理；不因此读取 `M.MSG`。

## 8. 音频

- VOC 以原采样率解码为单声道 PCM16 WAV。
- RIX 通过 Rust `RixSequencer + nuked-opl3` 离线合成为 44.1 kHz 双声道 PCM16 WAV。
- manifest 记录 channels、sample rate、sample frames 和循环范围建议。
- Godot 只播放 WAV，不实时模拟 OPL2，也不要求 SoundFont。

## 9. Godot 集成与必需资源

地图 TileSet 直接引用 `res://generated/textures/tiles/.../atlas.png`，TileMap cell 保存在具体地图 `.tscn`。`AssetLibrary` 启动时读取 `res://generated/manifest.json`，只接受 schema 1 和 `export_profile == "framework-lab"`；它先校验 20 个必需 source、规范化相对路径、PNG/FNT/WAV 文件签名和 SHA-256，全部通过后才按 `source.file + source.chunk` 建立索引，并把 BMFont 交给 DialogueLayer。失败诊断包含稳定 code、file、field 和可用的 source。

`generated/`、manifest 和场景引用的 atlas 都是工程与普通 CI 的必需资源。目录不存在、JSON 无效、profile 不匹配或条目不能加载时：

- AssetLibrary 输出明确错误诊断。
- 直接引用缺失 atlas 的 TileSet 不能通过工程加载或内容校验。
- 个别角色、头像或字体的程序化 fallback 只用于防止诊断界面崩溃，不构成无素材工程模式。
- 不可用的音乐和音效可以保持静默，但仍属于素材校验失败。

重新导出 `generated/` 后必须复核 manifest 路径、hash、frame 数量、TileSet atlas 坐标和场景截图。

可重复的截图与人工检查步骤见 `docs/visual-acceptance.md`。

## 10. 验证

Rust exporter：

```sh
cd ../../rust-pal
cargo test -p pal-godot-exporter --offline
cargo clippy -p pal-godot-exporter --offline -- -D warnings
```

Godot 导入与场景：

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
```

验收要点：

- 所有 PNG、`.fnt` 和 WAV 能由 Godot 无错误导入。
- manifest profile、条目路径、元数据和哈希与实际输出一致。
- 两组 Tile、角色透明与方向帧、头像、字体、等待图标和音频在 320×200 最近邻画面中正常。
- `generated/` 存在且 AssetLibrary 报告 profile 加载成功；缺失必需 atlas 或无效 TileSet cell 时内容校验失败。
- 输出不包含剧情、地图布局、脚本、事件、规则数据库和存档。

## 11. 版权与发布

- `generated/` 随当前项目维护；维护者在提交、共享或公开发行派生素材及其截图/录屏前负责确认相应权利。
- Rust-PAL 的原版输入 `data/` 和原版存档不得提交。普通 CI 使用仓库中的 `generated/`，不读取原版输入数据。
- 本地日志可以记录文件名、source chunk、尺寸与哈希，但不输出大段原始数据。
- 公开发行派生素材前必须取得明确授权；没有授权时需要替换相应素材。
