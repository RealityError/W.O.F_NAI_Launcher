# Android 本地放大「进阶能力」评估

本文回答一个问题：桌面端的高级本地放大（RTX Video、SeedVR2）以及更大的
Real-ESRGAN 模型，在 Android 端能追到什么程度、值不值得做。结论基于本仓库
现有引擎实现、官方发布物与 Hugging Face 上的模型索引核对，未做真机耗时基准的
部分会明确标注。

## 结论摘要

1. **桌面端的高级链路无法原样搬到 Android**：RTX Video 依赖 Windows 驱动与
   DXVA，SeedVR2 依赖 Python + uv + PyTorch + 3B/7B safetensors（fp8 也数 GB
   级），都要外部进程与 GPU/显存，手机端没有对等能力。
2. **可迁移的“进阶”是更多 ONNX 模型**。本轮已加入 Real-ESRGAN 通用模型
   `realesr-general-x4v3`（4.9 MB，动态输入、4 倍输出），与原有的
   `animevideov3-256` 并存；引擎只需按模型选 asset，推理管线不变。
3. **更大的模型（x4plus 系列）技术上可行，但性价比低**：ONNX fp32 体积
   18–67 MB，单块计算量约为当前模型的一个数量级，建议按需再做，默认不随包。
4. **提速空间在推理后端**：`onnxruntime` Dart 包 1.4.1 已暴露
   `appendNnapiProvider` / `appendXnnpackProvider`，可作为后续实验项；效果
   依真机而定，需要基准后再决定是否启用。

## 桌面端进阶方法 vs 手机现状

| 桌面方法 | 依赖 | 能否上 Android |
| --- | --- | --- |
| RTX Video | Windows + RTX 驱动/DXVA | ✗ 无 Windows 驱动与 DXVA |
| SeedVR2（3B/7B） | Python 3.12 + uv + PyTorch，fp8 safetensors 数 GB | ✗ 无 Python/GPU，内存与算力都不够 |
| 随包 realesrgan ncnn `.exe` | 可执行位 + Vulkan | ✗ Android 应用目录无可执行位 |
| ONNX Runtime 进程内推理 | `libonnxruntime.so`（随包 arm64） | ✓ 当前方案 |

因此 Android 的“进阶”不是在手机上复刻 SeedVR2/RTX，而是在同一条 ONNX 管线里
扩充**模型品种**、优化**推理速度**。

## 引擎约束（决定哪些 ONNX 模型能直接接）

实现见 `lib/data/services/onnx_upscale_engine.dart`：

- 输入：RGB、NCHW、float32、`[0,1]`（与 Real-ESRGAN 参考实现一致，不做
  mean/std 归一化）；输出为 `4×` 放大。
- 分块：固定 256×256、块间重叠 32 像素、块内边缘复制补齐；最后按目标倍率
  （1×–4×）缩放，因此模型只要**能接受 256×256 输入**即可——固定 shape 的
  animevideov3 与动态 shape 的 general-x4v3 都能直接跑。
- 像素预算：输入不超过 `onnxUpscaleMaxInputPixels`（1,200,000，约 19.2 MP
  输出），超过直接报 `deviceSizeLimit`。降低目标倍率不会解除该预算，因为仍需完整
  的 4 倍中间图。面板显示说明，自动本地增强在生成请求前检查；不自动缩图。
- 模型选择：`onnxUpscaleCatalog` + `onnxUpscaleAssetPath()`（asset 文件名与
  `engineName` 一致），`OnnxUpscaleEngine.upscale(modelAsset:)` 按次传入。

## 候选模型评估

体积按 fp32 ONNX 估算；相对算力以当前 animevideov3（SRVGGNetCompact，4 个
卷积块）为 1×。官方权重体积来自 Real-ESRGAN v0.2.5.0 发布物与 Hugging Face
模型索引实测值。

