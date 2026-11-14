# file_sync_pro (已冻结 Python 版) 实现分析与总结

> 分析对象: `src/file_sync_pro/` (共 23 个 Python 模块, 约 2600 行)
> 依赖: `airmise` (RPC), `lk_utils` (文件系统工具), `argsense` (CLI), `neoprint` (终端着色), UI 依赖 `streamlit` + `streamlit_canary` (均属 dev 依赖)
> 目的: 在迁移到 Flutter 之前, 把旧实现的**数据模型, 算法, 传输机制和缺陷**弄清楚, 作为新架构的输入, 而不是照搬对象.

---

## 0. 结论速览

1. **核心思想很简单**: 每个设备为目标目录生成一份 "文件清单" (relpath → mtime) 的 JSON 快照; 同步时用两个快照 + 一个共同基线 (base) 做**三方合并**, 只对差异项执行增/删/覆盖/移动.
2. **唯一判据是 mtime**. 不比对文件大小, 不比对内容哈希. 这直接解释了本项目长期存在的 "文件明明一样, 却报大量未同步" 的问题 (见 §7.1).
3. **同步方向不对称**: 只有 "mtime 变新" 才算变更, "mtime 变旧" 只打印一条弱警告然后被忽略 (见 §7.2).
4. **只同步文件, 不同步目录**: 快照里只有普通文件条目; 空目录不同步, 删光文件后残留的空目录也不会被清理 (见 §7.3).
5. **传输层用 `airmise` 的 "远程 exec Python 源码" 模型**: 服务端把 `fs`, `os` 模块暴露进一个常驻命名空间, 客户端把代码字符串 + 参数 pickle 过去执行; 扫描结果用生成器流式回传 (见 §5).
6. **代码库是两代实现的叠层**: `filesys/` + `snapshot/dataclass.py` 是 v1, `filesys2/` + `snapshot/api.py` 是 v2 (实际在用的). v1 有多处已不可运行, 且 v1/v2 的快照 JSON 字段名 (`data` vs `files`) 不兼容 (见 §8).
7. 值得带进 Flutter 版本的只有: **快照 + 三方合并的模型**, **按需增量传输**, **"目录 mtime 命中则跳过子树" 的扫描优化思路**. 其余 (mtime 单判据, 快照格式, RPC 方案, 冲突策略) 都应重新设计.

---

## 1. 代码地图

### 1.1 模块分层

```
file_sync_pro
├── __init__.py          终端初始化 (neoprint) + 对外导出
├── __main__.py          argsense CLI: create/update/sync/merge/rebuild snapshot, run_air_server ...
├── init.py              clone_project: 用 A 的快照一次性铺到 B (新设备接入)
├── doctor.py            fix_mtime: 修复 A/B 快照间 "时间戳不合理" 的问题
├── filesys/             [v1] 文件系统抽象 (Base / Local / Air / Ftp / Dufs / General)
├── filesys2/            [v2] 文件系统抽象 (local / remote / specific), 实际在用
├── snapshot/
│   ├── api.py           [v2] 全部核心逻辑: 建快照 / 更新 / 合并 / 同步 / 落锁
│   └── dataclass.py     [v1] Snapshot 类: 快照文件读写与 root 解析
└── ui_st/               Streamlit Web UI
    ├── app.py           主界面: 选左右设备 -> 更新快照 -> 预演/同步/合并
    ├── create_snapshot.py  创建快照的对话框
    └── snap_maker.py    更早的单页版建快照界面 (已被取代)
```

### 1.2 运行时的真实调用链 (v2)

```
ui_st/app.py
  ├─ snap_api.update_snapshot(snap_file, addr)
  │     └─ filesys2.FileSystem(root, addr)
  │           ├─ local  : lk_utils.fs 模块 (直接调用)
  │           └─ remote : airmise.Client → 远程 exec 'fs.findall_files(...)'
  │     └─ 写回 JSON (只替换 current, 保留 base)
  └─ snap_api.sync_snapshot(snap_a, addr_a, snap_b, addr_b, dry_run, ...)
        ├─ 读两份 JSON, 选 base, 双向 diff
        ├─ _compare_changelists()   生成最终动作序列 (带方向)
        ├─ dry_run ? 打印/渲染表格 : _apply_changes() 执行 + _lock_snapshot() 两边落锁
        └─ 冲突文件备份到 data/conflicts/<时间戳>/
```

v1 (`filesys/`) 与 `snapshot/dataclass.py` 只被 `init.py`, `doctor.py`, `__main__.py` 的部分旧命令引用.

---

## 2. 数据模型: 快照文件 (v2)

### 2.1 JSON 结构

```jsonc
{
  "root": "/Users/me/Documents/notes",   // 本地绝对路径, 或远端设备上的绝对路径 (不带 air:// 前缀)
  "ignores": [],                          // 相对路径前缀, 仅用于扫描时排除 (需手工编辑)
  "base": {                               // 上一次成功同步后的共同状态
    "version": "9f2c...-1760000000",
    "files": {
      "a.txt": 1755050328,
      "sub/b.png": 1613155218
    }
  },
  "current": {                            // 最近一次扫描到的状态
    "version": "1a3b...-1760009999",
    "files": { "...": 0 }
  }
}
```

