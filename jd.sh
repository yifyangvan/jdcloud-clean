#!/bin/sh
# ============================================================
# AX1800 Pro / AX6600 路由器管理工具（合并版）
#
# 功能：
#   - 推荐清理：禁用 PCDN/积分 + 关闭升级 + DNS 封锁 + Boot Guard
#   - 自定义工具：单项操作（PCDN/DNS/升级/Boot Guard）
#   - SSH 管理：安装/卸载/重启 Dropbear SSH
#   - 极限模式：禁用全部京东服务
#   - 完整备份/恢复机制
#
# 原则：
#   - 所有删除和修改的文件均备份到 BACKUP_DIR，可完整恢复
#   - 首次运行才备份，后续不覆盖原始备份
#   - Boot Guard 开机兜底 + 每小时巡逻，防止服务复活
#
# 在路由器上直接运行：sh jd.sh
# ============================================================

BACKUP_DIR="/etc/jd_clean_backup"
BACKUP_ORIGINAL="$BACKUP_DIR/original"
BACKUP_DELETED="$BACKUP_ORIGINAL/deleted_files"
BACKUP_CONFIG="$BACKUP_ORIGINAL/config"
STATE_FILE="$BACKUP_DIR/state"
MYHOSTS="/etc/custom_hosts"
BOOT_GUARD="/sbin/jd_boot_guard.sh"

# SSH 相关配置
DROPBEAR_URL="https://downloads.openwrt.org/releases/17.01.6/packages/arm_cortex-a53_neon-vfpv4/base/dropbear_2017.75-5_arm_cortex-a53_neon-vfpv4.ipk"
DROPBEAR_IPK="/tmp/dropbear.ipk"
DROPBEAR_KEY="/etc/dropbear/dropbear_rsa_host_key"
SSH_PORT=22

# ============================================================
# 基础函数
# ============================================================
pause()
{
    echo ""
    printf "按 Enter 返回菜单..."
    read dummy
}

header()
{
    clear 2>/dev/null
    echo "=============================================="
    echo "     京东云路由器管理工具（合并版）"
    echo "=============================================="
    echo ""
}

log()
{
    echo "  $1"
    logger -t jd_clean_tool "$1" 2>/dev/null
}

# ============================================================
# 备份函数（首次运行才备份，幂等）
# ============================================================

# 备份单个文件
backup_file()
{
    SRC="$1"
    REL_PATH="$2"
    DST="$BACKUP_ORIGINAL/$REL_PATH"
    if [ -e "$SRC" ] && [ ! -e "$DST" ]; then
        mkdir -p "$(dirname "$DST")"
        cp -a "$SRC" "$DST" 2>/dev/null
    fi
}

# 备份后删除（保持原始目录结构）
backup_and_delete()
{
    SRC="$1"
    if [ -e "$SRC" ]; then
        DST="$BACKUP_DELETED$SRC"
        if [ ! -e "$DST" ]; then
            mkdir -p "$(dirname "$DST")"
            cp -a "$SRC" "$DST" 2>/dev/null
        fi
        rm -f "$SRC"
        log "已删除并备份: $SRC"
    fi
}

# 记录原权限后 chmod -x
backup_and_chmod()
{
    FILE="$1"
    if [ -e "$FILE" ]; then
        if ! grep -q "^$FILE|" "$BACKUP_ORIGINAL/chmod_record.txt" 2>/dev/null; then
            ORIG_PERM=$(stat -c '%a' "$FILE" 2>/dev/null)
            echo "$FILE|$ORIG_PERM" >> "$BACKUP_ORIGINAL/chmod_record.txt"
        fi
        chmod -x "$FILE" 2>/dev/null
    fi
}

# 备份 UCI 配置
backup_uci()
{
    CONFIG="$1"
    if [ -f "/etc/config/$CONFIG" ]; then
        backup_file "/etc/config/$CONFIG" "config/$CONFIG"
    fi
}

# 备份 crontab
backup_crontab()
{
    if [ ! -e "$BACKUP_ORIGINAL/crontab" ]; then
        crontab -l > "$BACKUP_ORIGINAL/crontab" 2>/dev/null
    fi
}

# 备份 rc.d 相关软链接（记录链接名和目标）
backup_rcd_links()
{
    if [ ! -e "$BACKUP_ORIGINAL/rcd_links.txt" ]; then
        for link in /etc/rc.d/S*jdcbox* /etc/rc.d/S*jdcloudbi* \
                    /etc/rc.d/S*jdc_evtreport* /etc/rc.d/S*webdav* \
                    /etc/rc.d/S*dlspeed* /etc/rc.d/S*jdc_agent* \
                    /etc/rc.d/S*jdcapp_rpc* /etc/rc.d/S*jdcweb_rpc* \
                    /etc/rc.d/S*jdc_ezmesh* /etc/rc.d/S*jdc_flow* \
                    /etc/rc.d/S*dropbear*; do
            if [ -L "$link" ]; then
                TARGET=$(readlink "$link")
                echo "$link|$TARGET" >> "$BACKUP_ORIGINAL/rcd_links.txt"
            fi
        done
    fi
}

# 初始化备份目录（幂等）
init_backup()
{
    mkdir -p "$BACKUP_ORIGINAL"
    mkdir -p "$BACKUP_DELETED"
    mkdir -p "$BACKUP_CONFIG"

    if [ ! -e "$BACKUP_DIR/created" ]; then
        date > "$BACKUP_DIR/created"
        log "首次运行，备份目录已创建: $BACKUP_DIR"
    fi

    # 备份关键文件（首次才备份）
    backup_file /etc/rc.local "rc.local"
    backup_file /etc/hosts "hosts"
    backup_file /etc/opkg.conf "opkg.conf"
    backup_uci jd_clock
    backup_uci jd_product
    backup_uci jd_plugin
    backup_uci dhcp
    backup_crontab
    backup_rcd_links
}

