# G1 构建与实机操作

此阶段仅为最小诊断屏保。全部 G1 必需项通过前不得据此进入完整功能。

## 构建与安装

在仓库根目录执行：

```sh
./scripts/build.sh
./scripts/test-lifecycle.sh
xcrun swift scripts/generate-fixtures.swift "$PWD/LocalPhotos"
./scripts/install-local.sh
```

工程已提交，无需生成器或第三方依赖。`scripts/create-project.py` 只用于维护确定性工程描述。构建输出为 `build/MultiscreenSaver.saver`；安装脚本核验签名，备份已有同名产物，仅安装本项目到用户 Library。生成图像和原始日志不纳入版本控制。

## 实机步骤

1. 先记录原屏保选择，并确认用户可用测试时段。
2. 系统设置→墙纸：先在显示器下拉菜单选择横屏，再进入屏幕保护程序→其他→全部显示，选择 MultiscreenSaver，打开“选项…”。两套图库保存后返回墙纸，切换到竖屏，也选择 MultiscreenSaver。本机屏保选择按显示器保存，不能仅设置主屏。
3. 横屏按钮选择仓库 `LocalPhotos/H`，竖屏按钮选择 `LocalPhotos/V`，保存。仅用生成的 PNG；路径和书签不写入日志。
4. 分别核对设置缩略预览、设置中主动启动的全屏预览、关闭设置后直接启动系统引擎，以及自动闲置触发；各入口分开记录，不能只凭直接启动引擎覆盖其他入口。缩略预览应保持静态；全屏路径继续检查下述双屏画面。关闭设置，使用系统屏保入口实际启动。检查横屏蓝 H、竖屏橙 V、白色边缘标记以及白块往返移动/明暗变化。停止、再次启动，无需重选目录。
5. 完成至少 10 次真实双屏启停；每次记录画面和资源，不以单元测试次数充数。若自动锁屏，用户自己解锁。
6. 保存代码及恢复提示后，用户执行系统重启；再次启动验证书签与设置。不得以重启宿主代替系统重启。
7. 测试完成分别恢复两块显示器的原屏保选择，除非用户明确要求保留本项目。

## 日志

```sh
/usr/bin/log show --last 15m --style compact \
  --predicate 'subsystem == "com.lusheng.MultiscreenSaver"' > Private/host.log
```

日志含随机实例标签、PID、build、原始 preview 标志、视口、screen 尺寸与 backing scale、动画数/native timer、markerActive、帧回调/绘制次数状态、解码任务/作用域计数。不写文件路径、书签或图片内容。主线程停止会取消 ticket；已经进入 ImageIO 的单次解码不能强制中断，结束后释放作用域并丢弃过期结果，需观察回落。

公开记录只填写脱敏摘要。视觉结果必须来自限定合成内容的观察或用户明确反馈，不能用 `presented` 日志推断显示成功。

详见 [G1 记录](validation/g1.md)。