- **`files`**: `{相对路径: mtime 整数秒}`. 路径统一使用 `/` 分隔, 无前导 `/`.
- **`base` / `current`**: `base` 是 "上次双方达成一致" 的状态, `current` 是 "本机最近一次扫描" 的状态. 只有 `update_snapshot` 会改 `current`; 只有成功同步 (`_lock_snapshot`) 会把 `base` 和 `current` 一起改写成同一个新状态.
- **`version`**: `md5(json.dumps(files, sort_keys=True)) + "-" + int(time())`. 哈希用于**结构相等**判定, 时间戳只作辅助 (见 `snapshot/api.py#L715-L723`).
- **`root` 与地址解耦**: 0.2.1 起 "快照只描述设备上的文件树, 不描述设备地址"; IP/端口通过 `source_addr` 参数单独传入. 这是为了设备换 IP 后快照仍可复用.
- `ignores` 目前只在 `update_snapshot` 中作为 `str.startswith(tuple)` 前缀过滤 (见 §7.4), 建快照时固定写入 `[]`.

> v1 版本 (`snapshot/dataclass.py`) 的字段名是 `data` 而不是 `files`, 且 `root` 可能是相对快照文件位置的相对路径. 两代格式互不兼容.

### 2.2 动作词汇表

代码用 8 个箭头 + `?` 后缀表示合并意图 (`snapshot/api.py#L30-L45`):

| 符号 | 含义 | 右侧动作 |
|------|------|----------|
| `+>` | 左侧新增 | 在右侧创建 |
| `=>` | 左侧更新 | 用左侧内容覆盖右侧 |
| `->` | 左侧删除 | 删除右侧文件 |
| `~>` | 左侧移动 | 在右侧移动到新路径 |
| `<+` | 右侧新增 | 在左侧创建 |
| `<=` | 右侧更新 | 用右侧内容覆盖左侧 |
| `<-` | 右侧删除 | 删除左侧文件 |
| `<~` | 右侧移动 | 在左侧移动到新路径 |
| `==` | 无变化 | 只出现在类型定义中, 实际不产生 |
| `=>?` / `<=?` | 有疑问的覆盖 | 先备份被覆盖方, 再覆盖 |

`?` 后缀表示 "双方都改过同一个文件", 需要冲突处理.

---

## 3. 工作流程

### 3.1 建快照 `create_snapshot(snap_file, url)`

`snapshot/api.py#L74-L98`

1. `FileSystem.from_url(url)`: `air://<ip>:<port>/<path>` 转为 (remote, `/<path>`), 否则视为本地路径 (转绝对路径).
2. 若 root 不存在: 远端会 `make_dirs(root)` **顺手把目标目录建出来**, 然后写一份空快照 (`version = 'null-0'`).
3. 若存在: 扫描全部文件得到 `{relpath: mtime}`.
4. `base = current = {version, files}` 写入 JSON -- 注意这是**重建基线**语义, 会丢掉旧的共同祖先. 因此它既用于 "首次建快照", 也用于 "时间戳修好后重建" (`rebuild_snapshot`).

### 3.2 更新快照 `update_snapshot(snap_file, addr)`

`snapshot/api.py#L106-L118`

- 读 JSON → `FileSystem(root, addr)` → `findall_nodes(root, exclusion=ignores)` 全量扫描.
- 只替换 `current`; `base` 原样保留. 这是三方合并能工作的关键.
- 不做增量: 每次都全量遍历 + 全量哈希 + 全量写 JSON.

### 3.3 同步 `sync_snapshot(...)`

`snapshot/api.py#L121-L258`, 是整套系统的核心:

```
读 snap_a.json, snap_b.json
        │
        ├─ 选 base:
        │    手动指定 a/b, 或比较两边 base.version 的 hash:
        │      hash 相同 → 用任一
        │      hash 不同 → 选 "更旧" 的那份 base (近似共同祖先)
        │
        ├─ changes_a = diff(current_a, base)     (若 current_a.version hash == base hash 则为空)
        ├─ changes_b = diff(current_b, base)
        │
        ├─ final_changes = _compare_changelists(changes_a, changes_b, no_doubt, consider_moving)
        │
        ├─ dry_run? → 预览表格 (CLI 彩色表 / Streamlit 表)
        │
        └─ 执行:
             fs_a = FileSystem(root_a, addr_a)
             fs_b = FileSystem(root_b, addr_b)
             snap_new = _apply_changes(final_changes, base_files, current_a, current_b, fs_a.core, fs_b.core, ...)
             _lock_snapshot(A, snap_new, snap_file_a)   # base = current = 新状态
             _lock_snapshot(B, snap_new, snap_file_b)
```

关键点: **同步不重新扫描磁盘**, 完全信任两份快照. 用户必须先点 "Update left / Update right", 否则同步的是旧世界.

