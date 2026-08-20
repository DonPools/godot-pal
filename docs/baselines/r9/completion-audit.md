# R9 完成定义逐项审计

> 审计日期：2026-08-20
> Godot：4.8 dev `4173760fdf6c2c722e82e08cb58e55f34c9efd80`
> 结论：实现、自动门与静态门已通过；真实动态门和首次玩家门缺少外部证据，R9 不得标记完成。

本表把“代码存在”“自动测试通过”“截图可见”和“真人证据存在”分开。只有与要求范围一致的直接
证据才记为已证明；自动 Movie Writer 不能证明真人输入，空结果模板也不能证明盲测。

## 1. 阶段审计

| 阶段 | 状态 | 直接证据 | 限制 |
|---|---|---|---|
| R9-0 目标帧 | 已证明 | `target-frames.md`、四张 `640×360` 目标图、色板/字号/资产决策与录制脚本 | 目标图不是运行时证据，静态门使用后续 Metal 图 |
| R9-1 角色与世界 | 已证明 | 确定性 GLB/manifest；动画资源校验要求六段非静态关键帧和 relaxed idle；运行测试验证玩家六态、敌人 attack/cast、NPC idle；G6/G4/R9 Metal 图 | 真人对连续衔接的观感仍属于动态门 |
| R9-2 共享 UI | 已证明 | `roadside_theme.tres`；五地图 HUD 包装；标题、对话、菜单、商店、设置、存读档共享 Theme；焦点/空状态/提示避让测试；R9 十二图 | 商业可用性判断仍需盲测 |
| R9-3 操作与手感实现 | 已证明 | Esc/M/Start、点击/WASD/追击/强移/原地攻击、目标切换、拒绝、重绑、辅助模式与设备提示自动覆盖；四段自动动态诊断无告警 | 阶段退出门要求真人键鼠/手柄黄金流程，尚未证明 |
| R9-4 推广与回归 | 已证明 | 五地图共享 HUD 与目标、四地图入口环境推广；G6/G4/R7/UI/R9 共 47 图；内容、测试和三地图固定 seed 校验通过 | 不会替代 R9-3 的真人退出门 |
| 外部执行包 | 已证明 | 隔离 profile、只观察输入 JSONL、JSON/Markdown 模板和只读 CLI；真实 Metal GUI 元数据 smoke test | 工具只能校验证据结构，不能产生参与者 |

## 2. 自动门逐项证据

| R9 7.1 要求 | 结论 | 权威证据 |
|---|---|---|
| Esc/M/Start 打开、返回、隔离 | 已证明 | SettingsService 默认/冲突测试；GameRoot 菜单 push/pop 与战斗期间禁止事务菜单测试；动态 modal 诊断 |
| HUD 探索/战斗/模态及设备互斥 | 已证明 | MapHud 初始/战斗状态；测试在鼠标与手柄间切换并断言动作格只显示 `鼠左/鼠右` 或 `A/X`；菜单暂停底层场景 |
| 互动与出口提示避让 | 已证明 | DestinationLabel 上下文 suppression 场景测试；R9 互动图 |
| idle/run/attack/cast/hit/death 不停留绑定姿势 | 已证明 | Original3DAssetValidator 检查动画长度、轨道、关键帧变化及 idle 手臂；运行测试检查 AnimationPlayer 实际播放项；重生成 Metal 图可见 relaxed idle |
| 设置分类、冲突、清除/默认、辅助持久化 | 已证明 | SettingsService v3 往返、三设备 binding、冲突、legacy 迁移、分类 UI、减少闪烁测试；设置截图 |
| 流程结束/暂停/切图无导航、目标、透明材质残留 | 已证明 | Escaped 后导航/指针/软目标/HUD 清理断言；遮挡淡出恢复测试；hit-stop WeakRef 释放测试；四段 Metal 自动诊断退出无告警 |

审计时发现并修复两项此前被宽泛绿灯掩盖的问题：

1. `get_slice("/", -1)` 无法匹配 Godot 动画名，导致玩家、NPC 和敌人 AnimationPlayer 实际未播放；
   现统一使用 `get_file()`，并由实际 `current_animation` 断言覆盖。