| 候选 | 权重/ONNX 体积 | 架构 | 相对算力 | 适配改动 | 建议 |
| --- | --- | --- | --- | --- | --- |
| `animevideov3`（当前） | 2.4 MB / 2.5 MB | SRVGGNetCompact | 1× | — | 默认模型 |
| `realesr-general-x4v3` | 4.7 MB / 4.9 MB | SRVGGNetCompact | ≈1× | 已接入 | 已随包，照片备用 |
| `RealESRGAN_x4plus_anime_6B` | 17.9 MB / ≈18 MB | RRDB ×6 | ≈10–20× | 需自行导出 ONNX | 按需，先测真机耗时 |
| `RealESRGAN_x4plus` | ≈64 MB | RRDB ×23 | ≈30–60× | 需自行导出 ONNX | 不建议默认随包 |
| `4x-UltraSharp` 等社区模型 | ≈67 MB | ESRGAN 系 | ≈30–60× | 需授权与导出 | 不建议默认随包 |

说明：

- 官方发布物（v0.2.5.0）只直接提供 `.pth` 与 ncnn 包，列出的 pth 为
  `realesr-animevideov3.pth` 2.4 MB、`realesr-general-x4v3.pth` 4.7 MB；
  `RealESRGAN_x4plus_anime_6B.pth` 17.9 MB 见 Hugging Face 镜像。ONNX 可用
  `torch.onnx.export`（动态 H/W 轴，opset 17）自行导出。
- 分块 256 下，一张 832×1216 的图约 4×5=20 块。按手机 CPU 推算，anime 模型
  单块约零点几秒、整图几秒到十几秒；x4plus 家族单块可到数秒、整图分钟级。
  **这部分是估算，需要真机基准确认。**
- 量化（ORT 动态量化 w8a8/w8a16，或 Qualcomm QNN 包）能把体积压到
  1/4–1/2，速度取决于 CPU 指令集与厂商运行时；QNN 包绑定特定 SoC，不适合
  作为随包通用方案。若要做，优先尝试 ORT 动态量化并用同一批图对比画质。

## 如果继续加模型（实施清单）

1. `onnxUpscaleCatalog` 增加条目：`id`、显示名、`engineName`、`scales: [4]`、
   `modelBytes`，`bundled/installed: true`。
2. 模型文件按 `assets/local_upscale/onnx/<engineName>.onnx` 命名放入。
3. 面板在设备端多模型时会自动显示模型下拉（`local_upscale_panel.dart`，
   本轮已实现）；单模型时保持原来的只读行。
4. 导出脚本：`torch.onnx.export` + 256 分块自测（输入 `1×3×256×256`，输出
   `1×3×1024×1024`），核对 RGB 通道顺序与 `[0,1]` 数值范围。
5. 许可证：Real-ESRGAN 系为 BSD-3-Clause（Copyright © 2021 Xintao Wang），
   与现有 `LICENSE-BSD-3-Clause-Real-ESRGAN.txt` 一致；社区模型需单独核对。
6. 测试：catalog/asset 单元测试 + 手机实机对比（画质、耗时、内存峰值）。

## 本轮已落地

- 新增 `realesr-general-x4v3.onnx`（4,871,181 B，SHA-256
  `09b757ac…2b76fa4`，与 Hugging Face LFS 记录一致），来源与许可见
  `assets/local_upscale/onnx/README.md`。
- `onnxUpscaleCatalog` 扩为两个模型，默认仍为 animevideov3；桌面存档模型 id
  仍统一回退到默认模型。
- 引擎按 `modelAsset` 加载模型，服务层按所选 catalog 条目传路径；面板在
  手机端多模型时提供切换。
- 测试覆盖：模型清单/asset 路径、按模型传 asset 两条新用例。

## 趋势判断与建议

- **短期**：默认 anime 模型不变，照片类图片可用 general-x4v3；这是投入产出比
  最高的一步，本轮已完成。
- **中期**：先做 XNNPACK（CPU 卷积加速，ONNX Runtime 自带）的收益实验，再
  决定是否引入更大模型；NNAPI 依机型差异大，适合做成可回退的开关。
- **不做**：SeedVR2 / RTX Video 的移动端复刻；需要桌面级质量时走桌面端或云端。