### 3.4 合并 `merge_snapshot(...)`

`snapshot/api.py#L261-L306`: 针对 "首次把两个已有目录并到一起" 的场景. 它直接比较两边 `current`:
- 只在 A 有的文件 → `+>` (复制到 B); 只在 B 有的 → `<+`;
- 两边都有的路径 → 一律视为已同步 (哪怕 mtime/内容不同);
- 不处理删除.
- 注意: 它把 `{}` 当作 `snap_data_base` 传给 `_apply_changes`, 导致最终快照只包含 "单边存在" 的文件, 两边都有的文件会从快照里消失. 后续必须再 `update_snapshot` 才能恢复完整清单. 这是一个实打实的缺陷 (§7.5).

### 3.5 其它入口

| 入口 | 作用 | 现状 |
|------|------|------|
| `rebuild_snapshot(snap_file)` | 用磁盘现状重建 base/current | 可用 (v2) |
| `init.clone_project(snap_i, snap_o, root_o)` | 用 A 的快照把文件全量铺到 B 设备并重建 B 快照 | 依赖 v1 `Snapshot` + `AirFileSystem`, 已不可运行 |
| `doctor.fix_mtime(a, b)` | 对两边同 key 但 mtime 不同的项做内容 md5 对比, 一致则把 mtime 改成一致 | 读的是 v1 的 `current.data`, 对 v2 快照直接 KeyError |
| `__main__.fetch_remote_file` | 通过 air 下载单个文件 | 依赖已失效的 `AirFileSystem.create_from_url` |
| `__main__.fetch_remote_snapshot` | 拉取远端快照 | 断言 `ftp://` 后又用 `AirFileSystem` 解析, 自相矛盾, 必然失败 |
| `__main__.force_sync_snapshot` | 把本地快照强推到一个 FTP 位置 | 仅 FTP 场景 |

---

## 4. 三方合并算法详解

### 4.1 选 base

```python
def compare_version(ver_a, ver_b):
    hash_a, time_a = ver_a.split('-')
    hash_b, time_b = ver_b.split('-')
    if hash_a == hash_b:      return 0   # 同一棵树
    elif time_b <= time_a:    return 1   # b 更旧 → 用 b 的 base
    else:                     return 2   # a 更旧 → 用 a 的 base
```

设计意图: 上次同步后两边 base 应该相同; 如果某一侧被 `create_snapshot`/`rebuild_snapshot` 重建过, 它的 base 会变新而 losing 共同祖先, 此时退回选 "更旧" 的 base, 至少还能找到一个较近的共同状态.

隐患: 这个 "更旧" 只是按 `version` 里附加的写入时间排序, 与真实内容蕴含关系无关. 如果两侧各自独立重建过快照, 选出的 base 可能完全不代表任何共同状态, 于是产生大规模 `=>` 误判.

### 4.2 单边 diff: `compare_new_to_old`

`snapshot/api.py#L189-L212`

```
遍历 new:
  在 old 中:
    new.mtime >  old.mtime → '=>'
    new.mtime <  old.mtime → 只打印弱警告 (文件), 不产生动作
    new.mtime == old.mtime → 无动作
  不在 old 中 → '+>'
遍历 old 中不在 new 的 → '->'
```

于是单个快照相对于 base 的变化列表只包含 `+> / => / ->` 三种.

### 4.3 合并两张变化表: `_compare_changelists`

`snapshot/api.py#L309-L414`. 决策表 (`no_doubt=False` 时带 `?`):

| A 相对 base | B 相对 base | 输出 | 说明 |
|---|---|---|---|
| `+>`/`=>` | `+>`/`=>` | `ta > tb` → `=>?`; `ta == tb` → `=>?`; `ta < tb` → `<=?` | 双方都改, 取 mtime 新的一方, 另一方先备份 |
| `+>`/`=>` | `->` | `+>` | 一方改, 一方删 → 以 "改" 为准, 在删除方重建 |
| `->` | `+>`/`=>` | `<+` | 同上, 反向 |
| `->` | `->` | 无动作 | 双方都删 |
| 仅 A 有 (`+>`/`=>`/`->`) | - | 原样输出 | 单边变化直接应用到另一边 |
| 仅 B 有 (`+>`/`=>`/`->`) | - | `<+` / `<=` / `<-` | 单边变化直接应用到另一边 |

`no_doubt=True` 时: 丢掉 `?` 直接按 mtime 新的覆盖; 双方 mtime 相同且都改过时**什么都不做**. UI 里 "No doubt" 开关就是给熟悉情况的人用来跳过冲突备份的.

### 4.4 移动检测 (可选, 默认关闭)

`consider_moving=True` 时, 在正式合并前:

1. 收集本侧 `->` 项, 按 `(basename, mtime)` 建索引;
2. 再看本侧 `+>` 项, 若能在索引里唯一命中, 则认为是一次移动, 输出 `(新路径, 旧路径), '~>', t`;
3. 两侧各自做一遍; 命中过的 key 从后续常规合并中排除.

