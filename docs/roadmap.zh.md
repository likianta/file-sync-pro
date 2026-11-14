# Flutter 版开发计划 (初版)

> 状态: 草案 v0.2 · 2026-11-14
> 目标: 用 Flutter 重写 file-sync-pro, 解决旧 Python 版的问题 (见 [旧实现分析](./summary-analysis-of-frozen-python-implementation.zh.md)), 当前优先跑通 macOS ↔ 远端 Windows (经公网 frp 隧道) 的同步.

## 1. 产品目标与范围

**核心能力**

1. 局域网设备发现与文件互访 (浏览, 下载, 上传).
2. 两台设备之间指定目录的**双向增量同步**, 支持预演 (dry run).
3. 明确的冲突处理: 不静默覆盖, 冲突可回看, 可选择.
4. 可靠的基线语义: 中断可恢复, 不产生 "假装已同步" 或 "永远追不平" 的状态.

**平台优先级**

| 平台 | 优先级 | 说明 |
|---|---|---|
| macOS | P0 | 主力开发与客户端平台 |
| Windows | P0 | 当前作为远端服务端 (办公室), 通过公网 frp 暴露 |
| Android | P2 (暂缓) | 原本的首个场景, 现在排到 macOS ↔ Windows 之后 |
| iOS | P3 (未来) | 保留工程骨架, 暂不投入 |

**当前真实场景**

- 本机目录: `~/Desktop/work/likianta-projects/photolens`
- 远端目录: `http://47.102.108.149:2160/photolens` (frp) → Windows `C:/Likianta/workspace/dev.master.likianta/photolens`
- 排除: `/.git/`, `/.idea/`, `/.venv/`, `.DS_Store`, `__pycache__/`
- Windows 端运行 `dart run tool/run_file_server.dart`; macOS 端运行 `dart run tool/sync_cli.dart`.

**本期不做**

- 自建公网中转或云盘 (当前依赖用户已有的 frp 隧道).
- 多人共享与权限体系.
- iOS 真机发布.
- 文件版本历史 (先只保留冲突副本).

## 2. 里程碑总览

| 阶段 | 主题 | 主要交付 | 验收标准 |
|---|---|---|---|
| M0 | 工程基座 | Flutter 工程, 目录规范, 主题, 日志, CI 脚本 | macOS 可运行, `flutter analyze` 0 issue |
| M1 | 同步内核 (纯 Dart) | 清单模型, 扫描器, diff/plan, apply, 冲突与日志 | 单元测试覆盖决策矩阵; 本机目录可互相同步 |
| M2 | 传输层 | HTTP 文件服务端 (Windows), 远端 manifest, 流式上传下载 | macOS 与远端 Windows 可互传文件 |
| M3 | 同步 MVP | macOS ↔ 远端 Windows (photolens) 端到端同步 + CLI + UI | 真实目录完成双向同步, 中断可恢复 |
| M4 | Android 适配 (暂缓) | 存储权限, 前台服务, 通知, APK | 顺延到 macOS ↔ Windows 稳定后 |
| M5 | Windows 客户端 | 路径/编码/锁文件处理, Windows 桌面构建 | 视需要把服务端升级为完整客户端 |
| M6 | 打磨 | 大目录性能, 错误恢复, 设置项, 可观测性 | 1 万文件级目录可用, 常见故障可自愈 |
| M7 | iOS (可选) | 工程配置与基础联调 | 视需求启动 |

## 3. 阶段任务

### M0 工程基座

- [x] `flutter create` 初始化 (macos / windows / android / ios), 包名 `com.likianta.file_sync_pro`.
- [x] 目录规范与分层 (见 §4), 空壳页面 + 主题.
- [ ] 基础依赖: 状态管理, 路由, 日志, 本地存储, 网络 (选型见 §5).
- [ ] 主题与设计 token (颜色/间距/圆角/字体), 深色模式.
- [ ] 应用数据目录约定 (配置, 快照, 日志, 冲突副本).
- [ ] 开发脚本: `dart format`, `flutter analyze`, 测试命令写入 AGENTS.md 或 README.
- [ ] macOS: 窗口最小尺寸, 标题, 沙盒 entitlements (网络客户端/服务端, 用户选择文件读写).