# ============================================================
# 服务定义
# ============================================================
PCDN_SERVICES="jdcbox jdc_evtreport"
PCDN_PROGRAMS="/opt/jdc_node/jdc_node.sh /opt/jdc_node/jdc_node /opt/jdc_snake/snake.sh /opt/jdc_plugin_arg/jdc_plugin_arg"
OTHER_SERVICES="webdav dlspeed"
OTHER_PROGRAMS="/sbin/jdc_logbackup /etc/webdav.sh /opt/diagnosis_tools/diagnosis_tools.sh /opt/alchemist/alchemist /opt/dlspeed_rt/dlMonitor /usr/sbin/speedtest"
DELETE_FILES="/sbin/jd_online_upgrade.sh"

# ============================================================
# 清理函数
# ============================================================

stop_and_disable_service()
{
    SVC="$1"
    if [ -f "/etc/init.d/$SVC" ]; then
        /etc/init.d/$SVC stop 2>/dev/null
        /etc/init.d/$SVC disable 2>/dev/null
        log "已停止并禁用: $SVC"
    fi
}

remove_rcd_links()
{
    for pattern in "$@"; do
        rm -f /etc/rc.d/S*${pattern}* 2>/dev/null
    done
    log "已清理 rc.d 软链接"
}

disable_pcdn()
{
    echo ""
    echo "[禁用 PCDN / 积分服务]"

    for svc in $PCDN_SERVICES; do
        stop_and_disable_service "$svc"
        backup_and_chmod "/etc/init.d/$svc"
    done

    for prog in $PCDN_PROGRAMS; do
        if [ -e "$prog" ]; then
            pid=$(pgrep -f "$(basename "$prog")" 2>/dev/null)
            [ -n "$pid" ] && kill -9 $pid 2>/dev/null
            backup_and_chmod "$prog"
            log "已禁用: $prog"
        fi
    done

    remove_rcd_links jdcbox jdc_evtreport
    echo "  PCDN / 积分服务已禁用"
}

disable_other_services()
{
    echo ""
    echo "[禁用其他后台服务]"

    for svc in $OTHER_SERVICES; do
        stop_and_disable_service "$svc"
        backup_and_chmod "/etc/init.d/$svc"
    done

    for prog in $OTHER_PROGRAMS; do
        if [ -e "$prog" ]; then
            backup_and_chmod "$prog"
        fi
    done

    remove_rcd_links webdav dlspeed
    echo "  其他后台服务已禁用"
}

delete_upgrade_script()
{
    echo ""
    echo "[删除升级脚本]"
    for f in $DELETE_FILES; do
        backup_and_delete "$f"
    done
    echo "  升级脚本已删除"
}

clean_uci_upgrade()
{
    echo ""
    echo "[清理 UCI 升级配置]"

    # 关闭插件自动升级
    for p in $(uci show jd_plugin 2>/dev/null | grep '\.upgrade=' | cut -d= -f1); do
        uci set "$p"='0' 2>/dev/null
    done
    uci commit jd_plugin 2>/dev/null

    # 彻底删除升级 section
    uci delete jd_product.upgrade 2>/dev/null
    uci delete jd_clock.upgrade_plan 2>/dev/null
    uci commit jd_product 2>/dev/null
    uci commit jd_clock 2>/dev/null

    echo "  UCI 升级配置已清理"
}

clean_crontab()
{
    echo ""
    echo "[清理 crontab]"

    REMOVE_PATTERNS="webdav.sh|dlMonitor|diagnosis_tools|speedtest|jdc_logbackup|jd_online_upgrade"
    crontab -l 2>/dev/null | grep -vE "$REMOVE_PATTERNS" | grep -v 'jd_boot_guard' | crontab -

    echo "  crontab 已清理"
}

enable_dns_block()
{
    echo ""
    echo "[DNS 封锁]"

    cat > "$MYHOSTS" << 'EOF'
127.0.0.1 pidrouter-public.jdcloud.com
127.0.0.1 pidrouter-public-v6.jdcloud.com
127.0.0.1 terosaurs.jdcloud.com
127.0.0.1 jdbox-arthur.jdcloud.com
EOF

    # 方式1：通过 addnhosts 加到 dnsmasq（通用方式）
    uci del_list dhcp.@dnsmasq[0].addnhosts="$MYHOSTS" 2>/dev/null
    uci add_list dhcp.@dnsmasq[0].addnhosts="$MYHOSTS" 2>/dev/null
    uci commit dhcp 2>/dev/null

    # 方式2：用 ROM 纯净 hosts 覆盖（防止原厂 hosts 硬编码解析）
    if [ -f /rom/etc/hosts ]; then
        cp -f /rom/etc/hosts /etc/hosts
    fi

    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    echo "  DNS 封锁已开启（4 个域名）"
}

disable_dns_block()
{
    echo ""
    echo "[关闭 DNS 封锁]"

    uci del_list dhcp.@dnsmasq[0].addnhosts="$MYHOSTS" 2>/dev/null
    uci commit dhcp 2>/dev/null
    rm -f "$MYHOSTS"

    if [ -f "$BACKUP_ORIGINAL/hosts" ]; then
        cp -f "$BACKUP_ORIGINAL/hosts" /etc/hosts
    fi

    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    echo "  DNS 封锁已关闭"
}