只能识别**同一目录/跨目录的纯重命名或移动**, 且同名同 mtime 必须唯一; 对 "移动 + 编辑" 无法识别 (mtime 变了). 实现上靠 `_apply_changes` 里的 `fs.move_file` 完成, 避免重新传一遍数据.

### 4.5 冲突处理

- 出现 `=>?`: 先把 B 侧将被覆盖的文件下载/复制到 `data/conflicts/<ymd_hns>/<name>.b.<ext>`, 再执行覆盖.
- 出现 `<=?`: 把 A 侧文件复制到 `<name>.a.<ext>`, 再执行覆盖.
- 备份目录是**相对当前工作目录**的 `data/conflicts/...`, 不跟随快照位置; 备份仅按文件名平铺, 同名不同目录会互相覆盖; 无扩展名文件在 `lk_utils.fs.split(file, 3)` 处会抛 `ValueError`.
- 没有 "保留双方并让用户选择" 的交互, 也没有把冲突记入快照或历史.

### 4.6 应用变更: `_apply_changes`

`snapshot/api.py#L477-L712`

- 预先把两侧所有 "文件 → 父目录" 展开成 `_created_dirs_a/b`, 用于按需建目录.
- `snap_new` 直接**别名** `snap_data_base` (被注释掉的 `.copy()`), 即原地修改传进来的 base 字典; 因为最终 `_lock_snapshot` 会重新排序拷贝, 落盘结果无碍, 但语义上比较脏.
- 文件传输:
  - 上传到 B: `fs_a.load(file, 'binary')` 读全量 → `fs_b.dump(...)` → `fs_b.client.exec('os.utime(...)')` 设 mtime.
  - 下载到 A: `fs_b.load(...)` → `fs_a.dump(...)` → 本地 `os.utime`.
- 因此 **`fs_b` 必须是 airmise 的远程包装对象**: `_upload_file` 无条件访问 `fs_b.client`; 当 B 侧是本地 (`addr` 为空) 时会 `AttributeError`. 也就是说 **本地 ↔ 本地同步实际不可用**, 尽管 UI 允许两边都不填地址.
- 每项操作前后都打印彩色日志 (neoprint), 并可选更新 Streamlit 进度条.

### 4.7 落锁 `_lock_snapshot`

`snapshot/api.py#L726-L731`

```python
files_data = dict(sorted(files_data.items()))
full_data['base'] = full_data['current'] = {
    'version': _make_version(files_data),   # md5 + 当前时间
    'files': files_data,
}
dump(full_data, output_file)
```

两边依次写盘. 这是唯一的 "提交点": 只有全部文件操作成功后才更新快照. 但 A, B 是两次独立写盘, 中间失败会导致两侧快照不一致 (见 §7.6).

---

## 5. 文件系统抽象与传输层

### 5.1 v2 抽象: `filesys2`

`filesys2/specific.py` 把 "路径 + 地址" 归一成一个 `FileSystem`:

```python
fs = FileSystem(root, addr)
#   addr = '' / 'localhost' / 本机 IP  → 本地, core = lk_utils.fs 模块
#   其它                               → 远程, core = filesys2.remote.FileSystem
```

- `core` 暴露统一的 `exist / load / dump / make_dir(s) / remove_file / move_file / find_files / findall_dirs / findall_files`, 本地是 `lk_utils.fs` 的模块函数, 远程是 RPC 代理, 两者鸭子类型一致.
- `root` 对远程是 "远端设备的绝对路径" (如 `/storage/emulated/0/Likianta/...`), 与 IP 分离.
- `remote.create_fs_from_url` 里有一处硬约束: 远端路径必须以 `storage/emulated/0/Likianta` 开头, 否则断言失败 -- 只适配了作者自己的 Android 目录约定 (§7.8).

### 5.2 airmise 的工作方式

`airmise` 是一个基于 TCP + pickle 的 "远程 Python 执行" 框架:

- 服务端 `air.run_server(namespace)` 起 `Server`, 每个连接一个 `Responder` 线程;
- `Responder._mainloop` 维护一个**常驻** `ctx` 字典, 初始化为 `namespace + {'__ref__': ...}`; 每次请求把 `kwargs` `ctx.update()` 进去, 然后 `exec(code, ctx)`;
- 客户端 `client.exec(source, **kwargs)` 把 Python 源码字符串发过去, 把 "顶层 return" 改写成 `__ref__['__result__'] = ...`; 返回值 pickle 回来;
- 若返回值是生成器, 服务端把它登记为一个 iter_id, 客户端以 `const.ITERATOR` 轮询, 服务端每次最多攒 1 秒的数据回传一批 (`responder.py#L150-L178`) -- 这就是 "大量碎文件" 场景的流式优化.

`file_sync_pro` 的服务端命名空间 (`__main__.py#L44-L69`):

```python
{
  'find_files': ..., 'findall_dirs': ..., 'findall_files': ...,  # 生成器, 返回 (path, relpath, mtime)
  'fs': lk_utils.fs,   # 整个模块
  'os': os,
}
```

