#!/bin/sh
# ============================================================
# 京东云 AX1800 Pro / AX6600 服务管理工具
#
# 功能：
#   1. 推荐优化
#   2. 禁用全部相关服务
#   3. 恢复推荐服务
#   4. 恢复全部服务
#   5. 查看当前状态
#   6. DNS 封锁 开/关
#   7. 自动升级 开/关
#   8. 撤销本工具全部修改
#   9. 退出
#
# 原则：
#   - 不删除原厂服务文件
#   - 不删除 /etc/rc.d/ 原厂启动链接
#   - 推荐模式保留 jdcloud_bi
#   - 推荐模式保留 APP / Web / Mesh
#   - 禁用 PCDN / 积分及部分后台服务
#
# ============================================================

BACKUP_DIR="/etc/jd_service_manager"
BACKUP_ORIGINAL="$BACKUP_DIR/original"
STATE_FILE="$BACKUP_DIR/state"

MYHOSTS="/etc/myhosts"


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
    echo "     京东云 AX1800 Pro 服务管理工具"
    echo "=============================================="
    echo ""
}


backup_file()
{
    SRC="$1"
    DST="$2"

    if [ -e "$SRC" ] && [ ! -e "$DST" ]; then
        cp -a "$SRC" "$DST" 2>/dev/null
    fi
}


init_backup()
{
    mkdir -p "$BACKUP_ORIGINAL"

    # 第一次运行才备份
    backup_file /etc/rc.local \
        "$BACKUP_ORIGINAL/rc.local"

    backup_file /etc/config/dhcp \
        "$BACKUP_ORIGINAL/dhcp"

    backup_file /etc/config/jd_clock \
        "$BACKUP_ORIGINAL/jd_clock"

    backup_file /etc/config/jd_product \
        "$BACKUP_ORIGINAL/jd_product"

    backup_file /etc/config/jd_plugin \
        "$BACKUP_ORIGINAL/jd_plugin"

    # 记录第一次运行时间
    if [ ! -e "$BACKUP_DIR/created" ]; then
        date > "$BACKUP_DIR/created"
    fi
}


# ============================================================
# 服务定义
# ============================================================

# 推荐模式保留
RECOMMENDED="
jdcloud_bi
jdc_agent
jdcapp_rpc
jdcweb_rpc
jdc_ezmesh
jdc_flow
"


# 推荐模式禁用
DISABLE_RECOMMENDED="
jdcbox
jdc_evtreport
jdc_node
jdc_snake
webdav
dlspeed
"


# 后台程序
DISABLE_PROGRAMS="
/sbin/jdc_logbackup
/etc/webdav.sh
/sbin/jd_online_upgrade.sh
/opt/diagnosis_tools/diagnosis_tools.sh
/opt/alchemist/alchemist
/opt/dlspeed_rt/dlMonitor
/usr/sbin/speedtest
/opt/jdc_plugin_arg/jdc_plugin_arg
"


# PCDN / 相关文件
DISABLE_FILES="
/etc/init.d/jdcbox
/etc/init.d/jdc_evtreport
/opt/jdc_node/jdc_node.sh
/opt/jdc_node/jdc_node
/opt/jdc_snake/snake.sh
"


# ============================================================
# 服务停止
# ============================================================

stop_service()
{
    SVC="$1"

    if [ -f "/etc/init.d/$SVC" ]; then
        echo "  停止：$SVC"
        /etc/init.d/$SVC stop 2>/dev/null
        /etc/init.d/$SVC disable 2>/dev/null
    fi
}


disable_service()
{
    SVC="$1"

    if [ -f "/etc/init.d/$SVC" ]; then
        chmod -x "/etc/init.d/$SVC" 2>/dev/null
    fi
}


enable_service()
{
    SVC="$1"

    if [ -f "/etc/init.d/$SVC" ]; then
        chmod +x "/etc/init.d/$SVC" 2>/dev/null
        /etc/init.d/$SVC enable 2>/dev/null
    fi
}


