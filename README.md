# FileNest

iOS 文件管理器与压缩包解压工具。SwiftUI 实现，通过 GitHub Actions 产出**未签名 IPA**。

## 当前状态

`阶段 0：链路打通` — 工程骨架、文件浏览、预览已就绪，解压引擎尚未接入。
目标先让 CI 稳定产出可下载的 ipa，再逐步堆功能。

## 构建

无需 Mac，也无需开发者证书。向 `main` 分支推送即触发构建，或在 Actions 页手动 `Run workflow`。

产物在 Actions 运行的 **Artifacts → FileNest-unsigned-ipa**。

本地构建（需 macOS + Xcode）：

```bash
brew install xcodegen
xcodegen generate
open FileNest.xcodeproj
```

## 安装未签名 IPA

未签名 ipa 无法直接安装，iOS 会拒绝加载。必须用你的 Apple ID 重新签名：

| 工具 | 需要电脑 | 有效期 |
|---|---|---|
| Sideloadly | 是 | 免费账号 7 天 |
| AltStore + AltServer | 是 | 免费账号 7 天 |
| ESign / 企业证书 | 否 | 取决于证书 |
| TrollStore | 否 | 永久，但仅特定 iOS 版本 |

免费 Apple ID 每次重签有效期 7 天，最多同时安装 3 个自签 App。

## 已实现

- 沙盒目录浏览，文件夹逐级下钻
- 按名称 / 大小 / 修改日期排序，升降序切换
- 搜索过滤
- 新建文件夹（自动处理重名）
- 删除（带确认）、重命名
- 从「文件」App 导入（多选，安全作用域访问）
- 按扩展名分类的图标与配色
- QuickLook 预览、系统分享
- 暴露到「文件」App：`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`

## 计划

- **阶段 1** 解压引擎：libarchive 接入，覆盖 ZIP / 7z / RAR / TAR / GZ / BZ2 / XZ
- **阶段 2** 压缩包内直接浏览、密码解锁、解压进度、批量队列
- **阶段 3** 专用查看器：文本代码、十六进制、SQLite、图片 EXIF
- **阶段 4** 深色模式、国际化、大文件防息屏

## 已知边界

iOS 沙盒不允许访问其他 App 的数据。本 App 只能管理自己的 Documents 目录，以及用户通过文件选择器主动授权的外部文件。这不是实现缺陷，是系统限制。

后台解压受限于 `beginBackgroundTask` 的约 30 秒窗口，大文件需要保持前台。

## 许可

MIT