客户端因此可以:

```python
client.call('findall_files', root)                  # 流式拿目录清单
client.exec('fs.load(file, binary=True)', file=...) # 读文件
client.exec('fs.dump(data, file, binary=True)', ...) # 写文件
client.exec('os.utime(file, (mtime, mtime))', ...)  # 改 mtime
```

**安全模型**: 没有认证, 没有加密, 客户端可在服务端执行任意 Python, 且 pickle 反序列化本身就是 RCE 面. 设计前提是 "同一局域网内的可信设备", 服务端默认监听 `0.0.0.0:2160`, 对局域网完全开放.

### 5.3 v1 传输方案 (历史包袱)

`filesys/` 保留了更早的两条路线:

- **FTP** (`ftp.py`): 通过 Solid Explorer 的 FTP 服务访问 Android. 为了绕开 FTP 的种种限制, 写了很多 hack:
  - `mlsd` 不返回隐藏文件 → 用 `LIST -a` + 正则解析;
  - 文件名含 `[` `]` 时先临时重命名再递归;
  - `storbinary` 不截断已有文件 → 先 `delete` 再 `STOR`;
  - FTP 时间字符串无时区 → 硬编码 `+8h` 偏移, 上传/下载用 `MFMT` 修正.
- **dufs** (`dufs.py`): 用 HTTP PUT 直传, 只写了一半 (`...` 省略, TODO), 未完成.
- **Air** (`air.py`): 早一代 airmise 用法 (模块级 `air.config/connect/delegate`), 与当前 pin 住的 airmise 3.2.4 API 已不匹配.

v2 只用 air/local 两种, FTP/dufs 实际上已被放弃. 这些代码仍被 `__main__` 的部分命令和 `init.py` 引用, 构成 "能 import 但跑不通" 的死区.

---

## 6. 性能设计

| 设计 | 位置 | 效果 / 备注 |
|---|---|---|
| 哈希短路 | `sync_snapshot` 比较 `current.version` 与 base | 树未变时完全跳过 diff |
| 只传差异 | 按 mtime 比较, 同 mtime 不读内容 | 带宽下界接近真实变更量 |
| 生成器流式扫描 | airmise ITERATOR 协议 | 避免一次性 pickle 整个目录树, 服务端按 1s 分批 |
| 目录 mtime 缓存 | `filesys2/specific.findall_files(history=...)` | 目录 mtime 未变则复用历史清单, 跳过子树 stat. **但 `findall_nodes` 从未传 history, 该优化实际未启用** |
| 整文件走内存 | `_apply_changes._upload_file/_download_file` | 大文件 = 两份内存峰值 (读 + pickle), 无分块/断点续传 |
| 单线程串行 | `for k, m, t in changes` | 每个文件至少 2~3 次 RPC 往返, 碎文件多时受 RTT 限制 |
| 快照全量读写 | 每次 update/sync 都 load + dump 整个 JSON | 文件数 10 万级时 JSON 解析与 md5 成为可观开销 |

> 目录 mtime 缓存这一条在 v1/v2 两个实现里都没真正用上: v1 的 `local.py` / `general.py` 调用了**未定义**的 `get_dirnodes_cache()`, 一调用就 `NameError`; v2 的 `findall_nodes` 则根本不传 `history`. 它更像是一个 "设计过但没有接通" 的优化.

---

## 7. 正确性与可靠性分析

### 7.1 只认 mtime, 不认内容

- 判等标准是 `int(mtime)` 相同. 任何导致 mtime 变化但不改内容的操作都会制造差异: `git clone/checkout`, 解压, `cp`, 云盘同步, 备份恢复, Android 上某些文件系统的时间精度/时区处理.
- 反过来, mtime 相同但内容不同的文件**永远不会被同步** (例如手工 `touch -r` 或工具保持 mtime 的复制).
- 没有 size, 没有快速哈希, 没有内容校验, 无法区分 "真变了" 和 "时间戳变了". 这正是 AGENTS.md 里列出的痛点 #2 ("已同步的文件仍然报大量未同步") 的根因之一, 旧 readme 的 FAQ "文件没变化, 但是却提示大量覆盖操作" 也描述了同一现象.

### 7.2 只升不降 (单向偏好)

`compare_new_to_old` 在 `new.mtime < old.mtime` 时只 `print(':v5i', ...)` 弱警告, 不生成 `<=`. 结果是:

- 如果某文件被旧版本内容覆盖 (mtime 变旧), 它不会被同步, 双方长期保持不同内容, 直到该文件再次被 "变新" 地修改;
- 这与 7.1 结合, 会产生 "永远追不平" 的错觉.

### 7.3 目录不进入快照

- `findall_nodes` 只收集文件 (`findall_files`), 没有目录条目.
- 因此: 空目录不同步; 删除文件后另一侧的空目录会留下; 目录权限/时间戳不同步; 移动整个目录在快照里表现为 "一批文件删除 + 一批文件新增", 只能靠 `consider_moving` 的 basename+mtime 猜测.
- 代码里残留的 `key.endswith('/')` 分支 (v1 时代目录也进快照) 现在是死逻辑.

