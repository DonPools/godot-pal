# G4 固定视角 3D 正式切片验收

日期：2026-08-18

结果：通过，允许进入 3D 地图生成器与现有地图迁移。

## 正式内容

“北坡兽群遭遇”已经作为正式内容登记，不依赖 G1 原型：

- `map.roadside.north_slope_pack`：固定正交 Camera3D、模块地表、碰撞、导航资源、语义 spawn、
  返回 Portal 与 persistent EncounterSource；
- `encounter.roadside.north_slope_pack`：两名近战山客与一名远程投石手组成的有限敌群；
- `skill.roadside.wind_edge` 与 `skill.roadside.sweeping_arc`：直线投射与近身范围技能；
- `item.roadside.wound_powder`：首次遭遇原子给予两份，战斗中消费；
- `status.roadside.stone_cut`：远程命中施加的固定时间持续伤害；
- `story.roadside.north_slope_pack`：Victory 完成来源，Escaped 保留来源，Defeat 恢复队伍并
  terminal travel 到 `map.roadside.north_slope_wilds/default`。

地图可从北坡原野出生点附近的“兽径”人工 Portal 进入；G4 通过前没有替换默认新游戏入口。

## 运行时边界

- `MapGameScene3D` 继承正式 `MapGameScene`，复用同一 GameRun、StoryDirector、StoryContext、
  SaveService 与地图内 BattleSession；
- PlayerCharacter3D、EnemyActorView3D、Hurtbox3D 与投射物只提交动作意图和空间命中候选；
- HP/MP、冷却、状态、单次命中、奖励和 outcome 仍由 `1/60` 固定步 BattleSession 计算；
- 飞行中的投射动作保留规则凭证，施法者进入 Recovery 后仍可合法命中，命中或过期后失效；
- 活动战斗不 push BattleGameScene，保存继续稳定返回 `save_blocked_active_battle`。

## 原创表现

G3 的共骨骼人形、武器和环境模块直接用于正式地图。新增音频由
`assets/original/audio/sources/generate_action_combat_audio.py` 确定性生成，包括地图/战斗循环、
施法、命中、闪避及三种结果提示，不采样第三方音频。

固定截图命令：

```sh
godot --path . -s res://game/roadside/action_combat_3d/tools/capture_g4_formal_slice.gd
```

输出目录为 `/tmp/godot-pal-g4/`：

- `01_exploration.png`
- `02_alert.png`
- `03_windup.png`
- `04_projectile_obstruction.png`
- `05_victory.png`
- `06_escaped.png`
- `07_defeat.png`

七张 `640 x 360` 截图均确认角色、敌群、前摇圈、投射物、障碍、HUD、结果文字和最长目标文字
可见且不重叠。Victory 截图同时确认 persistent 敌群清除和目标更新。

## 自动验收

以下命令通过：

```sh
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
godot --headless --path . -s res://tests/run_tests.gd
```

`tests/run_tests.gd` 新增覆盖：

- G4 内容数量、ID、引用、地图结构、三名敌人和正交相机；
- StoryModule 的 Victory/Escaped/Defeat、一次性补给与安全 travel；
- 正式 3D MapGameScene 的 BattleSession/HUD/EnemyActorView 绑定；
- 键盘动作事件与映射后的 Joypad A 进入相同类型化动作 API；
- Escaped 不完成 persistent 来源并重置敌人表现；
- 延迟投射命中在施法 Recovery 后仍有效且保持单次命中。

内容 CLI 的 `list enemy`、`show encounter`、`refs encounter.roadside.north_slope_pack` 和
`story-test story.roadside.north_slope_pack confront_pack ... victory` 均返回稳定 JSON。

## 人工风险

当前自动环境没有物理手柄，已验证 Joypad 映射和同一输入处理路径，但不能替代不同品牌手柄的
死区与手感复核。该项保留为目标机发布前人工复核，不阻断 G4 的架构与内容生产决策；若物理
手柄出现瞄准漂移，只允许调整死区、迟滞和软锁定，不改变 BattleSession 或存档协议。
