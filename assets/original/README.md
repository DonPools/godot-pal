# 原创素材包

本目录只保存当前固定视角 3D 游戏使用或可确定性重建的原创素材，不依赖《仙剑奇侠传》、
Rust-PAL 输入、第三方游戏提取资源或旧 `generated/` 输出。

## 目录

```text
assets/original/
├── 3d/       低多边形模型、材质、纹理、manifest 与确定性生成脚本
└── audio/    地图、战斗和动作音频及确定性生成脚本
```

运行时只引用 GLB、Texture2D、Material、PackedScene 与 AudioStream Resource。地图结构、碰撞、
导航、NPC、StoryBinding 和 persistent ID 继续由 Godot `.tscn` 维护，不使用整张场景插画。

## 3D 素材

`3d/sources/generate_lowpoly_assets.py` 确定性生成：

- 基础旅人、共骨骼人形变体和山路敌人；
- 统一 13 骨骼以及 idle/run/attack/cast/hit/death 六组动画；
- 直剑、短杖、完整/割后返青草；
- 地面、道路、岩石、松树、灌木、围栏、小铺和生态细节模块。

全部模型使用米、+Y 向上、-Z 前向和脚底原点。`3d/manifest.json` 记录 GLB 哈希、三角面、
骨骼、动画、材质、纹理与导入边界；`game/presentation/action_combat_3d/original_3d_asset_validator.gd`
验证这些约束。

`3d/sources/render_title_portrait.gd` 从正式旅人 GLB 确定性渲染
`3d/title_traveler_portrait.png`，避免维护第二套角色画法。详细命令见
[`3d/README.md`](3d/README.md)。

## 音频

`audio/sources/generate_action_combat_audio.py` 确定性生成山路循环、战斗循环、攻击、施法、
闪避和三种战斗结果音频。文件清单与重建命令见 [`audio/README.md`](audio/README.md)。

## 验证

```sh
python3 assets/original/3d/sources/generate_lowpoly_assets.py
python3 assets/original/audio/sources/generate_action_combat_audio.py
godot --headless --path . -s res://tests/run_tests.gd
godot --path . -s res://game/presentation/action_combat_3d/tools/capture_g3_assets.gd
```

生成脚本重跑后必须核对 manifest、导入结果、共享动画、脚点、碰撞、固定镜头轮廓和
`640 x 360` 截图，不得手工修改派生 GLB 后绕过记录。
