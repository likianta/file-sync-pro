# 对一次真实的同步流程的逐步分析

1. 手机 (OnePlus11) 和电脑 (MacBook) 连入同一局域网
2. 手机 - 开发者模式 - 开启无线调试
3. 电脑: `adb pair 192.168.71.52:42007` -> 成功
4. 电脑: `adb connect 192.168.71.52:43189` -> 成功
5. 电脑: `flutter run -d 192.168.71.52:43189` -> 成功将 android app debug 安装在手机上并启动
6. 手机: 

    准备好两个 shared folders:

    ```yaml
    -   name: gitbook
        path: /storage/emulated/0/Likianta/documents/gitbook
    -   name: pictures
        path: /storage/emulated/0/Likianta/pictures
    ```

    点击 "Start server", 服务运行在 `192.168.71.52:2160`.

7. 电脑: `flutter run -d macos`

    配对信息:

    ```yaml
    remote_device: Likianta OnePlus 11
    remote_address: 192.168.71.52:2160
    pairs:
        android-gitbook:
            local_path: /Users/Likianta/Desktop/documents/gitbook
            remote_path: /storage/emulated/0/Likianta/documents/gitbook
        pictures:
            local_path: /Users/Likianta/Desktop/pictures
            remote_path: /storage/emulated/0/Likianta/pictures
    ```

