# 开发验证记录

## 2026-09-13：Phase 0 工程骨架

### 目的

建立可运行的原生 iOS 工程，验证 SwiftUI、Core Image、AVFoundation、ImageIO 和 PhotoKit 的最小集成路径。

### 改动点

- 创建 `LivePhotoApp.xcodeproj`，最低部署版本 iOS 17。
- 建立选图、9:16 预览、生成进度和保存结果界面。
- 实现 1080 × 1920、3 秒、30fps 的稳定推近渲染。
- 使用 `AVAssetWriter` 直接生成 H.264 MOV。
- 写入 JPEG/MOV Live Photo 配对标识和静态帧时间元数据。
- 使用 `PHAssetCreationRequest` 保存 `.photo + .pairedVideo`。
- 添加稳定推近曲线端点单元测试。

### 验证结果

- iOS 26.5 Simulator Debug build：通过。
- iPhone 17 Pro / iOS 26.5 Simulator 安装与启动：通过。
- 模拟器首屏视觉检查：通过。
- XCTest：通过。
- arm64 generic iOS Debug build（关闭签名）：通过。

### 未完成验证

- 模拟器无法代替真实“照片”App 对 Live Photo 配对资源的最终兼容性验收。
- 需要配置 Apple Developer Team，在真实 iPhone 上确认保存后显示 LIVE 标志并可长按播放。
- 当前只实现“稳定推近”，其余 6 种运镜和 5 种形变尚未迁移。

### 潜在风险

- Live Photo 手工配对元数据不是 Apple 完整公开规范，真机闭环仍是 Phase 0 的硬门槛。
- 当前中点 JPEG 与 MOV 共用渲染公式；已校验 metadata 轨存在，后续还需深入解析 marker 的具体值和时间范围。

## 2026-09-13：配对资源校验

### 目的

在请求照片权限和写入系统图库前阻断空文件、尺寸错误、配对标识不一致或 metadata 轨缺失的成品。

### 改动点

- 新增 `LivePhotoValidator`。
- 校验 JPEG/MOV 存在且非空。
- 校验 JPEG 为 1080 × 1920，MakerApple `17` 与任务 UUID 一致。
- 校验 MOV 视频轨尺寸、QuickTime content identifier 和 metadata 轨。
- `PhotoLibrarySaver` 在请求权限前强制执行校验。
- 新增完整生成一组 90 帧配对资源的模拟器集成测试。

### 验证结果

- iPhone 17 Pro / iOS 26.5 Simulator XCTest：2 项通过。
- 实际生成与校验集成测试：通过，约 3.0 秒。
- 该测试不写入系统照片库，也不能替代真实 iPhone 的 LIVE 标志验收。