**验收**: `flutter run -d macos` 启动空壳应用; `flutter analyze` 无问题.

### M1 同步内核 (纯 Dart, 无 UI/网络)

优先级最高, 因为它决定正确性.

- [x] 清单模型:
  - `ManifestEntry { kind(file/dir), mtime, size, hash? }`
  - `Manifest { root, scannedAt, entries }`
  - `SyncState { base }`, 按同步对持久化为 JSON (版本号 + 迁移策略); 不再为两侧各存一份 base, 避免基线分裂.
- [x] 扫描器: 递归枚举, 忽略规则 (gitignore 语义: glob, `!` 取反, 目录尾 `/`), 可选哈希 (大小/mtime 快速路径).
- [x] diff/plan 引擎: 纯函数 `plan(base, a, b) -> List<Action>`.
  - 动作: create / update / delete / conflict (重命名先按 "删除 + 新增" 处理, move 优化放到 M6).
  - 双方都改时: 哈希相同 → 无需动作; 哈希不同 → 冲突, 不自动覆盖.
  - 支持 "mtime 变旧也算变更" (与旧版的关键差异).
- [x] apply 引擎:
  - 先写临时文件再原子 rename; 写后校验大小.
  - 保留 mtime; 目录创建/空目录清理.
  - 操作日志 (journal): 当前记录动作与错误, 自动恢复待后续实现.
  - 冲突副本按相对路径保存, 不覆盖同名.
- [x] 单元测试: 决策矩阵表驱动 (47 个用例).
- [x] 本地目录 A ↔ B 的端到端测试 (无需网络).

**验收**: 30+ 场景已覆盖 (新增/修改/删除/重命名/双方修改/仅改 mtime/空目录/忽略规则/冲突/中断暂未覆盖), 全部通过.

### M2 传输层 (macOS ↔ 远端 Windows)

目标: macOS 通过 HTTP 访问 Windows 上的挂载目录, 不要求 Windows 端同时是 Flutter 应用.

- [x] 协议: HTTP JSON + 二进制流; 路由 `/<mount>/{manifest,file,dir,stat}`; 可选 token.
- [x] Windows 服务端: `FileServer` + `tool/run_file_server.dart`; 默认挂载 `../photolens`; 支持 `tool/file_server.config.json`.
- [x] macOS 客户端: `HttpTransport` / `HttpFileStore` / `RemoteScanner`; 接入 `SyncSource` 抽象.
- [x] 服务端 manifest 带 sha256, 并用内存缓存避免重复哈希; 上传/删除时失效缓存.
- [x] 安全: 默认绑定 `127.0.0.1` 供 frp 转发; token 校验; 拒绝路径穿越与软链接.
- [x] 集成测试: 本机起服务端, 覆盖上行/下行/删除/冲突/空目录/忽略/401/路径穿越.
- [x] 服务端支持 `Range` 下载 (客户端断点续传待接).
- [ ] 客户端并发传输与失败重试.
- [ ] UI: 远端目录浏览, 传输进度.
- [x] 本机 ↔ 本机同步测试 (降级为辅助): `test/local_sync_test/alice` 与 `bob`; 已加入 `.gitignore`, 仅用于本地调试/验证想法.

**验收**: 真实 macOS 与办公室 Windows 通过 frp 完成双向同步; 错误 token 无法访问; 路径穿越被拒绝.

### M3 同步 MVP (macOS ↔ 远端 Windows)

当前真实目录: 本机 `~/Desktop/work/likianta-projects/photolens` ↔ `http://47.102.108.149:2160/photolens`.