start_service()
{
    SVC="$1"

    if [ -f "/etc/init.d/$SVC" ]; then
        /etc/init.d/$SVC start 2>/dev/null
    fi
}


# ============================================================
# 禁止非 procd 程序
# ============================================================

disable_program()
{
    FILE="$1"

    if [ -e "$FILE" ]; then
        chmod -x "$FILE" 2>/dev/null
    fi
}


enable_program()
{
    FILE="$1"

    if [ -e "$FILE" ]; then
        chmod +x "$FILE" 2>/dev/null
    fi
}


# ============================================================
# 推荐模式
# ============================================================

recommended_mode()
{
    echo ""
    echo "=============================================="
    echo "       正在应用：推荐优化模式"
    echo "=============================================="
    echo ""

    echo "[保留服务]"
    echo "  ✓ jdcloud_bi"
    echo "  ✓ jdc_agent"
    echo "  ✓ jdcapp_rpc"
    echo "  ✓ jdcweb_rpc"
    echo "  ✓ jdc_ezmesh"
    echo "  ✓ jdc_flow"
    echo ""

    # --------------------------------------------------------
    # ★★★ 绝对不处理 jdcloud_bi ★★★
    # --------------------------------------------------------

    chmod +x /usr/sbin/jdcloud_bi 2>/dev/null


    # APP / Web / Mesh
    chmod +x /usr/sbin/jdc_agent 2>/dev/null
    chmod +x /sbin/jdcapp_rpc 2>/dev/null
    chmod +x /sbin/jdcweb_rpc 2>/dev/null
    chmod +x /usr/sbin/jdc_ezmesh 2>/dev/null
    chmod +x /usr/sbin/jdc_flow 2>/dev/null


    echo "[禁用 PCDN / 积分服务]"

    for svc in jdcbox jdc_evtreport; do
        stop_service "$svc"
        disable_service "$svc"
    done


    # 非 procd PCDN
    for file in \
        /opt/jdc_node/jdc_node.sh \
        /opt/jdc_node/jdc_node \
        /opt/jdc_snake/snake.sh \
        /opt/jdc_plugin_arg/jdc_plugin_arg
    do
        if [ -e "$file" ]; then
            chmod -x "$file" 2>/dev/null
            echo "  禁止执行：$file"
        fi
    done


    echo ""
    echo "[禁用其他后台服务]"

    for svc in webdav dlspeed; do
        stop_service "$svc"
        disable_service "$svc"
    done


    for file in $DISABLE_PROGRAMS; do
        disable_program "$file"
    done


    # --------------------------------------------------------
    # 升级
    # --------------------------------------------------------

    echo ""
    echo "[关闭自动升级]"

    uci set jd_clock.upgrade_plan.enable=0 2>/dev/null
    uci set jd_product.upgrade.fu=0 2>/dev/null

    uci commit jd_clock 2>/dev/null
    uci commit jd_product 2>/dev/null


    # 插件自动升级关闭
    for p in $(uci show jd_plugin 2>/dev/null \
        | grep '\.upgrade=' \
        | cut -d= -f1)
    do
        uci set "$p=0" 2>/dev/null
    done

    uci commit jd_plugin 2>/dev/null


    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    enable_dns_block


    echo ""
    echo "=============================================="
    echo " 推荐优化完成"
    echo "=============================================="
    echo ""
    echo "✓ jdcloud_bi：保留"
    echo "✓ 京东云 APP：保留"
    echo "✓ Web 管理：保留"
    echo "✓ Mesh：保留"
    echo "✓ PCDN / 积分：禁用"
    echo "✓ 自动升级：关闭"
    echo "✓ DNS 封锁：开启"
    echo ""
}


# ============================================================
# 禁用全部
# ============================================================

