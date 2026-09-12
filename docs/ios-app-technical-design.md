# iOS Live Photo App 技术调研与实施设计

> 状态：开发前设计基线  
> 分支：`codex/ios-app`  
> 基于 macOS 版本：`35532fe`  
> 更新日期：2026-09-12

## 1. 执行结论

iPhone 端可以在不依赖 FFmpeg、Homebrew 或服务器的前提下，完成“静态图 → 微动视频 → 真 Live Photo → 保存到系统照片”的全流程。

建议技术路线：

- SwiftUI 负责选图、效果预览、参数和进度界面。
- PhotosUI 负责以最小权限选择照片。
- Core Image + Metal 负责逐帧几何变换。
- AVFoundation 负责 H.264 MOV 编码和 Live Photo 元数据轨。
- ImageIO 负责生成带配对标识的 JPEG。
- PhotoKit 负责将 JPEG 和 paired MOV 作为一个 Live Photo 写入照片库。

现有 7 种运镜全部可实现。5 种形变中 4 种可由 Core Image 内建变换实现，1 种镜头畸变呼吸使用 Metal 反向径向采样 kernel 实现。不需要降级效果数量。

## 2. 现有 macOS 实现的可复用原理

现有处理分为两层：

1. `开始批量随机生成.command`
   - 用 FFmpeg 将图片居中放大裁切为 9:16。
   - 用时间函数生成 7 种运镜。
   - 叠加 5 种轻微几何形变之一。
   - 输出 1080 × 1920、3 秒、30fps、H.264 视频。
2. `LivePhotoMaker.swift`
   - 使用每个成品独立的 UUID 作为 asset identifier。
   - 从视频中帧取配对封面，避免原图和裁切后视频尺寸/方向不一致。
   - 在 JPEG Apple Maker dictionary 的 `17` 键写入 asset identifier。
   - 在 MOV 写入 `com.apple.quicktime.content.identifier`。
   - 在视频中点写入 `com.apple.quicktime.still-image-time`，值为有符号 `Int8(-1)` / `0xFF`。
   - 用 `PHAssetCreationRequest` 添加 `.photo` 和 `.pairedVideo` 资源。

iOS 版不应直接搬运 Shell 和 FFmpeg，但 Live Photo 的配对数据模型与元数据逻辑可直接抽象为原生 Swift 服务。

## 3. 目标范围

### 3.1 MVP 必须完成

- 从系统照片选择 1 张静态图。
- 自动纠正 EXIF 方向，居中裁切为 9:16。
- 选择 1 种运镜和 1 种形变，或使用随机组合。
- 提供低分辨率实时预览。
- 导出 1080 × 1920、3 秒、30fps 的无声 Live Photo。
- 保存到系统照片，并给出明确成功/失败结果。
- 导出前可在 App 内长按预览动效。
- 导出任务可取消，失败不留下孤立半成品。

### 3.2 MVP 不包含

- AI 人物动作生成、深度估计或 2.5D 分层视差。
- 批量同时编码多张图片。
- 后台长时间导出。
- iCloud 同步、账号体系、服务器上传。
- 原始 HDR/广色域端到端保留。MVP 统一导出 SDR BT.709，避免色彩元数据不匹配。

## 4. 技术基线

### 4.1 建议最低系统

建议 MVP 以 **iOS 17** 为最低版本，原因是 SwiftUI/PhotosUI 的异步资源加载路径较成熟，同时覆盖近年主流 iPhone。在得到目标手机型号和系统版本后，再锁定 deployment target。

不建议一开始追随最新 SDK 的废弃替代 API，否则会不必要地放弃旧系统。Live Photo 元数据轨可先使用现有已验证的 `AVAssetWriterInputMetadataAdaptor`，并用 availability 封装新 SDK 的 `inputMetadataReceiver(for:)` 路径。

### 4.2 依赖决策

- 仅使用 Apple 系统 framework：SwiftUI、PhotosUI、Photos、AVFoundation、CoreImage、Metal、ImageIO、UniformTypeIdentifiers。
- 不引入 FFmpeg iOS 二进制包：体积大、升级和 license 治理成本高，且本项目所需效果均可原生实现。
- 不引入任何网络依赖。照片处理默认完全本地完成。

## 5. 建议架构

