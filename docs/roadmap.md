# 开发路线

## 当前基线

当前正式基线是原创斜 45 度像素切片“北坡采药”：

```text
标题页
  -> map.roadside.shop
  -> 接下采药差事，选择旧路或碎石近坡
  -> map.roadside.herb_slope
  -> 割叶留根或连根采走，按时段返回交付
  -> 第二趟观察再生或永久枯竭
  -> 菜单、设置和三槽存读档
```

项目保留已经验证的 GameRoot、GameSceneStack、GameRun、内容数据库、StoryEvent/
StoryModule、菜单、商店、战斗、存档、设置、Dock 与 CLI 等通用框架能力；当前正式内容
登记一个角色、一种材料、两张地图和一个多 trigger StoryModule。

## 已完成

### R0：通用运行时

- `320 x 180` Viewport、默认 `960 x 540` 严格 3 倍可缩放窗口与 nearest 像素渲染。
- GameRoot、GameSceneStack、Overlay 与服务所有权。
- GameRun、队伍、背包、金钱、故事、标记、世界实体和位置存档结构。
- 标题、菜单、设置、三槽存读档与键盘/手柄输入。
- 类型化 StoryContext、常用 StoryEvent、可选 StoryModule 与内容 CLI。

### R1：原创等距美术基线

- `32 x 16` 菱形 TileSet 与四种地表。
- 主角和店主 `24 x 32`、`3 x 4` 四斜向图集。
- 松树、双向围栏和小铺独立透明物件。
- 正式 `map.roadside.shop` 的 TileMap、碰撞、YSort、spawn 和 DialogueEvent。
- ImageGen 源图、确定性后处理脚本和视觉截图流程。
- 移除运行时对第三方提取资源、manifest 与 source ID 的依赖。

### R2：山路采集闭环

- `map.roadside.herb_slope`、三处稳定药草来源和往返 portal。
- DialogueOption 语义选择，以及留根一份/连根两份的明确采集结果。
- 安全旧路固定耗时；碎石近坡使用可注入、可随存档往返的种子随机源。
- 两份返青草与工钱的原子交付，按时十二文、迟到六文。
- 第二趟让留根药丛恢复、连根来源保持完成，并给出无显式善恶值的地方结果。
- FakeStoryContext 轨迹、场景 smoke test 和十二张视觉验收截图。

## 下一步候选

下一阶段从真实玩法闭环中选择一个，不同时铺开：

1. 简单修理：用材料恢复路灯或桥梁，观察局部状态变化。
2. 短途交易：信息、材料和工钱之间的具体取舍。
3. 最小战斗：只有在一个实际冲突需要时，重新登记原创敌人与遭遇。

优先目标是让玩家先熟悉世界规律，再通过长期重复和异常发现背后的资源循环，而不是在
开场解释灵界、人界或历史真相。

## 持续原则

- 新系统必须由一个玩家可见内容闭环证明需要。
- `.tscn`、`.tres` 和类型化 GDScript 是内容真相。
- 内容使用语义 ID，不保存资源路径或 Node 引用到 GameRun。
- 简单内容使用内嵌 StoryEvent，复杂多阶段叙事才增加 StoryModule。
- 原创素材保持提示、源图、后处理和运行图可追踪。
- 每次扩展同时更新内容校验、场景测试、截图和文档。