# ============================================================
# SSH (Dropbear) 安装 / 卸载
# ============================================================
install_ssh()
{
    echo ""
    echo "=============================================="
    echo "       安装 Dropbear SSH"
    echo "=============================================="
    echo ""

    # 检查是否已安装
    if [ -f /usr/sbin/dropbear ] && [ -f /etc/init.d/dropbear ]; then
        if netstat -tlnp 2>/dev/null | grep -q ":${SSH_PORT} "; then
            echo "  SSH 已安装并在运行中，无需重复安装。"
            echo "  端口：$SSH_PORT"
            echo "  地址：$(ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 || echo '路由器IP')"
            pause
            return
        fi
    fi

    echo "将执行以下操作："
    echo "  1. 环境检查（musl libc / curl）"
    echo "  2. 关闭 opkg 签名校验"
    echo "  3. 下载 dropbear（LEDE 17.01.6 / arm_cortex-a53）"
    echo "  4. 安装 dropbear"
    echo "  5. 创建 musl 解释器软链接"
    echo "  6. 生成 RSA 主机密钥"
    echo "  7. 配置 init 脚本 + 开机自启 + 启动"
    echo ""
    printf "确定继续？输入 YES："
    read confirm
    if [ "$confirm" != "YES" ]; then
        echo "已取消。"
        return
    fi

    echo ""

    # 1. 环境检查
    echo "[1/7] 环境检查"
    if [ ! -f /lib/ld-musl-arm.so.1 ]; then
        echo "  错误：未检测到 musl libc，此脚本仅适用于京东云原厂固件！"
        pause
        return
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "  错误：未找到 curl 命令"
        pause
        return
    fi
    echo "  环境检查通过"

    # 2. 关闭 opkg 签名校验
    echo "[2/7] 关闭 opkg 签名校验"
    if grep -q '^option check_signature 1' /etc/opkg.conf 2>/dev/null; then
        sed -i 's/^option check_signature 1/option check_signature 0/' /etc/opkg.conf
        echo "  已关闭签名校验"
    else
        echo "  签名校验已关闭或无需修改"
    fi

    # 3. 下载 dropbear
    echo "[3/7] 下载 dropbear"
    if [ -f "$DROPBEAR_IPK" ]; then
        rm -f "$DROPBEAR_IPK"
    fi
    curl -k -L -o "$DROPBEAR_IPK" "$DROPBEAR_URL" 2>/dev/null
    if [ ! -s "$DROPBEAR_IPK" ]; then
        echo "  错误：下载失败，请检查网络连接"
        pause
        return
    fi
    FILE_SIZE=$(wc -c < "$DROPBEAR_IPK")
    if [ "$FILE_SIZE" -lt 10000 ]; then
        echo "  错误：下载文件过小（${FILE_SIZE} bytes），可能下载失败"
        pause
        return
    fi
    echo "  下载完成：${FILE_SIZE} bytes"

    # 4. 安装 dropbear
    echo "[4/7] 安装 dropbear"
    opkg --add-arch arm_cortex-a53_neon-vfpv4:10 -d root install --force-depends "$DROPBEAR_IPK" > /tmp/dropbear_install.log 2>&1
    if [ ! -f /usr/sbin/dropbear ]; then
        echo "  错误：安装失败，查看 /tmp/dropbear_install.log"
        tail -10 /tmp/dropbear_install.log
        pause
        return
    fi
    echo "  dropbear 二进制已安装"

    # 5. 创建 musl 解释器软链接
    echo "[5/7] 创建 musl 解释器软链接"
    if [ -e /lib/ld-musl-armhf.so.1 ]; then
        echo "  软链接已存在"
    else
        ln -s /lib/ld-musl-arm.so.1 /lib/ld-musl-armhf.so.1
        echo "  已创建 /lib/ld-musl-armhf.so.1 -> /lib/ld-musl-arm.so.1"
    fi

    # 验证 dropbear 可执行
    DROPBEAR_VER=$(dropbear -V 2>&1)
    if [ $? -ne 0 ]; then
        echo "  错误：dropbear 无法运行：$DROPBEAR_VER"
        pause
        return
    fi
    echo "  $DROPBEAR_VER"

    # 6. 清理空密钥 + 生成 RSA 主机密钥
    echo "[6/7] 生成 RSA 主机密钥"
    mkdir -p /etc/dropbear

    # 清理 opkg 留下的 0 字节空密钥占位文件
    for keyfile in /etc/dropbear/dropbear_*_host_key; do
        if [ -f "$keyfile" ]; then
            KEY_SIZE=$(wc -c < "$keyfile" 2>/dev/null || echo 0)
            if [ "$KEY_SIZE" -eq 0 ]; then
                rm -f "$keyfile"
            fi
        fi
    done

    # 生成 RSA 密钥
    if [ ! -f "$DROPBEAR_KEY" ] || [ ! -s "$DROPBEAR_KEY" ]; then
        dropbearkey -t rsa -f "$DROPBEAR_KEY" > /tmp/dropbear_keygen.log 2>&1
        if [ ! -f "$DROPBEAR_KEY" ] || [ ! -s "$DROPBEAR_KEY" ]; then
            echo "  错误：密钥生成失败"
            cat /tmp/dropbear_keygen.log
            pause
            return
        fi
    fi
    KEY_SIZE=$(wc -c < "$DROPBEAR_KEY")
    echo "  RSA 密钥已就绪（${KEY_SIZE} bytes）"

    # 7. 配置 init 脚本 + 开机自启 + 启动
    echo "[7/7] 配置开机自启并启动服务"

    cat > /etc/init.d/dropbear << 'INITEOF'
#!/bin/sh /etc/rc.common
START=99

DROPBEAR_KEY="/etc/dropbear/dropbear_rsa_host_key"

start() {
    mkdir -p /etc/dropbear

    # 密钥自检：如果不存在或为 0 字节，重新生成
    if [ ! -f "$DROPBEAR_KEY" ] || [ ! -s "$DROPBEAR_KEY" ]; then
        rm -f "$DROPBEAR_KEY"
        dropbearkey -t rsa -f "$DROPBEAR_KEY" >/dev/null 2>&1
    fi

    # 用 -r 明确指定密钥文件启动
    /usr/sbin/dropbear -p 22 -B -r "$DROPBEAR_KEY"
}

stop() {
    killall dropbear 2>/dev/null
}

restart() {
    stop
    sleep 1
    start
}
INITEOF
    chmod +x /etc/init.d/dropbear

    # 注册开机自启
    /etc/init.d/dropbear enable
    if [ ! -L /etc/rc.d/S99dropbear ]; then
        ln -sf /etc/init.d/dropbear /etc/rc.d/S99dropbear
    fi

    # 启动
    killall dropbear 2>/dev/null
    sleep 1
    /etc/init.d/dropbear start
    sleep 2

    # 最终验证
    echo ""
    echo "=============================================="
    if netstat -tlnp 2>/dev/null | grep -q ":${SSH_PORT} "; then
        echo "  Dropbear SSH 安装成功并已启动！"
        echo ""
        echo "  SSH 地址：$(ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 || echo '路由器IP'):${SSH_PORT}"
        echo "  用户名：  root"
        echo ""
        echo "  【下一步】请手动执行以下命令设置密码："
        echo "    passwd root"
        echo "    ssh root@路由器IP   # 测试连接"
        echo "=============================================="
    else
        echo "  警告：启动失败，端口 ${SSH_PORT} 未监听"
        echo "  排查命令："
        echo "    /usr/sbin/dropbear -p 22 -B -E -r $DROPBEAR_KEY  # 前台启动看错误"
        echo "=============================================="
    fi

    # 清理临时文件
    rm -f "$DROPBEAR_IPK" /tmp/dropbear_install.log /tmp/dropbear_keygen.log

    pause
}

