#!/bin/sh
# =====================================================
# 京东云 AX1800 Pro / AX6600 一键优化脚本
#
# 功能：
#   1. 保留 jdcloud_bi，确保 LED / 京东云状态正常
#   2. 保留手机 APP / Web 管理相关服务
#   3. 禁用 PCDN / 积分相关服务
#   4. 禁用部分后台统计、测速、诊断等服务
#   5. DNS 封锁京东云相关 PCDN 域名
#   6. 禁止自动升级
#   7. 开机自动执行 boot guard
#   8. 每小时巡逻，防止被京东云服务重新拉起
#
# 使用：
#   sh jd_full_optimize.sh
#
# 手机 APP：
#   默认保留 jdc_agent / jdcapp_rpcd
# =====================================================

echo "========================================="
echo " 京东云 AX1800 Pro / AX6600 优化脚本"
echo "========================================="


# =====================================================
# 0. 备份
# =====================================================

echo "[0/7] 创建配置备份..."

BACKUP_DIR="/etc/jd_optimize_backup"
mkdir -p "$BACKUP_DIR"

cp -f /etc/rc.local "$BACKUP_DIR/rc.local.bak" 2>/dev/null
cp -f /etc/config/dhcp "$BACKUP_DIR/dhcp.bak" 2>/dev/null
cp -f /etc/config/jd_clock "$BACKUP_DIR/jd_clock.bak" 2>/dev/null
cp -f /etc/config/jd_product "$BACKUP_DIR/jd_product.bak" 2>/dev/null

echo "  备份目录：$BACKUP_DIR"


# =====================================================
# 1. DNS 封锁
# =====================================================

echo "[1/7] 配置 DNS 封锁..."

cat > /etc/myhosts << 'BLOCKEOF'
127.0.0.1 pidrouter-public.jdcloud.com
127.0.0.1 pidrouter-public-v6.jdcloud.com
127.0.0.1 terosaurs.jdcloud.com
127.0.0.1 jdbox-arthur.jdcloud.com
BLOCKEOF

# 防止重复添加
uci del_list dhcp.@dnsmasq[0].addnhosts='/etc/myhosts' 2>/dev/null
uci add_list dhcp.@dnsmasq[0].addnhosts='/etc/myhosts'
uci commit dhcp

echo "  DNS 封锁已配置"


# =====================================================
# 2. 禁用 PCDN / 积分相关服务
# =====================================================

echo "[2/7] 禁用 PCDN / 积分服务..."

# -----------------------------------------------------
# procd 管理服务：必须 stop + disable
# -----------------------------------------------------

for svc in jdcbox jdc_evtreport; do

    if [ -x "/etc/init.d/$svc" ]; then
        /etc/init.d/$svc stop 2>/dev/null
        /etc/init.d/$svc disable 2>/dev/null
        echo "  已禁用：$svc"
    fi

done


# -----------------------------------------------------
# 非 procd 进程
# -----------------------------------------------------

for proc in jdc_node jdc_snake; do

    pid=$(pgrep -f "$proc" 2>/dev/null)

    if [ -n "$pid" ]; then
        kill -9 $pid 2>/dev/null
        echo "  已停止进程：$proc"
    fi

done


# -----------------------------------------------------
# 防止这些程序自行启动
# -----------------------------------------------------

chmod -x /etc/init.d/jdcbox 2>/dev/null
chmod -x /etc/init.d/jdc_evtreport 2>/dev/null

chmod -x /etc/init.d/jdcbox 2>/dev/null
chmod -x /etc/jdcbox/jdcbox.sh 2>/dev/null
chmod -x /opt/jdcbox/jdcbox 2>/dev/null

chmod -x /opt/jdc_node/jdc_node.sh 2>/dev/null
chmod -x /opt/jdc_node/jdc_node 2>/dev/null

chmod -x /opt/jdc_plugin_arg/jdc_plugin_arg 2>/dev/null
chmod -x /opt/jdc_snake/snake.sh 2>/dev/null

# 清理可能残留的启动链接
rm -f /etc/rc.d/S*jdcbox 2>/dev/null
rm -f /etc/rc.d/S*jdcloudbi 2>/dev/null
rm -f /etc/rc.d/S*jdc_evtreport 2>/dev/null

echo "  PCDN / 积分服务已处理"


# =====================================================
# 3. 保留 jdcloud_bi + APP / Web 相关服务
# =====================================================

echo "[3/7] 保留京东云状态及 APP 服务..."

# -----------------------------------------------------
# jdcloud_bi 是必须保留的
# 它负责京东云状态以及 LED 状态相关功能
# -----------------------------------------------------

chmod +x /usr/sbin/jdcloud_bi 2>/dev/null

echo "  保留：jdcloud_bi"


# -----------------------------------------------------
# APP / Web / Mesh
# -----------------------------------------------------

