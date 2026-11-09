# 设备端 ONNX 放大模型

Android 版把 Real-ESRGAN 模型随包分发，由 `lib/data/services/onnx_upscale_engine.dart`
在应用进程内通过 ONNX Runtime（`libonnxruntime.so`，arm64-v8a）推理，不需要可执行位、
不下载外部运行时。模型清单见 `lib/data/models/upscale/local_upscale_models.dart`
的 `onnxUpscaleCatalog`，UI 入口在生成页画布与「本地放大」面板。

## 模型

| 文件 | 用途 | 输入 | 输出 | 体积 | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| `animevideov3-256.onnx` | 二次元线条/平涂（与桌面 `anime-fast` 同模型族） | 固定 `1×3×256×256`，float32，RGB，`[0,1]` | `1×3×1024×1024` | 2,494,775 B | `139f166bd2b955c7d4cd31ca2616eb97dacc4365c1c315d880735ce72a0663d9` |
| `realesr-general-x4v3.onnx` | 通用照片/截图/细节插画（Real-ESRGAN 通用模型） | 动态 `1×3×H×W`，float32，RGB，`[0,1]` | `1×3×4H×4W` | 4,871,181 B | `09b757accd747d7e423c1d352b3e8f23e77cc5742d04bae958d4eb8082b76fa4` |

两个模型都是 4 倍输出。引擎按 256×256 分块、块间重叠 32 像素推理，再按目标倍率
（1×–4×）缩放；输入像素上限 `onnxUpscaleMaxInputPixels`（1,200,000，约 19.2 MP 输出），
超过时直接报 `sizeLimit`。默认模型仍是 `animevideov3-256`（`onnxUpscaleCatalog` 第一项，
桌面存档里的 `anime` 等模型 id 统一回退到它），手机端面板可在两个模型之间切换。

## 来源与许可

- `animevideov3-256.onnx`：由 Real-ESRGAN 官方 `realesr-animevideov3` 权重导出，
  固定 256 输入、4 倍输出；上游 <https://github.com/xinntao/Real-ESRGAN>。
- `realesr-general-x4v3.onnx`：Real-ESRGAN 官方 `realesr-general-x4v3` 权重的 ONNX
  导出，动态输入、4 倍输出，下载自
  <https://huggingface.co/Heliosoph/realesrgan-onnx>（BSD-3-Clause，与上游一致；
  上游权威来源为 <https://github.com/xinntao/Real-ESRGAN/releases/tag/v0.2.5.0>）。
  文件哈希已与 Hugging Face LFS 记录核对一致。

两个模型均按 BSD-3-Clause 分发，许可证全文见同目录
`LICENSE-BSD-3-Clause-Real-ESRGAN.txt`（Copyright © 2021 Xintao Wang）。
