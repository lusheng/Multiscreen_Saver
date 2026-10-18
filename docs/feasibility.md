# 可行性调研

调研日期：2026-10-18（Asia/Shanghai）

状态：调研快照；方案已于 2026-10-18 获用户批准，见[已批准规划](plan.md)及[执行提示词](../goal_prompt.md)。本报告不是 G1 或产品验收结论。

## 结论

**有条件可行，建议进入小规模原生宿主验证。** 图片解码、Ken Burns 几何、双图库播放和原生设置都具备实现基础；决定项目能否按原始诉求交付的主要因素，是 macOS 27 的实际屏保宿主能否稳定显示两个实例，并持续访问分别选定的图库。

本机已验证 macOS 27.0.1、Xcode 27.1、macOS SDK 27.0；公开 `ScreenSaver.framework` 可以导入和链接，五种要求的文件扩展名均完成真实样本解码。尚未创建、安装或启动产品 `.saver`，因此不能声称双屏屏保已经可用。详细证据见[本机核验记录](verification.md)。

推荐先采用 **Swift + ScreenSaver.framework + AppKit + Core Animation + ImageIO**，输出原生 `.saver`。将宿主验证设为第一阶段门槛，避免先完成大量功能后才发现系统限制。

## 1. macOS 27 与原生屏保接口

Apple 已有 [macOS 27 Golden Gate 发布说明](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)。本次读取了该页面的结构化正文，没有检索到屏保或壁纸相关条目；“没有提到”不能证明已修复历史问题，也不能证明接口已移除。

