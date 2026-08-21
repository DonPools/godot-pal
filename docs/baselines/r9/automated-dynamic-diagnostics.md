# R9 自动动态诊断记录（2026-08-20 快照）

> 证据范围：提交 `06ccc87`。四种诊断均在 Godot 4.8 Metal Compatibility 下干净通过；
> 这里的帧数、大小与结论是该提交的历史快照，不代表后续 IES、Content CLI contract v2 或
> 显式 StoryBinding 迁移后的当前工作树。
> 这些录像使用脚本注入输入、调用场景方法并构造状态，只证明渲染与生命周期回归，不是真人输入
> 动态门，也不计入 5 人首次玩家盲测。

## 1. 运行命令

```sh
godot --path . --write-movie /tmp/godot-pal-r9-dynamic/01_golden_diagnostic.avi --fixed-fps 60 --disable-vsync -s res://game/roadside/action_combat_3d/tools/capture_r9_dynamic_diagnostic.gd -- golden
godot --path . --write-movie /tmp/godot-pal-r9-dynamic/02_pointer_diagnostic.avi --fixed-fps 60 --disable-vsync -s res://game/roadside/action_combat_3d/tools/capture_r9_dynamic_diagnostic.gd -- pointer
godot --path . --write-movie /tmp/godot-pal-r9-dynamic/03_combat_diagnostic.avi --fixed-fps 60 --disable-vsync -s res://game/roadside/action_combat_3d/tools/capture_r9_dynamic_diagnostic.gd -- combat
godot --path . --write-movie /tmp/godot-pal-r9-dynamic/04_modal_diagnostic.avi --fixed-fps 60 --disable-vsync -s res://game/roadside/action_combat_3d/tools/capture_r9_dynamic_diagnostic.gd -- modal
```

每种模式成功时输出稳定 JSON：

```json
{"kind":"automated_dynamic_diagnostic","mode":"golden","ok":true}
```

## 2. 快照结果

| 文件 | 覆盖 | 帧数 | 60 FPS 时长 | 大小 |
|---|---|---:|---:|---:|
| `01_golden_diagnostic.avi` | 标题、移动、互动、首战、菜单与设置 | 706 | 11.77 秒 | 17 MB |
| `02_pointer_diagnostic.avi` | 点地、直移接管、不可达与点击互动 | 564 | 9.40 秒 | 12 MB |
| `03_combat_diagnostic.avi` | 普攻、技能、闪避、资源拒绝与逃跑 | 673 | 11.22 秒 | 17 MB |
| `04_modal_diagnostic.avi` | 设备切换、菜单、设置、冲突重绑与存读档 | 613 | 10.22 秒 | 15 MB |

四个文件均为 `640 x 360` Motion JPEG AVI。Godot Movie Writer 日志确认固定 `60 FPS`，四次退出均无
项目告警、残留自定义光标或 GLES3 空材质依赖。combat 诊断同时回归闪避残影：副本只使用单一
半透明 override，不继承角色运行时轮廓的嵌套 material chain；hit-stop 通过 WeakRef 恢复运动状态，
战斗结束先释放 EnemyActorView 时不会访问失效实例。四段录像已在玩家、NPC、敌人 AnimationPlayer
名称匹配修复后重录，实际覆盖 relaxed idle 与 run/attack/cast/hit/death 切换。

2026-08-21 后续功能和内容契约变更稳定后，必须重新执行四条命令并以新的 build commit、帧数、
时长、大小和 SHA-256 建立新记录；在此之前不能把本快照写成当前自动门证据。

## 3. 与真实动态门的边界

真实动态门仍必须按 `field-test-protocol.md` 执行：默认 `1280 x 720` 2 倍窗口、真人键鼠/手柄、
正常场景生命周期、四段完整流程、系统输入显示或独立按键日志，以及逐帧时间码记录。自动诊断文件名
带 `_diagnostic`，不能改名冒充 `01_golden_90s.mp4` 等真人证据。