uninstall_ssh()
{
    echo ""
    echo "=============================================="
    echo "       卸载 Dropbear SSH"
    echo "=============================================="
    echo ""

    if [ ! -f /usr/sbin/dropbear ] && [ ! -f /etc/init.d/dropbear ]; then
        echo "  SSH 未安装，无需卸载。"
        pause
        return
    fi

    echo "将执行以下操作："
    echo "  1. 停止 dropbear 服务"
    echo "  2. 禁用开机自启 + 删除 rc.d 链接"
    echo "  3. 删除 init 脚本和二进制"
    echo "  4. 删除密钥目录（可选保留）"
    echo ""
    printf "确定卸载？输入 UNINSTALL："
    read confirm
    if [ "$confirm" != "UNINSTALL" ]; then
        echo "已取消。"
        return
    fi

    echo ""

    # 停止服务
    if [ -f /etc/init.d/dropbear ]; then
        /etc/init.d/dropbear stop 2>/dev/null
        echo "  [1/4] 已停止 dropbear 服务"
    else
        killall dropbear 2>/dev/null
        echo "  [1/4] 已 kill dropbear 进程"
    fi

    # 禁用自启 + 删除链接
    if [ -f /etc/init.d/dropbear ]; then
        /etc/init.d/dropbear disable 2>/dev/null
    fi
    rm -f /etc/rc.d/S*dropbear 2>/dev/null
    echo "  [2/4] 已禁用开机自启"

    # 删除 init 脚本和二进制
    backup_and_delete /etc/init.d/dropbear
    if [ -f /usr/sbin/dropbear ]; then
        backup_and_delete /usr/sbin/dropbear
    fi
    if [ -f /usr/bin/dropbearkey ]; then
        backup_and_delete /usr/bin/dropbearkey
    fi
    if [ -f /usr/bin/dbclient ]; then
        backup_and_delete /usr/bin/dbclient
    fi
    echo "  [3/4] 已删除 init 脚本和二进制"

    # 询问是否保留密钥
    echo ""
    printf "是否保留 SSH 密钥目录 /etc/dropbear/？(y/n): "
    read keep_key
    if [ "$keep_key" = "n" ] || [ "$keep_key" = "N" ]; then
        if [ -d /etc/dropbear ]; then
            # 备份密钥后删除
            if [ -f "$DROPBEAR_KEY" ]; then
                backup_file "$DROPBEAR_KEY" "dropbear/dropbear_rsa_host_key"
            fi
            rm -rf /etc/dropbear
            echo "  [4/4] 已删除密钥目录（已备份）"
        fi
    else
        echo "  [4/4] 已保留密钥目录 /etc/dropbear/"
    fi

    # 恢复 opkg.conf（如果备份了）
    if [ -f "$BACKUP_ORIGINAL/opkg.conf" ]; then
        cp -f "$BACKUP_ORIGINAL/opkg.conf" /etc/opkg.conf
        echo "  已恢复 opkg.conf"
    fi

    echo ""
    echo "=============================================="
    echo " SSH 已卸载。"
    echo "=============================================="
    pause
}

