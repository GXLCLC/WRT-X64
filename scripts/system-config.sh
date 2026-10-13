#!/usr/bin/env bash
# ============================================================================
#  系统个性化配置脚本（无密码版）
#  变更：ROOT_PASSWORD 留空 = root 无密码，
#        首次通过 LuCI 登录（http://192.168.2.1）后再自行设置密码
#  使用：仅需修改下方【可修改配置项】并提交，Release 说明自动同步
# ============================================================================
set -euo pipefail

# ==================== 可修改配置项 ====================
LAN_IP="192.168.2.1"              # LAN 口 IP（后台管理地址）
NETMASK="255.255.255.0"           # 子网掩码
ROOT_PASSWORD=""                  # ★ 留空 = 无密码；如需固定密码在此填写明文
HOSTNAME="ImmortalWrt"            # 主机名
DEFAULT_THEME="argon"             # LuCI 默认主题
TIMEZONE="CST-8"                  # 时区（东八区）
ZONENAME="Asia/Shanghai"          # 时区名称
NTP_SERVERS="ntp.aliyun.com time1.cloud.tencent.com ntp.ntsc.ac.cn"
# ======================================================

OPENWRT_DIR="${1:-openwrt}"
UCI_DEFAULTS="$OPENWRT_DIR/files/etc/uci-defaults"
mkdir -p "$UCI_DEFAULTS"

echo " 注入系统个性化配置："
echo "    LAN 口 IP : $LAN_IP"
echo "    后台密码  : ${ROOT_PASSWORD:-<无密码，首次登录后再设置>}"
echo "    主机名    : $HOSTNAME"
echo "    默认主题  : $DEFAULT_THEME"

# --------- 1. root 密码（空 = 无密码；非空 = 写入 SHA-512 哈希）---------
if [ -z "$ROOT_PASSWORD" ]; then
    # 无密码：显式清空 shadow 密码字段（幂等，防止上游源码默认值变化）
    cat > "$UCI_DEFAULTS/99-root-password" <<'EOF'
#!/bin/sh
# root 无密码：首次登录 LuCI 后请立即设置密码
sed -i 's|^root:[^:]*:|root::|' /etc/shadow
exit 0
EOF
else
    PASSWD_HASH=$(openssl passwd -6 "$ROOT_PASSWORD")
    cat > "$UCI_DEFAULTS/99-root-password" <<EOF
#!/bin/sh
sed -i 's|^root:[^:]*:|root:$PASSWD_HASH:|' /etc/shadow
exit 0
EOF
fi
chmod +x "$UCI_DEFAULTS/99-root-password"

# --------- 2. LAN 口 IP 地址 ----------
cat > "$UCI_DEFAULTS/97-network-lan" <<EOF
#!/bin/sh
uci set network.lan.ipaddr='$LAN_IP'
uci set network.lan.netmask='$NETMASK'
uci commit network
exit 0
EOF
chmod +x "$UCI_DEFAULTS/97-network-lan"

# --------- 3. 主机名 / 时区 / 系统日志 ----------
cat > "$UCI_DEFAULTS/96-system-info" <<EOF
#!/bin/sh
uci set system.@system[0].hostname='$HOSTNAME'
uci set system.@system[0].timezone='$TIMEZONE'
uci set system.@system[0].zonename='$ZONENAME'
uci set system.@system[0].log_size='64'
uci commit system
echo '$HOSTNAME' > /proc/sys/kernel/hostname
exit 0
EOF
chmod +x "$UCI_DEFAULTS/96-system-info"

# --------- 4. NTP 时间服务器 ----------
{
    echo '#!/bin/sh'
    echo "uci -q delete system.ntp.server"
    for server in $NTP_SERVERS; do
        echo "uci add_list system.ntp.server='$server'"
    done
    echo "uci set system.ntp.enabled='1'"
    echo "uci commit system"
    echo 'exit 0'
} > "$UCI_DEFAULTS/95-system-ntp"
chmod +x "$UCI_DEFAULTS/95-system-ntp"

# --------- 5. LuCI 默认主题与界面语言 ----------
cat > "$UCI_DEFAULTS/94-default-theme" <<EOF
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/$DEFAULT_THEME/'
uci set luci.main.lang='zh_cn'
uci commit luci
exit 0
EOF
chmod +x "$UCI_DEFAULTS/94-default-theme"

echo " ✔ 系统个性化配置注入完成（files/etc/uci-defaults/）"