### 7.4 忽略规则很弱

- `ignores` 只在 `update_snapshot` 时以 `relpath.startswith(tuple)` 的方式过滤, 只支持 "目录前缀", 不支持通配/正则/取反, 且无法在 UI 编辑 (只能手改 JSON).
- `create_snapshot` 总是写 `ignores: []`.
- 实际生效的 "默认忽略" 来自 `lk_utils.fs.default_filter`: `.git/`, `.idea/`, `.vscode/`, `__pycache__/`, `.DS_Store`, `.gitkeep`, `~*`, `*~`. 这层过滤对本地扫描有效, 但远端 `findall_files` 走的是同一套 `lk_utils`, 所以也算一致.
- 远端 `findall_nodes` 的 `exclusion` 是前缀, 不会传递给远端 RPC (过滤在本地做).

### 7.5 冲突与合并的边界

- 冲突判定只看 "双方 mtime 是否都新于 base", 不看内容; 双方同时改但内容相同也会产生 `?` 与备份.
- 一方修改, 一方删除时, **删除总是输** (会重建文件); 对 "我确实想删" 的场景不友好.
- `merge_snapshot` 会把 "两边都有" 的文件从新快照里丢掉 (§3.4), 必须再 update 一次才恢复.
- `data/conflicts` 是相对 CWD 的固定目录, 平铺命名, 无去重/清理策略.

### 7.6 非事务性

- 所有文件操作先执行, 最后才写两份快照.
- A 快照写完, B 快照写失败 (磁盘满/权限/进程被杀) → 两侧 base 不一致. 下一次同步会选 "更旧" 的 base 重算, 可能:
  - 重复执行已完成的删除/覆盖 (多数是幂等的);
  - 已删除的文件因 "另一侧快照仍认为存在" 而被 `<+` 复活.
- 没有任何 journal / 操作日志 / 回滚; 中途崩溃后只能靠下一次 diff 自愈.
- 同步过程也不校验源文件在扫描后是否再次变化 (`update_file_a2b` 用**实时** `fs0.filetime(file_i)` 而不是快照里的 `t`, 而 `snap_new[k]` 记的又是 `t`, 会造成快照与实际 mtime 漂移).

### 7.7 内存与延迟

- 整文件读入内存 → pickle → 网络 → 落盘; 大文件会同时占用读缓冲与序列化缓冲.
- 每个文件 "上传 + utime" 至少 2 次往返, 且串行; 碎文件场景性能主要由 RTT 决定, 而不是带宽. 旧 readme 提到 "大量碎文件的特殊优化" 指的是生成器分批扫描和目录缓存, 不是传输并发.
- 无断点续传, 无校验重传, 无压缩.

### 7.8 平台与路径耦合

- `remote.create_fs_from_url` 断言远端路径必须以 `storage/emulated/0/Likianta` 开头 → 只能同步这个 Android 目录约定下的路径.
- `is_remote_path` 在 POSIX 上遇到 `/` 开头的路径直接 `raise Exception`; `create_snapshot` 里 `assert is_local_path(snap_file)` 因此**不接受 macOS/Linux 的绝对快照路径** (UI/CLI 都传相对路径, 才没暴露).
- FTP 实现硬编码 UTC+8 与 `/Likianta/documents/appdata/file-sync-pro/temp/`.
- UI 里设备名/IP/端口/快照目录 (`data/snapshots/<device>/`) 全部硬编码, 换设备要改代码.
- 大量 Windows 风格注释与 `C:/` 示例, 但代码本身用 `/` 归一, 主要问题在断言与默认值.

### 7.9 依赖漂移

- `.venv` 里是 `airmise 3.2.4b1`, 而 v1 代码按 3.2.3 的 API 写: `air.config(host, port, verbose=True)` 在 3.2.4 已没有 `verbose` 参数; `air.delegate(LocalFileSystem)` 在 `working_mode='native'` 时返回的是**本地实例**而不是远程代理. 所以 v1 的 `AirFileSystem.__init__` 必然抛错.
- 3.2.4 的 `run_server(user_namespace, host, port)` 与 `__main__.run_air_server` 的位置参数调用仍然兼容, 因此 air 服务端本身可用.

### 7.10 缺陷清单 (按严重度)

