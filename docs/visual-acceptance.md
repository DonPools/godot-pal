# 原创等距切片视觉验收

## 1. 自动检查

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
```

## 2. 截图

```sh
godot --path . -s res://game/roadside/tools/capture_isometric_art_test.gd
file /tmp/godot-pal-roadside/*.png
```

必须生成十二张 `320 x 180` RGBA PNG：

- `title.png`：原创标题与素材状态。
- `roadside.png`：正式斜坡小铺自由探索画面。
- `tree_behind.png`：玩家位于树后。
- `tree_front.png`：玩家位于树前。
- `dialogue.png`：店主的采药委托正在显示。
- `commission_choice.png`：接下差事或稍后再说的语义选项。
- `route_choice.png`：旧石路与碎石近坡的路线选项。
- `herb_slope.png`：三丛完整返青草和回程围栏。
- `harvest_choice.png`：割叶留根与连根挖走的采法选项。
- `herb_left_root.png`：采后仍保留矮株和根系。
- `herb_regrown.png`：第二趟同一脚点重新长成完整植株。
- `herb_uprooted.png`：连根采走后同一来源保持消失。

## 3. 人工检查

- 草地、石路、硬土与垄田均由 `32 x 16` 菱形 Tile 组成。
- 主角和店主使用 `24 x 32` 四斜向图集，脚底落在地面且停止时使用站立帧。
- 玩家不能穿过松树、小铺和围栏。
- 树前后两张图呈现正确的 YSort 遮挡。
- 对话框无旧头像、旧字体或旧 UI 图集引用，中文清晰且不越界。
- 两个选项按钮不重叠，长对白不会被按钮裁切，键盘/手柄焦点清楚。
- 完整、割后、再生和消失状态使用同一地图脚点，药草不会漂浮或被平滑缩放。
- 北坡截图来自固定 seed 烘焙的 `32 x 16` TileMap；湿润林缘、干燥松林、碎石坡、旧路和
  人工清地能够从地表与物件分布中辨认，但不出现均匀随机撒点。
- 生成松树、灌木、岩石和倒木与玩家、药草共享 YSort；阻挡物不覆盖道路、spawn、Portal、
  三处药草或对话构图。
- Camera 周围不出现占据主要画面的地图外黑区；地图边缘允许少量留黑，但玩家出生与采集
  画面的主体始终位于有效地表内。
- 标题、地图与对话均不出现旧验证片段名称或第三方游戏素材。
- 默认 `960 x 540` 窗口是内部画面的严格 3 倍；窗口可缩放并可切换全屏，世界中的 Tile、角色和物件保持原像素尺寸。