disable_all()
{
    echo ""
    echo "=============================================="
    echo "           禁用全部相关服务"
    echo "=============================================="
    echo ""
    echo "⚠️ 注意："
    echo "此模式可能导致："
    echo "  - 京东云 APP 无法使用"
    echo "  - LED 状态功能异常"
    echo "  - Mesh 功能异常"
    echo "  - Web/远程管理功能异常"
    echo ""

    printf "确定继续？输入 YES："
    read confirm

    if [ "$confirm" != "YES" ]; then
        echo "已取消。"
        return
    fi


    echo ""
    echo "[停止所有可识别服务]"

    for svc in \
        jdcbox \
        jdc_evtreport \
        jdc_agent \
        jdcweb_rpc \
        webdav \
        dlspeed
    do
        stop_service "$svc"
        disable_service "$svc"
    done


    echo ""
    echo "[禁用程序]"

    for file in \
        /usr/sbin/jdcloud_bi \
        /sbin/jdcapp_rpc \
        /usr/sbin/jdc_agent \
        /sbin/jdcweb_rpc \
        /usr/sbin/jdc_ezmesh \
        /usr/sbin/jdc_flow \
        /opt/jdc_node/jdc_node.sh \
        /opt/jdc_node/jdc_node \
        /opt/jdc_snake/snake.sh \
        /opt/jdc_plugin_arg/jdc_plugin_arg \
        /sbin/jdc_logbackup \
        /etc/webdav.sh \
        /sbin/jd_online_upgrade.sh \
        /opt/diagnosis_tools/diagnosis_tools.sh \
        /opt/alchemist/alchemist \
        /opt/dlspeed_rt/dlMonitor \
        /usr/sbin/speedtest
    do
        if [ -e "$file" ]; then
            chmod -x "$file" 2>/dev/null
            echo "  禁止执行：$file"
        fi
    done


    echo ""
    echo "全部相关服务已尽可能禁用。"
    echo "原厂文件没有删除。"
}


# ============================================================
# 恢复推荐服务
# ============================================================

restore_recommended()
{
    echo ""
    echo "=============================================="
    echo "          恢复推荐服务"
    echo "=============================================="
    echo ""

    # ★ jdcloud_bi
    echo "恢复 jdcloud_bi..."

    chmod +x /usr/sbin/jdcloud_bi 2>/dev/null

    # 如果存在原厂 init 服务
    if [ -f /etc/init.d/jdcloudbi ]; then
        chmod +x /etc/init.d/jdcloudbi 2>/dev/null
        /etc/init.d/jdcloudbi enable 2>/dev/null
        /etc/init.d/jdcloudbi start 2>/dev/null
    fi


    # APP
    echo "恢复 APP / Web / Mesh..."

    chmod +x /usr/sbin/jdc_agent 2>/dev/null
    chmod +x /sbin/jdcapp_rpc 2>/dev/null
    chmod +x /sbin/jdcweb_rpc 2>/dev/null
    chmod +x /usr/sbin/jdc_ezmesh 2>/dev/null
    chmod +x /usr/sbin/jdc_flow 2>/dev/null


    # PCDN 仍然保持关闭
    echo ""
    echo "PCDN / 积分服务继续保持关闭。"

    for svc in jdcbox jdc_evtreport; do
        stop_service "$svc"
        disable_service "$svc"
    done


    chmod -x /opt/jdc_node/jdc_node.sh 2>/dev/null
    chmod -x /opt/jdc_node/jdc_node 2>/dev/null
    chmod -x /opt/jdc_snake/snake.sh 2>/dev/null
    chmod -x /opt/jdc_plugin_arg/jdc_plugin_arg 2>/dev/null


    # Webdav / dlspeed 仍关闭
    for svc in webdav dlspeed; do
        stop_service "$svc"
        disable_service "$svc"
    done


    # 升级保持关闭
    uci set jd_clock.upgrade_plan.enable=0 2>/dev/null
    uci set jd_product.upgrade.fu=0 2>/dev/null

    uci commit jd_clock 2>/dev/null
    uci commit jd_product 2>/dev/null


    enable_dns_block


    echo ""
    echo "✓ 推荐服务已恢复"
    echo "✓ jdcloud_bi 已恢复"
    echo "✓ APP 已恢复"
    echo "✓ PCDN 仍保持关闭"
}


# ============================================================
# 恢复全部
# ============================================================

