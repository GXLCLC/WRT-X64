#!/usr/bin/env bash
# ============================================================================
#  系统个性化配置脚本（独立维护，无需改动工作流）
#  用途：将 LAN IP、后台密码、主机名、默认主题、时区等写入源码 files/ 目录，
#        打包进固件，首次启动时通过 uci-defaults 自动生效
#  使用：后续仅需修改下方【可修改配置项】并提交，
#        Release 发布说明会自动同步读取此处配置（保持数据同源）
# ============================================================================
set -e

# ==================== 可修改配置项 ====================
LAN_IP="192.168.2.1"                # LAN 口 IP（后台管理地址）
NETMASK="255.255.255.0"             # 子网掩码
ROOT_PASSWORD="asdfghjkL666666"     # root / LuCI 后台登录密码
HOSTNAME="ImmortalWrt"              # 主机名
DEFAULT_THEME="argon"               # LuCI 默认主题（对应 luci-theme-argon）
TIMEZONE="CST-8"                    # 时区（东八区）
ZONENAME="Asia/Shanghai"            # 时区名称
NTP_SERVERS="ntp.aliyun.com time1.cloud.tencent.com ntp.ntsc.ac.cn"   # NTP 服务器
# ======================================================

OPENWRT_DIR="${1:-openwrt}"
UCI_DEFAULTS="$OPENWRT_DIR/files/etc/uci-defaults"

echo ">>> 注入系统个性化配置："
echo "    LAN 口 IP : $LAN_IP"
echo "    后台密码  : $ROOT_PASSWORD"
echo "    主机名    : $HOSTNAME"
echo "    默认主题  : $DEFAULT_THEME"

mkdir -p "$UCI_DEFAULTS"

# ---------- 1. 后台登录密码（SHA-512 哈希写入 shadow，首次启动生效）----------
PASSWD_HASH=$(openssl passwd -6 "$ROOT_PASSWORD")
cat > "$UCI_DEFAULTS/99-root-password" <<EOF
#!/bin/sh
# 设置 root / LuCI 后台登录密码
sed -i "s|^root:[^:]*:|root:$PASSWD_HASH:|" /etc/shadow
exit 0
EOF
chmod +x "$UCI_DEFAULTS/99-root-password"

# ---------- 2. LAN 口 IP 地址 ----------
cat > "$UCI_DEFAULTS/97-network-lan" <<EOF
#!/bin/sh
# 修改 LAN 口 IP 与子网掩码
uci set network.lan.ipaddr='$LAN_IP'
uci set network.lan.netmask='$NETMASK'
uci commit network
exit 0
EOF
chmod +x "$UCI_DEFAULTS/97-network-lan"

# ---------- 3. 主机名 / 时区 / 系统日志 ----------
cat > "$UCI_DEFAULTS/96-system-info" <<EOF
#!/bin/sh
# 设置主机名与时区
uci set system.@system[0].hostname='$HOSTNAME'
uci set system.@system[0].timezone='$TIMEZONE'
uci set system.@system[0].zonename='$ZONENAME'
uci set system.@system[0].log_size='64'
uci commit system
echo '$HOSTNAME' > /proc/sys/kernel/hostname
exit 0
EOF
chmod +x "$UCI_DEFAULTS/96-system-info"

# ---------- 4. NTP 时间服务器 ----------
{
    echo '#!/bin/sh'
    echo '# 设置 NTP 时间服务器'
    echo "uci -q delete system.ntp.server"
    for server in $NTP_SERVERS; do
        echo "uci add_list system.ntp.server='$server'"
    done
    echo "uci set system.ntp.enabled='1'"
    echo "uci commit system"
    echo 'exit 0'
} > "$UCI_DEFAULTS/95-system-ntp"
chmod +x "$UCI_DEFAULTS/95-system-ntp"

# ---------- 5. LuCI 默认主题与界面语言 ----------
cat > "$UCI_DEFAULTS/94-default-theme" <<EOF
#!/bin/sh
# 设置 Argon 为默认主题，界面语言为简体中文
uci set luci.main.mediaurlbase='/luci-static/$DEFAULT_THEME/'
uci set luci.main.lang='zh_cn'
uci commit luci
exit 0
EOF
chmod +x "$UCI_DEFAULTS/94-default-theme"

echo ">>> 系统个性化配置注入完成（files/etc/uci-defaults/）"