```text
LivePhotoApp
├─ App
│  └─ LivePhotoApp.swift
├─ Features/Composer
│  ├─ ComposerView.swift
│  ├─ ComposerViewModel.swift
│  └─ Components/
├─ Domain
│  ├─ MotionPreset.swift
│  ├─ ShapePreset.swift
│  ├─ RenderConfiguration.swift
│  └─ ExportState.swift
├─ Rendering
│  ├─ MotionCurve.swift
│  ├─ FrameRenderer.swift
│  ├─ CoreImagePipeline.swift
│  └─ Kernels/LensBreathing.metal
├─ LivePhoto
│  ├─ MovieWriter.swift
│  ├─ PairedJPEGWriter.swift
│  ├─ LivePhotoMetadataWriter.swift
│  ├─ LivePhotoValidator.swift
│  └─ PhotoLibrarySaver.swift
├─ Media
│  ├─ PhotoPickerLoader.swift
│  └─ ImageNormalizer.swift
└─ Tests
   ├─ MotionCurveTests.swift
   ├─ MetadataTests.swift
   └─ RenderSnapshotTests.swift
```

设计原则：

- 运动曲线、渲染、编码、Live Photo 打包、照片库写入分层，避免所有逻辑集中在 ViewModel。
- 预览和导出调用同一个 `FrameRenderer`，只改变输出尺寸，保证所见即所得。
- 导出由 actor 串行化，同一时间只有一个高分辨率任务。
- 参数使用 `Codable` 值类型，后续可安全增加预设和导入/导出。

## 6. 渲染与编码数据流

```text
PhotosPickerItem
    ↓ loadTransferable / 临时文件
ImageIO 解码 + EXIF 方向归一化
    ↓
CIImage（源图，仅保留一份）
    ↓ 每帧 t = frameIndex / fps
填充裁切 → 运镜仿射变换 → 单一形变 → 输出裁切
    ↓ CIContext.render
CVPixelBufferPool 提供的 BGRA pixel buffer
    ↓ append(frame, presentationTime)
AVAssetWriterInputPixelBufferAdaptor
    ↓
H.264 / MOV + content identifier + still-image-time metadata
    ↓
中帧同源渲染为 JPEG + MakerApple[17]
    ↓
PHAssetCreationRequest(.photo + .pairedVideo)
```

不生成 90 张中间图片，不将全部帧常驻内存。每帧渲染完后立即送给 writer，由 pixel buffer pool 复用缓冲区。

## 7. 7 种运镜的实现映射

现有曲线可直接转写为 Swift `Double` 函数。令：

- `u = frameIndex / (frameCount - 1)`，范围 0...1。
- `p = u²(3 - 2u)`，即 smoothstep。
- `settle = (1 - exp(-4u)) / (1 - exp(-4))`。

| 效果 | 缩放 | 平移 | iOS 实现 | 可行性 |
|---|---|---|---|---|
| v1.3 手持基准 | `1 + 0.08(0.15 + 0.85p)` | X/Y 带一次往复项 | `CGAffineTransform` | 完全可实现 |
| v1.3 快门基准 | `1 + 0.04(0.12 + 0.88settle)` | 指数趋稳 + 衰减小振荡 | `CGAffineTransform` | 完全可实现 |
| 柔和手持 | `1 + 0.075(0.15 + 0.85p)` | 更小幅 X/Y | `CGAffineTransform` | 完全可实现 |
| 稳定推近 | `1 + 0.075p` | 无 | `CGAffineTransform` | 完全可实现 |
| 轻微上提 | `1 + 0.075p` | X 微移，Y 向上 | `CGAffineTransform` | 完全可实现 |
| 轻微下压 | `1 + 0.075p` | X 微移，Y 向下 | `CGAffineTransform` | 完全可实现 |
| 轻微左漂 | `1 + 0.075p` | X 向左，Y 微移 | `CGAffineTransform` | 完全可实现 |

坐标系注意：Core Image 与 UIKit 的 Y 轴方向不同，运镜曲线不能直接照抄正负号。应在 `FrameRenderer` 入口将所有业务坐标统一为左上原点，最后一次转换到 CI 坐标。

## 8. 5 种形变的实现映射

| 形变 | 现有原理 | iOS 方案 | 差异/风险 |
|---|---|---|---|
| 纵向形变 | 四角透视，振幅为 `sin(πu)` | `CIPerspectiveTransform` | 可等价实现；需校准 CI 四角顺序 |
| 横向形变 | 动态 X 缩放 + 居中裁切 | `CGAffineTransform(scaleX:y:)` | 可等价实现 |
| 仿射倾斜 | 水平 shear | `CGAffineTransform(a:b:c:d:tx:ty:)` | 可等价实现；需预留 overscan |
| 轻微侧倾 | 中心旋转 | 中心平移 + rotate + 逆平移 | 可等价实现；需预留 overscan |
| 镜头畸变呼吸 | 径向 `k1·sin(πu)` | Metal 反向径向采样 kernel | 可实现，但要用截图基准校准与 FFmpeg 的强度感知 |

