#!/bin/sh
# =====================================================
# 京东云 AX1800 Pro 全量修复一键脚本
# 一次性基建 + 调用 boot guard 立即生效
# 在路由器上直接运行：sh jd_full_fix.sh
# =====================================================

echo "========================================="
echo " 京东云 AX1800 Pro 全量修复脚本"
echo "========================================="

# === 1. UCI 清理升级封锁（一次性，破坏性操作）===
echo "[1/6] 清理升级计划..."
uci delete jd_product.upgrade 2>/dev/null
uci delete jd_clock.upgrade_plan 2>/dev/null

# 关闭所有插件自动升级
for p in $(uci show jd_plugin 2>/dev/null | grep '\.upgrade=' | cut -d= -f1); do
  uci set ${p}='0' 2>/dev/null
done

# 删除升级脚本
rm -f /sbin/jd_online_upgrade.sh 2>/dev/null

uci commit
echo "  升级计划已清理"

# === 2. DNS 封锁写入 /etc/custom_hosts ===
echo "[2/6] DNS 封锁写入 custom_hosts..."
cat > /etc/custom_hosts << 'BLOCKEOF'
127.0.0.1 pidrouter-public.jdcloud.com
127.0.0.1 pidrouter-public-v6.jdcloud.com
127.0.0.1 terosaurs.jdcloud.com
127.0.0.1 jdbox-arthur.jdcloud.com
BLOCKEOF
cp -f /rom/etc/hosts /etc/hosts
echo "  DNS 封锁已写入 /etc/custom_hosts（重启后不会丢失）"

# === 3. 创建 jd_boot_guard.sh ===
echo "[3/6] 创建开机兜底脚本..."
cat > /sbin/jd_boot_guard.sh << 'GUARDSCRIPT'
#!/bin/sh
# 开机兜底 + 定时巡逻脚本：
#   禁用 PCDN/积分服务 + 清理 crontab + 确保 DNS 封锁
# 由 /etc/rc.local 开机调用 + crontab 每小时巡逻
# 执行时机：所有 S99 服务启动完毕后（含 jdc_agent 写 crontab）
#
# ⚠️ PCDN 服务是 procd 管理的，带 respawn 自动拉起
#    单纯 kill -9 后 procd 会重新启动，必须先 stop 再 disable
#
# ⚠️ crontab 清理后会写回自己的巡逻条目，形成闭环：
#    boot guard → 清脏条目 → 写回巡逻条目 → 1小时后再执行 → 又清理 → 又写回...
#
# ⚠️ firewall/dnsmasq 重启不在本脚本内，由 rc.local 开机时单独执行（只跑一次）

logger -t jd_boot_guard "Starting boot guard..."

# === 1. 禁用 PCDN/积分服务（procd 管理的必须 stop+disable，不能只 kill）===
for svc in jdcbox jdcloudbi jdc_evtreport; do
    if [ -f /etc/init.d/$svc ]; then
        /etc/init.d/$svc stop 2>/dev/null
        /etc/init.d/$svc disable 2>/dev/null
        logger -t jd_boot_guard "Stopped and disabled $svc"
    fi
done

# 非 procd 管理的进程，直接杀
for proc in jdc_node jdc_snake; do
    pid=$(pgrep -f "$proc")
    [ -n "$pid" ] && {
        kill -9 $pid 2>/dev/null
        logger -t jd_boot_guard "Killed $proc (pid=$pid)"
    }
done

# 防复活：去掉执行权限 + 强制删除 rc.d 软链接（disable 不一定可靠）
chmod -x /etc/init.d/jdcbox 2>/dev/null
chmod -x /opt/jdc_node/jdc_node.sh 2>/dev/null
chmod -x /opt/jdc_snake/snake.sh 2>/dev/null
rm -f /etc/rc.d/S*jdcbox /etc/rc.d/S*jdcloudbi /etc/rc.d/S*jdc_evtreport 2>/dev/null

# === 2. 禁用 webdav 和 dlspeed（防 firewall 规则被冲）===
for svc in webdav dlspeed; do
    if [ -f /etc/init.d/$svc ]; then
        /etc/init.d/$svc stop 2>/dev/null
        /etc/init.d/$svc disable 2>/dev/null
        chmod -x /etc/init.d/$svc 2>/dev/null
        logger -t jd_boot_guard "Stopped and disabled $svc"
    fi
done
rm -f /etc/rc.d/S*webdav /etc/rc.d/S*dlspeed 2>/dev/null

# === 3. 清理 crontab + 写回巡逻条目（闭环）===
logger -t jd_boot_guard "Cleaning crontab..."
# 第一步：删脏条目
REMOVE_PATTERNS="webdav.sh|dlMonitor|diagnosis_tools|speedtest|jdc_logbackup"
crontab -l | grep -vE "$REMOVE_PATTERNS" | crontab -
# 第二步：删旧的reboot和巡逻条目（避免重复）
crontab -l | grep -v 'jd_boot_guard' | crontab -
# 第三步：写回自己的巡逻条目（每小时执行一次）
(crontab -l; echo "0 */1 * * * /sbin/jd_boot_guard.sh >/dev/null 2>&1") | crontab -
logger -t jd_boot_guard "Crontab cleaned, patrol entry restored"

