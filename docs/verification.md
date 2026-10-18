# 本机核验记录

日期：2026-10-18（Asia/Shanghai）

范围：当前执行主机；仅记录必要的非识别性技术信息。未读取个人照片、实际图库目录或已保存屏保配置。

## 环境

| 项目 | 现场结果 | 取得方式 |
| --- | --- | --- |
| 系统 | macOS 27.0.1，build `26A434` | `sw_vers` |
| 架构 | arm64 | `uname -m` |
| Xcode | 27.1，build `27A9275` | `xcodebuild -version` |
| macOS SDK | 27.0 | `xcrun --show-sdk-version` |
| 屏幕 0 | 2560 × 1440 points，backing scale 2.0 | `NSScreen.screens` |
| 屏幕 1 | 1440 × 2560 points，backing scale 2.0 | 同上 |

上述屏幕数值是 AppKit 视口及 backing scale，不等同于面板原生硬件规格；未采集显示器名称或序列号。

## ScreenSaver 接口

1. 检查当前 SDK 的 `ScreenSaverView.h`、`ScreenSaverDefaults.h`：公开视图、生命周期、配置窗口和按模块设置入口存在，没有发现类级废弃标记。
2. 在临时目录编译了导入 `ScreenSaver`、`AppKit`、`ImageIO` 的 Swift 命令行探针，声明一个空的 `ScreenSaverView` 子类；编译、链接和进程执行成功。没有实例化或启动屏保视图。
3. 在系统 framework 下找到 `legacyScreenSaver.appex`；只读检查其签名 entitlement，确认包含 App Sandbox、图片只读、用户选择文件只读及 app-scope bookmark 能力。
4. 在 ScreenSaver 公共头文件中检索 `ScreenSaverExtension` / `ScreenSaverViewController` / `ScreenSaverConfiguration`，没有命中。此结果限定为本机该框架公共头文件，不声称整个系统没有对应运行时符号。
5. 读取 Apple macOS 27 发布说明结构化正文，未检索到 `screen saver`、`screensaver` 或 `wallpaper`。未据此推断宿主行为。

## ImageIO 解码探针

样本均为临时生成的 `128×96` 不透明静态色块，无个人图片：JPG/JPEG、PNG、HEIC 用系统 ImageIO 编码；WebP 用现有通用 Python 环境中的 Pillow 12.3.0 编码。没有新增或升级依赖。

运行时 ImageIO 类型列表包含 `public.jpeg`、`public.png`、`public.heic`、`org.webmproject.webp`；随后逐一调用实际解码 API，而非仅检查扩展名或类型列表。

| 文件 | `CGImageSourceCreateImageAtIndex` | 带方向变换选项的 thumbnail 解码 |
| --- | --- | --- |
| sample.jpg | 成功，128×96 | 成功，64×48 |
| sample.jpeg | 成功，128×96 | 成功，64×48 |
| sample.png | 成功，128×96 | 成功，64×48 |
| sample.heic | 成功，128×96 | 成功，64×48 |
| sample.webp | 成功，128×96 | 成功，64×48 |

探针在普通命令行进程中执行。上述样本没有非默认 EXIF 方向，也没有复杂 ICC、HDR、多帧、透明或损坏编码；“传入方向变换选项成功”不等于 EXIF 各方向都已验收。

临时探针与合成文件放在系统临时目录，未作为产品代码提交，也未运行第三方仓库中的程序或安装脚本。当前仓库没有产品构建产物。

## 尚未验证

- `.saver` 在 macOS 27 系统设置中的加载、缩略预览与配置窗口。
- 实际屏保宿主下两块屏幕的并发播放、屏幕绑定和实例生命周期。
- `NSOpenPanel` 选择目录后，配置预览、实际屏保及重启之间的权限持久性。
- 真正的 Ken Burns 渲染、连续帧无黑边、交叉过渡与播放序列。
- 睡眠/唤醒、锁屏、显示器插拔/旋转和设置变化。
- 大图库、超大照片、长时间运行、CPU/GPU/内存表现。
- Developer ID 签名、公证和其他机器的安装。

这些项目是后续规划的验收内容。不得将本记录表述为“产品已通过双屏测试”。
