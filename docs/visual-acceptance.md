# Framework Lab 视觉验收记录

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

脚本在保存前把所有 `AnimatedSprite2D` 固定到第 0 帧，避免角色动画采样造成无意义差异。必须生成十一个 `320 x 200` RGBA PNG：

| 文件 | 固定状态 |
|---|---|
| `title.png` | 标题、新游戏、读取与设置入口 |
| `hall.png` | 前厅 entry 对话结束后的自由探索画面 |
| `hall_dialogue.png` | 前厅 opening 对话正在显示 |
| `courtyard.png` | `looking_for_owner` 阶段进入雨院后的自由探索画面 |
| `herbal_room.png` | G6 药房地图、药师、药箱和药露 |
| `menu.png` | G6 行囊菜单和队伍状态 |
| `shop.png` | G6 雨夜药房商品与金钱界面 |
| `broken_bridge.png` | G7 断桥地图与伏击敌人 |
| `battle.png` | G7 BattleGameScene 初始命令界面 |
| `save_slots.png` | G8 正式三槽保存界面 |
| `settings.png` | G8 音频、语言、键盘与手柄提示界面 |

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

### G6 药房、菜单和商店

- `herbal_room.png` 左上显示“听雨客栈·药房”，药师、药箱、药露和返回门均可辨认。
- `menu.png` 的队长 HP/MP、金钱和行囊列表不越界，提示文字清楚。
- `shop.png` 显示两种药品、说明、单价和现有金钱，焦点与边框完整。

### G7 断桥与战斗

- `broken_bridge.png` 显示断桥地图、玩家、匪徒和返回雨院的路径，角色脚底与 Tile 对齐。
- `battle.png` 显示双方 HP/MP、攻击/技能/物品/防御/逃跑五个命令与完整边框。

### G8 标题、存档与设置

- `title.png` 的新游戏、读取和设置三个入口清楚可辨，焦点边框、头像和底部素材诊断不重叠。
- `save_slots.png` 显示三个独立槽位，空槽/有效槽文案、标题、状态和返回提示在 320×200 内完整。
- `settings.png` 显示音乐、音效、中文/English 选择、六项键盘动作、修改按键按钮与手柄映射提示。

## 5. 交互与音频补充

需要发行前人工复核时，运行 `godot --path .` 并确认：

- 方向键移动保持像素清晰，角色四方向动画与朝向一致。
- Enter/Space 交互时只触发一次音效，对话期间玩家不能移动。
- 前厅与雨院 BGM 连续播放，portal 音效和普通交互音效可区分。
- 窗口关闭、跨地图、正式存读档和 F5/F9 调试存档后没有残留 UI 或重复输入。

音频文件存在性、WAV 签名和哈希由自动校验覆盖；是否听感正常仍属于带扬声器环境的人工发行检查。

## 6. 2026-08-12 基线记录

环境：Godot `4.8.dev.custom_build.4173760fd`，macOS Metal Compatibility renderer。

| 文件 | SHA-256（仅追踪本次产物） | 结果 | 备注 |
|---|---|---|---|
| `hall.png` | `e0b426ec991dd26961b5fa9053900065a046e29e8714b1fd9ae0f33ee85fee27` | 通过 | 前厅 Tile、三名角色、HUD 正常 |
| `hall_dialogue.png` | `434ba0b8dba26d4dc2fa79a971582ac6bade271c2ab4b859ba7d92f452fc7abe` | 通过 | 头像、字体、窗口、等待图标正常 |
| `courtyard.png` | `e35eed2e7124438f17aff6ff441aba16263110eb06d5b92bc23b58be870820f2` | 通过 | 雨院 Tile、蓑衣客、旧伞、目标文字正常 |

| `herbal_room.png` | `9884345d242748aaf97f93eeb5317fe4795ae272699700f8346fdd1d99b096ff` | 通过 | 药师、药箱、药露、返回门与地图 HUD 正常 |
| `menu.png` | `99dfa6e7031b434ed540e8ad1683582a59b8d1a513a8fe2d92d374fbe32c7c4a` | 通过 | 队长状态、两种药品、存读档/设置入口与操作提示正常 |
| `shop.png` | `490bd581e46969149ea2df5f1749c1df08759df876cec0d1a96ac3eb2c5445c9` | 通过 | 两种药品、单价、说明、现有金钱与操作提示正常 |
| `broken_bridge.png` | `6c935a8836991622dadd5574aa221e756d99a3a9828ad73e16a39ff105599134` | 通过 | 断桥 Tile、玩家、匪徒与地图 HUD 正常 |
| `battle.png` | `7cd7ba0a6f1f0ea891d2048ab4de378110877884e097cf0295791258106cfa02` | 通过 | 双方状态、五个命令、滚动列表与红色战斗边框正常 |

G8 新增界面在同一环境的基线：

| 文件 | SHA-256（仅追踪本次产物） | 结果 | 备注 |
|---|---|---|---|
| `title.png` | `879f40ad3b00d0c6de149ab4ecf1dc4b34a431ccc677d35cfa3adb380d5b50ec` | 通过 | 新游戏、读取、设置入口完整 |
| `save_slots.png` | `c3300708d5ec4c7efaa3956008cdd8b984e4f5e6e380e30c9f92938767584a63` | 通过 | 三槽、空槽与操作提示完整 |
| `settings.png` | `28ea418775988c49b64df17e78ce265cd3d66604e6cc28051cef8f3ce929fad6` | 通过 | 音频、语言、按键、手柄提示完整 |

不同 Godot 构建或渲染后端可能改变 PNG 编码或像素结果；哈希变化要求重新执行本页检查，不直接等同于失败。
