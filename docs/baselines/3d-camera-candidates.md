# 固定视角 3D 摄影机候选

历史说明：本文件记录 G0/G1 的摄影机选择。G6 完成后原型捕获脚本已删除，正式截图入口为
`game/roadside/action_combat_3d/tools/capture_g6_formal_slice.gd`。

记录日期：2026-08-18

## 1. 结论

默认摄影机：

- yaw：45°
- elevation：35.264°
- offset：`Vector3(10, 10, 10)`
- projection：orthogonal
- orthographic size：12
- 玩家胶囊体在 `640 x 360` 中的投影高度：约 48.99 像素
- 构图：朝玩家瞄准方向前看 2.4 world unit，让遭遇空间落在 HUD 下方的主要可视区

动作可读性备选：

- yaw：45°
- elevation：29.496°
- offset：`Vector3(10, 8, 10)`
- orthographic size：12
- 玩家投影高度：约 52.22 像素

44.711° 高角度候选不进入后续默认配置。它能展示更多地面关系，但玩家投影高度只有约 42.64
像素，后方角色也更容易与顶部 HUD、较高障碍形成遮挡。

## 2. 生成方法

```sh
godot --path . -s res://game/prototypes/action_combat_3d/capture_camera_candidates.gd
```

输出目录：`/tmp/godot-pal-action-combat-3d/`

| 候选 | elevation | 角色高度 | SHA-256 |
|---|---:|---:|---|
| `camera_true_iso.png` | 35.264° | 48.99 px | `8c9dccda5619daa5ab92575f308b0ccea7a43e4f4d0bd19e57258aa2b83e4a0d` |
| `camera_low_action.png` | 29.496° | 52.22 px | `28f3169db36abe8f510323f4685e4fdd7d27df7e2bd2d0b64a91b2c75156e290` |
| `camera_high_clarity.png` | 44.711° | 42.64 px | `a32b0cf40b2dd49ab3176486b82b9c36286f5b1e74d8b423a42304f98b9c6dfc` |

三张截图均为 `640 x 360`。hash 标识本次视觉基线，不作为跨 Godot 或 GPU 的像素级自动断言。

## 3. 选择依据

- 真等距候选符合现有斜 45 度地图阅读习惯，并达到计划规定的 48 至 64 像素角色高度。
- 低角度候选让角色与动作轮廓略大，适合在正式动画出现后重新比较，但地面与敌群纵深更压缩。
- 高角度候选更像战术视图，不适合当前强调人物动作和攻击前摇的目标。
- 固定镜头向瞄准方向前看，避免玩家始终占据画面中心而把前方敌人推到 HUD 下方。
- 后续摄影机不允许玩家自由旋转；剧情镜头仍由独立 CameraRig 高层用例控制。