采样必须使用双线性或更高质量插值。对所有会露边的变换，先根据最大幅度计算安全 overscan，再做最终 1080 × 1920 裁切，不用黑色填边。

### 8.1 为什么默认不做 2× 超采样

2160 × 3840 的 BGRA 渲染表面单帧约 31.6 MiB，还未计入源纹理、中间纹理和编码器缓冲。在 iPhone 上默认 2× 容易导致内存压力、发热和导出速度过慢。

MVP 默认在 1080 × 1920 直接使用 GPU 高质量采样。若边缘阶梯验收不达标，再增加可选 1.5×/2× 高质量导出，并以真机内存数据决定支持的设备范围。

## 9. Live Photo 打包设计

### 9.1 MOV

- 容器：QuickTime MOV。
- 视频：H.264、1080 × 1920、30fps、SDR BT.709、无音轨。
- 顶层 metadata：`com.apple.quicktime.content.identifier = UUID`。
- timed metadata track：`com.apple.quicktime.still-image-time = Int8(-1)`。
- key photo time：MVP 固定视频中点（1.5 秒）。
- marker duration：1 帧。

不再先生成 MP4 然后解码转 MOV。视频帧第一次编码就直接写入目标 MOV，避免二次损耗和额外时间。

### 9.2 JPEG

- 使用与 MOV 中点完全相同的 `FrameRenderer` 输出。
- 尺寸固定 1080 × 1920，orientation 固定为 1。
- 写入 `kCGImagePropertyMakerAppleDictionary: [\"17\": UUID]`。
- 使用 sRGB/SDR，避免封面与视频颜色空间不一致。

### 9.3 照片库保存

- 在导出完成后再请求 add-only 照片权限，避免用户还未看到价值就被索要广泛权限。
- 调用 `PHAssetCreationRequest.supportsAssetResourceTypes`，传入 `.photo` 与 `.pairedVideo` 的 raw value NSNumber 数组做组合预检。该 API 只验证资源类型组合，不验证文件内容。
- 在一个 `performChanges` 中同时添加 `.photo` 与 `.pairedVideo`。
- MOV 使用 `PHAssetResourceCreationOptions.shouldMoveFile = true`，降低大文件复制成本。
- Photos 回调成功后才清理 JPEG；MOV 被移动后不再假设原 URL 存在。

Apple 官方明确支持用 `PHAssetCreationRequest` 将静态图与 `.pairedVideo` 作为单个 Live Photo 资产保存。需要区分的是：Apple 没有把手工构造配对文件所需的 MakerApple `17`、`content.identifier` 和 `still-image-time` 完整定义成公开 Live Photo 文件规范；现有 macOS 方案虽已工作，iOS 与新系统版本仍必须用真机闭环验证。

## 10. 预览设计

预览不先导出视频，而是用 `CADisplayLink`/SwiftUI Timeline 驱动同一个 `FrameRenderer`：

- 预览内部辨率：不超过 540 × 960。
- 预览帧率：30fps；如设备发热或掉帧可自动降到 20/15fps，不改变导出帧率。
- 循环方式：0 → 3s 后直接回到首帧，与最终 Live Photo 播放逻辑一致。
- 导出后用 `PHLivePhoto.request` 从临时 JPEG/MOV 构造 `PHLivePhoto`，在 `PHLivePhotoView` 内做最终长按验收。

## 11. 用户流程

```text
首页
  → 选择照片
  → 自动进入 9:16 预览
  → 选运镜 / 选形变 / 随机换一组
  → 长按预览
  → 生成 Live Photo
  → 导出进度（可取消）
  → App 内最终验收
  → 保存到照片
  → 成功页（再做一张 / 保留当前参数）
```

MVP 将专业参数收起，主界面只展示效果卡片、强度和生成按钮。高级页再提供时长、帧率、运镜强度和形变强度。

## 12. 状态、并发与取消

`ExportState` 使用明确有限状态：

```text
idle → loadingSource → ready → rendering(progress)
     → validating → awaitingPhotoPermission → saving → completed
     → failed(reason)
     → cancelled
```