| # | 问题 | 位置 | 影响 |
|---|---|---|---|
| 1 | mtime 单判据, 无内容校验 | `snapshot/api.py#L189-L212` | 误报/漏同步的根因 |
| 2 | mtime 变旧被静默忽略 | 同上 | 内容可能永久不一致 |
| 3 | 本地 ↔ 本地同步会在 `fs_b.client` 崩溃 | `snapshot/api.py#L587-L592` | UI 允许的错误组合 |
| 4 | `merge_snapshot` 丢失两边共有的文件条目 | `snapshot/api.py#L294-L303` | 合并后快照不完整 |
| 5 | 快照提交非原子 (先 A 后 B) | `snapshot/api.py#L726-L731` | 崩溃后可能出现反向操作 |
| 6 | 目录/空目录不同步 | `filesys2/specific.py#L124-L132` | 目录结构不完整 |
| 7 | 冲突备份按文件名平铺, 无扩展名会抛错 | `snapshot/api.py#L539-L552` | 冲突文件相互覆盖/崩溃 |
| 8 | 远端路径断言写死 Android 目录 | `filesys2/remote.py#L33` | 无法同步其它路径/设备 |
| 9 | POSIX 绝对快照路径被拒 | `filesys2/remote.py#L12-L21`, `snapshot/api.py#L80` | macOS/Linux CLI 受限 |
| 10 | v1/v2 快照格式并存且互不兼容 | `snapshot/dataclass.py` vs `api.py` | `doctor`/`clone_project` 不可用 |
| 11 | `findall_files(history=...)` 目录缓存未接通 | `filesys2/specific.py#L75-L122` | 优化失效 |
| 12 | v1 `get_dirnodes_cache` 未定义 | `filesys/local.py#L26` | v1 扫描路径 NameError |
| 13 | 无测试 | 全仓库 | 合并矩阵/边界行为无回归保护 |

---

## 8. 代码质量观察

**做得好的地方**

- 数据模型小而清晰: 一份 JSON, 两个状态 (base/current), 一张动作表, 概念负担低.
- 动作符号 (`+>`, `=>`, `->`, `~>`, `?`) 表意直观, 预演/执行共用同一份 `changes`, dry-run 与真跑行为一致.
- 扫描, diff, 应用, 落锁职责分离, `snap_new` 的构造方式让 "应用后状态" 天然一致.
- 日志/进度/预演三套呈现都基于同一份变更列表, UI 与 CLI 可复用.

**需要避免继承的地方**

- **两代实现并存**: `filesys/` 与 `filesys2/`, `dataclass.py` 与 `api.py`, `snap_maker.py` 与 `create_snapshot.py`. 字段名 `data`/`files` 分裂, 文档与代码脱节, 新人 (包括 AI) 需要先考古才能判断哪个是活的.
- **隐式前置条件多**: 必须先 update 两边, B 必须是远程, 快照路径必须是相对路径, 冲突目录相对 CWD, 子进程/服务端必须先启动等, 没有任何校验或提示.
- **魔法字符串/硬编码**: 设备名, IP, 端口, Android 路径, 时区, `data/` 目录.
- **注释即文档**: readme.zh.md 已过期, 真正的行为只能靠读代码; `doctor.py` 的 docstring 与 v2 格式不符.
- **无测试**: 三方合并是一个纯函数式的决策矩阵, 非常适合表驱动测试, 但目前没有任何测试.

---

## 9. 对 Flutter 重写的启示

按 AGENTS.md 列出的四个旧问题逐条对应:

| 旧问题 | 根因 | 新版本应采取的做法 |
|---|---|---|
| 手机端难打包 (Termux) | 传输依赖在对端跑 Python 解释器 | 用 Dart 实现协议两端; 手机端只依赖 Flutter 运行时 |
| 已同步却报大量未同步 | mtime 单判据 + 单向偏好 + 快照重建语义 | 清单里同时记录 **size + 内容哈希 (或快速哈希)**; mtime 只做快速预筛; 哈希不一致才算变更; 明确 "基线" 的生命周期, 不做隐式重建 |
| 桌面打包体积 | Python 运行时 + Streamlit + 依赖树 | Flutter 原生打包, 传输层用 dart:io / 原生 socket, 不引入运行时 |
| Streamlit 性能 | 每次 rerun 全量重算, 单线程 | Flutter 本地状态管理 + 后台 isolate 扫描/传输; 增量刷新 |

具体到设计:

1. **快照 (manifest) 结构**: 建议每设备一份 `{relpath: {mtime, size, hash}}` + 一份 `lastSynced` 基线. 哈希可为 xxh3/blake3 (快) 或采样哈希 (大文件). 目录条目也要有, 至少记录空目录.
2. **变更判定**: `size` 不同 → 变更; `size` 同但 `mtime` 不同 → 计算哈希再判; 都同 → 视为未变 (可接受的风险). 这样能把 "git clone 改了 mtime" 的误报彻底消掉.
3. **双向对称**: 允许 "内容变旧" 也被识别为变更 (旧内容覆盖新内容属于真实事件), 用哈希而不是方向来判定谁赢.
4. **提交语义**: 引入操作日志 (intent journal) 与幂等操作; 所有操作成功后再原子写入基线 (临时文件 + rename); 两侧基线用 "同步会话 ID" 绑定, 中断后可恢复.
5. **传输**: 分块流式传输 + 并行 (信号量控制并发) + 断点续传 + 传输后校验; 不再整文件进内存.
6. **目录**: 显式下发 "创建目录/删除空目录", 或在文件操作后清理空父目录.
7. **忽略规则**: 参考 `.gitignore` 语义 (glob, `!` 取反, 目录尾 `/`), 在扫描端统一执行, 并允许按同步对配置.
8. **设备发现**: mDNS/局域网广播替代硬编码 IP; 端口可配置; 首次配对 + 简单认证, 替代 "无认证远程 exec".
9. **冲突 UX**: 冲突应进入待办列表, 展示双方 mtime/大小/哈希, 让用户选择保留哪边, 而不是静默备份+覆盖.
10. **可测试性**: 把 "diff + 合并决策" 实现为纯函数, 用表驱动 + 属性测试 (`apply(diff(a, b), a) == b`) 覆盖; 对传输层做故障注入 (断网/磁盘满/进程被杀).
11. **保留的好点子**: 快照 + 三方合并的概念模型, dry-run 预演, 目录 mtime 短路扫描, 生成器式流式枚举.