# ============================================================
# Boot Guard 安装 / 卸载
# ============================================================
install_boot_guard()
{
    echo ""
    echo "[安装 Boot Guard 开机兜底 + 定时巡逻]"

    cat > "$BOOT_GUARD" << 'GUARDEOF'
#!/bin/sh
# 开机兜底 + 定时巡逻脚本
# 由 /etc/rc.local 开机调用 + crontab 每小时巡逻
# 执行时机：所有 S99 服务启动完毕后（含 jdc_agent 写 crontab）

logger -t jd_boot_guard "Starting boot guard..."

# === 1. 禁用 PCDN/积分服务（procd 管理的必须 stop+disable+chmod）===
for svc in jdcbox jdc_evtreport; do
    if [ -f /etc/init.d/$svc ]; then
        /etc/init.d/$svc stop 2>/dev/null
        /etc/init.d/$svc disable 2>/dev/null
        chmod -x /etc/init.d/$svc 2>/dev/null
    fi
done
for proc in jdc_node jdc_snake; do
    pid=$(pgrep -f "$proc")
    [ -n "$pid" ] && kill -9 $pid 2>/dev/null
done
chmod -x /opt/jdc_node/jdc_node.sh 2>/dev/null
chmod -x /opt/jdc_node/jdc_node 2>/dev/null
chmod -x /opt/jdc_snake/snake.sh 2>/dev/null
rm -f /etc/rc.d/S*jdcbox /etc/rc.d/S*jdc_evtreport 2>/dev/null

# === 2. 禁用 webdav 和 dlspeed（防 firewall 规则被冲）===
for svc in webdav dlspeed; do
    if [ -f /etc/init.d/$svc ]; then
        /etc/init.d/$svc stop 2>/dev/null
        /etc/init.d/$svc disable 2>/dev/null
        chmod -x /etc/init.d/$svc 2>/dev/null
    fi
done
rm -f /etc/rc.d/S*webdav /etc/rc.d/S*dlspeed 2>/dev/null

# === 3. 清理 crontab + 写回巡逻条目（闭环）===
REMOVE_PATTERNS="webdav.sh|dlMonitor|diagnosis_tools|speedtest|jdc_logbackup|jd_online_upgrade"
crontab -l 2>/dev/null | grep -vE "$REMOVE_PATTERNS" | grep -v 'jd_boot_guard' | crontab -
(crontab -l 2>/dev/null; echo "0 */1 * * * /sbin/jd_boot_guard.sh >/dev/null 2>&1") | crontab -

# === 4. 确保 DNS 封锁 ===
if ! grep -q "pidrouter-public" /etc/custom_hosts 2>/dev/null; then
    cat > /etc/custom_hosts << 'BLOCKEOF'
127.0.0.1 pidrouter-public.jdcloud.com
127.0.0.1 pidrouter-public-v6.jdcloud.com
127.0.0.1 terosaurs.jdcloud.com
127.0.0.1 jdbox-arthur.jdcloud.com
BLOCKEOF
fi
uci del_list dhcp.@dnsmasq[0].addnhosts="/etc/custom_hosts" 2>/dev/null
uci add_list dhcp.@dnsmasq[0].addnhosts="/etc/custom_hosts" 2>/dev/null
uci commit dhcp 2>/dev/null
if [ -f /rom/etc/hosts ]; then
    cp -f /rom/etc/hosts /etc/hosts
fi

# === 5. 确保 UCI 升级配置已关闭 ===
uci delete jd_product.upgrade 2>/dev/null
uci delete jd_clock.upgrade_plan 2>/dev/null
uci commit jd_product 2>/dev/null
uci commit jd_clock 2>/dev/null

# === 6. 极限模式：额外禁用全部京东基础服务（如果启用了极限模式）===
if [ -f /etc/jd_clean_backup/extreme_mode ]; then
    logger -t jd_boot_guard "Extreme mode enabled, disabling all JD services..."
    for svc in jdcloudbi jdc_agent; do
        if [ -f /etc/init.d/$svc ]; then
            /etc/init.d/$svc stop 2>/dev/null
            /etc/init.d/$svc disable 2>/dev/null
            chmod -x /etc/init.d/$svc 2>/dev/null
        fi
    done
    for prog in jdcloud_bi jdc_agent jdcapp_rpc jdcweb_rpc jdc_ezmesh jdc_flow; do
        pid=$(pidof "$prog" 2>/dev/null)
        [ -n "$pid" ] && kill -9 $pid 2>/dev/null
    done
    chmod -x /usr/sbin/jdcloud_bi /usr/sbin/jdc_agent /sbin/jdcapp_rpc /sbin/jdcweb_rpc /usr/sbin/jdc_ezmesh /usr/sbin/jdc_flow 2>/dev/null
    rm -f /etc/rc.d/S*jdcloudbi /etc/rc.d/S*jdc_agent /etc/rc.d/S*jdcapp_rpc /etc/rc.d/S*jdcweb_rpc /etc/rc.d/S*jdc_ezmesh /etc/rc.d/S*jdc_flow 2>/dev/null
fi

logger -t jd_boot_guard "Boot guard completed."
GUARDEOF

    chmod +x "$BOOT_GUARD"

    # 配置 rc.local（先移除旧行，再插入新行）
    sed -i '/jd_boot_guard/d; /^sleep 120$/d; /firewall restart/d; /dnsmasq restart/d' /etc/rc.local
    sed -i '/^exit 0/i sleep 120\n/sbin/jd_boot_guard.sh >/dev/null 2>&1\n/etc/init.d/firewall restart >/dev/null 2>&1\n/etc/init.d/dnsmasq restart >/dev/null 2>&1' /etc/rc.local

    # 立即执行一次
    "$BOOT_GUARD"
    /etc/init.d/firewall restart >/dev/null 2>&1
    /etc/init.d/dnsmasq restart >/dev/null 2>&1

    echo "  Boot Guard 已安装并执行"
}

uninstall_boot_guard()
{
    echo ""
    echo "[卸载 Boot Guard]"

    # 从 crontab 移除
    crontab -l 2>/dev/null | grep -v 'jd_boot_guard' | crontab -

    # 从 rc.local 移除
    sed -i '/jd_boot_guard/d; /^sleep 120$/d; /firewall restart/d; /dnsmasq restart/d' /etc/rc.local

    # 删除脚本
    rm -f "$BOOT_GUARD"

    echo "  Boot Guard 已卸载"
}

# ============================================================
# 推荐清理
# ============================================================
do_full_clean()
{
    echo ""
    echo "=============================================="
    echo "       正在执行：推荐清理"
    echo "=============================================="
    echo ""
    echo "将执行以下操作："
    echo "  1. 备份所有原始文件到 $BACKUP_DIR"
    echo "  2. 禁用 PCDN / 积分服务"
    echo "  3. 禁用其他后台服务（webdav / dlspeed 等）"
    echo "  4. 删除升级脚本"
    echo "  5. 清理 UCI 升级配置"
    echo "  6. 开启 DNS 封锁"
    echo "  7. 清理 crontab"
    echo "  8. 安装 Boot Guard（开机兜底 + 每小时巡逻）"
    echo ""
    printf "确定继续？输入 YES："
    read confirm
    if [ "$confirm" != "YES" ]; then
        echo "已取消。"
        return
    fi

    echo ""

    init_backup
    echo "  [1/8] 备份完成"

    disable_pcdn
    echo "  [2/8] PCDN 已禁用"

    disable_other_services
    echo "  [3/8] 其他后台服务已禁用"

    delete_upgrade_script
    echo "  [4/8] 升级脚本已删除"

    clean_uci_upgrade
    echo "  [5/8] UCI 升级配置已清理"

    enable_dns_block
    echo "  [6/8] DNS 封锁已开启"

    clean_crontab
    echo "  [7/8] crontab 已清理"

    install_boot_guard
    echo "  [8/8] Boot Guard 已安装"

    echo ""
    echo "=============================================="
    echo " 推荐清理完成！"
    echo "=============================================="
    echo ""
    echo "  PCDN / 积分：已禁用"
    echo "  自动升级：已关闭"
    echo "  DNS 封锁：已开启"
    echo "  crontab：已清理"
    echo "  Boot Guard：已安装（开机兜底 + 每小时巡逻）"
    echo "  所有原始文件已备份到 $BACKUP_DIR"
    echo ""
    echo " 建议：重启路由器后 2 分钟，用选项 4 查看状态确认"
}