chmod +x /usr/sbin/jdc_agent 2>/dev/null
chmod +x /sbin/jdcapp_rpc 2>/dev/null
chmod +x /sbin/jdcweb_rpc 2>/dev/null
chmod +x /usr/sbin/jdc_ezmesh 2>/dev/null

echo "  保留：jdc_agent"
echo "  保留：jdcapp_rpc"
echo "  保留：jdcweb_rpc"
echo "  保留：jdc_ezmesh"


# -----------------------------------------------------
# jdc_flow 保留
# -----------------------------------------------------

chmod +x /usr/sbin/jdc_flow 2>/dev/null


# =====================================================
# 4. 禁用其它不需要的后台服务
# =====================================================

echo "[4/7] 禁用其它后台服务..."

# webdav
if [ -x /etc/init.d/webdav ]; then
    /etc/init.d/webdav stop 2>/dev/null
    /etc/init.d/webdav disable 2>/dev/null
fi

chmod -x /etc/init.d/webdav 2>/dev/null
rm -f /etc/rc.d/S*webdav 2>/dev/null


# dlspeed
if [ -x /etc/init.d/dlspeed ]; then
    /etc/init.d/dlspeed stop 2>/dev/null
    /etc/init.d/dlspeed disable 2>/dev/null
fi

chmod -x /etc/init.d/dlspeed 2>/dev/null
rm -f /etc/rc.d/S*dlspeed 2>/dev/null


# 其它后台工具
chmod -x /sbin/jdc_logbackup 2>/dev/null
chmod -x /etc/webdav.sh 2>/dev/null
chmod -x /sbin/jd_online_upgrade.sh 2>/dev/null
chmod -x /opt/diagnosis_tools/diagnosis_tools.sh 2>/dev/null

chmod -x /opt/alchemist/alchemist 2>/dev/null
chmod -x /opt/dlspeed_rt/dlMonitor 2>/dev/null
chmod -x /usr/sbin/speedtest 2>/dev/null

echo "  后台服务已处理"


# =====================================================
# 5. 禁止自动升级
# =====================================================

echo "[5/7] 禁止自动升级..."

# 不删除整个配置，仅关闭功能
uci set jd_clock.upgrade_plan.enable=0 2>/dev/null
uci set jd_product.upgrade.fu=0 2>/dev/null

uci commit jd_clock 2>/dev/null
uci commit jd_product 2>/dev/null

# 插件自动升级全部关闭
for p in $(uci show jd_plugin 2>/dev/null | grep '\.upgrade=' | cut -d= -f1); do
    uci set "$p"='0' 2>/dev/null
done

uci commit jd_plugin 2>/dev/null

# 删除在线升级脚本
rm -f /sbin/jd_online_upgrade.sh 2>/dev/null

echo "  自动升级已关闭"


# =====================================================
# 6. 创建 boot guard
# =====================================================

echo "[6/7] 创建 jd_boot_guard.sh..."

cat > /sbin/jd_boot_guard.sh << 'GUARDSCRIPT'
#!/bin/sh

# =====================================================
# 京东云 boot guard
#
# 每小时巡逻一次：
#   - 确保 PCDN / 积分服务关闭
#   - 清理相关 crontab
#   - 确保 DNS 封锁
#   - 确保升级关闭
#   - 确保 jdcloud_bi 正常运行
#
# 注意：
#   jdcloud_bi 是刻意保留的服务
#   不得 stop / disable / kill
# =====================================================

logger -t jd_boot_guard "Starting..."


# =====================================================
# 1. 禁止 PCDN / 积分服务
# =====================================================

for svc in jdcbox jdc_evtreport; do

    if [ -f "/etc/init.d/$svc" ]; then
        /etc/init.d/$svc stop 2>/dev/null
        /etc/init.d/$svc disable 2>/dev/null
    fi

done


# 非 procd 进程
for proc in jdc_node jdc_snake; do

    pid=$(pgrep -f "$proc" 2>/dev/null)

    if [ -n "$pid" ]; then
        kill -9 $pid 2>/dev/null
        logger -t jd_boot_guard "Killed $proc"
    fi

done


# 防止启动
chmod -x /etc/init.d/jdcbox 2>/dev/null
chmod -x /etc/init.d/jdc_evtreport 2>/dev/null

chmod -x /opt/jdc_node/jdc_node.sh 2>/dev/null
chmod -x /opt/jdc_node/jdc_node 2>/dev/null
chmod -x /opt/jdc_snake/snake.sh 2>/dev/null

rm -f /etc/rc.d/S*jdcbox 2>/dev/null
rm -f /etc/rc.d/S*jdc_evtreport 2>/dev/null


# =====================================================
# 2. webdav / dlspeed
# =====================================================

