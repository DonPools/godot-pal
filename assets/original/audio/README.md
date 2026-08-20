# 原创即时战斗音频

本目录中的 WAV 由 `sources/generate_action_combat_audio.py` 使用 Python 标准库确定性生成，
不采样或改编第三方游戏音频。运行以下命令可完整重建：

```sh
python3 assets/original/audio/sources/generate_action_combat_audio.py
```

`mountain_path.wav` 与 `battle_pulse.wav` 是可循环的短环境/战斗动机；基础动作覆盖风系施法、
命中、闪避和 Victory/Escaped/Defeat。R7 新增 `charge_windup.wav`、`pillar_stagger.wav`、
`array_restore.wav`、`array_salvage.wav` 与 `breakthrough.wav`，分别表达冲撞蓄势、撞柱失衡、
修复、拆取和筑基。所有文件为 22050 Hz、单声道、16-bit PCM。
