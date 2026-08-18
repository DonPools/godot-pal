# 固定视角 3D 即时战斗 G1 验收

历史说明：G6 正式基线通过后，`game/prototypes/action_combat_3d/` 已按计划删除，避免形成
第二套长期运行时。本文件保留当时的命令、数字和决策证据；当前可重复验证入口见
`docs/baselines/3d-content-migration-g6.md`。

验收日期：2026-08-18

结论：通过，选择继续原生 3D。

本验收只证明固定视角 3D 与地图内即时战斗的操作、画面、规则边界和性能方向成立。正式素材的
建模、骨骼、动画和环境模块复用成本仍由 G3 检查，未在 G1 中提前宣告成功。

## 1. 隔离边界

灰盒位于 `game/prototypes/action_combat_3d/`：

- 不登记 ContentDatabase；
- 不改变 GameRoot 默认入口；
- 不被正式三张地图引用；
- 不写 GameRun 或存档；
- 不执行地图生成器；
- 输出只进入 `/tmp/godot-pal-action-combat-3d/`。

现有 2D 正式切片在灰盒开发期间继续通过原有测试。

## 2. 已验证能力

### 输入与摄影机

- 键盘、方向键和左摇杆使用摄影机空间直接移动；
- 鼠标射线投射到 XZ 地面，右摇杆提供独立瞄准；
- 摇杆死区为 0.25，软锁定使用 50° 获取锥和 65° 保留锥；
- 没有指针、摇杆或软锁目标时恢复最后有效移动方向；
- 移动使用加速、减速、最大速度和 CharacterBody3D 碰撞滑动；
- focus-out 冻结模拟，focus-in 恢复；F11 与 F3 调试动作已登记；
- 默认摄影机为 45° yaw、35.264° elevation、orthographic size 12，角色约 48.99 像素高。

自动测试验证键盘、鼠标、左/右摇杆和手柄按钮的 InputMap 事件。当前环境没有接入实体手柄，
正式切片 G4 仍需执行一次真实硬件人工验收。

### 动作与敌人

- Idle、Move、Windup、Active、Recovery、Stagger、Dodge 和 Dead；
- 普攻前摇、生效窗口、恢复、单目标单次命中；
- 类型化 Hitbox3D/Hurtbox3D；
- 直线投射技能、近身范围技能、MP、冷却、施法与结构化拒绝原因；
- 有无敌窗口的固定距离闪避、受击硬直和死亡；
- 近战与远程行为、攻击前摇、投射飞行、leash、Return 和简单箱体绕障；
- F3 可视化攻击范围；
- 攻击开始、命中、伤害、结束和结果使用类型化调试事件。

### Encounter 与结果

- `PrototypeBattleSession3D` 拥有有限敌群和 Dormant/Active/Finished 生命周期；
- 首次警戒开始；全部必要敌人死亡返回 Victory；完整脱战返回 Escaped；玩家死亡返回 Defeat；
- 三种结束均产生现有类型化 BattleResult；
- 重复结束不会产生第二个结果；
- 自动测试连续重开并完成 20 次 Victory，没有卡死、重复命中或残留输入。

## 3. 自动测试

```sh
godot --headless --path . -s res://tests/action_combat_3d/action_combat_3d_test.gd
```

结果：退出码 0，输出 `action combat 3D prototype tests passed`。

测试覆盖：

- 摄影机候选和 48 至 64 像素角色高度；
- InputMap 键盘、鼠标、摇杆、手柄、F11 和 F3；
- 移动、停止与碰撞；
- 普攻单次命中和 start/hit/finish 事件顺序；
- 投射、范围、MP、冷却拒绝；
- 闪避无敌窗口和窗口结束后的伤害；
- 远程敌人前摇、投射和命中；
- 直接寻路绕过一个简单箱体；
- Victory、Escaped、Defeat、BattleResult 和 20 次重开；
- focus-out/focus-in 模拟所有权；
- 调试攻击范围。

## 4. 性能

环境：Apple M5，OpenGL 4.1 Metal Compatibility，`640 x 360` 渲染目标，`1280 x 720` 窗口。

命令：

```sh
godot --path . -s res://game/prototypes/action_combat_3d/measure_stress.gd -- --enemies 3
godot --path . -s res://game/prototypes/action_combat_3d/measure_stress.gd -- --enemies 10
godot --path . -s res://game/prototypes/action_combat_3d/measure_stress.gd -- --enemies 20
```

每档预热 120 帧、采样 300 帧：

| 敌人数 | average FPS | average wall frame | p95 frame | draw calls | primitives | nodes | static memory |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 3 | 111.34 | 8.768 ms | 12.205 ms | 35.72 | 46,803 | 50 | 162,847,387 B |
| 10 | 105.65 | 8.551 ms | 12.410 ms | 57.03 | 119,585 | 99 | 163,156,807 B |
| 20 | 105.55 | 8.553 ms | 12.308 ms | 87.17 | 222,634 | 169 | 163,570,863 B |

三档均通过 60 FPS 门槛。JSON 同时输出 Godot Performance 的 process、physics 和 navigation 原始
monitor 平均值。Compatibility renderer 未提供可靠的 GPU frame timing，因此明确输出
`gpu_timing_available=false`；Movie Maker 记录的 CPU render 平均为 0.67 ms/frame，GPU 项为
0.00，视为不可用而不是零成本。

## 5. 视觉证据

摄影机候选命令与 hash 见 `docs/baselines/3d-camera-candidates.md`。

战斗状态截图命令：

```sh
godot --path . -s res://game/prototypes/action_combat_3d/capture_combat_states.gd
```

它生成 `combat_dormant.png`、`combat_enemy_windup.png`、`combat_projectile.png`、
`combat_victory.png`、`combat_defeat.png` 和 `combat_escaped.png`，全部为 `640 x 360`。

压力截图为 `stress_3_enemies.png`、`stress_10_enemies.png` 和 `stress_20_enemies.png`。

短录像命令：

```sh
godot --path . \
  --write-movie /tmp/godot-pal-action-combat-3d/action_combat_states.avi \
  --fixed-fps 60 \
  -s res://game/prototypes/action_combat_3d/capture_combat_states.gd
```

结果：Motion JPEG AVI，`640 x 360`，60 FPS，369 帧，约 6.15 秒，约 6.6 MB。最后一次记录的
SHA-256 为 `a7414be1f60a1248ad46933cfb7905f3777197d4976a25b55a4e69353d57bc01`。

动态战斗截图包含按时间推进的敌人位置和伤害数字，hash 只用于标识单次报告，不作为跨运行的
像素级 golden。三张静态摄影机截图已重复生成并得到相同 hash。

## 6. G1 决策

选择“继续原生 3D”，原因：

- 正交固定视角达到目标角色高度，前摇、敌我与投射物可读；
- 直接移动、双输入瞄准和有限软锁定成立；
- 20 敌人压力仍显著高于 60 FPS；
- 实时规则可以继续保留 BattleResult、StoryContext 和 GameRun 的既有上层边界；
- 原型没有迫使项目引入全局模式、EventBus、通用行为树或运行时地图生成。

进入阶段 2 后，原型代码只作为行为证据。正式实现必须迁入 framework/gameplay 与正式地图所有权，
不能让 `game/prototypes/action_combat_3d/` 成为第二套长期运行时。
