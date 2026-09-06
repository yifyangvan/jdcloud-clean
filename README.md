# 京东云路由器清理工具

适用于京东云 AX1800 Pro / AX6600 等路由器，一键禁用 PCDN/积分服务、关闭自动升级、DNS 封锁、安装开机兜底防复活机制。所有修改均有备份，可完整恢复。

## 前置条件

路由器已开启 Telnet，可通过 Telnet 登录获取 root 权限。
没开启的可以用telnet这个脚本开启。

## 安装

### 1. Telnet 登录路由器

```sh
telnet 192.168.1.1
```

（默认 IP 以你的路由器实际地址为准，登录后即为 root）

### 2. 下载并固化脚本

```sh
curl -L -o /usr/bin/jd 'https://raw.githubusercontent.com/yifyangvan/jdcloud-clean/refs/heads/main/clean4.sh'
chmod +x /usr/bin/jd
```

脚本安装在 `/usr/bin/jd`，属于 overlay 分区，**重启不会丢失**。

### 3. 运行

直接输入：

```sh
jd
```

即可进入交互菜单。

## 菜单功能

```
1. 推荐清理
   备份 + 禁用 PCDN + 清理升级 + DNS 封锁
   + 清理 crontab + 安装 Boot Guard
   （保留 APP / Web / Mesh / LED 基础功能）

2. 仅禁用 PCDN / 积分及后台服务

3. DNS 封锁管理
   开启 / 关闭 4 个京东云域名的 DNS 封锁

4. 自动升级管理
   彻底关闭 / 从备份恢复自动升级

5. Boot Guard 管理
   安装 / 卸载 / 立即执行一次开机兜底脚本

6. 查看当前状态
   进程、服务、DNS、Boot Guard、crontab、备份状态

7. 从备份恢复全部
   一键恢复所有修改到原始状态

8. 极限模式：禁用全部京东服务
   ⚠️  APP / Web / Mesh / LED 可能全部失效

9. 退出
```

## 推荐使用流程

首次使用建议按以下步骤操作：

### 第一步：推荐清理

运行 `jd`，选 **1（推荐清理）**，输入 `YES` 确认。

这会执行：
- 备份所有原始文件到 `/etc/jd_clean_backup/`
- 禁用 PCDN / 积分服务（jdcbox、jdc_evtreport、jdc_node、jdc_snake）
- 禁用无用后台服务（webdav、dlspeed、speedtest 等）
- 删除升级脚本，彻底删除 UCI 升级配置
- 开启 DNS 封锁（4 个京东云域名指向 127.0.0.1）
- 清理 crontab 脏条目
- 安装 Boot Guard（开机兜底 + 每小时巡逻，防止服务复活）

### 第二步：重启路由器

```sh
reboot
```

### 第三步：验证

重启后等待 2 分钟，Telnet 登录后运行 `jd`，选 **6（查看当前状态）**，确认：

- `jdcbox` / `jdc_node` / `jdc_snake` / `webdav` / `dlspeed` 显示 `[停止]`
- `jdcloud_bi` / `jdc_agent` / `jdcapp_rpc` / `jdcweb_rpc` 显示 `[运行]`（推荐模式保留的基础服务）
- DNS 封锁显示 `开启`
- Boot Guard 显示 `已安装`，巡逻 `已启用`，开机自启 `已配置`
- 自动升级显示 `无 upgrade_plan（已删除）`

## Boot Guard 说明

Boot Guard 是本工具的核心防复活机制：

- **开机自启**：路由器开机后延迟 120 秒执行，等所有原厂服务启动完毕后再清理
- **每小时巡逻**：通过 crontab 每小时执行一次，防止 jdc_agent 等进程重新写回配置或拉起服务
- **巡逻内容**：重新禁用 PCDN 服务、清理 crontab 脏条目、确保 DNS 封锁、确保升级配置关闭
- **日志**：执行日志可通过 `logread | grep jd_boot_guard` 查看

## 备份目录

所有原始文件备份在 `/etc/jd_clean_backup/original/`：

