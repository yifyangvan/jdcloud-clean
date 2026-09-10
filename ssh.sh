#!/bin/sh
# ============================================================
# 京东云雅典娜/亚瑟路由器原厂固件安装 Dropbear SSH 脚本
# 适用系统：JDBox 4.5.x / 内核 4.4.60 / musl 1.1.16 / armv7l
# 用法：上传到路由器后执行  sh install-dropbear.sh
# ============================================================

# ---------- 配置 ----------
DROPBEAR_URL="https://downloads.openwrt.org/releases/17.01.6/packages/arm_cortex-a53_neon-vfpv4/base/dropbear_2017.75-5_arm_cortex-a53_neon-vfpv4.ipk"
DROPBEAR_IPK="/tmp/dropbear.ipk"
SSH_PORT=22

# ---------- 颜色输出（busybox ash 兼容） ----------
INFO()  { echo "[INFO]  $*"; }
OK()    { echo "[ OK ]  $*"; }
WARN()  { echo "[WARN]  $*"; }
ERROR() { echo "[ERROR] $*"; }

echo "============================================================"
echo "  京东云路由器 Dropbear SSH 一键安装"
echo "============================================================"
echo ""

# ---------- 1. 环境检查 ----------
INFO "第 1/7 步：环境检查"

if [ ! -f /lib/ld-musl-arm.so.1 ]; then
    ERROR "未检测到 musl libc，此脚本仅适用于京东云原厂固件！"
    exit 1
fi
OK "musl libc 检测通过"

if ! command -v curl >/dev/null 2>&1; then
    ERROR "未找到 curl 命令，请先确认系统有 curl"
    exit 1
fi
OK "curl 可用"

# ---------- 2. 关闭 opkg 签名校验 ----------
INFO "第 2/7 步：关闭 opkg 签名校验"
if grep -q '^option check_signature 1' /etc/opkg.conf 2>/dev/null; then
    sed -i 's/^option check_signature 1/option check_signature 0/' /etc/opkg.conf
    OK "已关闭签名校验"
else
    OK "签名校验已关闭或无需修改"
fi

# ---------- 3. 下载 dropbear ----------
INFO "第 3/7 步：下载 dropbear（LEDE 17.01.6 / arm_cortex-a53）"

if [ -f "$DROPBEAR_IPK" ]; then
    WARN "已存在旧的安装包，删除重新下载"
    rm -f "$DROPBEAR_IPK"
fi

curl -k -L -o "$DROPBEAR_IPK" "$DROPBEAR_URL" 2>/dev/null

if [ ! -s "$DROPBEAR_IPK" ]; then
    ERROR "下载失败！请检查网络连接"
    exit 1
fi

FILE_SIZE=$(wc -c < "$DROPBEAR_IPK")
if [ "$FILE_SIZE" -lt 10000 ]; then
    ERROR "下载文件过小（${FILE_SIZE} bytes），可能下载失败"
    exit 1
fi
OK "下载完成：${FILE_SIZE} bytes"

# ---------- 4. 安装 dropbear ----------
INFO "第 4/7 步：安装 dropbear（强制架构 + 强制依赖 + 安装到 root）"

# opkg 会输出大量 "has no valid architecture" 警告，重定向到日志
opkg --add-arch arm_cortex-a53_neon-vfpv4:10 -d root install --force-depends "$DROPBEAR_IPK" > /tmp/dropbear_install.log 2>&1

if [ -f /usr/sbin/dropbear ]; then
    OK "dropbear 二进制已安装"
else
    ERROR "安装失败，查看 /tmp/dropbear_install.log"
    tail -20 /tmp/dropbear_install.log
    exit 1
fi

# ---------- 5. 创建 musl 解释器软链接 ----------
INFO "第 5/7 步：创建 musl 解释器软链接（armhf -> arm）"

if [ -e /lib/ld-musl-armhf.so.1 ]; then
    OK "软链接已存在"
else
    ln -s /lib/ld-musl-arm.so.1 /lib/ld-musl-armhf.so.1
    OK "已创建 /lib/ld-musl-armhf.so.1 -> /lib/ld-musl-arm.so.1"
fi

# ---------- 6. 验证 dropbear 可执行 ----------
INFO "第 6/7 步：验证 dropbear"

DROPBEAR_VER=$(dropbear -V 2>&1)
if [ $? -eq 0 ]; then
    OK "$DROPBEAR_VER"
else
    ERROR "dropbear 无法运行：$DROPBEAR_VER"
    exit 1
fi

# ---------- 7. 配置 init 脚本 + 开机自启 + 启动 ----------
INFO "第 7/7 步：配置开机自启并启动服务"

mkdir -p /etc/dropbear

# 写入简化版 init 脚本（不依赖 /etc/config/dropbear，稳定可靠）
cat > /etc/init.d/dropbear << 'INITEOF'
#!/bin/sh /etc/rc.common
START=99

start() {
    mkdir -p /etc/dropbear
    # 首次启动会自动生成主机密钥
    /usr/sbin/dropbear -p 22 -B
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
OK "init 脚本已写入"

# 注册开机自启
/etc/init.d/dropbear enable
if [ -L /etc/rc.d/S99dropbear ]; then
    OK "开机自启已注册（/etc/rc.d/S99dropbear）"
else
    WARN "自启软链接未检测到，手动创建"
    ln -sf /etc/init.d/dropbear /etc/rc.d/S99dropbear
fi

# 先杀掉可能已经在跑的实例
killall dropbear 2>/dev/null
sleep 1

# 启动
/etc/init.d/dropbear start
sleep 2

# ---------- 最终验证 ----------
echo ""
echo "============================================================"
if netstat -tlnp 2>/dev/null | grep -q ":${SSH_PORT} "; then
    OK "Dropbear SSH 安装成功并已启动！"
    echo ""
    echo "  SSH 地址：$(ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 || echo '路由器IP'):${SSH_PORT}"
    echo "  用户名：  root"
    echo ""
    echo "  【下一步】请手动执行以下命令："
    echo "    passwd root          # 设置 root 登录密码"
    echo "    ssh root@路由器IP    # 测试连接"
    echo "    reboot               # 重启后验证开机自启"
    echo ""
    echo "  当前监听状态："
    netstat -tlnp 2>/dev/null | grep ":${SSH_PORT} "
    echo "============================================================"
    exit 0
else
    ERROR "启动失败，端口 ${SSH_PORT} 未监听"
    echo ""
    echo "  排查命令："
    echo "    dropbear -V           # 确认二进制可用"
    echo "    /usr/sbin/dropbear -p 22 -B -E   # 前台启动看错误"
    echo "    netstat -tlnp         # 查看端口"
    echo "============================================================"
    exit 1
fi