# ============================================================
# 极限模式：禁用全部京东服务
# ============================================================
extreme_mode()
{
    echo ""
    echo "=============================================="
    echo "       极限模式：禁用全部京东服务"
    echo "=============================================="
    echo ""
    echo "⚠️  警告：此模式将在推荐清理基础上，额外禁用以下服务："
    echo ""
    echo "  基础服务（推荐模式保留的）："
    echo "    - jdcloud_bi  （基础服务 / LED 状态）"
    echo "    - jdc_agent    （代理 / APP 通信）"
    echo "    - jdcapp_rpc   （APP RPC 接口）"
    echo "    - jdcweb_rpc   （Web RPC 接口）"
    echo "    - jdc_ezmesh   （Mesh 组网）"
    echo "    - jdc_flow     （流量统计）"
    echo ""
    echo "可能导致的后果："
    echo "  - 京东云 APP 无法连接和管理路由器"
    echo "  - Web 管理页面部分功能异常"
    echo "  - Mesh 组网功能失效"
    echo "  - LED 状态灯可能异常"
    echo "  - 路由器部分基础功能可能受影响"
    echo ""
    echo "所有修改均会备份，可通过选项 5 完整恢复。"
    echo ""
    printf "确定继续？输入 EXTREME："
    read confirm
    if [ "$confirm" != "EXTREME" ]; then
        echo "已取消。"
        return
    fi

    echo ""
    echo "=== 第一步：执行推荐清理 ==="

    init_backup
    echo "  [1/8] 备份完成"
    disable_pcdn
    echo "  [2/8] PCDN 已禁用"
    disable_other_services
    echo "  [3/8] 其他后台服务已禁用"
    delete_upgrade_script
    echo "  [4/8] 升级脚本已删除"
    clean_uci_upgrade
    echo "  [5/8] UCI 升级配置已清理"
    enable_dns_block
    echo "  [6/8] DNS 封锁已开启"
    clean_crontab
    echo "  [7/8] crontab 已清理"
    install_boot_guard
    echo "  [8/8] Boot Guard 已安装"

    echo ""
    echo "=== 第二步：额外禁用全部京东基础服务 ==="

    # 禁用 init 管理的服务
    for svc in jdcloudbi jdc_agent; do
        if [ -f "/etc/init.d/$svc" ]; then
            /etc/init.d/$svc stop 2>/dev/null
            /etc/init.d/$svc disable 2>/dev/null
            backup_and_chmod "/etc/init.d/$svc"
            log "已停止并禁用: $svc"
        fi
    done

    # 禁用二进制程序（先 kill 再 chmod -x）
    for prog in \
        /usr/sbin/jdcloud_bi \
        /usr/sbin/jdc_agent \
        /sbin/jdcapp_rpc \
        /sbin/jdcweb_rpc \
        /usr/sbin/jdc_ezmesh \
        /usr/sbin/jdc_flow; do
        if [ -e "$prog" ]; then
            pid=$(pidof "$(basename "$prog")" 2>/dev/null)
            [ -n "$pid" ] && kill -9 $pid 2>/dev/null
            backup_and_chmod "$prog"
            log "已禁用: $prog"
        fi
    done

    # 删除 rc.d 自启链接
    remove_rcd_links jdcloudbi jdc_agent jdcapp_rpc jdcweb_rpc jdc_ezmesh jdc_flow

    # 创建极限模式标记文件
    touch "$BACKUP_DIR/extreme_mode"
    log "已创建极限模式标记: $BACKUP_DIR/extreme_mode"

    echo ""
    echo "=============================================="
    echo " 极限模式完成！"
    echo "=============================================="
    echo ""
    echo "  全部京东云相关服务已禁用"
    echo "  极限模式标记已创建，Boot Guard 将自动巡逻"
    echo "  所有原始文件已备份到 $BACKUP_DIR"
    echo ""
    echo " 如需恢复，使用选项 5 从备份恢复全部"
    echo " 建议：重启路由器后确认功能"
}

# ============================================================
# 恢复全部（从备份）
# ============================================================
restore_all()
{
    echo ""
    echo "=============================================="
    echo "         从备份恢复全部修改"
    echo "=============================================="
    echo ""
    echo "将恢复以下内容："
    echo "  - 卸载 Boot Guard"
    echo "  - /etc/rc.local"
    echo "  - /etc/hosts"
    echo "  - crontab"
    echo "  - UCI 配置（jd_clock / jd_product / jd_plugin / dhcp）"
    echo "  - 被删除的文件（升级脚本、SSH 等）"
    echo "  - 被 chmod -x 的文件权限"
    echo "  - rc.d 启动软链接"
    echo "  - opkg.conf"
    echo ""
    printf "确定恢复？输入 RESTORE："
    read confirm
    if [ "$confirm" != "RESTORE" ]; then
        echo "已取消。"
        return
    fi

    if [ ! -d "$BACKUP_ORIGINAL" ]; then
        echo "错误：未找到备份目录 $BACKUP_ORIGINAL"
        return
    fi

    echo ""

    # 1. 卸载 Boot Guard
    uninstall_boot_guard

    # 删除极限模式标记
    rm -f "$BACKUP_DIR/extreme_mode"
    echo "  已删除极限模式标记"

    # 2. 恢复 rc.local
    if [ -f "$BACKUP_ORIGINAL/rc.local" ]; then
        cp -f "$BACKUP_ORIGINAL/rc.local" /etc/rc.local
        chmod +x /etc/rc.local
        echo "  [1/9] 已恢复 /etc/rc.local"
    else
        echo "  [1/9] 跳过 rc.local（无备份）"
    fi

    # 3. 恢复 /etc/hosts
    if [ -f "$BACKUP_ORIGINAL/hosts" ]; then
        cp -f "$BACKUP_ORIGINAL/hosts" /etc/hosts
        echo "  [2/9] 已恢复 /etc/hosts"
    else
        echo "  [2/9] 跳过 hosts（无备份）"
    fi

    # 4. 恢复 crontab
    if [ -f "$BACKUP_ORIGINAL/crontab" ]; then
        crontab "$BACKUP_ORIGINAL/crontab"
        echo "  [3/9] 已恢复 crontab"
    else
        echo "  [3/9] 跳过 crontab（无备份）"
    fi

    # 5. 恢复 UCI 配置
    for cfg in jd_clock jd_product jd_plugin dhcp; do
        if [ -f "$BACKUP_ORIGINAL/config/$cfg" ]; then
            cp -f "$BACKUP_ORIGINAL/config/$cfg" "/etc/config/$cfg"
            uci commit "$cfg" 2>/dev/null
        fi
    done
    echo "  [4/9] 已恢复 UCI 配置"

    # 6. 恢复 opkg.conf
    if [ -f "$BACKUP_ORIGINAL/opkg.conf" ]; then
        cp -f "$BACKUP_ORIGINAL/opkg.conf" /etc/opkg.conf
        echo "  [5/9] 已恢复 opkg.conf"
    else
        echo "  [5/9] 跳过 opkg.conf（无备份）"
    fi

    # 7. 恢复被删除的文件（保持原始目录结构）
    if [ -d "$BACKUP_DELETED" ]; then
        find "$BACKUP_DELETED" -type f 2>/dev/null | while read f; do
            ORIG_PATH="${f#$BACKUP_DELETED}"
            mkdir -p "$(dirname "$ORIG_PATH")"
            cp -a "$f" "$ORIG_PATH"
            chmod +x "$ORIG_PATH" 2>/dev/null
            echo "    已恢复: $ORIG_PATH"
        done
    fi
    echo "  [6/9] 已恢复被删除的文件"

    # 8. 恢复被 chmod -x 的文件权限
    if [ -f "$BACKUP_ORIGINAL/chmod_record.txt" ]; then
        while IFS='|' read -r FILE PERM; do
            if [ -e "$FILE" ] && [ -n "$PERM" ]; then
                chmod "$PERM" "$FILE" 2>/dev/null
            fi
        done < "$BACKUP_ORIGINAL/chmod_record.txt"
    fi
    echo "  [7/9] 已恢复文件权限"

    # 9. 恢复 rc.d 软链接
    if [ -f "$BACKUP_ORIGINAL/rcd_links.txt" ]; then
        while IFS='|' read -r LINK TARGET; do
            if [ -n "$LINK" ] && [ -n "$TARGET" ]; then
                mkdir -p "$(dirname "$LINK")"
                ln -sf "$TARGET" "$LINK" 2>/dev/null
            fi
        done < "$BACKUP_ORIGINAL/rcd_links.txt"
    fi
    echo "  [8/9] 已恢复 rc.d 软链接"

    # 重新 enable 服务
    for svc in jdcbox jdc_evtreport webdav dlspeed jdc_agent dropbear; do
        if [ -f "/etc/init.d/$svc" ]; then
            /etc/init.d/$svc enable 2>/dev/null
        fi
    done

    # 重启 firewall/dnsmasq
    /etc/init.d/firewall restart >/dev/null 2>&1
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    echo "  [9/9] 已重启 firewall/dnsmasq"

    echo ""
    echo "=============================================="
    echo " 恢复完成！建议重启路由器。"
    echo "=============================================="
}

