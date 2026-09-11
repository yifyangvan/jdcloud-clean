# AX1800&AX6600路由器管理工具

适用于 OpenWrt 系路由器（arm_cortex-a53 / musl libc），一键禁用 PCDN/积分服务、关闭自动升级、DNS 封锁、安装开机兜底防复活机制、安装 Dropbear SSH。所有修改均有备份，可完整恢复。

## 功能特性
<img width="376" height="405" alt="jd" src="https://github.com/user-attachments/assets/405f2470-c386-4547-883d-1e8e982b070f" />

<img width="379" height="757" alt="status" src="https://github.com/user-attachments/assets/c4a747d1-f9ce-467e-9681-ae28764126c9" />



- **推荐清理**：一键禁用 PCDN/积分服务、关闭自动升级、DNS 封锁、清理 crontab、安装 Boot Guard 防复活
- **自定义工具**：PCDN / DNS / 升级 / Boot Guard 单项操作
- **SSH 管理**：安装 / 卸载 / 重启 Dropbear SSH
- **极限模式**：禁用全部原厂后台服务
- **完整备份/恢复**：所有删除和修改的文件均备份，可一键恢复

## 前置条件

- 路由器已开启 Telnet 或 SSH，可登录获取 root 权限
- 没开telnet的，可以用目录里面telnet来开启。在web管理页面登录状态下，按F12进入控制台，复制telnet里面的命令运行，即可开启
- 路由器架构为 arm_cortex-a53，系统为 musl libc（多数原厂 OpenWrt 固件满足）
- 路由器可访问互联网（用于下载 Dropbear 安装包）

## 安装

### 1. 登录路由器

```sh
telnet 192.168.1.1
# 或
ssh root@192.168.1.1
```

（默认 IP 以你的路由器实际地址为准，登录后即为 root）

### 2. 下载并固化脚本

```sh
curl -L -o /usr/bin/jd 'https://raw.githubusercontent.com/yifyangvan/jdcloud-clean/refs/heads/main/jd.sh'
chmod +x /usr/bin/jd
```

脚本安装在 `/usr/bin/jd`，属于 overlay 分区，**重启不会丢失**。

### 3. 运行

直接输入：

```sh
jd
```

即可进入交互菜单。

## 菜单说明

### 主菜单

```
1. 推荐清理
   备份 + 禁用 PCDN + 清理升级 + DNS 封锁
   + 清理 crontab + 安装 Boot Guard
   （保留 APP / Web / Mesh / LED 基础功能）

2. 自定义工具
   PCDN / DNS / 升级 / Boot Guard 单项操作

3. SSH (Dropbear) 管理
   安装 / 卸载 / 重启 SSH 服务

4. 查看当前状态

5. 从备份恢复全部

6. 极限模式：禁用全部原厂服务
   ⚠️  APP / Web / Mesh / LED 可能全部失效

7. 退出
```

### 自定义工具子菜单

```
1. 仅禁用 PCDN / 积分及后台服务
2. DNS 封锁管理
3. 自动升级管理
4. Boot Guard 管理
5. 返回主菜单
```

### SSH 管理子菜单

```
1. 安装 SSH
2. 卸载 SSH
3. 重启 SSH 服务
4. 返回
```

## 推荐使用流程

首次使用建议按以下步骤操作：

### 第一步：推荐清理

运行 `jd`，选 **1（推荐清理）**，输入 `YES` 确认。

这会执行：
- 备份所有原始文件到 `/etc/jd_clean_backup/`
- 禁用 PCDN / 积分服务
- 禁用无用后台服务（webdav / dlspeed 等）
- 删除升级脚本，彻底删除 UCI 升级配置
- 开启 DNS 封锁（4 个域名指向 127.0.0.1）
- 清理 crontab 脏条目
- 安装 Boot Guard（开机兜底 + 每小时巡逻）

### 第二步：重启路由器

```sh
reboot
```

### 第三步：验证

重启后等待 2 分钟，登录后运行 `jd`，选 **4（查看当前状态）**，确认：
- PCDN 相关进程显示 `[停止]`
- 基础服务（agent / rpc 等）显示 `[运行]`
- DNS 封锁显示 `开启`
- Boot Guard 显示 `已安装`，巡逻 `已启用`，开机自启 `已配置`
- 自动升级显示 `无 upgrade_plan（已删除）`

## Boot Guard 说明

Boot Guard 是本工具的核心防复活机制：

- **开机自启**：路由器开机后延迟 120 秒执行，等所有原厂服务启动完毕后再清理
- **每小时巡逻**：通过 crontab 每小时执行一次，防止原厂进程重新写回配置或拉起服务
- **巡逻内容**：重新禁用 PCDN 服务、清理 crontab 脏条目、确保 DNS 封锁、确保升级配置关闭
- **日志**：执行日志可通过 `logread | grep jd_boot_guard` 查看

## SSH 安装说明

选 **3（SSH 管理）→ 1（安装 SSH）**，脚本会自动完成：

