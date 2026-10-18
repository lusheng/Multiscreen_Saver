# 构建与开发检查

目标：macOS 27 / Apple Silicon，使用已安装 Xcode，无产品第三方依赖。

```sh
./scripts/build.sh             # Release；可用 CONFIGURATION=Debug 切换
./scripts/test-core.sh
./scripts/test-lifecycle.sh
```

格式检查使用测试环境中已有的 Pillow（支持 WebP），不要求产品运行机安装 Python：

```sh
python3 scripts/generate-format-fixtures.py
./scripts/test-decode.sh
python3 scripts/generate-playback-fixtures.py
xcrun swift scripts/generate-playback-heic.swift
```

仅生成 LocalPhotos 下原创合成图片，不扫描个人图库。test-decode 会生成 HEIC 合成样本和专用 SessionFixture 子目录。普通进程检查不能替代真实屏保宿主验收。

安装前保存原屏保选择；`./scripts/install-local.sh` 只更新本项目用户级 saver，并备份旧版本到 Private。产物在 `build/MultiscreenSaver.saver`。系统设置→墙纸→屏幕保护程序，对每块屏幕选择本项目；“选项…”分别指定 H/V 文件夹并保存。新版本尚待实机验证，当前不提供二进制 Release。

完整设置默认间隔 5 秒、过渡 1.5 秒、上限 1.20、随机开、递归关。非法值不能保存，取消不生效；旧 G1 书签作为首次迁移来源保留，新设置写入带版本的 SettingsV1。空库/失效目录显示中性提示，坏图会话内隔离，加载慢时保持当前画面。

卸载前逐屏恢复原来的照片 / Ken Burns，再通过 Finder 将用户 Library/Screen Savers 中的 MultiscreenSaver.saver 移到废纸篓。旧 bundle 可从本项目 Private 备份恢复。不要导入整个系统墙纸配置，不更改锁屏策略或个人图库来源。
