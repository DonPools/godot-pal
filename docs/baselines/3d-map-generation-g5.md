# G5 固定视角 3D 地图生成器验收

日期：2026-08-19

结果：通过，允许按小铺、药草坡、北坡原野的顺序迁移正式地图。

## 生成契约

- `MapGenerationProfile` 使用 `schema_version = 2` 并只输出 3D；迁移完成后的主线清理已删除
  `target_mode`、旧 2D Profile、schema/generator v1 和 TileMap baker。
- seed、生态场、四邻域 A*、保护区、阻挡 footprint、anchor 可达性和内容指标继续由同一逻辑
  plan 计算；3D 只替换表现映射和 baker。
- Profile 的逻辑 cell 明确映射到 `WorldRoot` 的 XZ 平面；GridMap cell center、生成 Prop、导航
  polygon 和边界共用该坐标契约。
- 地表、道路和 Detail 使用少量 GridMap/MeshLibrary；大型环境物件继续使用独立 PackedScene。
- 非阻挡 Prop 的物理层固定为 0；阻挡 Prop 的物理层为世界碰撞层 2，并从逻辑导航中剔除。

## 固定验收资源

- Profile：`res://tests/map_generation/map_generation_3d_profile_fixture.tres`
- Target：`res://tests/map_generation/map_generation_3d_target_fixture.tscn`
- seed：`240816`
- generator version：`3`（主线清理后移除 2D atlas DTO）
- plan hash：`ef23f5124e00922281999a56b4a1d2a19630eabd69360868c7b638dd271680d5`

8 x 8 fixture 固定生成 64 个 Ground GridMap cell；导航 polygon 数等于逻辑可行走且未阻挡
cell 数。测试同时覆盖不同 seed 产生不同有效 hash。

## 所有权与回滚

- 生成器只移除和重建带 `map_generator_owned` 元数据的 Ground、Road、Detail、Prop、导航和边界。
- 人工 `Marker3D` spawn、Portal、`StoryInteractable3D` trigger、persistent ID 与目标 map/spawn
  在 Preview、Undo Preview、原子 bake、临时重载后保持不变。
- 含 `StoryInteractable3D` 的生成 Prop 会在临时重载校验中被拒绝；目标 `.tscn` 的 SHA-256
  保持不变。
- terrain module 必须含 Mesh 和 CollisionShape3D；blocking Prop 必须含 Mesh 与碰撞。

## 验证结果

以下检查通过，完整测试日志没有 `SCRIPT ERROR`：

```sh
godot --headless --path . -s res://tests/run_tests.gd
godot --headless --path . -s res://tools/map_generator_cli.gd -- validate res://tests/map_generation/map_generation_3d_profile_fixture.tres --json
godot --headless --path . -s res://tools/map_generator_cli.gd -- plan res://tests/map_generation/map_generation_3d_profile_fixture.tres --seed 240817 --json
godot --headless --editor --path . --quit
```

编辑器命令在当前受限环境仍会报告系统 CA 与用户目录 editor settings 写入错误；工程扫描、脚本
注册和 Dock 加载均完成且没有工程脚本错误。