```
/etc/jd_clean_backup/
├── created                    # 首次运行时间
└── original/
    ├── rc.local               # 原始开机自启配置
    ├── hosts                  # 原始 hosts 文件
    ├── crontab                # 原始定时任务
    ├── chmod_record.txt       # 被修改权限的文件及原始权限
    ├── rcd_links.txt          # 被删除的 rc.d 启动链接记录
    ├── config/
    │   ├── jd_clock           # UCI 配置备份
    │   ├── jd_product
    │   ├── jd_plugin
    │   └── dhcp
    └── deleted_files/         # 被删除的文件（保持原始目录结构）
        └── sbin/
            └── jd_online_upgrade.sh
```

备份目录在 overlay 分区，**重启不会丢失**。

## 恢复方法

如果需要恢复到原始状态：

### 方法一：通过菜单恢复（推荐）

运行 `jd`，选 **7（从备份恢复全部）**，输入 `RESTORE` 确认。

这会：
- 卸载 Boot Guard
- 恢复 rc.local、hosts、crontab
- 恢复 UCI 配置
- 恢复被删除的文件和权限
- 重建 rc.d 启动链接
- 重新 enable 所有服务
- 重启 firewall/dnsmasq

恢复完成后建议重启路由器：

```sh
reboot
```

### 方法二：手动恢复关键服务

如果只是某个服务需要恢复：

```sh
# 恢复 jdcloudbi（LED 基础服务）
/etc/init.d/jdcloudbi enable
/etc/init.d/jdcloudbi start

# 恢复 jdc_agent（APP 通信）
/etc/init.d/jdc_agent enable
/etc/init.d/jdc_agent start
```

## 升级脚本

GitHub 上脚本更新后，重新执行安装命令覆盖即可：

```sh
curl -L -o /usr/bin/jd 'https://raw.githubusercontent.com/yifyangvan/jdcloud-clean/refs/heads/main/clean4.sh'
chmod +x /usr/bin/jd
```

覆盖后建议重新选 **1（推荐清理）** 或 **5 → 1（安装 Boot Guard）**，确保 Boot Guard 脚本也更新到最新版。

## 注意事项

1. **必须 root 运行**：Telnet 登录后默认就是 root，无需额外操作
2. **推荐清理保留基础功能**：APP 管理、Web 管理、Mesh 组网、LED 状态均可正常使用
3. **极限模式慎用**：选项 8 会禁用全部京东服务，可能导致 APP 无法连接、Web 管理异常、Mesh 失效、LED 异常
4. **DNS 封锁域名**：封锁了 pidrouter-public、pidrouter-public-v6、terosaurs、jdbox-arthur 四个京东云域名
5. **PCDN 服务被禁用后**：京东云 APP 中的积分/收益功能将失效，路由器不再跑 PCDN 上行流量
6. **升级被关闭后**：路由器不会自动升级固件，如需升级请先通过菜单恢复自动升级

## 常见问题

**Q: 重启后 PCDN 服务又起来了怎么办？**
A: 确认 Boot Guard 已安装（菜单选 6 查看）。Boot Guard 会在开机后 120 秒自动清理，并每小时巡逻一次。如果 Boot Guard 未安装，选 5 → 1 安装。

**Q: jdcloud_bi 进程起不来？**
A: 旧版本脚本存在误删 jdcloudbi 启动链接的 bug，已修复。手动恢复：`/etc/init.d/jdcloudbi enable && /etc/init.d/jdcloudbi start`，然后重新安装 Boot Guard。

**Q: 京东云 APP 还能用吗？**
A: 推荐清理模式下 APP 可以正常使用（jdc_agent、jdcapp_rpc 保留）。只有积分/收益相关功能会失效。

**Q: 会影响上网吗？**
A: 不会。本工具只禁用京东云的后台服务，不影响路由、拨号、WiFi、DHCP 等基础网络功能。

**Q: 备份会占用多少空间？**
A: 备份文件通常几十 KB，对路由器存储空间几乎没有影响。

有其他优化建议欢迎提供
