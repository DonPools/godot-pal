# 3D 迁移前 2D 基线

记录日期：2026-08-18

基准提交：`fc05ebd91e66`，分支 `main`

记录时工作区已有 93 个修改或未跟踪路径。本报告描述的是当时工作区实际状态，不声称只对应
基准提交。迁移工作不得通过回退这些已有改动来重现基线。

## 1. 环境

- Godot：`4.8.dev.custom_build.4173760fd`
- 渲染器：OpenGL 4.1 Metal Compatibility
- GPU：Apple M5
- 根 Viewport 逻辑画面：`640 x 360`
- 默认窗口：`1280 x 720`
- 3D 物理：Jolt Physics

## 2. 工程与内容检查

### 编辑器加载

```sh
godot --headless --editor --path . --quit
```

结果：退出码 0。macOS 系统证书与沙盒内 editor settings 写入产生环境警告，没有脚本解析或
Resource 加载错误。

### 内容校验

```sh
godot --headless --path . -s res://tools/content_cli.gd -- validate --json
```

结果：`ok=true`，`error_count=0`，diagnostics 为空。

### 正式测试

```sh
godot --headless --path . -s res://tests/run_tests.gd
```

结果：退出码 0，输出 `roadside gathering slice tests passed`。

## 3. 地图生成基线

### 北坡原野

- Profile：`res://game/roadside/map_generation/north_slope_wilds_profile.tres`
- target：`res://game/roadside/maps/north_slope_wilds.tscn`
- seed：`260816`
- generator version：1
- plan hash：`a5eb1f13b8dd4b12232db7d0219c20bd5896eb2402db1ce421b0b827869242ec`
- cell：2048
- road cell：100
- detail cell：100
- Prop：95，其中 blocking footprint 128
- gameplay anchor：6
- reachable walkable cell：1920
- unreachable walkable cell：0

### 药草坡

- Profile：`res://game/roadside/map_generation/herb_slope_profile.tres`
- target：`res://game/roadside/maps/herb_slope.tscn`
- seed：`240816`
- generator version：1
- plan hash：`a44a912b54d4e21aece034baf8a7f6e459e4c2bec35823cb1ce24cd4f5c3aabd`
- cell：512
- road cell：16
- detail cell：34
- Prop：29，其中 blocking footprint 27
- gameplay anchor：6
- reachable walkable cell：485
- unreachable walkable cell：0

两个 Profile 的 `validate --json` 均退出 0 且 diagnostics 为空。

## 4. 视觉截图基线

生成命令：

```sh
godot --path . -s res://game/roadside/tools/capture_isometric_art_test.gd
```

输出目录：`/tmp/godot-pal-roadside/`

全部截图为 `640 x 360`：

| 文件 | SHA-256 |
|---|---|
| `title.png` | `d01144aa5081fda10cd47d9d5de1011714af302d79d40b41762c74717f725e5d` |
| `north_slope_wilds.png` | `2b28d523b879014e1a4196bb4411a6e8f7d376974d901b75b008d8edd2070ddc` |
| `roadside.png` | `9a38cd29ce9996abf9cf20b72a3081e3960f906efce781d69c22746ae8dd6c7f` |
| `tree_behind.png` | `a58a4f75989a47dadcd8353a47b37ef49193dbdf63ad130f2462b323c6d48195` |
| `tree_front.png` | `6be15ba8298d59ec3be4607d128b8bf527756d56e97a8f70a22f47c091858671` |
| `dialogue.png` | `e3e0d9e5dd708f50e4430f623ff4d4bf04b7cc2e6e6a5ffb79293b1deeee0384` |
| `commission_choice.png` | `50bcff5de788ff0e5b37424109db27d1701fe8cc790bd275623c2701abd1799b` |
| `route_choice.png` | `5f98abd52eaa08cd7bbbeda768d1f5dbcaaa4877ba4d3029a60a51a480c19866` |
| `herb_slope.png` | `cf9444d5cfec4ff342d72aba4d3b9b2c6cf5a36e93ad349dc0ad998e56e4ad12` |
| `harvest_choice.png` | `6f0425120b2d9ed8be6cb91442750a32c3fa308851f54b8785e978022d458cec` |
| `herb_left_root.png` | `43d7fd987badb7d8f3bfc6e249ba8c2d604149c3acbe3158c9f201ad1be09262` |
| `herb_regrown.png` | `8d26e5ec72f8f29a46899ad93b017254f3670c87947e50b6d3f2a4e7eae5bbad` |
| `herb_uprooted.png` | `7dfebb1481ffb28d9801dbf334c77a033bda0e03eee6926b6fee0f2d708c6cbc` |

截图 hash 用于标识本次基线，不作为跨 Godot 版本的像素级自动测试断言。

## 5. 默认地图性能

测量命令：

```sh
godot --path . -s res://game/roadside/tools/measure_2d_baseline.gd
```

测量场景：`map.roadside.north_slope_wilds`

采样方式：预热 120 帧，采样 180 帧，应用未限制到 60 FPS。

| 指标 | 数值 |
|---|---:|
| average FPS | 110.44 |
| average frame time | 8.329 ms |
| p95 frame time | 15.402 ms |
| draw calls | 19 |
| primitives | 2724 |
| node count | 309 |
| static memory | 160,701,373 bytes |
| static memory peak | 160,703,421 bytes |

该结果只用于同一开发机、相近后台负载下的方向比较。G1 仍以稳定 60 FPS 和 20 敌人压力场景为
硬门槛，不用当前未限帧平均值替代正式性能验收。

## 6. 素材与场景数量

`assets/original/` 当前约 20 MB：

- PNG 总数：62
- 运行 PNG：32，不含 `_source` 与 `_preview`
- source PNG：11
- preview PNG：19
- characters：17
- portraits：4
- tiles：8
- props：24
- plants：5
- maps：4

当前场景 node 数：

- `north_slope_wilds.tscn`：120
- `roadside_shop.tscn`：27
- `herb_slope.tscn`：73

当前角色管线仍是四方向 `3 x 4` 图集，环境由严格菱形 Tile、透明 Prop、碰撞和 YSort 组合。

## 7. 存档基线

生成命令：

```sh
godot --headless --path . -s res://game/roadside/tools/generate_2d_save_baselines.gd
```

生成器使用 SaveService 写入并立刻回读验证：

| fixture | 内容 | SHA-256 |
|---|---|---|
| `tests/fixtures/save_baselines/new_game_v3.json` | 固定 seed 新游戏，默认北坡入口 | `98f2e2bae1bb54d1527d49e29ccaf84ba89267833738d8de01ef74bb0d4c137d` |
| `tests/fixtures/save_baselines/gathering_completed_v3.json` | 两趟采药完成，留根与连根混合结果 | `cd172c88d2a678f3ee431b39ee0032cbaf70ad1f0a4fd59822c7cdad5dc906be` |

完成存档保留 story stage、八个采药 flag、36 文钱和
`map.roadside.herb_slope::herb_patch.centre` 的 persistent 完成态。两个 fixture 将用于后续存档版本
迁移测试；3D 迁移不得损坏 Party、Inventory、Economy、StoryState、GameFlags 或 WorldState。