- [x] 同步对默认配置: `localRoot` / `remoteUrl` / `token` / `stateDir` / ignores.
- [x] 流程: 扫描双方 → 拉取远端清单 → 生成计划 → dry run → 执行 → 提交新基线.
- [x] CLI: `tool/sync_cli.dart`, 支持 `--dry-run` / `--token` / `--timeout` / 配置文件.
- [x] 桌面 UI 第一版: 同步对信息, Check/Sync, 变更分组列表, 执行进度, Activity 日志, 错误提示.
- [x] 首次真实同步: 2026-11-14 通过 frp 从 Windows 拉取 45 个文件到本机, 二次同步 no-op.
- [ ] 冲突 UI: 列出冲突项, 提供 "保留本机 / 保留远端 / 两者都留" 选择.
- [ ] 中断恢复: 基于 journal 的恢复流程与部分完成提示.
- [ ] 真实公网链路强化验证: 大文件, 慢速网络, 断线重连.

**验收**: photolens 在 macOS 与 Windows 之间完成新建/修改/删除/冲突/断网恢复; 默认忽略规则生效.

### M4 Android 适配与打包 (暂缓)

macOS ↔ Windows 稳定后再启动.

- [ ] 存储访问方案 (见 §6): SAF 目录授权, 或 "所有文件访问" 权限 (个人使用优先).
- [ ] 前台服务 + 常驻通知, 保证同步/扫描不被杀; 仅 Wi-Fi 选项.
- [ ] 电池优化白名单引导; 网络变化监听.
- [ ] Android 13+ 通知权限; 局域网权限 (如系统要求).
- [ ] APK 构建: `flutter build apk --split-per-abi`; release 签名 keystore.
- [ ] 真机验证: 后台 30 分钟, 锁屏, 切换网络后的恢复.

**验收**: 手机端连续运行稳定; APK 可安装, 可升级; 与 macOS 同步无回归.

### M5 Windows 客户端 (后续)

Windows 服务端已在 M2 完成; 本节指把 Windows 也做成完整 Flutter 客户端.

- [ ] 路径: 长路径, 保留名 (`CON`, `NUL`...), 大小写不敏感, 盘符与 UNC.
- [ ] 文件锁/占用文件的处理与重试.
- [ ] 构建与打包 (MSIX 或 zip + 安装脚本).
- [ ] 在 Windows 机器上完成构建, 与 macOS/Android 互通验证.

**验收**: Windows ↔ macOS ↔ Android 三方互通, 无平台相关崩溃.

### M6 打磨与性能

- [ ] 增量扫描: 目录 mtime 缓存, 平台文件监听 (FSEvents/inotify) 预研.
- [ ] 大目录: 1 万 / 10 万文件基准, 清单压缩, 分页拉取.
- [ ] 可观测性: 结构化日志, 同步报告 (耗时/字节/失败项), 导出诊断包.
- [ ] 设置: 并发数, 忽略规则编辑, 带宽限制 (可选).
- [ ] 自动更新策略 (桌面端后续).

### M7 iOS (可选)

- [ ] Xcode 签名, 文件访问 (UIDocumentPicker), 后台限制评估.
- [ ] 复用 M1–M3, 仅做平台适配.

## 4. 架构草案

```
lib/
├── main.dart
├── app/                 # App 壳: 路由、主题、本地化、启动流程
├── core/                # 通用能力: 结果类型、日志、错误、平台信息、路径
├── data/                # 本地持久化: 配置、快照、日志、冲突副本
├── features/
│   ├── devices/         # 设备发现、配对、设备列表
│   ├── browser/         # 远端文件浏览与传输
│   └── sync/            # 同步对、计划、执行、冲突
│       ├── domain/      # 纯 Dart: Manifest / Scanner / Planner / Applier
│       ├── application/ # 用例编排、状态机
│       └── presentation/# 页面与组件
└── transport/           # 协议、发现、HTTP/WS 客户端与服务端
```

原则:

- `features/sync/domain` 保持**纯函数, 无 IO**, 便于测试;
- 平台差异收敛在 `core/platform` 与各 feature 的 `data` 层;
- UI 不直接做 IO, 通过 application 层用例驱动.

## 5. 关键技术决策 (默认方案, 可调整)

