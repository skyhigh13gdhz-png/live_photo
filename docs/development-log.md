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
- 当前中点 JPEG 与 MOV 共用渲染公式，但尚未加入导出前资源解析校验。
