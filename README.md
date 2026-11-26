# FileNest

iOS 文件管理器与压缩包解压工具。SwiftUI 实现，通过 GitHub Actions 用 **Xcode 27 / iOS 27 SDK** 产出**未签名 IPA**。

无需 Mac，无需开发者证书。

## 格式支持

### 解压

| 格式 | 扩展名 | 读取 | 解压 | 加密 | 引擎 |
|---|---|---|---|---|---|
| ZIP | zip, cbz | ✅ | ✅ | ✅ ZipCrypto / AES | libarchive |
| RAR / RAR5 | rar, cbr | ✅ | ✅ | ✅ | libarchive |
| 7-Zip | 7z | ✅ | ✅ | ❌ | SWCompression |
| TAR | tar | ✅ | ✅ | — | SWCompression |
| GZip | gz, tgz | ✅ | ✅（内层 tar 自动展开） | — | SWCompression |
| BZip2 | bz2, tbz, tbz2 | ✅ | ✅（内层 tar 自动展开） | — | SWCompression |
| XZ | xz, txz | ✅ | ✅（内层 tar 自动展开） | — | SWCompression |
| ISO | iso | ✅ | ✅ | — | libarchive |
| CAB | cab | ✅ | ✅ | — | libarchive |

格式识别读文件头魔数，不看扩展名——改了后缀的包也能正确识别。

不支持：DMG、ARJ、LZH/LHA、ACE、Z（compress）、分卷压缩包、加密 7z。遇到这些会明确报「无法识别这个压缩包的格式」，不会静默失败。

### 预览

| 类型 | 扩展名 | 实现 |
|---|---|---|
| 图片（可双指缩放、双击放大） | jpg, jpeg, png, gif, heic, heif, webp, tiff, bmp | UIImage + UIScrollView |
| PDF（连续滚动、自动缩放） | pdf | PDFKit |
| 文本 / 代码（等宽、可选中、自动识别 GB18030） | txt, md, log, csv, json, xml, yml, swift, py, js, html, css, sh … | 原生文本视图 |
| 音频 / 视频 | mp3, m4a, aac, wav, flac, mp4, mov, m4v | AVKit |
| Office 及其余可预览格式 | docx, xlsx, pptx, rtf, svg … | QuickLook |
| 无法预览 | 老版 doc/xls、CAD、加密 PDF、DRM 音视频、压缩包 | 显示说明 + 分享 |

文本预览上限 4 MB（超出只读前 4 MB 并提示），避免大文件把内存打满。


## 为什么是两个引擎

这不是选择困难，是 iOS 的客观限制：

- **libarchive** 是唯一能解 RAR 的宽松许可实现（BSD）。但 iOS SDK 有 `libz.tbd`、`libbz2.tbd`，**没有 `lzma.h`**，所以它编不出 7z 的 LZMA 解码能力。
- **SWCompression** 是纯 Swift（MIT），自带 LZMA/LZMA2 实现，覆盖 7z / XZ / TAR，但**不支持 RAR，也不支持加密 ZIP**。

所以分工是互补而非冗余：RAR 和加密 ZIP 走 libarchive，其余走 SWCompression。

libarchive 在 CI 里用 CMake 交叉编译成 iOS 静态库（真机 + 模拟器两个 slice），并链接 `libiconv` 处理中文文件名的字符集转换。

## 构建

推送 `main` 即触发，或在 Actions 页手动 `Run workflow`。产物在 **Artifacts → FileNest-unsigned-ipa**，约 700 KB。

流水线做的事：

1. 交叉编译 libarchive（arm64 device + arm64 simulator）
2. 用 XcodeGen 从 `project.yml` 生成 `.xcodeproj`
3. `xcodebuild` 以 `CODE_SIGNING_ALLOWED=NO` 编译
4. 打包成 `Payload/FileNest.app` → zip → ipa
5. 在 iOS 27 模拟器上跑解压单元测试

本地构建（需 macOS + Xcode）：

```bash
brew install xcodegen cmake ninja
# 需先自行编译 libarchive 到 vendor/，参见 .github/workflows/build.yml
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

免费 Apple ID 每次重签 7 天有效，最多同时安装 3 个自签 App。

## 已实现

**文件管理**：沙盒目录浏览、逐级下钻、按名称/大小/日期排序、搜索、新建文件夹、删除（带确认）、重命名、从「文件」App 多选导入、按类型着色的图标、QuickLook 预览、系统分享。

**解压**：格式嗅探、条目列表（不解压即可查看内部结构）、全部解压、实时进度、密码解锁、Zip Slip 路径逃逸防护、同名目录自动避让。

**系统集成**：`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`，App 出现在「文件」App 的「我的 iPhone」下。

最低支持 iOS 17.0（SWCompression 4.9 的要求）。

## 待办

- 压缩包内单条内容预览（当前只能看列表）
- 压缩功能（选文件 → 打包 ZIP）
- 解压时的 GBK 文件名兜底（目前依赖 libiconv 自动判定，Windows 老包仍可能乱码）
- 大文件解压的前台保活与中断恢复

## 已知边界

iOS 沙盒不允许访问其他 App 的数据。本 App 只能管理自己的 Documents 目录，以及用户通过文件选择器主动授权的外部文件。这不是实现缺陷，是系统限制。

后台解压受限于 `beginBackgroundTask` 的约 30 秒窗口，大文件需要保持前台。

## 许可

MIT。libarchive 为 BSD-2-Clause，SWCompression 为 MIT。