restore_all()
{
    echo ""
    echo "=============================================="
    echo "              恢复全部服务"
    echo "=============================================="
    echo ""

    printf "⚠️ 确定恢复原厂相关服务？输入 YES："
    read confirm

    if [ "$confirm" != "YES" ]; then
        echo "已取消。"
        return
    fi


    echo ""
    echo "[恢复程序执行权限]"

    for file in \
        /usr/sbin/jdcloud_bi \
        /sbin/jdcapp_rpc \
        /usr/sbin/jdc_agent \
        /sbin/jdcweb_rpc \
        /usr/sbin/jdc_ezmesh \
        /usr/sbin/jdc_flow \
        /opt/jdc_node/jdc_node.sh \
        /opt/jdc_node/jdc_node \
        /opt/jdc_snake/snake.sh \
        /opt/jdc_plugin_arg/jdc_plugin_arg \
        /sbin/jdc_logbackup \
        /etc/webdav.sh \
        /sbin/jd_online_upgrade.sh \
        /opt/diagnosis_tools/diagnosis_tools.sh \
        /opt/alchemist/alchemist \
        /opt/dlspeed_rt/dlMonitor \
        /usr/sbin/speedtest
    do
        enable_program "$file"
    done


    echo ""
    echo "[恢复服务]"

    for svc in \
        jdcbox \
        jdc_evtreport \
        jdc_agent \
        webdav \
        dlspeed
    do
        enable_service "$svc"
    done


    # jdcloud_bi 特别处理
    if [ -f /etc/init.d/jdcloudbi ]; then
        chmod +x /etc/init.d/jdcloudbi 2>/dev/null
        /etc/init.d/jdcloudbi enable 2>/dev/null
        /etc/init.d/jdcloudbi start 2>/dev/null
    fi


    # 恢复升级开关
    if [ -f "$BACKUP_ORIGINAL/jd_clock" ]; then
        cp -f "$BACKUP_ORIGINAL/jd_clock" /etc/config/jd_clock
        uci commit jd_clock 2>/dev/null
    fi

    if [ -f "$BACKUP_ORIGINAL/jd_product" ]; then
        cp -f "$BACKUP_ORIGINAL/jd_product" /etc/config/jd_product
        uci commit jd_product 2>/dev/null
    fi


    echo ""
    echo "恢复完成。"
    echo "建议重启路由器。"
}


# ============================================================
# DNS 开启
# ============================================================

enable_dns_block()
{
    cat > "$MYHOSTS" << 'EOF'
127.0.0.1 pidrouter-public.jdcloud.com
127.0.0.1 pidrouter-public-v6.jdcloud.com
127.0.0.1 terosaurs.jdcloud.com
127.0.0.1 jdbox-arthur.jdcloud.com
EOF


    # 避免重复
    uci del_list dhcp.@dnsmasq[0].addnhosts="$MYHOSTS" 2>/dev/null

    uci add_list dhcp.@dnsmasq[0].addnhosts="$MYHOSTS" 2>/dev/null

    uci commit dhcp 2>/dev/null

    /etc/init.d/dnsmasq restart >/dev/null 2>&1

    echo "DNS 封锁：开启"
}


# ============================================================
# DNS 关闭
# ============================================================

disable_dns_block()
{
    uci del_list dhcp.@dnsmasq[0].addnhosts="$MYHOSTS" 2>/dev/null
    uci commit dhcp 2>/dev/null

    rm -f "$MYHOSTS"

    /etc/init.d/dnsmasq restart >/dev/null 2>&1

    echo "DNS 封锁：关闭"
}


# ============================================================
# 自动升级开关
# ============================================================

upgrade_off()
{
    uci set jd_clock.upgrade_plan.enable=0 2>/dev/null
    uci set jd_product.upgrade.fu=0 2>/dev/null

    uci commit jd_clock 2>/dev/null
    uci commit jd_product 2>/dev/null

    echo "自动升级：关闭"
}