for svc in webdav dlspeed; do

    if [ -f "/etc/init.d/$svc" ]; then
        /etc/init.d/$svc stop 2>/dev/null
        /etc/init.d/$svc disable 2>/dev/null
        chmod -x "/etc/init.d/$svc" 2>/dev/null
    fi

done

rm -f /etc/rc.d/S*webdav 2>/dev/null
rm -f /etc/rc.d/S*dlspeed 2>/dev/null


# =====================================================
# 3. 清理 crontab
# =====================================================

REMOVE_PATTERNS="webdav.sh|dlMonitor|diagnosis_tools|speedtest|jdc_logbackup"

crontab -l 2>/dev/null \
    | grep -vE "$REMOVE_PATTERNS" \
    | crontab - 2>/dev/null


# 删除旧 boot guard 条目
crontab -l 2>/dev/null \
    | grep -v 'jd_boot_guard.sh' \
    | crontab - 2>/dev/null


# 写入新的每小时巡逻
(
    crontab -l 2>/dev/null
    echo "0 * * * * /sbin/jd_boot_guard.sh >/dev/null 2>&1"
) | crontab -


# =====================================================
# 4. DNS 封锁
# =====================================================

if [ ! -f /etc/myhosts ]; then

cat > /etc/myhosts << 'BLOCKEOF'
127.0.0.1 pidrouter-public.jdcloud.com
127.0.0.1 pidrouter-public-v6.jdcloud.com
127.0.0.1 terosaurs.jdcloud.com
127.0.0.1 jdbox-arthur.jdcloud.com
BLOCKEOF

fi


# =====================================================
# 5. 升级关闭
# =====================================================

uci set jd_clock.upgrade_plan.enable=0 2>/dev/null
uci set jd_product.upgrade.fu=0 2>/dev/null

uci commit jd_clock 2>/dev/null
uci commit jd_product 2>/dev/null


# =====================================================
# 6. ★ 保证 jdcloud_bi 正常运行
# =====================================================

chmod +x /usr/sbin/jdcloud_bi 2>/dev/null

if ! pidof jdcloud_bi >/dev/null 2>&1; then

    logger -t jd_boot_guard "Starting jdcloud_bi..."

    /usr/sbin/jdcloud_bi >/dev/null 2>&1 &

fi


logger -t jd_boot_guard "Completed."

GUARDSCRIPT

chmod +x /sbin/jd_boot_guard.sh

echo "  boot guard 已创建"


# =====================================================
# 7. 配置 rc.local
# =====================================================

echo "[7/7] 配置 rc.local..."

# 防止重复
sed -i '/jd_boot_guard/d' /etc/rc.local
sed -i '/jdcloud_bi/d' /etc/rc.local
sed -i '/sleep 120/d' /etc/rc.local
sed -i '/firewall restart/d' /etc/rc.local
sed -i '/dnsmasq restart/d' /etc/rc.local

# 在 exit 0 前插入
sed -i '/^exit 0/i\
sleep 120\
/sbin/jd_boot_guard.sh >/dev/null 2>&1\
/etc/init.d/firewall restart >/dev/null 2>&1\
/etc/init.d/dnsmasq restart >/dev/null 2>&1\
' /etc/rc.local


# =====================================================
# 立即执行
# =====================================================

echo ""
echo "========================================="
echo " 正在立即执行优化..."
echo "========================================="

/sbin/jd_boot_guard.sh

/etc/init.d/firewall restart >/dev/null 2>&1
/etc/init.d/dnsmasq restart >/dev/null 2>&1


# =====================================================
# 最终检查
# =====================================================

echo ""
echo "========================================="
echo " 优化完成，检查结果"
echo "========================================="

echo ""
echo "--- jdcloud_bi ---"
ps | grep jdcloud_bi | grep -v grep \
    || echo "❌ jdcloud_bi 未运行"

echo ""
echo "--- jdc_agent ---"
ps | grep jdc_agent | grep -v grep \
    || echo "⚠️ jdc_agent 当前未运行"

echo ""
echo "--- PCDN 进程 ---"
ps | grep -E "jdc_node|jdc_snake|jdcbox|jdc_evtreport" | grep -v grep \
    || echo "✅ PCDN 进程未运行"

echo ""
echo "--- DNS 封锁 ---"
cat /etc/myhosts

echo ""
echo "--- crontab ---"
crontab -l

echo ""
echo "--- rc.local ---"
cat /etc/rc.local

echo ""
echo "========================================="
echo " 完成"
echo "========================================="
echo ""
echo "★ jdcloud_bi：保留"
echo "★ 手机 APP：保留"
echo "★ Web 管理：保留"
echo "★ Mesh：保留"
echo "★ PCDN / 积分：禁用"
echo "★ 自动升级：关闭"
echo "★ DNS 封锁：启用"
echo ""
echo "建议重启路由器测试。"
echo "重启后约 2 分钟再检查 jdcloud_bi 和 LED。"
echo "========================================="
