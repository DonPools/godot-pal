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
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_r7_lantern_foundation.gd
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_ui_baseline.gd
file /tmp/godot-pal-g6/*.png /tmp/godot-pal-g4/*.png /tmp/godot-pal-r7/*.png /tmp/godot-pal-ui/*.png
```

G6 必须生成十一张 `640 x 360` RGBA PNG：

- `01_title.png`：原创标题、3D 旅人派生头像、左右分区和纵向主菜单；正常状态不显示开发诊断。
- `02_north_slope_wilds.png`：G6 工具显式进入的 `64 x 32` 北坡生态原野。
- `03_roadside_shop.png`：斜坡小铺入口构图，木栅“北坡原野”和幼松“北坡药草地”出口标牌同时可辨。
- `04_shopkeeper_dialogue.png`：店主采药委托正在显示。
- `05_commission_choice.png`：接下差事或稍后再说的语义选项。
- `06_route_choice.png`：旧石路与碎石近坡的路线选项。
- `07_herb_slope_full.png`：完整返青草与固定正交镜头构图。
- `08_harvest_choice.png`：割叶留根与连根挖走的采法选项。
- `09_herb_cut.png`：采后保留的可辨根茬。
- `10_herb_regrown.png`：第二趟同一脚点重新长成完整植株。
- `11_herb_uprooted.png`：连根采走后同一来源保持消失。

G4 生成八张战斗图：探索、警戒、敌人前摇、投射物/障碍、命中反馈、Victory、Escaped 和 Defeat。

- `01_exploration.png`：探索构图与语义入口提示。
- `02_alert.png`：有限敌群进入战斗。
- `03_windup.png`：敌人前摇范围可读。
- `04_projectile_obstruction.png`：远程方向、投射物和障碍关系可读。
- `05_hit_feedback.png`：确认命中同时出现剑弧、火花和局部命中停顿取帧。
- `06_victory.png` / `07_escaped.png` / `08_defeat.png`：三种 outcome 的正式表现。

R7 必须生成十张 `640 x 360` RGBA PNG：

- `01_lantern_exploration.png`：守灯人、旧路、第一批幼兽与隘口入口。
- `02_pack_combat.png`：四只正式食炁幼兽、真气 HUD 和第三技能槽。
- `03_elite_equipment_choice.png`：回风剑匣/镇岳剑印语义选择完整可读。
- `04_boss_charge_telegraph.png`：食炁岩兽、三根亮柱与指向玩家的橙红冲撞长条同屏。
- `05_pillar_stagger.png`：一根阵柱变为损坏态，Boss 显示“破阵·失衡”。
- `06_array_restored.png`：阵灯已修复、绿色区域光与“阵灯捷径”同时可辨。
- `07_array_salvaged.png`：阵芯已拆、捷径消失且区域恢复昏暗。
- `08_sharp_metal_foundation.png`：筑基坛与锐金金色角色光。
- `09_flowing_water_foundation.png`：同构图下流泉蓝色角色光。
- `10_foundation_final_test.png`：十二只幼兽、筑基后 HP/真气上限和第三技能 HUD。

UI 基线必须生成六张 `640 x 360` RGBA PNG：

- `01_ground_click_navigation.png`：左键落点标记清晰，且不遮挡玩家与道路。
- `02_interaction_prompt.png`：靠近守灯人时显示不遮挡目标文本的左键语义互动提示。
- `03_keyboard_battle_hud.png`：键鼠提示、体力/真气和六个动作槽同时可读。
- `04_gamepad_battle_hud.png`：最近输入切到手柄后，普攻、闪避、丹药和三个技能键位同步切换。
- `05_resource_feedback.png`：真气不足时技能槽与短时拒绝反馈同时表达原因。
- `06_settings_input_accessibility.png`：三设备绑定、摇杆调校、对话速度与减少闪烁均在面板内可读。

## 3. 人工检查

- 草地、旧路、湿地与碎石坡来自 schema v2 逻辑格烘焙的 3D 模块，色值不过曝。
- 主角和店主通过 ActorDefinition/NpcDefinition 注入共骨骼 GLB，脚底落在 y=0。
- 玩家不能穿过松树、小铺和围栏。
- 小铺从 `from_wilds` 或 `from_slope` 进入时，对应出口位于初始固定镜头内；金色目的地标牌
  清楚区别北坡原野与北坡药草地，且出生点不会直接触发返程。
- 固定 yaw/pitch 下角色、NPC、树木、攻击范围和投射物前后关系清楚。
- 锁定普通敌人或唯一首领时，镜头在不超过 3.2 米的范围内偏向目标，玩家、目标与主要前摇保持
  同屏；树木、幼松或屋檐进入相机到玩家射线时半透明，离开后无残留透明材质。
- 对话框使用紧凑的“山野行笺”样式：22px 米白正文、18px 暗金姓名签、细暗金边框，文字无模糊投影且不越界。
- 对话逐字显示时正文逐步出现且等待图标隐藏；第一次推进只补全当前句，完整句和等待图标必须在
  同一取帧中出现，第二次才推进。32/48/72/120 字每秒设置在重新打开游戏后保持。
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
- 默认 `1280 x 720` 窗口是内部画面的严格 2 倍；设置页的 `1920 x 1080` 是严格 3 倍，
  全屏与 F11 返回最后一个窗口预设，固定镜头构图和 UI 比例不变。
- 标题、HUD、菜单和对话使用原生双倍字号，中文笔画清晰，不依赖低分辨率 UI 放大。
- 探索时不常驻战斗准星；左键点地出现短时落点标记，点选敌人后目标环持续跟随。进入战斗后方向线
  与端点能读出攻击朝向。靠近 NPC、采集物和 Portal 时显示当前输入设备对应的语义操作，离开范围、
  进入剧情或进入战斗后及时隐藏；键鼠显示左键，手柄显示 A。
- 底部 ARPG 战斗条使用条形量、数值和文字共同表达体力/真气；普攻、三个技能、丹药和闪避六个槽位
  分别显示当前输入设备键位、名称、消耗/数量与可用/冷却/真气不足状态，最长名称不越界。
  操作条不遮住玩家、近身敌人、Boss 冲撞路径或底部任务目标，键鼠与手柄提示不会同时堆在一行。
- 玩家输入因动作未收、冷却、真气或丹药不足被拒绝时，必须给出短时原因，不能只表现为无响应。
- 普攻/技能命中必须同时读出剑弧与火花，受击角色短时闪白/红，闪避保留递减残影；开启减少闪烁
  后角色不闪白、命中停顿明显缩短，但剑弧、火花、前摇和声音仍提供完整信息。
- 任意窗口尺寸只选择完整整数倍并以黑边补足；移动时 Camera3D 没有明显几何抖动或边缘闪烁。
- `1440 x 900` 等非 16:9 窗口以 `1280 x 720` 内容居中，四周黑边对称；编辑器使用
  `Embedded Window Sizing: Fixed Size` 时默认嵌入画面不出现异常窄高窗口。
- GridMap cell 不出现黑缝，导航与视觉 cell 中心一致，地表材质保持有限、非荧光的山野色板。

## 4. 战斗视觉门

G1 灰盒截图、录像和压力指标保存在 `docs/baselines/3d-action-combat-g1.md`，G4 正式战斗证据
保存在 `docs/baselines/3d-action-combat-g4.md`。固定摄影机截图必须覆盖探索全景、三敌遮挡、近战前摇、投射物路径、闪避命中、
死亡、Victory、Escaped、Defeat 和最长中文 HUD。角色在 `640 x 360` 中保持约 48–64 像素高；
固定 yaw/pitch 下前后关系、攻击范围与地面障碍清楚，窗口缩放不改变构图或 UI 清晰度。

## 5. 阵灯筑基视觉门

- 三种小型食炁兽至少通过体型、背部晶簇和发光色区分；Boss 的宽体、双角和背甲不能被误认成普通幼兽。
- 冲撞长条必须从 Boss 延伸到玩家方向；仅看静帧即可理解危险方向，不能依赖文字教程。
- 亮柱、损坏柱、Boss 失衡标签和战斗主体处于同一固定镜头，不需要转动镜头寻找机制物件。
- 修复与拆取使用同一脚点；前者显示绿色阵灯光和捷径，后者保持昏暗且不显示捷径。
- 锐金与流泉在同一筑基坛构图中分别呈金/蓝光，菜单与 HUD 同时显示对应境界层数和派生上限。
- 最终十二怪仍能在 `640 x 360` 内读出队形和角色位置；HUD 不遮住主要敌群或底部目标。
- 阵灯隘口长路每个主要遭遇段至少有树木、幼松、灌木或石块形成侧边节奏，环境物件不得侵入
  4.2 米主路或破坏南端到首群、Boss、阵灯与最终试炼的导航连通。
- 五组新增 WAV 能分别辨认蓄势、撞柱失衡、阵灯修复、拆取和筑基，不采样第三方素材。