Apple 的公开 [Screen Saver 文档](https://developer.apple.com/documentation/screensaver)仍描述 `.saver` bundle、`ScreenSaverView` 和 `ScreenSaverDefaults`。本机 SDK 头文件中这些入口存在，未发现类级废弃标记；系统中也存在 `legacyScreenSaver.appex` 宿主。

原生配置入口为 `hasConfigureSheet` / [`configureSheet`](https://developer.apple.com/documentation/screensaver/screensaverview/configuresheet)，可以提供 AppKit `NSWindow`。设置存储应使用按模块标识隔离的 [`ScreenSaverDefaults`](https://developer.apple.com/documentation/screensaver/screensaverdefaults)，不能把宿主的 `UserDefaults.standard` 当成本产品的配置域。

“系统会为每台显示器运行独立的屏幕保护”在设计上应理解为**每个显示区域有独立的播放实例**，不能假设每块屏幕必然对应独立进程，也不能把实例数量固定为屏幕数量。预览、无尺寸视图、重复加载都可能增加实例；播放状态不能放在共享的单例中。

### 三条原生相关路线

| 路线 | 优点 | 限制 | 本项目建议 |
| --- | --- | --- | --- |
| 公开 API `.saver` | 公开屏保入口；直接进入系统屏保选择；交付简单 | 依赖系统兼容宿主，历史上有副屏、预览及生命周期问题 | 首选，先通过 G1 实机门槛 |
| `.app` 内嵌 `com.apple.screensaver` 扩展 | 社区已有运行样例；进程隔离与生命周期可能更合适 | 当前参考样例使用私有声明；配置、签名、书签共享须另行验证 | `.saver` 被实际阻断时再审议 |
| `com.apple.wallpaper` 扩展 | Aerial 4.1 用它实现壁纸/屏保衔接 | 依赖私有 `WallpaperExtensionKit`，复杂度超出当前需求 | 不纳入首版 |

独立全屏 App 也能播放照片，但它的空闲检测、锁屏与原生屏保集成需要另外实现，不满足本轮默认的交付形态。未经用户改变目标，不将它作为“原生屏保已完成”的替代品。

## 2. GitHub 与类似项目

以下为本次查看的原始仓库/作者资料，不代表已安装验收。

| 项目 | 已核实的相关能力 | 与本项目的差距及用途 |
| --- | --- | --- |
| [ArtSaver](https://github.com/GabZach/ArtSaver) / [作者主页](https://user.informatik.uni-bremen.de/zach/software/ArtSaver/index.html) | 作者明确描述 Ken Burns、每屏不同图库、时长设置和一轮内不重复 | 功能最接近；GitHub README 明确表示没有产品代码，树中只有文档，无项目许可证。不能作为开源底座；macOS 27、WebP、严格无边缘黑边等未验证 |
| [ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal) | Swift `.saver`、独立调试 App、配置界面、宿主问题说明；MIT | 适合作为结构与故障排查参考；不是照片播放器，不能把旧版本 workaround 原样搬入新产品 |
| [AppexSaverMinimal](https://github.com/AerialScreensaver/AppexSaverMinimal) | 宿主 App 加屏保扩展、共享渲染、配置入口；MIT | 可研究现代原生扩展方案，但仓库明确使用 private API，不能称为 Apple 公开支持的替代接口 |
| [Aerial](https://github.com/AerialScreensaver/Aerial) | 活跃的原生多屏屏保项目；4.0 转为扩展，4.1 加入壁纸扩展；MIT | 适合研究多屏、宿主生命周期和分发；面向视频及较复杂功能，整体 fork 会引入大量无关内容 |
| [openscopeproject/MultiScreenSaver](https://github.com/openscopeproject/MultiScreenSaver) | 明确支持横/竖屏不同照片目录、随机播放、缩放及混合过渡；GPL-3.0 | 需求非常相近，但采用 Windows/Direct2D/wxWidgets，不能作为 macOS 原生实现直接使用 |
| [SaveCannes](https://github.com/PerpetualBeta/SaveCannes) | 本地照片/视频、每屏来源设置；Unlicense | 当前交付是菜单栏 `.app`，自主处理空闲与全屏窗口；适合作为功能对照，不能视作已满足系统原生屏保要求 |

**因此：有相近产品和可参考的原生项目，但本次未找到经过 macOS 27 双屏验证、完整满足这组需求且可以直接采用的开源成品。** 该结论仅限本次检索范围，不声称不存在其他项目。

检索使用了 GitHub 仓库搜索与网页搜索，关键词包括 `screensaver Ken Burns macOS`、`photo screensaver macOS`、`ArtSaver`、`MultiScreenSaver`，并核对了候选仓库 README、目录树、许可证元数据及部分相关源码。

### 已固定的源码参考版本

| 仓库 | 本次检查的 HEAD | 该提交时间（UTC） |
| --- | --- | --- |
| AerialScreensaver/Aerial | `03fe7bc01009607b8a8e1af68389413e096d802d` | 2026-10-16 17:56:41 |
| AerialScreensaver/ScreenSaverMinimal | `0bd0cd2d0f03078918946b54f74ca7df81be8545` | 2025-07-29 15:34:35 |
| AerialScreensaver/AppexSaverMinimal | `6be6c85b49e827320711289853726e68d3fbd7ea` | 2026-05-17 19:56:36 |
| openscopeproject/MultiScreenSaver | `b5fa23390c076eac3451257ac1b24c1341c3f5c3` | 2025-01-23 08:40:15 |
| GabZach/ArtSaver | `70fb806435588600981c6ed2ef1eaa2e5ff5e82b` | 2022-12-13 17:47:09 |

以上为提交时间，不把 star、issue 等活动导致的仓库更新时间误写成产品更新日期。

## 3. 必须先处理的兼容性风险

### 3.1 副屏、预览与生命周期

[Apple 开发者论坛的 Tahoe 问题线程](https://developer.apple.com/forums/thread/787444)记录了 macOS 26 测试版的副屏不显示、配置面板异常、预览标志与实例累积问题。它们是风险线索，**不是 macOS 27.0.1 仍然发生这些问题的证据**。

[ScreenSaverMinimal 源码](https://github.com/AerialScreensaver/ScreenSaverMinimal/blob/0bd0cd2d0f03078918946b54f74ca7df81be8545/ScreenSaverMinimal/ScreenSaverMinimalView.swift)包含基于系统状态的判断和退出宿主的可选 workaround。共享宿主中的 `exit(0)` 会影响其他实例，不应成为本项目默认处理。设计应先做好幂等启动/停止、离屏取消解码、销毁观察者和零尺寸等待，再记录真实宿主行为。

G1 必须运行原生 `.saver`：预览正常、横竖两屏同时显示、反复启停后没有后台动画或持续增长，才允许继续实现完整播放器。若失败，应记录系统 build 与复现条件，先尝试限定范围的公开 API 修复；不得无限堆积启发式判断。

### 3.2 文件权限与设置共享

屏保在系统宿主中运行。终端能读取照片，不代表屏保也能读取。用户选目录应使用原生 `NSOpenPanel`；持久访问需要验证只读 security-scoped bookmark、陈旧书签更新和成对的访问释放。[Apple 文件沙盒说明](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)说明了持久授权和显式恢复访问的要求。

本机系统宿主 entitlement 包含 sandbox、用户选择只读访问和 app-scope bookmark 支持，但这不等于任意目录自动获准，也不排除 TCC 等限制。G1 应在配置窗口选择两个合成测试图库，关闭系统设置后、屏保重启后分别验证访问；不扫描用户照片库。

不要假定独立配置 App 创建的书签可以无条件供 `.saver` 使用。Apple 的 [bookmarkData 文档](https://developer.apple.com/documentation/foundation/nsurl/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:))说明 app-scoped bookmark 与创建者身份相关。首版优先将设置入口放在屏保自己的 `configureSheet`；若该入口不可用，再评估伴随 App 所需的签名、共享配置与权限方案。

### 3.3 私有扩展路线的事实边界

Aerial 当前 README 已明确其架构变化。[AppexSaverMinimal 的私有头文件](https://github.com/AerialScreensaver/AppexSaverMinimal/blob/6be6c85b49e827320711289853726e68d3fbd7ea/AppexSaverMinimalExtension/PrivateHeaders/ScreenSaverPrivate.h)声明了 `ScreenSaverExtension`、`ScreenSaverViewController` 等类；本次在 SDK 的 ScreenSaver 公共头文件内没有查到这些声明。

样例文档个别位置对历史引入版本和符号可见性的表述并不完全一致。本规划只据其代码认定“存在社区使用的私有扩展路线”，不据此承诺长期 API 稳定性、App Store 可用性或 macOS 27 双屏验收结果。

## 4. Ken Burns 与黑边约束

本节是本项目拟采用的几何设计，不是已有实现结果。

先对图片执行 EXIF 方向归一化，得到尺寸 `(Iw, Ih)`；视口尺寸为 `(Vw, Vh)`。计算填充基准：

```text
s0 = max(Vw / Iw, Vh / Ih)
B  = (Iw * s0, Ih * s0)
```

这对应等比填充并裁剪。Apple 的 [`resizeAspectFill`](https://developer.apple.com/documentation/quartzcore/contents-gravity-values)描述了填充语义，但**仅设置 aspect fill 不足以保证后续平移不露边**。

在缩放倍率 `z` 下，图片中心相对视口中心的偏移必须满足：

```text
|tx| <= (B.width  * z - Vw) / 2
|ty| <= (B.height * z - Vh) / 2
```

从合法起点 `(z=1, tx0, ty0)` 和合法终点 `(z=随机1.10…上限, tx1, ty1)` 出发，缩放和平移使用同一个插值进度 `u∈[0,1]`。这些约束是线性的，合法端点之间的线性插值仍合法；若使用缓动，也必须共用同一个进度，不分别应用不同曲线。最终对实际渲染几何加断言，并留约 1–2 个 backing pixel 的覆盖余量，避免取整/采样细缝。

若图片与屏幕宽高比完全相同，`z=1` 的起始可平移空间约为零，应从中心开始，随放大逐渐平移。任意宽高比均优先填满，允许裁掉内容；无法同时保证完整保留图片和全屏无留白。

交叉过渡采用“下层保持不透明，上层从 0 增至 1”，得到 `C=(1-f)A+fB`。不要在普通 source-over 合成中同时将上下两层透明度设为 `1-f` 和 `f`，否则底色可能透出并造成暗闪。两张图片在重叠期间都继续运动。

透明 PNG/WebP 还可能在图像内部露出背景，这与几何越界不同。建议先以同图的模糊填充底图合成为不透明画面，再进行动画；该策略列为需要审阅的产品语义。

## 5. 图片、扫描与性能

本机 ImageIO 已对合成的 JPG、JPEG、PNG、HEIC、WebP 样本完成全图解码及缩略图解码，不需要为了 WebP 默认引入第三方库。该检查仅证明常见静态样本可用，不代表所有编码变体、损坏文件、透明度、EXIF 和色彩管理都已通过。

首版建议使用 [`CGImageSourceCreateThumbnailAtIndex`](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:))，结合显示器 backing pixels、缩放上限和最大解码预算确定大小；后台扫描与解码，主线程只提交图层和界面变化。扩展名匹配忽略大小写，随后以解码结果为准；动态 WebP、APNG 或多图 HEIC 按首个主图/首帧静态显示，暂不播放内部动画。

每屏只保留当前、过渡及必要的下一张；双屏各自维护播放队列，禁止每帧重新读取磁盘。超长全景图采用有上限的降采样，必要时降低该图清晰度，不能为避免裁剪无限放大解码内存。

本机两屏视口为 `2560×1440 @2x` 与 `1440×2560 @2x`。按 backing 尺寸计算，一张 `5120×2880` 的 8-bit RGBA 图约 56.25 MiB；若两个方向都额外保留 1.2 倍采样，约 81 MiB。双屏各两张约 324 MiB，尚不含 GPU 副本、解码中间态和宿主开销。不能把小窗口预览的内存表现外推到双屏。

## 6. 继续与停止条件

- **可继续：** 规划已获批准；在新的执行会话中进入 G1，使用合成图库验证真实宿主。
- **必须先解决：** 副屏不显示、设置不能保存、重启后失去图库权限、重复实例不释放工作负载。
- **需要重新决策：** 公开 API 路线被目标系统阻断，只能通过私有扩展或独立全屏 App 实现；不能在用户不知情时改变产品形态。
- **后置项：** 面向其他用户的 Developer ID 签名、公证和 Release 分发，不作为本轮“公开 GitHub 仓库”的隐含承诺。

完整执行顺序与验收矩阵见[开发规划](plan.md)。
