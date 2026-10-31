# android-eggs-mac

把 Android 各个版本的彩蛋搬到 macOS——做成**锁屏动画**或**屏保**，保留原版的手感。

每个彩蛋都是独立的 Swift 重写（不跑安卓模拟器、不嵌 web），物理/动画参数按 AOSP 原版 1:1 搬运。

## 已有彩蛋

| 彩蛋 | Android 版本 | 形态 | 说明 |
|---|---|---|---|
| [Landroid](eggs/landroid/) | 17 (Cinnamon Bun) | 锁屏动画 / 屏保 / 全屏 App | 星际飞行模拟：恒星 + 行星开普勒公转，飞船自动驾驶探索，座舱遥测 UI |

## 直接下载成品

不想自己编译：[**下载 Landroid-macOS-v1.0.0.zip**](https://github.com/DerekHemcis/android-eggs-mac/releases/download/v1.0.0/Landroid-macOS-v1.0.0.zip)（约 76MB，含预编译 .saver 和锁屏视频）

解压后依次双击 `install.command` → `应用锁屏动画.command` 即可，无需 Xcode。

## 快速开始

```bash
git clone git@github.com:DerekHemcis/android-eggs-mac.git
cd android-eggs-mac
./build.sh                       # 构建所有彩蛋
cd eggs/landroid && open .       # 每个彩蛋目录里有独立 README 说明安装
```

安装步骤见各彩蛋目录里的 `README.md`（`eggs/landroid/README.md` 是最完整的一份，含 macOS 26 锁屏壁纸机制的说明）。

## 目录约定

```
eggs/<name>/
├── README.md          安装方法 + 该彩蛋的原理说明
├── src/               Swift 源码（.saver / 渲染逻辑）
├── tools/             辅助工具（视频渲染、全屏运行器等）
├── scripts/           一键安装 / 切换脚本（.command 可双击）
├── prebuilt/          预编译产物
├── build.sh           构建
└── build-video.sh     需要视频形态时生成（可选）
```

新增彩蛋时，复制一份结构、写好 `build.sh`，顶层 `./build.sh` 会自动带上。

## 许可

各彩蛋分别沿用其上游的许可（Landroid 源自 AOSP，Apache-2.0）。详见 `LICENSE` 与 `NOTICE`。