1. 环境检查（musl libc / curl）
2. 关闭 opkg 签名校验
3. 下载 Dropbear（LEDE 17.01.6 / arm_cortex-a53）
4. 安装 Dropbear
5. 创建 musl 解释器软链接
6. 生成 RSA 主机密钥（含空密钥清理）
7. 配置 init 脚本 + 开机自启 + 启动

安装完成后需手动设置 root 密码：

```sh
passwd root
```

然后即可通过 SSH 登录：

```sh
ssh root@192.168.1.1
```

## 备份目录

所有原始文件备份在 `/etc/jd_clean_backup/original/`：

```
/etc/jd_clean_backup/
├── created                    # 首次运行时间
└── original/
    ├── rc.local               # 原始开机自启配置
    ├── hosts                  # 原始 hosts 文件
    ├── opkg.conf              # 原始 opkg 配置
    ├── crontab                # 原始定时任务
    ├── chmod_record.txt       # 被修改权限的文件及原始权限
    ├── rcd_links.txt          # 被删除的 rc.d 启动链接记录
    ├── config/
    │   ├── jd_clock           # UCI 配置备份
    │   ├── jd_product
    │   ├── jd_plugin
    │   └── dhcp
    └── deleted_files/         # 被删除的文件（保持原始目录结构）
```

备份目录在 overlay 分区，**重启不会丢失**。

## 恢复方法

### 方法一：通过菜单恢复（推荐）

运行 `jd`，选 **5（从备份恢复全部）**，输入 `RESTORE` 确认。

这会：
- 卸载 Boot Guard
- 恢复 rc.local、hosts、opkg.conf、crontab
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
# 恢复基础服务
/etc/init.d/jdcloudbi enable
/etc/init.d/jdcloudbi start

# 恢复 agent 服务
/etc/init.d/jdc_agent enable
/etc/init.d/jdc_agent start
```

## 极限模式说明

选 **6（极限模式）**，输入 `EXTREME` 确认。

此模式在推荐清理基础上，额外禁用全部原厂基础服务：
- 基础服务 / LED 状态
- 代理 / APP 通信
- APP RPC 接口
- Web RPC 接口
- Mesh 组网
- 流量统计

**可能导致的后果**：
- APP 无法连接和管理路由器
- Web 管理页面部分功能异常
- Mesh 组网功能失效
- LED 状态灯可能异常
- 路由器部分基础功能可能受影响

所有修改均会备份，可通过选项 5 完整恢复。

## 升级脚本

脚本更新后，重新执行安装命令覆盖即可：

```sh
curl -L -o /usr/bin/jd 'https://raw.githubusercontent.com/yifyangvan/jdcloud-clean/refs/heads/main/jd.sh'
chmod +x /usr/bin/jd
```

覆盖后建议重新选 **1（推荐清理）** 或 **2 → 4 → 1（安装 Boot Guard）**，确保 Boot Guard 脚本也更新到最新版。

## 注意事项

1. **必须 root 运行**：Telnet/SSH 登录后默认就是 root，无需额外操作
2. **推荐清理保留基础功能**：APP 管理、Web 管理、Mesh 组网、LED 状态均可正常使用
3. **极限模式慎用**：可能导致 APP 无法连接、Web 管理异常、Mesh 失效、LED 异常
4. **DNS 封锁域名**：封锁了 pidrouter-public、pidrouter-public-v6、terosaurs、jdbox-arthur 四个域名
5. **PCDN 服务被禁用后**：积分/收益相关功能将失效，路由器不再跑 PCDN 上行流量
6. **升级被关闭后**：路由器不会自动升级固件，如需升级请先通过菜单恢复自动升级
7. **SSH 安装后需设密码**：Dropbear 安装完成后必须执行 `passwd root` 设置密码才能登录

## 常见问题

**Q: 重启后 PCDN 服务又起来了怎么办？**
A: 确认 Boot Guard 已安装（菜单选 4 查看）。Boot Guard 会在开机后 120 秒自动清理，并每小时巡逻一次。如果 Boot Guard 未安装，选 2 → 4 → 1 安装。

**Q: 基础服务进程起不来？**
A: 旧版本脚本可能存在误删启动链接的问题，已修复。手动恢复：`/etc/init.d/jdcloudbi enable && /etc/init.d/jdcloudbi start`，然后重新安装 Boot Guard。

**Q: APP 还能用吗？**
A: 推荐清理模式下 APP 可以正常使用（agent、rpc 服务保留）。只有积分/收益相关功能会失效。

**Q: 会影响上网吗？**
A: 不会。本工具只禁用原厂后台服务，不影响路由、拨号、WiFi、DHCP 等基础网络功能。

**Q: 备份会占用多少空间？**
A: 备份文件通常几十 KB，对路由器存储空间几乎没有影响。

**Q: SSH 安装失败怎么办？**
A: 确认路由器可访问互联网，且架构为 arm_cortex-a53。可手动执行 `/usr/sbin/dropbear -p 22 -B -E -r /etc/dropbear/dropbear_rsa_host_key` 前台启动查看错误信息。