# ============================================================
# 状态查看
# ============================================================
show_status()
{
    echo ""
    echo "=============================================="
    echo "                 当前状态"
    echo "=============================================="
    echo ""

    echo "----- 进程 -----"
    for proc in jdcloud_bi jdc_agent jdcapp_rpc jdcweb_rpc jdc_ezmesh jdc_flow jdcbox jdc_node jdc_snake webdav dlspeed dropbear; do
        if pidof "$proc" >/dev/null 2>&1; then
            echo "  [运行] $proc"
        else
            echo "  [停止] $proc"
        fi
    done

    echo ""
    echo "----- 服务启动状态 -----"
    for svc in jdcloudbi jdcbox jdc_evtreport jdc_agent webdav dlspeed dropbear; do
        if [ -f "/etc/init.d/$svc" ]; then
            if /etc/init.d/$svc enabled 2>/dev/null; then
                echo "  [enabled]  $svc"
            else
                echo "  [disabled] $svc"
            fi
        fi
    done

    echo ""
    echo "----- SSH (Dropbear) -----"
    if [ -f /usr/sbin/dropbear ]; then
        echo "  状态：已安装"
        if netstat -tlnp 2>/dev/null | grep -q ":${SSH_PORT} "; then
            echo "  端口：$SSH_PORT（监听中）"
            echo "  地址：$(ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 || echo '路由器IP')"
        else
            echo "  端口：$SSH_PORT（未监听）"
        fi
        if [ -f "$DROPBEAR_KEY" ] && [ -s "$DROPBEAR_KEY" ]; then
            echo "  密钥：已生成（$(wc -c < "$DROPBEAR_KEY") bytes）"
        else
            echo "  密钥：未生成或为空"
        fi
    else
        echo "  状态：未安装"
    fi

    echo ""
    echo "----- DNS 封锁 -----"
    if [ -f "$MYHOSTS" ]; then
        echo "  状态：开启"
        cat "$MYHOSTS" | sed 's/^/    /'
    else
        echo "  状态：关闭"
    fi

    echo ""
    echo "----- Boot Guard -----"
    if [ -f "$BOOT_GUARD" ]; then
        echo "  状态：已安装"
        if crontab -l 2>/dev/null | grep -q 'jd_boot_guard'; then
            echo "  巡逻：已启用（每小时）"
        else
            echo "  巡逻：未启用"
        fi
        if grep -q 'jd_boot_guard' /etc/rc.local 2>/dev/null; then
            echo "  开机自启：已配置"
        else
            echo "  开机自启：未配置"
        fi
    else
        echo "  状态：未安装"
    fi

    echo ""
    echo "----- 自动升级 -----"
    VAL=$(uci get jd_clock.upgrade_plan.enable 2>/dev/null)
    if [ -n "$VAL" ]; then
        echo "  jd_clock.upgrade_plan.enable: $VAL"
    else
        echo "  jd_clock: 无 upgrade_plan（已删除）"
    fi
    VAL=$(uci get jd_product.upgrade.fu 2>/dev/null)
    if [ -n "$VAL" ]; then
        echo "  jd_product.upgrade.fu: $VAL"
    else
        echo "  jd_product: 无 upgrade（已删除）"
    fi

    echo ""
    echo "----- crontab -----"
    crontab -l 2>/dev/null || echo "  无 crontab 条目"

    echo ""
    echo "----- 备份状态 -----"
    if [ -d "$BACKUP_DIR" ]; then
        echo "  备份目录：$BACKUP_DIR"
        echo "  创建时间：$(cat "$BACKUP_DIR/created" 2>/dev/null || echo '未知')"
        echo "  备份文件数：$(find "$BACKUP_ORIGINAL" -type f 2>/dev/null | wc -l)"
        if [ -f "$BACKUP_DIR/extreme_mode" ]; then
            echo "  极限模式：已启用"
        fi
    else
        echo "  无备份"
    fi
}

