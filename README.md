# Live Photo iOS

将静态照片转换为带轻微运镜和几何形变的 Apple Live Photo，并直接保存到 iPhone 系统照片。

当前分支 `codex/ios-app` 是 iOS App 的独立开发基线，不包含可执行的 macOS/Homebrew/FFmpeg 工具。

## 当前状态

- 已完成 iOS 技术调研与实施设计。
- 已创建 SwiftUI iOS 工程并通过真机 Live Photo 保存验收。
- 支持最多 20 张有序多选与批量生成。
- 支持推近、拉远、上下左右平移和斜向 7 种运镜。
- 支持纵向伸缩、横向伸缩、仿射倾斜、轻微侧倾和镜头呼吸 5 种形变。
- 可选运镜、形变、组合或每张随机；高级参数默认收起。
- 预览与导出共用同一 Core Image 渲染器。
- iOS 26.5 Simulator 构建、单元测试、安装启动和首屏检查已通过。
- arm64 iPhoneOS 26.5 SDK 无签名构建已通过。
- 下一阶段：真机验收批量生成、7 种运镜、5 种形变及 35 种组合的视觉强度。

## 文档

- [iOS App 技术调研与实施设计](docs/ios-app-technical-design.md)
- [开发验证记录](docs/development-log.md)
- [macOS 原型参考说明](references/macos-prototype/README.md)

## 原型参考边界

`references/macos-prototype/` 仅保留两类迁移依据：

- 7 种运镜、5 种形变及参数基准。
- JPEG/MOV Live Photo 配对元数据和 PhotoKit 保存逻辑。

该目录不会加入 iOS App target，也不作为 iOS 可执行代码发布。完成原生迁移与回归基准固化后，可整体删除。