- 高分辨率导出放入独立 actor，避免 UI 线程卡顿。
- 每渲染一帧检查 cancellation。
- App 进入后台时，为正在收尾的任务申请短时 background task；不承诺后台长时间编码。
- 被系统中止后，下次启动清理 App Caches 内超过 24 小时的孤立临时文件。

## 13. 内存与性能预算

1080 × 1920 BGRA 单帧原始缓冲约 7.9 MiB。通过 pixel buffer pool 小规模复用，再加上源图纹理、CI 中间表面和编码器内部缓冲，MVP 的工程目标是：

- 常规导出内存峰值：尽量控制在 250 MiB 内。
- 不保留帧数组。
- `CIContext` 全局复用，不按帧创建。
- 不在主线程解码原图或调用 `CIContext.render`。
- 对超大照片先按“输出尺寸 + overscan”下采样，不长期持有 48MP 全分辨率 bitmap。
- 收到 memory warning 时清理预览 cache，不中断已进入编码器的当前帧。

真机时间目标不在设计阶段猜测，以第一个 vertical slice 在目标 iPhone 上的测量为准。验收门槛建议为：3 秒成品在近 4 年主流设备上导出不超过 10 秒，且不出现系统内存终止。

## 14. 输入与颜色边界

- 输入格式：JPEG、HEIC、PNG；WebP 是否支持以系统解码能力检测结果为准，不在 UI 中做无条件承诺。
- 从 PhotosPicker 获得的资源可能需要从 iCloud 下载，需显示单独的 loading 与网络失败状态。
- 输入可能是 Display P3/HDR。MVP 在解码后显式转换到 sRGB/BT.709 SDR，避免 JPEG 封面和 H.264 视频色彩不一致。
- 透明 PNG 默认使用不透明白色合成底色，并在高级设置允许更改。

## 15. 错误分类与恢复

| 阶段 | 典型错误 | 用户可执行恢复 |
|---|---|---|
| 选图 | iCloud 资源不可用/格式不支持 | 重试加载或重选 |
| 解码 | 图片损坏/尺寸异常 | 告知具体文件，不进入导出 |
| 渲染 | Metal/CI 创建表面失败 | 降低质量重试 |
| 编码 | codec/writer 失败或空间不足 | 显示原始错误及清理建议 |
| 打包 | JPEG/MOV identifier 或 metadata 校验失败 | 禁止保存，保留调试文件 |
| 权限 | 照片 add-only 权限被拒绝 | 保留当前导出，提供进设置指引 |
| 保存 | PhotoKit 事务失败 | 不宣称成功，允许重试 |

日志不记录图片像素、文件绝对路径或照片标题。只记录任务 ID、阶段、耗时、输入尺寸、输出参数和错误码。

## 16. 导出前自校验

保存到 Photos 之前，`LivePhotoValidator` 必须检查：

1. JPEG 和 MOV 文件存在且大小非零。
2. JPEG 尺寸为 1080 × 1920、orientation = 1。
3. JPEG MakerApple `17` 可读，与当次 UUID 相同。
4. MOV 存在 H.264 视频轨，尺寸和方向正确。
5. MOV content identifier 与 JPEG 一致。
6. MOV 含 `still-image-time` metadata 轨，且 marker 位于合法时间范围。
7. `PHLivePhoto.request` 可从两个临时资源构造可播放 Live Photo。

第 7 项是系统级组合验证，不能只用自己的元数据解析替代。

## 17. 测试策略

### 17.1 单元测试

- 7 种运镜在 `u=0/0.25/0.5/0.75/1` 的 scale/x/y 黄金值。
- 曲线连续性、边界值和不越界裁切。
- 5 种形变在首帧/中帧/末帧的矩阵或 kernel 参数。
- UUID 在 JPEG 与 MOV 之间的一致性。
- 状态机禁止非法跳转。

### 17.2 截图回归

为 35 种组合各渲染首帧、中帧、末帧，与批准的基准 PNG 做差异测试。首帧与末帧应验证图像回到预期几何状态，中帧验证最大形变。

### 17.3 真机矩阵

至少测试：

- 一台最低支持性能级别设备。
- 一台当前主力 iPhone。
- 系统照片库开启 iCloud 优化存储的情况。
- 照片权限：首次允许、拒绝、限制、从设置恢复。
- 输入：竖图、横图、方图、48MP HEIC、Display P3、HDR、透明 PNG。
- 生成后在系统“照片”中确认 `LIVE` 标志、长按播放、封面方向、无黑边、无闪帧。

## 18. 开发阶段与门槛

### Phase 0：环境与最小技术验证