| 决策点 | 默认方案 | 理由 |
|---|---|---|
| 状态管理 | Riverpod | 可测试, 依赖注入方便, 社区成熟 |
| 路由 | go_router | 桌面多窗口/深链后续可扩展 |
| 清单变更判定 | size + sha256 为主; mtime 仅作快速路径与回退 | 修掉旧版 "mtime 单一判据" 的根因 |
| 哈希算法 | sha256 (MVP) → 可换 xxh3/blake3 | 先正确后提速 |
| 传输 | HTTP/1.1 + 流式 body; 服务端支持 Range 下载 | 简单, 可调试, 可跨公网隧道 |
| 发现 | 手动 URL (公网 frp); 局域网 mDNS 后续再加 | 当前场景不需要自动发现 |
| 认证 | 共享 token (`X-File-Sync-Token`) | frp 暴露到公网时必需 |
| 本地存储 | JSON 快照 + 轻量设置存储 | 可读, 易迁移; 大数据量再换 sqlite |
| 并发 | 当前串行; 后续 2–4 并发传输 | 先保证正确性 |

> 以上为当前实现基线; 变更选型时需同步更新本文档.

## 6. 平台要点

**macOS**

- 开发期关闭 App Sandbox 或配置 `com.apple.security.network.client/server` 与用户选择文件读写; 上架 App Store 需重新评估.
- 监听端口需允许入站连接 (防火墙提示).

**Windows**

- 当前作为远端服务端: `dart run tool/run_file_server.dart` (纯 Dart, 不需要 Flutter).
- 默认监听 `127.0.0.1:2160`, 由用户自己的 frp 隧道暴露到公网; 仅暴露必要端口.
- 配置由 `tool/file_server.config.json` 提供, 需与 macOS 端使用同一个 token.
- 后续再做 Windows Flutter 客户端时, 只需复用现有同步内核.

**Android**

- 暂缓. 恢复时仍按原计划评估 SAF 与前台服务.

**iOS**

- 文件系统沙盒严格, 只能同步应用容器或用户选择的目录; 后台调度受限.

## 7. 测试策略

1. **单元测试**: Planner 决策矩阵, 忽略规则, 路径规范化, 清单序列化.
2. **属性测试**: 随机生成文件树与操作序列, 验证 `apply(plan(...))` 的不变量.
3. **集成测试**: 本机启动 HTTP 服务端 + 临时目录, 覆盖上行/下行/删除/冲突/空目录/忽略/鉴权/路径穿越.
4. **端到端手测清单**: macOS ↔ 远端 Windows (经 frp) 的真实目录场景表.
5. **性能基准**: 1k / 10k / 100k 文件的扫描, diff, 传输耗时.
6. `test/local_sync_test/alice|bob` 仅作为辅助调试夹具, 不纳入常规测试路径.

## 8. 当前环境与待办

- Flutter 3.47.9 / Dart 3.13.7, Xcode 27.2, CocoaPods 1.17.0 - 就绪.
- Android SDK 未安装; Android 阶段暂缓, 暂不阻塞当前工作.
- iOS Simulator runtime 未安装 (当前不影响).
- Chrome 未安装 (暂无 Web 计划, 不影响).

## 9. 风险清单

| 风险 | 影响 | 应对 |
|---|---|---|
| frp 隧道不稳定/带宽低 | 长同步中断 | 断点续传 + 失败重试 + 日志恢复 |
| 公网暴露 | 未授权访问 | 强制 token; 服务端只监听 127.0.0.1; 不做任意代码执行 |
| 远端首次哈希耗时 | 第一次清单慢 | 服务端哈希缓存; 后续只重算变更文件 |
| Windows 路径/大小写差异 | 重名冲突 | 以服务端返回的真实路径为准; 后续补大小写检测 |
| 大目录性能 | 体验差 | 增量扫描与清单分页, M6 专项 |

## 10. 下一步

1. 在 Windows 上创建 `tool/file_server.config.json`, 填入与 macOS 相同的 token, 重启服务 (当前公网实例未启用 token).
2. 冲突解决 UI: 逐项选择保留本机/远端/两者.
3. Range 断点续传与失败重试; 补大文件与弱网测试.
4. macOS 窗口标题/最小尺寸与打包配置.

---

相关文档: [旧 Python 实现分析](./summary-analysis-of-frozen-python-implementation.zh.md)