2. 战斗在 hit-stop 中释放 EnemyActorView 时，运动状态缓存会访问失效实例；现以 WeakRef 保存并跳过
   已释放节点。

## 3. 静态门证据

`capture_r9_mature_presentation.gd` 当前生成 12 张 `640×360 RGBA` PNG。启用实际动画后的 SHA-256：

```text
412b99e64449d60c51d6b0af0dfa3b3f9fb7dbea919c4824885ec2eedd64289a  01_title_first_focus.png
cf38dfcce33839734b6531dc77606e1d51b0071b371f1255536fc241b239d56d  02_lantern_entry.png
c1560f0755cfe37ac5fd9c4e5562468a937b73a1419677a467898ec294f3d957  03_ground_click.png
14a4dd33277607708457e640a1b64cb87f9bc0a4661e8bc681193902d49366ff  04_keeper_interaction.png
21a713489d4817bac9263fd067a04e4af5058b6484eb5bab8ec8e353c588cd5c  05_keyboard_battle.png
6d37563bd8d7ff9734ff5db13c71e8d82e7b7fb2400bcf613989d91be188201a  06_gamepad_battle.png
b25cb022ce8c12753e356137dc9998075596f4c9c17a34abbd13f239e6b64791  07_windup_and_hit.png
be956f5d79d87c8182df7fb6e8cb5d6359fb43bc4ac1e034e4263a91286beb76  08_boss_charge.png
eb6e7c13c8cf3494a6ec837cb4bf00fa9ef9ad8c7f4365380f5a9dbd64b5a0e6  09_dialogue_choice.png
e8d14d51726ae054066812c433b26fee087ab7646f5d1092fed4818a3c866ed3  10_pause_menu.png
8685e126fd2a369dde11a14c6f25c751bf0a7f67d99d7a3204380e307c89de50  11_settings_rebind.png
1f04854783af2ad4000103ed6e1373167e0881b372d72d3b3dfb80e78d3750a1  12_save_load_summary.png
```

功能回归集数量为 G6 11、G4 8、R7 10、UI 6；连同 R9 共 47 张。所有文件均经 `file` 确认为
`640×360 8-bit RGBA`。

## 4. 自动动态诊断

四段 Metal Movie Writer 诊断在实际动画修复后重新录制，均输出 `ok: true` 且无项目告警：

| 模式 | 帧数 | 60 FPS 时长 | SHA-256 |
|---|---:|---:|---|
| golden | 706 | 11.77 秒 | `dcca4e5f835b48e4db2569daced50e8ad33a79d87031efa5cf8decef592a6324` |
| pointer | 564 | 9.40 秒 | `34f9d3c3eea32dcbf10b638a15d20eb3c593f7e80500a861af8b8910c4ee69bd` |
| combat | 673 | 11.22 秒 | `187f41c93727da238b4eda3b88b679661d6be2c18e43222284517b15b159b344` |
| modal | 613 | 10.22 秒 | `22f0bf1ff741e1941510d3e01399116288f33183df6bd9ae7535fe546e4b33ad` |

这些 AVI 是脚本驱动的生命周期回归，不是 R9 7.3 的真人输入 MP4。

## 5. 未完成证据

### 5.1 真实动态门：缺失

以下文件及其独立输入日志尚不存在：

- `01_golden_90s.mp4`
- `02_pointer_and_direct_control.mp4`
- `03_combat_feedback.mp4`
- `04_device_modal_roundtrip.mp4`

### 5.2 首次玩家门：缺失

`field-test-results.json` 尚未创建，P1–P5 没有真实观察、计时、设备和原话。当前只有明确标记为待填写的
模板。运行 `r9_field_test_cli.gd` 校验空模板会返回非零，不能据此宣称通过。

## 6. 完成判定

R9 完成定义由四类证据合取：自动门、十二张静态图、四段真人动态录像、五人首次玩家盲测。当前前
两类已证明，后两类缺失，因此总体状态必须保持“进行中”。下一次状态变化只能来自按
`field-test-protocol.md` 采集的真实外部证据，或该证据暴露缺陷后的修复与重测。
