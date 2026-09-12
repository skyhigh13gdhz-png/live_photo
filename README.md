# Live Photo iOS

将静态照片转换为带轻微运镜和几何形变的 Apple Live Photo，并直接保存到 iPhone 系统照片。

当前分支 `codex/ios-app` 是 iOS App 的独立开发基线，不包含可执行的 macOS/Homebrew/FFmpeg 工具。

## 当前状态

- 已完成 iOS 技术调研与实施设计。
- 下一阶段：创建 iOS 工程并完成最小 Live Photo 真机闭环。
- 当前开发环境仍需安装完整 Xcode 和 iPhoneOS SDK。

## 文档

- [iOS App 技术调研与实施设计](docs/ios-app-technical-design.md)
- [macOS 原型参考说明](references/macos-prototype/README.md)

## 原型参考边界

`references/macos-prototype/` 仅保留两类迁移依据：

- 7 种运镜、5 种形变及参数基准。
- JPEG/MOV Live Photo 配对元数据和 PhotoKit 保存逻辑。

该目录不会加入 iOS App target，也不作为 iOS 可执行代码发布。完成原生迁移与回归基准固化后，可整体删除。