# === 4. 确保 DNS 封锁在 custom_hosts ===
logger -t jd_boot_guard "Ensuring DNS blockade in custom_hosts..."
if ! grep -q "pidrouter-public" /etc/custom_hosts 2>/dev/null; then
    cat > /etc/custom_hosts << 'BLOCKEOF'
127.0.0.1 pidrouter-public.jdcloud.com
127.0.0.1 pidrouter-public-v6.jdcloud.com
127.0.0.1 terosaurs.jdcloud.com
127.0.0.1 jdbox-arthur.jdcloud.com
BLOCKEOF
    logger -t jd_boot_guard "Wrote DNS blockade to /etc/custom_hosts"
fi
cp -f /rom/etc/hosts /etc/hosts

# === 5. 确认 UCI 升级配置已关闭 ===
uci set jd_clock.upgrade_plan.enable=0 2>/dev/null
uci set jd_product.upgrade.fu=0 2>/dev/null
uci commit jd_clock 2>/dev/null
uci commit jd_product 2>/dev/null

logger -t jd_boot_guard "Boot guard completed."
GUARDSCRIPT
chmod +x /sbin/jd_boot_guard.sh
echo "  jd_boot_guard.sh 已创建"

# === 4. 配置 rc.local 开机自启 ===
echo "[4/6] 配置 rc.local 开机自启..."
# rc.local 在 overlay 分区，重启不丢失
# sleep 120 等所有 S99 服务完成（含 jdc_agent 写 crontab、jd_process_hosts.sh 检查 hosts）
# 先移除旧的自启行（避免重复插入），再插入新的
sed -i '/jd_boot_guard/d; /^sleep 120$/d; /firewall restart/d; /dnsmasq restart/d' /etc/rc.local
sed -i '/^exit 0/i sleep 120\n/sbin/jd_boot_guard.sh >/dev/null 2>&1\n/etc/init.d/firewall restart >/dev/null 2>&1\n/etc/init.d/dnsmasq restart >/dev/null 2>&1' /etc/rc.local
echo "  rc.local 已配置（内容如下：）"
cat /etc/rc.local

# === 5. 立即执行 boot guard（一次性基建已完成，现在调用 boot guard 生效）===
echo "[5/6] 立即执行 boot guard + 重启 firewall/dnsmasq..."
/sbin/jd_boot_guard.sh
/etc/init.d/firewall restart >/dev/null 2>&1
/etc/init.d/dnsmasq restart >/dev/null 2>&1
echo "  boot guard 已执行 + firewall/dnsmasq 已重启"

# === 6. 验证 ===
echo "[6/6] 验证..."

echo ""
echo "========================================="
echo " 验证结果"
echo "========================================="

echo "--- 1. hosts 文件（应只有 127.0.0.1 localhost）---"
cat /etc/hosts

echo "--- 2. custom_hosts（应有 4 条封锁）---"
cat /etc/custom_hosts

echo "--- 3. crontab ---"
crontab -l

echo "--- 4. 端口转发规则（UCI 预期 vs iptables 实际）---"
expected=$(uci show firewall | grep -c '=redirect')
actual=$(iptables -t nat -L zone_wan_prerouting -n 2>/dev/null | grep -c DNAT)
echo "  UCI redirect 条目: $expected | iptables DNAT 规则: $actual"
if [ "$actual" -ge "$expected" ]; then
    echo "  ✅ 端口转发正常"
else
    echo "  ❌ 端口转发规则缺失，建议检查"
fi

echo "--- 5. 被禁用的服务软链接（应无输出）---"
ls /etc/rc.d/S*webdav* /etc/rc.d/S*dlspeed* /etc/rc.d/S*jdcbox* /etc/rc.d/S*jdcloudbi* /etc/rc.d/S*jdc_evtreport* 2>/dev/null || echo "(none - OK)"

echo "--- 6. jd_boot_guard.sh ---"
ls -la /sbin/jd_boot_guard.sh

echo "--- 7. rc.local 内容 ---"
cat /etc/rc.local

echo "--- 8. DNS 封锁是否被 dnsmasq 加载 ---"
cat /var/hosts/custom_hosts 2>/dev/null || echo "(dnsmasq 还没加载，等几秒再查)"

echo "--- 9. PCDN 进程是否还在 ---"
ps | grep -E "jdc_node|jdc_snake|jdcbox|webdav" | grep -v grep || echo "(none - OK)"

echo "--- 10. 升级计划 ---"
uci show jd_clock 2>/dev/null | grep upgrade || echo "(no upgrade plan - OK)"
uci show jd_product 2>/dev/null | grep upgrade || echo "(no upgrade section - OK)"

echo ""
echo "========================================="
echo " ⚠️ 还需手动部署的文件："
echo "========================================="
echo "1. DDNS 脚本修复："
echo "   从本地 scp ddns/dynamic_dns_functions_fixed.sh"
echo "   到路由器 /usr/lib/ddns/dynamic_dns_functions.sh"
echo "   然后执行: /etc/init.d/ddns restart"
echo ""
echo "2. DDNS 前端 JS 修正："
echo "   从本地 scp PC/seniorManagement/DDNS.9ce6c4e3d73877da44ad.js"
echo "   到路由器 /www/PC/seniorManagement/DDNS.9ce6c4e3d73877da44ad.js"
echo ""
echo "3. 重启路由器后 2 分钟再检查 firewall 规则"
echo "   iptables -t nat -L zone_wan_prerouting -n | grep DNAT | wc -l"
echo "========================================="