upgrade_on()
{
    if [ -f "$BACKUP_ORIGINAL/jd_clock" ]; then
        cp -f "$BACKUP_ORIGINAL/jd_clock" /etc/config/jd_clock
        uci commit jd_clock 2>/dev/null
    else
        uci set jd_clock.upgrade_plan.enable=1 2>/dev/null
        uci commit jd_clock 2>/dev/null
    fi


    if [ -f "$BACKUP_ORIGINAL/jd_product" ]; then
        cp -f "$BACKUP_ORIGINAL/jd_product" /etc/config/jd_product
        uci commit jd_product 2>/dev/null
    else
        uci set jd_product.upgrade.fu=1 2>/dev/null
        uci commit jd_product 2>/dev/null
    fi

    echo "自动升级：恢复"
}


# ============================================================
# 状态检查
# ============================================================

status()
{
    echo ""
    echo "=============================================="
    echo "                 当前状态"
    echo "=============================================="

    echo ""
    echo "----- 进程 -----"

    for proc in \
        jdcloud_bi \
        jdc_agent \
        jdcapp_rpc \
        jdcweb_rpc \
        jdc_ezmesh \
        jdc_flow \
        jdcbox \
        jdc_node \
        jdc_snake \
        webdav \
        dlspeed
    do

        if pidof "$proc" >/dev/null 2>&1; then
            echo "  [运行] $proc"
        else
            echo "  [停止] $proc"
        fi

    done


    echo ""
    echo "----- 执行权限 -----"

    for file in \
        /usr/sbin/jdcloud_bi \
        /usr/sbin/jdc_agent \
        /sbin/jdcapp_rpc \
        /sbin/jdcweb_rpc \
        /usr/sbin/jdc_ezmesh \
        /opt/jdc_node/jdc_node \
        /opt/jdc_snake/snake.sh
    do

        if [ -e "$file" ]; then

            if [ -x "$file" ]; then
                echo "  [可执行] $file"
            else
                echo "  [禁用]   $file"
            fi

        fi

    done


    echo ""
    echo "----- 服务启动状态 -----"

    for svc in \
        jdcloudbi \
        jdcbox \
        jdc_evtreport \
        jdc_agent \
        webdav \
        dlspeed
    do

        if [ -f "/etc/init.d/$svc" ]; then

            if /etc/init.d/$svc enabled 2>/dev/null; then
                echo "  [enabled]  $svc"
            else
                echo "  [disabled] $svc"
            fi

        fi

    done


    echo ""
    echo "----- DNS -----"

    if [ -f "$MYHOSTS" ]; then
        echo "  DNS 封锁：开启"
        cat "$MYHOSTS"
    else
        echo "  DNS 封锁：关闭"
    fi


    echo ""
    echo "----- 自动升级 -----"

    echo "jd_clock:"
    uci get jd_clock.upgrade_plan.enable 2>/dev/null || echo "  未找到"

    echo "jd_product:"
    uci get jd_product.upgrade.fu 2>/dev/null || echo "  未找到"


    echo ""
    echo "----- crontab -----"

    crontab -l 2>/dev/null || echo "  无 crontab"


    echo ""
}


# ============================================================
# 撤销全部修改
# ============================================================

