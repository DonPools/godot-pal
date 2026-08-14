# 原创等距切片视觉验收

## 1. 自动检查

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
```

## 2. 截图

```sh
godot --path . -s res://tools/capture_isometric_art_test.gd
file /tmp/godot-pal-roadside/*.png
```

必须生成五张 `320 x 180` RGBA PNG：

- `title.png`：原创标题与素材状态。
- `roadside.png`：正式斜坡小铺自由探索画面。
- `tree_behind.png`：玩家位于树后。
- `tree_front.png`：玩家位于树前。
- `dialogue.png`：店主嵌入式 DialogueEvent 正在显示。

## 3. 人工检查

- 草地、石路、硬土与垄田均由 `32 x 16` 菱形 Tile 组成。
- 主角和店主使用 `24 x 32` 四斜向图集，脚底落在地面且停止时使用站立帧。
- 玩家不能穿过松树、小铺和围栏。
- 树前后两张图呈现正确的 YSort 遮挡。
- 对话框无旧头像、旧字体或旧 UI 图集引用，中文清晰且不越界。
- 标题、地图与对话均不出现旧验证片段名称或第三方游戏素材。
- 默认 `960 x 540` 窗口是内部画面的严格 3 倍；窗口可缩放并可切换全屏，世界中的 Tile、角色和物件保持原像素尺寸。
