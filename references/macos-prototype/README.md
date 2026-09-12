# macOS 原型参考

此目录是 iOS 迁移期间的只读行为参考，不是 iOS App 的组成部分。

## 保留内容

| 文件 | 暂时保留原因 | 删除条件 |
|---|---|---|
| `开始批量随机生成.command` | 保存 7 种运镜、5 种形变的原始 FFmpeg 时间函数、参数和组合逻辑 | iOS 的 35 组合关键帧回归基准全部通过 |
| `批量生成参数.conf` | 保存原型参数默认值及建议强度 | 参数已转为 iOS `RenderConfiguration` 并有单元测试 |
| `LivePhotoMaker.swift` | 保存已验证的 JPEG/MOV 配对元数据与 PhotoKit 导入逻辑 | iOS 真机连续生成验证通过，且 fixture 校验已建立 |

## 已移除内容

- Homebrew/FFmpeg 首次安装脚本：iOS 不使用外部命令行依赖。
- macOS 单张测试入口：将由 iOS Phase 0 真机闭环替代。
- macOS 可执行文件 Info.plist：不属于 iOS App target。
- macOS Swift 编译 CI：将在 iOS 工程建立后替换为 iOS build/test workflow。

## 使用约束

- 不在此目录继续开发新功能。
- 不从 iOS target 引用或打包此目录。
- 行为迁移以截图回归和真机 Live Photo 验收为准，不机械逐行翻译 Shell。