undo_all()
{
    echo ""
    echo "=============================================="
    echo "        撤销本工具的配置修改"
    echo "=============================================="
    echo ""

    echo "这将恢复首次运行本工具时保存的："
    echo "  - rc.local"
    echo "  - dhcp"
    echo "  - jd_clock"
    echo "  - jd_product"
    echo "  - jd_plugin"
    echo ""

    printf "确定？输入 RESTORE："
    read confirm

    if [ "$confirm" != "RESTORE" ]; then
        echo "已取消。"
        return
    fi


    for file in \
        rc.local \
        dhcp \
        jd_clock \
        jd_product \
        jd_plugin
    do

        if [ -f "$BACKUP_ORIGINAL/$file" ]; then

            case "$file" in

                rc.local)
                    cp -f "$BACKUP_ORIGINAL/$file" /etc/rc.local
                    ;;

                dhcp)
                    cp -f "$BACKUP_ORIGINAL/$file" /etc/config/dhcp
                    ;;

                jd_clock)
                    cp -f "$BACKUP_ORIGINAL/$file" /etc/config/jd_clock
                    ;;

                jd_product)
                    cp -f "$BACKUP_ORIGINAL/$file" /etc/config/jd_product
                    ;;

                jd_plugin)
                    cp -f "$BACKUP_ORIGINAL/$file" /etc/config/jd_plugin
                    ;;

            esac

        fi

    done


    # 恢复执行权限
    for file in \
        /usr/sbin/jdcloud_bi \
        /sbin/jdcapp_rpc \
        /usr/sbin/jdc_agent \
        /sbin/jdcweb_rpc \
        /usr/sbin/jdc_ezmesh \
        /usr/sbin/jdc_flow \
        /opt/jdc_node/jdc_node.sh \
        /opt/jdc_node/jdc_node \
        /opt/jdc_snake/snake.sh \
        /opt/jdc_plugin_arg/jdc_plugin_arg \
        /sbin/jdc_logbackup \
        /etc/webdav.sh \
        /sbin/jd_online_upgrade.sh \
        /opt/diagnosis_tools/diagnosis_tools.sh \
        /opt/alchemist/alchemist \
        /opt/dlspeed_rt/dlMonitor \
        /usr/sbin/speedtest
    do
        enable_program "$file"
    done


    # 恢复服务
    for svc in \
        jdcbox \
        jdc_evtreport \
        jdc_agent \
        webdav \
        dlspeed \
        jdcloudbi
    do
        enable_service "$svc"
    done


    rm -f "$MYHOSTS"

    /etc/init.d/dnsmasq restart >/dev/null 2>&1


    echo ""
    echo "撤销完成。"
    echo "建议重启路由器恢复完整原厂状态。"
}


# ============================================================
# 菜单
# ============================================================

menu()
{
    while true
    do

        header

        echo "  1. 推荐优化"
        echo "     保留 jdcloud_bi + APP + Web + Mesh"
        echo "     禁用 PCDN / 积分 / 无用后台"
        echo ""

        echo "  2. 禁用全部相关服务"
        echo "     ⚠️ APP / LED / Mesh 等可能失效"
        echo ""

        echo "  3. 恢复推荐服务"
        echo "     恢复 jdcloud_bi + APP + Web + Mesh"
        echo "     PCDN 继续禁用"
        echo ""

        echo "  4. 恢复全部服务"
        echo "     恢复本工具处理过的相关服务"
        echo ""

        echo "  5. 查看当前状态"
        echo ""

        echo "  6. DNS 封锁"
        echo ""

        echo "  7. 自动升级"
        echo ""

        echo "  8. 撤销本工具全部修改"
        echo ""

        echo "  9. 退出"
        echo ""

        printf "请选择 [1-9]: "
        read choice


        case "$choice" in

            1)
                recommended_mode
                pause
                ;;

            2)
                disable_all
                pause
                ;;

            3)
                restore_recommended
                pause
                ;;

            4)
                restore_all
                pause
                ;;

            5)
                status
                pause
                ;;

            6)
                header

                echo "DNS 设置："
                echo ""
                echo "  1. 开启 DNS 封锁"
                echo "  2. 关闭 DNS 封锁"
                echo "  3. 返回"
                echo ""

                printf "请选择："
                read dns_choice

                case "$dns_choice" in
                    1)
                        enable_dns_block
                        pause
                        ;;
                    2)
                        disable_dns_block
                        pause
                        ;;
                esac
                ;;

            7)
                header

                echo "自动升级："
                echo ""
                echo "  1. 关闭自动升级"
                echo "  2. 恢复自动升级"
                echo "  3. 返回"
                echo ""

                printf "请选择："
                read upgrade_choice

                case "$upgrade_choice" in
                    1)
                        upgrade_off
                        pause
                        ;;
                    2)
                        upgrade_on
                        pause
                        ;;
                esac
                ;;

            8)
                undo_all
                pause
                ;;

            9)
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


init_backup

menu
