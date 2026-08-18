# 固定视角 3D 素材生产 G3 复盘

验收日期：2026-08-18

结论：通过素材复用门，允许进入第一个正式 3D 内容切片；美术完成度仍由 G4 单独验收。

## 1. 可重建管线

- 源：`assets/original/3d/sources/generate_lowpoly_assets.py`，Python 3.9+ 标准库。
- 输出：13 个 GLB、1 张 `4 x 4` 原创调色纹理、`manifest.json` 和 Godot wrapper Scene。
- 坐标：米制、+Y 向上、-Z 前方、角色脚底 `y = 0`。
- 摄影机：yaw 45°、elevation 35.264°、orthographic size 12。
- 完整重建实测 0.05 秒；首次 Godot 导入约 2.2 秒。
- 连续两次生成的 manifest SHA-256 均为
  `b46331dcbab3298f12026687131ea0176cb1fc4af44a1765b9e2ee0b49cc5d8b`。

本轮从生成器文件建立到最终截图复核的实际自动化生产窗口为 22:43–23:05，共约 22 分钟。
这是程序化低模管线的代理工时，不等同于人工建模师制作高细节角色的报价。

## 2. 角色与动画复用

`humanoid_base`、`humanoid_variant` 和 `mountain_raider` 使用同一 13 骨骼拓扑：

```text
hips, spine, head,
upper_arm_l, lower_arm_l, upper_arm_r, lower_arm_r,
upper_leg_l, lower_leg_l, foot_l, upper_leg_r, lower_leg_r, foot_r
```

三者都导入 idle、run、attack、cast、hit、death。validator 比较基础人形与第二变体的每条
Animation track NodePath，六组全部同构；第二变体只增加一次比例/配色调用，没有增加方向动画。
三个人形每个 156 三角形，GLB 合计约 120KB。

当前 2D 四斜向角色仅一个走路动作就需要 12 格。若六个动作每方向保守使用三帧，每个角色至少
需要 72 个方向性绘制帧；3D 管线仍只有六组动作曲线，任意地面朝向复用。运行文件仍各自嵌入
动画数据，后续只有在文件体积成为真实负担时才外置 AnimationLibrary。

## 3. 武器与环境增量

- 武器：直剑与铁杖共用 box/cone 生成、材质和导入契约，不需要方向专用图。
- 环境：草地、石路、岩石、成松、幼松、灌木、围栏、小屋八类模块。
- 成松到幼松只调整三段轮廓与比例；两者可任意旋转、缩放并复用同一材质集合。
- 13 个 GLB 总计 183,636 bytes；单个环境模块为 2.3–8.8KB，全部低于 1,000 三角形预算。

环境 wrapper 使用 StaticBody3D 和明确 CollisionShape3D；人形 wrapper 使用 CharacterBody3D、
胶囊碰撞和 NavigationAgent3D。模型只负责表现，地图生命周期与碰撞继续由 `.tscn` 组合。

## 4. 自动与视觉验收

`Original3DAssetValidator` 已纳入 `tests/run_tests.gd`，检查：

- manifest 路径、SHA-256 和完整输出数；
- CharacterBody3D/StaticBody3D 根、单位 scale、碰撞和 NavigationAgent3D；
- Mesh、Material、三角形预算、脚底与角色高度；
- 13 个骨骼、六组动画和基础/变体轨道同构；
- `4 x 4` 调色纹理。

截图命令生成 `/tmp/godot-pal-3d-assets/g3_asset_showcase.png`。最终图在 `640 x 360` 下能分别
辨认三个人形、两件武器、地面/道路、岩石、两种松树、灌木、围栏与小屋；角色高度落在固定
正交镜头的可读区间，近远遮挡没有覆盖主角。

## 5. G3 判断

长期素材数量会下降的证据成立于两类内容：

- 角色方向和通用动作：骨骼/动画随方向复用，第二角色不再成倍增加方向帧。
- 环境变体：模型可旋转、缩放和换材质，不需要为斜向视角另画多个版本。

但 3D 不保证每项成本都下降：第一套骨骼、动画调试、材质、碰撞与导入校验是新增固定成本，
特写角色、复杂布料和独特 Boss 仍可能比像素图昂贵。因此 G3 只允许制作一个正式切片；若 G4
无法达到当前 2D 切片同级可运行、可读和可创作标准，应回退到预渲染 3D 精灵或 2D 即时战斗。
