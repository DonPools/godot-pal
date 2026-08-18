# 原创即时战斗音频

本目录中的 WAV 由 `sources/generate_action_combat_audio.py` 使用 Python 标准库确定性生成，
不采样或改编第三方游戏音频。运行以下命令可完整重建：

```sh
python3 assets/original/audio/sources/generate_action_combat_audio.py
```

`mountain_path.wav` 与 `battle_pulse.wav` 是可循环的短环境/战斗动机；其余文件分别用于风系
施法、命中、闪避和 Victory/Escaped/Defeat。所有文件为 22050 Hz、单声道、16-bit PCM，
保持首个 3D 内容切片的体积与制作范围有限。

