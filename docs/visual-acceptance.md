# 固定视角 3D 正式切片视觉验收

## 1. 自动检查

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
```

## 2. 截图

```sh
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_g6_formal_slice.gd
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_g4_formal_slice.gd
file /tmp/godot-pal-g6/*.png /tmp/godot-pal-g4/*.png
```

G6 必须生成十一张 `640 x 360` RGBA PNG：

- `01_title.png`：原创标题、3D 旅人派生头像与素材状态。
- `02_north_slope_wilds.png`：新游戏默认进入的 `64 x 32` 北坡生态原野。
- `03_roadside_shop.png`：斜坡小铺自由探索画面。
- `04_shopkeeper_dialogue.png`：店主采药委托正在显示。
- `05_commission_choice.png`：接下差事或稍后再说的语义选项。
- `06_route_choice.png`：旧石路与碎石近坡的路线选项。
- `07_herb_slope_full.png`：完整返青草与固定正交镜头构图。
- `08_harvest_choice.png`：割叶留根与连根挖走的采法选项。
- `09_herb_cut.png`：采后保留的可辨根茬。
- `10_herb_regrown.png`：第二趟同一脚点重新长成完整植株。
- `11_herb_uprooted.png`：连根采走后同一来源保持消失。

G4 继续生成七张战斗图：探索、警戒、敌人前摇、投射物/障碍、Victory、Escaped 和 Defeat。

## 3. 人工检查

- 草地、旧路、湿地与碎石坡来自 schema v2 逻辑格烘焙的 3D 模块，色值不过曝。
- 主角和店主通过 ActorDefinition/NpcDefinition 注入共骨骼 GLB，脚底落在 y=0。
- 玩家不能穿过松树、小铺和围栏。
- 固定 yaw/pitch 下角色、NPC、树木、攻击范围和投射物前后关系清楚。
- 对话框使用紧凑的“山野行笺”样式：22px 米白正文、18px 暗金姓名签、细暗金边框，文字无模糊投影且不越界。
- 普通对白不会遮住大半场景；两个纵向选项按钮不重叠，长对白不会被按钮裁切，键盘/手柄焦点有明确的金色左边标记。
- 完整、割后、再生和消失状态使用同一地图脚点，药草不会漂浮或被平滑缩放。
- 药草坡截图来自固定 seed 烘焙的 `32 x 16` 3D 逻辑格；湿润林缘、干燥松林、碎石坡、旧路和
  人工清地能够从地表与物件分布中辨认，但不出现均匀随机撒点。
- 北坡原野截图来自 seed `260816` 的 `64 x 32` Bake；出生点落在旧路保护区内，左侧人工
  围栏可通往小铺，Camera 视野内有可辨认的生态层次且不被环境物件封死。
- 生成松树、灌木、岩石和倒木具有明确 Mesh/碰撞/导航影响；阻挡物不覆盖道路、spawn、Portal、
  三处药草或对话构图。
- Camera 周围不出现占据主要画面的地图外黑区；地图边缘允许少量留黑，但玩家出生与采集
  画面的主体始终位于有效地表内。
- 标题、地图与对话均不出现旧验证片段名称或第三方游戏素材。
- 默认 `1280 x 720` 窗口是内部画面的严格 2 倍；窗口可缩放并可切换全屏，固定镜头构图和 UI 比例不变。
- 标题、HUD、菜单和对话使用原生双倍字号，中文笔画清晰，不依赖低分辨率 UI 放大。
- 任意窗口尺寸只选择完整整数倍并以黑边补足；移动时 Camera3D 没有明显几何抖动或边缘闪烁。
- GridMap cell 不出现黑缝，导航与视觉 cell 中心一致，地表材质保持有限、非荧光的山野色板。

## 4. 战斗视觉门

G1 灰盒截图、录像和压力指标保存在 `docs/baselines/3d-action-combat-g1.md`，G4 正式战斗证据
保存在 `docs/baselines/3d-action-combat-g4.md`。固定摄影机截图必须覆盖探索全景、三敌遮挡、近战前摇、投射物路径、闪避命中、
死亡、Victory、Escaped、Defeat 和最长中文 HUD。角色在 `640 x 360` 中保持约 48–64 像素高；
固定 yaw/pitch 下前后关系、攻击范围与地面障碍清楚，窗口缩放不改变构图或 UI 清晰度。
