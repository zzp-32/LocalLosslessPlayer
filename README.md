# LocalLosslessPlayer 首版测试

这是截图需求的第一版可运行骨架，目标部署版本为 iOS 16。首版已包含：

- SwiftUI 音乐库列表
- 文件导入、多选、复制到 App 音乐目录
- Core Data 本地歌曲记录
- AVAudioEngine 播放、暂停、上一首、下一首、进度拖动
- 后台音频会话与锁屏/控制中心播放控制

## Windows 开发目录

项目和测试媒体目录位于：`E:\CodexProjects\LocalLosslessPlayer`。
工作区的 `work\LocalLosslessPlayer` 是指向该目录的 Junction，不会在 C 盘生成第二份工程。

## Mac/Xcode 首次运行

1. 将 `LocalLosslessPlayer` 目录复制到 Mac，或通过 Git/网盘同步。
2. 直接打开 `LocalLosslessPlayer.xcodeproj`。`project.yml` 仅作为可选的 XcodeGen 配置保留。
3. 在 Signing & Capabilities 设置开发团队。后台音频配置已写入工程。
4. 运行到 iPhone X 或更新设备。点右上角加号导入 FLAC、ALAC、WAV、AIFF、M4A 等音频。

## 本地路径说明

iOS 不允许 App 直接写入 E 盘。正式运行时媒体文件与 `Library.sqlite` 会写入沙盒的 `Library/Application Support/LocalLosslessPlayer`。Windows 端的 `E:\CodexProjects\LocalLosslessPlayer\TestMedia` 仅用于准备测试样本；调试时可通过 `LOCAL_PLAYER_DATA_ROOT` 环境变量覆盖整个数据根目录。

## 首轮验收清单

- 导入单个和多个音频，重启后歌曲仍存在
- 播放/暂停、上一首/下一首、拖动进度
- 锁屏后继续播放，控制中心暂停/恢复
- 导入同名文件不会覆盖已有文件
- 无法读取的文件不会导致应用崩溃

可在 Windows 上先生成一个 3 秒测试音：
`powershell -ExecutionPolicy Bypass -File scripts/Create-TestTone.ps1`

Windows 上无法运行 Xcode/iOS 模拟器，因此本环境只做源码结构检查；音频编解码、锁屏控制和真机权限必须在 macOS 上验证。

## TrollStore IPA

不能将源码或 Xcode 工程直接改名为 IPA。IPA 必须先通过 macOS 上的 Xcode/iOS SDK 编译出 arm64 App，再封装为 `Payload/LocalLosslessPlayer.app`。

本项目已提供两种无开发者证书的构建方式：

1. GitHub Actions：将整个项目推送到 GitHub 仓库，打开 Actions，运行 `Build TrollStore IPA`，完成后下载 `LocalLosslessPlayer-TrollStore` artifact。
2. Mac：在项目根目录运行 `bash scripts/build-trollstore-ipa.sh`。

得到 `LocalLosslessPlayer-TrollStore.ipa` 后传到 iPhone X，在 TrollStore 中点加号并选择该文件安装。该 IPA 是为 TrollStore 准备的无签名 arm64 包，最低系统版本为 iOS 16.0。
