# Landroid · Android 17 星际飞行

把 Android 17（Cinnamon Bun）彩蛋里的「兰卓伊德宇宙」搬到 macOS：一颗恒星 + 若干行星按开普勒定律公转，一艘飞船在真实引力场里飞。

- **Auto 模式常开**：飞船自己挑最近的未探索行星 → 加速追 → 减速接近 → 着陆 → 观光 15 秒 → 起飞 → 换下一颗
- **动态变焦**：镜头按到最近天体的距离自动推拉，像电影运镜
- **座舱 UI**：左上星际档案（恒星编号/光谱等级/已探明天体 + 每颗行星的类型大气动植物），左下遥测（自动驾驶目标/动作 + ALT/THR/POS/VEL，着陆时变 LND/JOB），带 CRT 闪烁淡入

物理积分、自动驾驶策略、渲染参数均按原版 Kotlin 1:1 搬运，行星命名沿用 AOSP 原词表。

---

## 三种形态

| 形态 | 效果 | 依赖 |
|---|---|---|
| **锁屏动画** | 锁屏即播放，3 分钟循环 | 视频壁纸通道，需要 macOS 26 |
| **屏保** | 闲置后启动，真·实时物理，永不重复 | 标准 `.saver` |
| **全屏预览** | 双击立刻跑，任意键退出 | 独立 App，可加登录项自启 |

锁屏要「立刻动」只能用视频（系统锁屏不接受实时进程）；要「永不重复」只能走屏保（代价是锁屏后要等闲置时间）。这是 macOS 的硬限制，不是实现取舍。

---

## 安装

### 前提

- macOS 26 (Tahoe) 或更新，Apple Silicon
- **只有从源码构建才需要** Xcode Command Line Tools（`xcode-select --install`）；直接用 Release 里预编译的 `.saver` 不需要

### 方式 A：锁屏动画（推荐）

```bash
git clone git@github.com:DerekHemcis/android-eggs-mac.git
cd android-eggs-mac/eggs/landroid
```

然后依次双击（或在终端执行）：

1. `scripts/install.command` —— 把 `.saver` 装到 `~/Library/Screen Savers/`
2. `scripts/应用锁屏动画.command` —— 生成/发布视频资产，并把它挂到锁屏的 `Idle` 层

锁一次屏就能看到。若仍是旧画面，解锁再锁一次（系统第一次会重建该资产缓存）。

### 方式 B：屏保（实时模拟）

1. 双击 `scripts/install.command`
2. 双击 `scripts/设为屏保·实时模拟.command`
3. 缩短闲置触发时间（可选）：

```bash
defaults -currentHost write com.apple.screensaver idleTime -int 60
```

### 方式 C：全屏预览

```bash
./build.sh                      # 产出 dist/LandroidPreview
./dist/LandroidPreview          # 全屏跑，任意键退出
```

想开机自启：系统设置 → 通用 → 登录项 → 添加该可执行文件。

### 其它一键脚本

| 脚本 | 作用 |
|---|---|
| `scripts/设为锁屏动画·视频版.command` | 锁屏 = 视频版 |
| `scripts/设为屏保·实时模拟.command` | 锁屏/闲置 = 实时模拟屏保 |
| `scripts/还原系统默认锁屏.command` | 换回 macOS 自带 |
| `scripts/应用锁屏动画.command` | 重新发布视频资产（清单被系统刷新时用） |

### 卸载

```bash
rm -rf ~/Library/Screen\ Savers/Landroid.saver
../landroid/scripts/还原系统默认锁屏.command
```

---

## 从源码构建

```bash
./build.sh          # → dist/Landroid.saver（+ dist/LandroidPreview）
./build-video.sh    # → dist/Landroid 锁屏.mov（180s / 2560×1440 / 30fps / HEVC，约 30 秒）
./package.sh        # → dist/Landroid-macOS.zip
```

`build.sh` 用 `swiftc` 直接产出 `.saver` bundle 并 ad-hoc 签名，不需要 Xcode 工程。

---

## 工作原理

### 代码结构

| 文件 | 职责 |
|---|---|
| `src/LandroidSaver.swift` | 全部实现：Vec2/物理积分、行星与恒星、飞船、自动驾驶、渲染、座舱 UI、`ScreenSaverView` 子类 |
| `src/wordlists.swift` | 由 AOSP 字符串资源导出的命名词表（星座/后缀/行星描述/活动） |
| `tools/render-video.swift` | 离屏渲染 180 秒视频（AVAssetWriter + HEVC） |
| `tools/fullscreen-runner.swift` | 独立全屏运行器 |

### 关键点：macOS 26 的锁屏壁画不是「屏保」

macOS 26 把锁屏/桌面统一进 wallpaper store，`Index.plist` 里分两个 scope：

```
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist
  AllSpacesAndDisplays:
    Desktop ← 桌面壁纸
    Idle    ← 锁屏 / 闲置时显示的内容
```

`Idle` 的 `Provider` 决定由哪个扩展渲染：

| Provider | 用途 |
|---|---|
| `com.apple.wallpaper.choice.macintosh` | 系统默认壁纸 |
| `com.apple.wallpaper.choice.screen-saver` | 加载第三方 `.saver`（屏保） |
| `com.apple.wallpaper.choice.aerials` | 动态视频壁纸（锁屏即动） |

所以：

- **锁屏要立刻动** → 写 `Idle` = `aerials` + `{'assetID': <uuid>}`
- **要用实时模拟** → 写 `Idle` = `screen-saver` + `{'module': {'relative': 'file:///…/Landroid.saver'}}`

自定义视频资产的注册分三步（`scripts/apply-lock.py` 自动完成）：

1. 视频放进 `~/Library/Application Support/com.apple.wallpaper/aerials/videos/<uuid>.mov`
2. 在 `…/aerials/manifest/entries.json` 的 `assets` 里加一条同 uuid 的条目
3. 同步写进 `…/aerials/manifest.tar`（系统重新解包清单时不会丢）

改完 `killall WallpaperAgent` 让系统重读。

> 每次 `apply-lock.py` 都会生成**新的 uuid**，避免旧资产被缓存住。

---

## 已知限制

- 系统偶尔会重新下载动态壁纸清单，把自定义条目冲掉。冲掉了就重跑 `scripts/应用锁屏动画.command`。
- 锁屏视频是录制好的 180 秒循环，不是实时模拟；每轮开头有 1~3 秒 CRT 闪烁淡入（照原版行为）。
- `.saver` 走实时模拟时，闲置多久启动由系统「屏幕保护程序」设置决定。

---

## 许可

代码源自 AOSP Landroid 彩蛋（Apache-2.0），经 [hushenghao/AndroidEasterEggs](https://github.com/hushenghao/AndroidEasterEggs)（`eggs/CinnamonBun`）移植而来。详见 `LICENSE` 与 `NOTICE`。