---

## 10. 附: 逐文件摘要

| 文件 | 角色 | 状态 |
|---|---|---|
| `__init__.py` | neoprint 初始化, 对外导出 | 可用 |
| `__main__.py` | argsense CLI 入口, air server 启动 | 部分命令失效 |
| `init.py` | `clone_project`: 新设备全量铺数据 | 依赖 v1, 不可用 |
| `doctor.py` | `fix_mtime`: 对齐两侧 mtime | 读 v1 字段, 对 v2 不可用 |
| `filesys/base.py` | v1 文件系统接口 | 遗留 |
| `filesys/local.py` | 本地实现 + 目录缓存 | `get_dirnodes_cache` 未定义 |
| `filesys/air.py` | airmise 1 代远程 FS | 与 airmise 3.2.4 不兼容 |
| `filesys/air2.py` | 更早的 air 客户端包装 | 遗留 |
| `filesys/ftp.py` | FTP (Android Solid Explorer) | 遗留, 已放弃 |
| `filesys/dufs.py` | HTTP PUT (dufs) | 半成品 |
| `filesys/general.py` | 运行时切换本地/远程 (全局 `fs1`) | 遗留, 有未定义调用 |
| `filesys2/api.py` | `create_fs_handlers` 三件套工厂 | 未被使用 |
| `filesys2/specific.py` | v2 统一 FS: root + addr, `findall_nodes` | 在用 |
| `filesys2/remote.py` | v2 airmise 客户端包装, URL 解析 | 在用 (URL 断言过窄) |
| `filesys2/local.py` | 直接 re-export `lk_utils.fs` | 在用 |
| `filesys2/general.py` | `get_general_fs` 便捷函数 | 未使用 |
| `snapshot/api.py` | 核心: create/update/sync/merge/rebuild + 合并算法 | 在用 |
| `snapshot/dataclass.py` | v1 `Snapshot` 类: 读写/root 解析/哈希 | 遗留 |
| `ui_st/app.py` | Streamlit 主界面 (设备表, 预演, 进度) | 在用 (硬编码设备) |
| `ui_st/create_snapshot.py` | 建快照对话框 | 在用 |
| `ui_st/snap_maker.py` | 早期单页建快照 | 被取代 |

---

## 11. 附: 关键命令速查 (CLI)

```sh
# 建快照 (本地)
python -m file_sync_pro create_snapshot data/snapshots/<device>/<name>.json /path/to/dir

# 建快照 (远端, 需先在目标设备跑 air server)
python -m file_sync_pro run_air_server
python -m file_sync_pro create_snapshot data/snapshots/<device>/<name>.json \
    air://<ip>:2160/storage/emulated/0/Likianta/documents

# 更新快照 (远端需传 addr; 本地可省略)
python -m file_sync_pro update_snapshot <snap.json> [<ip>:<port>]

# 预演 / 执行同步
python -m file_sync_pro sync_snapshot <snap_a> <addr_a> <snap_b> <addr_b> -d
python -m file_sync_pro sync_snapshot <snap_a> <addr_a> <snap_b> <addr_b> [-n] [-m] [-b b]

# 合并 (首次并库) / 重建
python -m file_sync_pro merge_snapshot <snap_a> <addr_a> <snap_b> <addr_b>
python -m file_sync_pro rebuild_snapshot <snap.json>

# 修复时间戳 (v1 快照格式)
python -m file_sync_pro.doctor <snap_a> <snap_b> [-d] [-n]
```

参数含义: `-d` dry-run; `-n` no-doubt (跳过冲突备份, 直接按 mtime 新者覆盖); `-m` consider-moving (检测移动); `-b a|b` 手动指定以哪一侧快照的 base 为基线.

---

## 12. 一句话总结

这是一个**用文件 mtime 清单 + 三方合并做局域网双向增量同步**的务实实现: 模型优雅, 预演与执行统一, 传输层借助 airmise 实现了 "远程跑本地文件系统 API" 的巧妙抽象; 但它的正确性完全押注在 mtime 上, 缺少内容校验, 目录语义, 事务保证与测试, 这些正是 Flutter 重写需要优先补齐的部分.
