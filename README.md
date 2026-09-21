# TouchGuard

打字时自动屏蔽触控板，防止手掌误触导致光标乱跳、误点击。macOS 菜单栏常驻小工具。

## 原理

用 `CGEventTap` 在系统事件流的最前端插入一个过滤器：

- 监听 `keyDown`，记录最后一次「真正打字」的时间（按住 ⌘/⌃ 的快捷键不算打字）。
- 在这之后的一段时间内（默认 500 毫秒），丢弃触控板的点击、指针移动和两指滚动事件。
- 被吞掉 mouse-down 的按键，其后续 drag 和 mouse-up 也一并吞掉，避免应用里出现「按下了却没松开」的悬挂状态。
- 事件里带有修饰键（⌘⌥⌃⇧）时默认放行，⌘-click 之类的操作不受影响。

外接鼠标的识别是启发式的：滚轮事件按「是否像素级连续滚动」区分，指针事件看 `mouseEventSubtype`。
默认策略是「识别不出来就照样拦截」，保证功能不会静默失效。若你外接鼠标且希望鼠标完全不受影响，
先用诊断模式确认能识别出来，再打开菜单里的「只拦截触控板（严格）」。

## 下载

[Releases](https://github.com/cod7ce/TouchGuard/releases) 里有编译好的 `TouchGuard-0.2.1.zip`（universal，arm64 + x86_64）。
解压后拖进「应用程序」即可。它用开发者证书签名但未经 Apple 公证，别人下载后首次打开会被 Gatekeeper 拦下，
右键点图标选「打开」，或到「系统设置 › 隐私与安全性」页面底部点「仍要打开」。自己编译则没有这个问题。

## 自动更新

装好之后不用再回来看这个页面。菜单里有「检查更新…」和「自动检查更新」开关，
开着的话每天查一次 GitHub Releases，有新版本才会弹窗，没有就一声不吭。
确认更新后它会下载、就地替换自己，然后重启。

下载回来的包必须满足当前这份 app 的 designated requirement 才会被安装，
也就是说新版本得由同一张证书签名，否则直接拒绝。这条校验顺带保住了辅助功能授权 ——
macOS 的授权认的是签名而不是文件，签名不变，更新后不用重新授权。

如果当前这份 app 是临时（ad-hoc）签名的，自动更新会主动拒绝：ad-hoc 签名的
designated requirement 锁死了二进制哈希，任何新版本都不可能匹配，只能手动更新。

## 构建

```
./build.sh                      # 产物在 build/TouchGuard.app
./Scripts/release.sh            # 再打出 build/TouchGuard-<版本>.zip 并自检签名
swift Scripts/make-icon.swift   # 重新生成 Resources/AppIcon.icns
```

用本机的 Apple Development 证书签名。签名保持稳定，辅助功能授权才不会每次重新编译后失效。

发布包必须用 `ditto` 打，不能用 `zip` —— 后者会在 bundle 里塞进 `._` 伴生文件、
破坏签名结构，让自动更新在用户机器上校验失败。`Scripts/release.sh` 会解压回来重新验一遍签名。

## 首次运行

1. `open build/TouchGuard.app`
2. 弹出授权提示后，在「系统设置 › 隐私与安全性 › 辅助功能」里勾选 TouchGuard。
3. 授权后无需重启，菜单栏图标会从警告三角变成手掌图标。

菜单里可调：启用/暂停、停用时长（200–1000 毫秒）、拦截内容（点击/移动/滚动）、开机自启、自动检查更新。

## 诊断

```
./build/TouchGuard.app/Contents/MacOS/TouchGuard --diagnose
```

打印每个指针事件的来源判定，用触控板和外接鼠标各点几下，即可确认识别是否准确。
（终端需要有辅助功能权限。）
