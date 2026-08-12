# 《借来的伞》视觉验收记录

## 1. 用途

本记录把 `framework-lab` 的手工视觉检查固定为可重复流程。截图只作为本地验收产物写入 `/tmp/godot-pal-framework-lab/`，不作为跨平台像素哈希 golden，也不提交到仓库。

自动测试继续负责剧情状态、TileMap cell、输入锁、地图切换和存档；本记录只覆盖需要人眼判断的构图、素材映射和 UI 可读性。

## 2. 前置检查

在仓库根目录执行：

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
```

三项必须以退出码 0 完成。`validate` 会逐条检查 `framework-lab` manifest 的必需输出、路径、文件类型与 SHA-256，因此视觉检查不接受 fallback 素材作为通过条件。

## 3. 生成截图

使用带显示渲染器的 Godot 执行：

```sh
godot --path . -s res://tools/capture_framework_lab.gd
file /tmp/godot-pal-framework-lab/*.png
```

脚本在保存前把所有 `AnimatedSprite2D` 固定到第 0 帧，避免角色动画采样造成无意义差异。必须生成三个 `320 x 200` RGBA PNG：

| 文件 | 固定状态 |
|---|---|
| `hall.png` | 前厅 entry 对话结束后的自由探索画面 |
| `hall_dialogue.png` | 前厅 opening 对话正在显示 |
| `courtyard.png` | `looking_for_owner` 阶段进入雨院后的自由探索画面 |

## 4. 逐图检查

### 通用

- 画面严格为 `320 x 200`，像素边缘清晰，没有过滤、MipMap、插值缩放或有损压缩痕迹。
- 地图菱形格、角色脚底和交互物对齐；角色没有悬空、切脚或明显偏离格心。
- 地图外黑色留白、HUD 和场景内容之间没有未预期的覆盖。

### `hall.png`

- 左上显示“听雨客栈·前厅”，底部显示当前操作或目标文字，字形完整且不越界。
- 前厅使用灰色地砖和红色墙面；玩家、掌柜与住客均使用正确角色图集。
- 玩家和 NPC 的脚底排序自然，人物没有被地砖错误遮挡。

### `hall_dialogue.png`

- 对话窗位于画面下部且四边完整，不盖住左上地图名。
- 头像比例正确、透明边缘干净；说话人名称与两行正文使用位图字体并保持可读。
- 黄色等待图标位于窗口右下，未超出边框。

### `courtyard.png`

- 左上显示“听雨客栈·雨院”，底部目标文字为“去雨院寻找蓑衣客”。
- 雨院使用与前厅不同的棕色 Tile atlas；蓑衣客、井边旧伞和玩家素材映射正确。
- 人物、墙面和地面层次清楚，没有透明底色块或错误 atlas frame。

## 5. 交互与音频补充

需要发行前人工复核时，运行 `godot --path .` 并确认：

- 方向键移动保持像素清晰，角色四方向动画与朝向一致。
- Enter/Space 交互时只触发一次音效，对话期间玩家不能移动。
- 前厅与雨院 BGM 连续播放，portal 音效和普通交互音效可区分。
- 窗口关闭、跨地图和 F5/F9 后没有残留 UI 或重复输入。

音频文件存在性、WAV 签名和哈希由自动校验覆盖；是否听感正常仍属于带扬声器环境的人工发行检查。

## 6. 2026-08-12 基线记录

环境：Godot `4.8.dev.custom_build.4173760fd`，macOS Metal Compatibility renderer。

| 文件 | SHA-256（仅追踪本次产物） | 结果 | 备注 |
|---|---|---|---|
| `hall.png` | `ed1c9a7fdd7771732fb93d643e24f495628ec832707a0e04ec668fa4484e13ed` | 通过 | 前厅 Tile、三名角色、HUD 正常 |
| `hall_dialogue.png` | `ffb405f3c810cc34203f05acf3b1ec0210a594fb9498a8544d6b73d522e7d393` | 通过 | 头像、字体、窗口、等待图标正常 |
| `courtyard.png` | `ecd3e54be91f620f7cd4e5769dfedad83fe1ff35eec575b0e1121470869dbb7e` | 通过 | 雨院 Tile、蓑衣客、旧伞、目标文字正常 |

不同 Godot 构建或渲染后端可能改变 PNG 编码或像素结果；哈希变化要求重新执行本页检查，不直接等同于失败。
