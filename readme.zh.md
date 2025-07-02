# 文件同步工具

...

## 安装

### PC

...

### Android

1. 下载 Termux

2. 配置 Termux

   1. 允许访问所有文件

   2. 安装 Python 及其依赖

      ```sh
      ...
      pip install -r http://172.20.128.132:2135/reqlock/file_sync_pro.txt
      ```

   3. 开启 SSH

      ```sh
      # setup password
      passwd
      #   ...
      
      # start service
      sshd
      
      # if kill service
      pkill sshd
      ```

      注意: 请保持 Termux 应用在前台, 否则 PC 端可能会连不上.

## 使用

### PC

...

通过 WebUI:

```sh
strun 2162 src/file_sync_pro/ui.py
```

界面:

![](./images/151653.png)

## Android

1. 打开 Termux, 开启 SSH

2. PC 端连接 SSH:

   ```sh
   ssh <android_ip> -p 8022
   #   first time connection, type "yes" when console asks if continue connecting.
   #   prompt to input password.
   # --- ssh ---
   # if file-sync-pro package has updated, redo pip install:
   #   pip install -r http://172.20.128.132:2135/reqlock/file_sync_pro.txt
   # run server
   python -m file_sync_pro run_air_server
   #   server running at 0.0.0.0:2160
   ```

同步快照:

安卓切换应用到 Solid Explorer, 开启 FTP 服务, 并保持应用在前台.

来到 PC 端的控制台:

```sh
# dry run
pox -m file_sync_pro sync_snapshot \
    C:/Likianta/documents/gitbook/source-docs/snapshot.json \
    ftp://192.168.8.31:2160/Likianta/documents/gitbook/source-docs/snapshot.json \
    -d
# execute
pox -m file_sync_pro sync_snapshot \
    C:/Likianta/documents/gitbook/source-docs/snapshot.json \
    ftp://192.168.8.31:2160/Likianta/documents/gitbook/source-docs/snapshot.json
```

## 问题解答

### 局域网中的传输速度非常慢

- 尝试切换网络, 例如从公共网络切换到手机热点 (建议使用 5GHz 频段).

  笔者自己的经历是, 使用公共网络速度只有 40KB/s, 改用手机共享热点速度 10MB/s (百兆带宽级别).

  此外, 建议在设置中查看当前网络的传输能力:

  ![](./images/171928.png)

### 文件没变化, 但是却提示大量覆盖操作

目前发现以下场景会导致出现此情况:

1. A 电脑和 B 手机通过 file-sync-pro 完成了同步
2. A 电脑和 C 电脑通过 git 完成了同步
3. 由于 A, C 电脑 git clone 的时间不同, 导致它们之间尽管文件内容相同, 但所有文件的 mtime 都不同
4. 此时 C 电脑想和 B 手机通过 file-sync-pro 同步, 由于 file-sync-pro 是基于时间戳校验的, 就产生了大量 `=>` 覆盖操作

以上情况还有更细节的地方需要说明:

如果 `C/file:mtime < A/file:mtime = B/file:mtime`, 那么控制台会有一条弱警告, 但不会给出覆盖操作; 

如果 `C/file:mtime > A/file:mtime = B/file:mtime`, 那么才会给出 `C => B` 的覆盖操作.

综上两条, 你会看到大量 `=>` "误报", 但不会看到 `<=` "误报".

另外, 对于 `+>` `->` `<+` `<-` 操作, 仍然能正确计算, 不受 git 同步影响.

