# 安卓真机无线调试指南

适用于 macOS 主机与 Android 真机处于同一局域网的场景. 本项目的 Android 端是"被控文件服务器", 调试时通常还需要在手机上启动 File server 才能被 Mac 端访问.

## 1. 开启无线调试

1. 设置 → 关于手机 → 连续点击"版本号" 7 次, 打开"开发者选项".
2. 开发者选项 → 打开"无线调试".
3. 保持手机与电脑在同一 Wi-Fi 下, 并保持屏幕解锁.

在"无线调试"页面点击"使用配对码配对设备", 会显示:

- 配对地址: `192.168.x.x:xxxxx` (配对端口)
- 6 位配对码

注意: 配对端口与稍后 `adb connect` 使用的调试端口不是同一个.

## 2. 电脑与手机配对

先确认 `adb` 可用:

```bash
adb version
```

如果提示找不到命令, 把 Android SDK 的 `platform-tools` 加入 `PATH`, 例如:

```bash
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
```

然后配对并连接:

```bash
# 1. 配对 (输入手机上显示的 6 位码)
adb pair 192.168.x.x:<配对端口>

# 2. 连接 (使用"无线调试"页面顶部的 IP:端口, 不是配对端口)
adb connect 192.168.x.x:<调试端口>

# 3. 确认设备在线
adb devices
```

输出中出现 `192.168.x.x:xxxxx   device` 即连接成功. 首次连接时手机上会弹出"允许 USB 调试吗", 选择允许即可.

常见问题:

- 显示 `unauthorized`: 在开发者选项中"撤销 USB 调试授权", 重新配对.
- 显示 `offline`: `adb disconnect 192.168.x.x:<端口>` 后重新 `adb connect`.
- 手机重启, 切换 Wi-Fi 或关闭再打开无线调试后, 端口会变化, 需要重新 `adb connect`.

## 3. 用 Flutter 安装并调试

```bash
flutter devices
```

应能看到类似:

```text
PHB110 (mobile) • 192.168.x.x:xxxxx • android-arm64 • Android 16
```

直接运行 (构建 debug 包, 安装并附加调试器):

```bash
flutter run -d 192.168.x.x:xxxxx
```

运行期间的常用按键:

- `r`: 热重载 (保留应用状态)
- `R`: 热重启 (重置应用状态)
- `q`: 退出并结束调试会话

如果只想安装 APK:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
flutter attach -d 192.168.x.x:xxxxx
```

`flutter run` 启动后会输出 VM Service 地址, 形如 `http://127.0.0.1:62950/xxxxx=/`. 后续 MCP 工具都依赖这个调试会话, 所以调试期间不要关闭 `flutter run`.

## 4. AI 通过 MCP 控制真机

### 4.1 mcp_dart: 开发期控制

mcp_dart 通过 Dart Tooling Daemon (DTD) 连接正在运行的 Flutter 应用, 需要应用处于 debug 模式且 `flutter run` 会话存活.

典型流程:

1. `dtd listDtdUris`: 找到 Workspace Root 指向本项目的 DTD 实例.
2. `dtd connect <ws URI>`: 连接后自动挂上该实例下的所有应用.
3. `dtd listConnectedApps`: 确认能看到 `Device: PHB110` 及其 VM Service 地址.
4. 之后可以调用:
   - `hot_restart` / `hot_reload`
   - `get_runtime_errors`: 读取运行时报错与堆栈
   - `analyze_files` / `lsp`: 静态检查与跳转
   - `widget_inspector` / `vm_service`: 检查控件树与运行时状态

注意: 热重启会重置应用状态. 对本项目而言, 手机端的 File server 会停止, 需要重新点击 `Run file server`, 否则 Mac 端 check 会连接失败.

### 4.2 mcp_marionette: 运行时 UI 操作

Marionette 只负责与运行中的 UI 交互: 读取控件, 点击, 输入, 滚动, 截图.

前置条件:

- `pubspec.yaml` 已包含 `marionette_flutter`.
- `main.dart` 在 debug 模式下初始化 `MarionetteBinding` (本项目已配置).
- 应用由 `flutter run` 以 debug 模式启动.

连接步骤:

```text
marionette_connect(uri: "ws://127.0.0.1:<VM Service 端口>/<token>/ws")
```

物理设备上的 VM Service 会被 `flutter run` 转发到本机 `127.0.0.1`, 端口以运行输出为准.

连接后可用:

- `get_interactive_elements`: 列出当前可交互控件 (含 `ValueKey`)
- `tap` / `double_tap` / `long_press` / `swipe` / `scroll_to`
- `enter_text` / `press_back_button`
- `take_screenshots`: 截图, 默认内联返回 PNG
- `get_logs`: 读取应用日志
- `hot_reload`: 保留状态的代码热更新

使用建议:

- 给需要被 AI 操作的控件加 `ValueKey`, 例如本项目已有的 `server.run`, `sync.check`, `sync.run`.
- Android 端使用 Material 3, Marionette 可以直接识别标准控件; 桌面端的 Forui 自定义控件需要额外配置才能被 Marionette 识别.
- Marionette 连接依赖 VM Service, 应用热重启或进程退出后连接会失效, 需要重新连接.
- 若开启了 session reports, 交互日志与截图会保存在项目下的 `.marionette/sessions/` 目录.

## 5. 一次完整调试的最短路径

```bash
# 手机: 开启无线调试, 取得配对地址与配对码
adb pair 192.168.x.x:<配对端口>
adb connect 192.168.x.x:<调试端口>
flutter run -d 192.168.x.x:<调试端口>
```

然后在 AI 侧:

1. 用 mcp_dart 连接 DTD 并做代码热重载或读取运行错误.
2. 用 mcp_marionette 连接同一 VM Service, 读取控件树, 点击"Run file server", 再让 Mac 端执行 check.