8. 电脑: 选择配对设备 "Likianta OnePlus 11", 选择配对项 "android-gitbook"

    > ASK: 首次选中 android-gitbook 时, 两边初始化文件树, 具体是做了什么?

    简短回答: 这里并没有在磁盘上 "创建" 两棵文件树. 它做的是把本地和手机上的目录各扫描一遍, 得到两份清单 (manifest), 再据此渲染出左右两棵用于展示的树. 整个过程只读, 不会写入或移动任何被同步的文件.

    展开来说, 依次发生这些事:

    1. 建立控制器. 选中设备 "Likianta OnePlus 11" 和配对 "android-gitbook" 后, `SyncWorkspacePage._syncSelection()` 从配对配置取出 `localRoot`, `remoteUrl`, `token`, `stateDir`, `extraIgnores`, 创建一个 `SyncDashboardController`, 并在下一帧调用 `refresh()`.

    2. 准备环境. `refresh()` 先把状态切到 scanning, 清掉上一次的 diff; 确认本地根目录存在 (不存在就递归创建); 并准备本地哈希缓存 `stateDir/hash_cache.json`.

        > ASK: 这个 `stateDir/hash_cache.json` 指的是 `data/sync_pairs/android-gitbook/hash_cache.json` 文件吗? 它的数据结构长什么样?

        是的. `android-gitbook` 在 `tool/sync.config.json` 里显式配置了 `stateDir`, 值为 `/Users/Likianta/Desktop/work/likianta-projects/file-sync-pro/data/sync_pairs/android-gitbook`; 控制器再拼接 `hash_cache.json`, 所以实际路径就是 `data/sync_pairs/android-gitbook/hash_cache.json`. 每个配对各自一份, 只用于本地侧的文件哈希缓存 (远端手机侧用的是 `file_server.hash_cache.json`).

        文件结构 (`version` 当前为 2):

        ```json
        {
          "version": 2,
          "entries": {
            "/Users/Likianta/Desktop/documents/gitbook/notes/a.md": {
              "size": 1024,
              "mtime": 1763890000000,
              "hash": "原始字节的 sha256 (hex)",
              "textHash": "LF 归一化后的 sha256 (hex)"
            }
          }
        }
        ```

        - key 是扫描时看到的绝对路径.
        - `size` 和 `mtime` 用来判断缓存是否仍然有效; `hash` 是原始内容的 SHA-256; `textHash` 仅文本文件才有.
        - 写入用 "临时文件 + rename" 的原子替换; 文件损坏或 `version` 不匹配时, 整个缓存会被丢弃并在下次扫描时重建.
        
        > ASK: 如果这个 hash_cache.json 之前已经存在了, 但从上次更新到本次使用中间可能隔了较长一段时间, 两边的 gitbook 文件树是否变动未知, 它会重新递归扫描所有文件并计算它们的哈希吗?

        会重新递归扫描, 但不会盲目重算所有哈希.

        - 每次 `refresh()` / `check()` 都会完整遍历一遍目录树并 `stat` 每个文件, 缓存不参与"目录里有哪些文件"的判断, 也不记录删除. 所以文件树的变动一定能被发现.
        - 对每个文件, 缓存只在 `size` 和 `mtime` 都完全一致时才命中. 命中就直接复用 `hash` / `textHash`, 不重新读文件内容; 只要有一项不同就重算该文件并更新缓存.
        - 因此间隔很久但文件没动过时, 扫描仍然要走目录, 但哈希部分几乎不花时间; 只有真正变动的文件才会被重新哈希.
        - 极端情况下, 如果文件内容变了但大小和 mtime 被刻意还原成原值, 缓存会误命中, 这是该策略的已知取舍.
        - 已删除文件的旧条目不会被主动清理, 但它们不会影响结果, 因为本轮扫描只以实际遍历到的文件为准.

    3. 读取两边的基线. `SyncEngine.preview()` 分别从本地根和远端根读取 `.file_sync_shot.json`. 第一次同步之前两边都没有这个文件, 所以两侧基线都是空 manifest. 这个快照文件本身在默认忽略规则里, 永远不会被当成待同步内容.

        > ASK: `.file_sync_shot.json` 的数据结构长什么样?

        它保存的是某一侧作为下一次比较基线的文件清单, 结构如下 (`schema` 当前为 1):

        ```json
        {
          "schema": 1,
          "committedAt": "2026-11-23T08:30:00.000Z",
          "entries": {
            "notes/a.md": {
              "kind": "file",
              "size": 1024,
              "mtime": 1763890000000,
              "hash": "...",
              "textHash": "..."
            },
            "notes": {
              "kind": "dir",
              "size": 0,
              "mtime": 1763890000000
            }
          }
        }
        ```

        - `entries` 的 key 是相对同步根目录的 POSIX 路径, 不带开头的 `/`; 文件里不保存根路径.
        - 值的字段与 manifest 条目一致: `kind` 为 `file` 或 `dir`, `size` 对目录为 0, `mtime` 为毫秒时间戳, `hash` 仅文件有, `textHash` 仅文本文件有.
        - `committedAt` 是写入快照时的 UTC 时间, 读取后会作为该侧 base manifest 的 `scannedAt`.
        - 两侧各写各的: 本地根一份, 远端根一份 (通过 HTTP 原子写入). 两份内容按各自设备的 mtime 和哈希记录, 所以 `preview` 里会同时有 `baseA` 和 `baseB`.
        - 文件缺失, 为空, JSON 损坏或 `schema` 不是 1 时, 都会被当作"没有基线"; 下一次成功同步会重新写入.

    4. 扫描本地. `LocalScanner` 递归遍历 `/Users/Likianta/Desktop/documents/gitbook`, 生成 "相对路径 -> 条目" 的映射表. 每个条目记录类型 (文件/目录), 大小和 mtime; 文件还计算原始字节的 SHA-256, 若前 8 KiB 不含 NUL 字节 (沿用 Git 的判断方式) 则再计算一个把换行统一为 LF 后的 `textHash`. 扫描时套用默认忽略规则 (`.git/`, `.idea/`, `.vscode/`, `.venv/`, `__pycache__/`, `.filesync/`, `.DS_Store`, `.file_sync_shot.json` 等), 并跳过符号链接. 每扫到约 200 个条目上报一次进度, 界面显示 "Scanning local files... N".

        > ASK: 对本机的 `/Users/Likianta/Desktop/documents/gitbook` 进行一次遍历扫描, 允许你使用 `data/sync_pairs/android-gitbook/hash_cache.json` 来快速获取哈希, 你统计一下耗时要多久 (用 dart 写一个 prob script 实测一下).

        实测结果 (临时 Dart 脚本直接复用 `LocalScanner` + `FileHashCache` + 该配对的 extra ignores; 测完已删除脚本):

        - 扫描范围: 2384 个条目, 其中 2097 个文件, 287 个目录, 文件合计 238,720,767 字节 (约 227.7 MiB).
        - 哈希缓存: 2097 次命中, 0 次未命中.
        - 第一次: 175 ms; 紧接着第二次: 125 ms.

        也就是说, 在缓存完整有效的情况下, 完整遍历 + `stat` 这棵约 230 MiB 的树只需要约 0.1 - 0.2 秒, 哈希计算基本为零. 两次差异来自 JIT 预热和系统页缓存, 不是哈希开销.

        反过来说, 只要缓存里出现 miss (新增文件, 或 size/mtime 变化的文件), 耗时就主要变成读取并哈希这些文件; 首次没有缓存时, 才是整个 230 MiB 都要读一遍并计算哈希. 另外, 机器上共有 2323 个文件, 实际扫描到 2097 个, 差额是被忽略规则排除的内容 (如 `.git/` 等).

    5. 扫描远端. 客户端向手机的文件服务请求 `GET /gitbook/manifest` (带 token). 手机端用同一套 `LocalScanner` 扫描 `/storage/emulated/0/Likianta/documents/gitbook`, 返回 JSON 形式的 manifest; 服务端也有哈希缓存 (`file_server.hash_cache.json`) 来避免重复哈希. 客户端收到后再套一次忽略规则, 并把路径统一成相对 mount 根目录的形式. 远端是一次 HTTP 请求, 没有逐文件进度, 所以等待期间界面显示 "Downloading remote manifest...".

    6. 做三方比较. 两份 manifest 和两份基线交给 `SyncPlanner.plan()`. 首次没有基线时, 规则是:

        - 只在一侧存在 -> 计划在另一侧创建;
        - 两侧都存在且内容相同 (原始哈希相同, 或 LF 归一化后的 `textHash` 相同) -> 视为已经一致, 不产生动作;
        - 两侧都存在但内容不同 -> 记为 `bothCreated` 冲突, 因为无法判断哪边更新, 不会自动覆盖任何一侧;
        - 一侧缺失不会被识别为"删除". 空基线里没有可对照的历史, 只能把它理解为"另一侧新建".

    7. 构建展示树. 界面用 `preview.a` / `preview.b` 两份原始 manifest 调用 `buildSyncTree()`, 根节点名就是配对名 "android-gitbook". manifest 里没有显式列出的中间目录会被补成合成节点; 同级排序是目录优先, 再按名称 (忽略大小写) 排序; 根节点默认展开, 其余节点默认折叠. 重新扫描时会保留用户之前的展开状态, 并重新定位当前选中的节点.

    8. 不写盘. 到这里只是"看见"了两边的现状. 树上显示的是两边各自有什么, 不是"接下来要做什么"; 只有在 Check 时才会把动作和冲突列出来. 也只有第一次成功执行 Sync/Pull/Push 之后, 才会在两边各自写入 `.file_sync_shot.json`, 作为下一次比较的基线.

    两个实际影响:

    - 首次扫描的成本主要花在读文件和算哈希上, 目录越大越慢; 之后本地能命中哈希缓存, 远端服务端也有缓存, 会快很多.
    - 树里文件很多不代表都会被传输. 真正决定传输量的是 Check 算出来的动作列表.