- 安装完整 Xcode，确认 iOS SDK、签名团队和目标真机。
- 只实现“一张内置图 + 稳定推近 → MOV/JPEG → Photos”垂直切片。
- 通过系统照片 App 的 LIVE 标志和长按播放验收。

**门槛：** 配对资产真机保存成功且重复 10 次无失败，再开始铺开 UI 和全部效果。

### Phase 1：渲染核心

- 图片归一化、高质量裁切。
- 7 种运镜、4 种 Core Image 形变。
- 共用预览/导出 renderer。
- 单元测试和截图回归。

### Phase 2：完整 Live Photo 作业流

- PhotosPicker、导出状态机、取消、校验、保存。
- `PHLivePhotoView` 最终预览。
- 权限和失败恢复。

### Phase 3：镜头畸变与质量调优

- Metal 镜头畸变 kernel。
- 与 macOS/FFmpeg 输出的感知强度对齐。
- 真机 Instruments 的 Time Profiler、Metal System Trace、Allocations 测量。

### Phase 4：产品化

- 参数预设、随机组合、新手引导。
- 多尺寸设备和 Dynamic Type 适配。
- 隐私文案、App 图标、TestFlight 分发准备。

## 19. 开发前必须确认的三个外部条件

1. **完整 Xcode：** 当前环境只有 `/Library/Developer/CommandLineTools`，`iphoneos` SDK 不存在，暂时无法创建或编译 iOS target。
2. **目标 iPhone：** 需要知道最低要支持的 iPhone 型号和 iOS 版本，用于锁定 deployment target 和性能门槛。
3. **签名：** 真机调试需要在 Xcode 选择 Apple Developer Team；本地个人签名可先做验证，TestFlight/App Store 发布再需要付费开发者账号。

## 20. 主要风险与应对

| 风险 | 级别 | 应对 |
|---|---:|---|
| Live Photo 私有命名元数据在新 SDK 的长期兼容性 | 高 | Phase 0 先真机端到端验证；封装 metadata writer；保留 fixture 回归 |
| `AVAssetWriterInputMetadataAdaptor` 在新 SDK 标记 deprecated | 中 | 用 availability 双路径封装，不让 API 差异泄漏到业务层 |
| 2× 超采样造成内存/发热问题 | 高 | 默认 1×；只在实测证明有价值后提供高质量模式 |
| Core Image 与 FFmpeg 坐标/采样差异 | 中 | 35 组合三关键帧截图回归，不依赖目测 |
| iCloud 资源加载慢或断网 | 中 | 独立 loading/重试状态，加载完之前不创建导出任务 |
| App 退到后台导出被中止 | 中 | 明确前台导出预期，短时 background task 只做收尾，支持重试 |
| 原图和视频色差 | 中 | JPEG/MOV 共享渲染帧与显式 SDR 色彩空间 |

## 21. 官方资料

- [Apple: Capturing and saving Live Photos](https://developer.apple.com/documentation/avfoundation/capturing-and-saving-live-photos)
- [Apple: PHAssetCreationRequest](https://developer.apple.com/documentation/photos/phassetcreationrequest)
- [Apple: Displaying Live Photos](https://developer.apple.com/documentation/photokit/displaying-live-photos)
- [Apple: PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker)
- [Apple: AVAssetWriterInputPixelBufferAdaptor](https://developer.apple.com/documentation/avfoundation/avassetwriterinputpixelbufferadaptor)
- [Apple: AVAssetWriterInputMetadataAdaptor](https://developer.apple.com/documentation/avfoundation/avassetwriterinputmetadataadaptor)
- [Apple: AVAssetWriterInput](https://developer.apple.com/documentation/avfoundation/avassetwriterinput)
- [Apple: CIPerspectiveTransform](https://developer.apple.com/documentation/coreimage/ciperspectivetransform)
- [Apple: CILanczosScaleTransform](https://developer.apple.com/documentation/coreimage/cilanczosscaletransform)
- [Apple: Processing an Image Using Built-in Filters](https://developer.apple.com/documentation/coreimage/processing-an-image-using-built-in-filters)
- [Apple: kCGImagePropertyMakerAppleDictionary](https://developer.apple.com/documentation/imageio/kcgimagepropertymakerappledictionary)

## 22. 下一步执行结论

不应立即开始铺全部 UI。正确的第一个开发任务是 Phase 0 垂直切片：用内置图片完成一种稳定推近，在真机上验证 MOV/JPEG 配对、Photos 保存与长按播放。该闭环通过后，再扩展到 35 种组合与完整界面。
