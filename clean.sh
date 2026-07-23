#!/bin/sh
# =====================================================
# 京东云 AX1800Pro/AX6600 一键优化脚本
#
# jdc_agent 远程控制
# jdcapp_rpc 手机APP（需要jdc_agent）
# jdcweb_rpc Web管理服务
# jdcloud_bi 联网状态
# jdc_flow 流量统计
# jdc_ezmesh mesh服务
#
# 在路由器上直接运行：
#
# 允许手机APP使用：
# sh jd_my_fix_r4546.sh online
#
# 不允许手机APP使用：
# sh jd_my_fix_r4546.sh
# =====================================================
echo "========================================="
echo " 京东云 AX1800Pro/AX6600 一键优化脚本"
echo "========================================="

# === 1. DNS 封锁写入 /etc/myhosts ===
echo "[1/3] DNS 封锁写入 myhosts..."
cat > /etc/myhosts << 'BLOCKEOF'
127.0.0.1 pidrouter-public.jdcloud.com
127.0.0.1 pidrouter-public-v6.jdcloud.com
127.0.0.1 terosaurs.jdcloud.com
127.0.0.1 jdbox-arthur.jdcloud.com
BLOCKEOF

uci delete dhcp.@dnsmasq[0].addnhosts
uci add_list dhcp.@dnsmasq[0].addnhosts='/etc/myhosts'
uci commit dhcp
/etc/init.d/dnsmasq restart

# === 2. 禁用插件 ===
echo "[2/3] 禁用插件..."

/etc/init.d/jdcbox stop && /etc/init.d/jdcbox disable
/etc/init.d/jdc_evtreport stop && /etc/init.d/jdc_evtreport disable

#chmod -x /usr/sbin/jdcloud_bi
chmod +x /usr/sbin/jdcloud_bi

chmod -x /etc/init.d/jdc_evtreport
chmod -x /usr/sbin/jdc_evtreport
chmod -x /usr/sbin/jdc_guard

chmod -x /etc/init.d/jdcbox
chmod -x /etc/jdcbox/jdcbox.sh
chmod -x /opt/jdcbox/jdcbox

chmod -x /opt/jdc_node/jdc_node.sh
chmod -x /opt/jdc_node/jdc_node
#chmod +x /opt/jdc_node/jdc_node.sh
#chmod +x /opt/jdc_node/jdc_node

chmod -x /opt/jdc_plugin_arg/jdc_plugin_arg
chmod -x /opt/jdc_snake/snake.sh

#chmod -x /usr/sbin/jdc_flow
chmod +x /usr/sbin/jdc_flow

chmod -x /sbin/jdc_logbackup
chmod -x /etc/webdav.sh
chmod -x /sbin/jd_online_upgrade.sh
chmod -x /opt/diagnosis_tools/diagnosis_tools.sh

chmod -x /opt/alchemist/alchemist
#chmod +x /opt/alchemist/alchemist

chmod -x /opt/dlspeed_rt/dlMonitor
chmod -x /usr/sbin/speedtest

chmod +x /sbin/jdcweb_rpc
chmod +x /usr/sbin/jdc_ezmesh

# 启用/禁用远程控制，影响手机APP使用
if [ $# -ne 1 ]; then
    chmod -x /usr/sbin/jdc_agent
    chmod -x /sbin/jdcapp_rpc
    echo "禁用远程控制：手机APP无法使用。"
else
    if [ "$1" = "online" ]; then
        chmod +x /usr/sbin/jdc_agent
        chmod +x /sbin/jdcapp_rpc
        echo "启用远程控制：手机APP可以正常使用。"
    else
        chmod -x /usr/sbin/jdc_agent
        chmod -x /sbin/jdcapp_rpc
        echo "禁用远程控制：手机APP无法使用。"
    fi
fi

# 取消升级
echo "[3/3] 取消升级..."
uci set jd_clock.upgrade_plan.enable=0
uci set jd_product.upgrade.fu=0
uci commit jd_clock
uci commit jd_product

# 执行后的提示信息
echo ""
echo "========================================="
echo " ⚠️ 可能需要重启路由器，才能生效！"
echo "========================================="