# ============================================================
# 自定义工具子菜单（合并原 2/3/4/5）
# ============================================================
custom_menu()
{
    while true; do
        header
        echo "自定义工具："
        echo ""
        echo "  1. 仅禁用 PCDN / 积分及后台服务"
        echo ""
        echo "  2. DNS 封锁管理"
        echo ""
        echo "  3. 自动升级管理"
        echo ""
        echo "  4. Boot Guard 管理"
        echo ""
        echo "  5. 返回主菜单"
        echo ""
        printf "请选择："
        read c
        case "$c" in
            1)
                init_backup
                disable_pcdn
                disable_other_services
                pause
                ;;
            2) dns_submenu ;;
            3) upgrade_submenu ;;
            4) bootguard_submenu ;;
            5) return ;;
        esac
    done
}

dns_submenu()
{
    while true; do
        header
        echo "DNS 封锁管理："
        echo ""
        echo "  1. 开启 DNS 封锁"
        echo "  2. 关闭 DNS 封锁"
        echo "  3. 返回"
        echo ""
        printf "请选择："
        read c
        case "$c" in
            1) init_backup; enable_dns_block; pause ;;
            2) disable_dns_block; pause ;;
            3) return ;;
        esac
    done
}

upgrade_submenu()
{
    while true; do
        header
        echo "自动升级管理："
        echo ""
        echo "  1. 关闭自动升级（彻底删除配置 + 删脚本）"
        echo "  2. 恢复自动升级（从备份）"
        echo "  3. 返回"
        echo ""
        printf "请选择："
        read c
        case "$c" in
            1)
                init_backup
                clean_uci_upgrade
                delete_upgrade_script
                pause
                ;;
            2)
                if [ -f "$BACKUP_ORIGINAL/config/jd_clock" ]; then
                    cp -f "$BACKUP_ORIGINAL/config/jd_clock" /etc/config/jd_clock
                    uci commit jd_clock 2>/dev/null
                fi
                if [ -f "$BACKUP_ORIGINAL/config/jd_product" ]; then
                    cp -f "$BACKUP_ORIGINAL/config/jd_product" /etc/config/jd_product
                    uci commit jd_product 2>/dev/null
                fi
                if [ -f "$BACKUP_DELETED/sbin/jd_online_upgrade.sh" ]; then
                    cp -a "$BACKUP_DELETED/sbin/jd_online_upgrade.sh" /sbin/jd_online_upgrade.sh
                    chmod +x /sbin/jd_online_upgrade.sh
                fi
                echo "  自动升级已恢复"
                pause
                ;;
            3) return ;;
        esac
    done
}

bootguard_submenu()
{
    while true; do
        header
        echo "Boot Guard 管理："
        echo ""
        echo "  1. 安装 Boot Guard（开机兜底 + 每小时巡逻）"
        echo "  2. 卸载 Boot Guard"
        echo "  3. 立即执行一次 Boot Guard"
        echo "  4. 返回"
        echo ""
        printf "请选择："
        read c
        case "$c" in
            1) init_backup; install_boot_guard; pause ;;
            2) uninstall_boot_guard; pause ;;
            3)
                if [ -f "$BOOT_GUARD" ]; then
                    "$BOOT_GUARD"
                    /etc/init.d/firewall restart >/dev/null 2>&1
                    /etc/init.d/dnsmasq restart >/dev/null 2>&1
                    echo "  已执行 Boot Guard"
                else
                    echo "  Boot Guard 未安装，请先安装"
                fi
                pause
                ;;
            4) return ;;
        esac
    done
}

ssh_submenu()
{
    while true; do
        header
        echo "SSH (Dropbear) 管理："
        echo ""
        echo "  1. 安装 SSH"
        echo "  2. 卸载 SSH"
        echo "  3. 重启 SSH 服务"
        echo "  4. 返回"
        echo ""
        printf "请选择："
        read c
        case "$c" in
            1) init_backup; install_ssh ;;
            2) uninstall_ssh ;;
            3)
                if [ -f /etc/init.d/dropbear ]; then
                    /etc/init.d/dropbear restart
                    sleep 1
                    if netstat -tlnp 2>/dev/null | grep -q ":${SSH_PORT} "; then
                        echo "  SSH 已重启，端口 $SSH_PORT 监听中"
                    else
                        echo "  SSH 重启后端口未监听，请检查"
                    fi
                else
                    echo "  SSH 未安装，请先安装"
                fi
                pause
                ;;
            4) return ;;
        esac
    done
}

# ============================================================
# 主菜单
# ============================================================
menu()
{
    while true; do
        header
        echo "  1. 推荐清理"
        echo "     备份 + 禁用 PCDN + 清理升级 + DNS 封锁"
        echo "     + 清理 crontab + 安装 Boot Guard"
        echo "     （保留 APP / Web / Mesh / LED 基础功能）"
        echo ""
        echo "  2. 自定义工具"
        echo "     PCDN / DNS / 升级 / Boot Guard 单项操作"
        echo ""
        echo "  3. SSH (Dropbear) 管理"
        echo "     安装 / 卸载 / 重启 SSH 服务"
        echo ""
        echo "  4. 查看当前状态"
        echo ""
        echo "  5. 从备份恢复全部"
        echo ""
        echo "  6. 极限模式：禁用全部京东服务"
        echo "     ⚠️  APP / Web / Mesh / LED 可能全部失效"
        echo ""
        echo "  7. 退出"
        echo ""
        printf "请选择 [1-7]: "
        read choice
        case "$choice" in
            1)
                do_full_clean
                pause
                ;;
            2) custom_menu ;;
            3) ssh_submenu ;;
            4)
                show_status
                pause
                ;;
            5)
                restore_all
                pause
                ;;
            6)
                extreme_mode
                pause
                ;;
            7)
                echo ""
                echo "退出。"
                exit 0
                ;;
            *)
                echo ""
                echo "无效选择。"
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# 主程序
# ============================================================
if [ "$(id -u 2>/dev/null)" != "0" ]; then
    echo "错误：请使用 root 运行。"
    exit 1
fi

menu
