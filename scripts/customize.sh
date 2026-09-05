#!/bin/bash
# 拉取 easytier
rm -rf package/luci-app-easytier
git clone https://github.com/EasyTier/luci-app-easytier package/luci-app-easytier

#拉取smartdns
rm -rf package/smartdns
git clone https://github.com/pymumu/smartdns package/smartdns
# ======================================================================
#  OpenWrt 固件自定义脚本（改这一个文件就够了）
# ----------------------------------------------------------------------
#  这个脚本干什么：
#    1. 在编译好的固件里写入"首次启动自动执行"的定制脚本
#       （改 LAN IP、设语言、设时区、设主机名 等）
#    2. 把你在这里设的 LAN_IP/账号/密码等信息输出给工作流，
#       让 GitHub Release 发布页能自动展示对应信息
#
#  改哪里：只改下面"自定义区"那几行变量，不用动工作流、不用动 config
#  机制说明：
#    本脚本会在 openwrt/files/etc/uci-defaults/ 下生成一个脚本，
#    OpenWrt 首次开机时会自动执行一次它，执行后自动删除。
#    这是 OpenWrt 官方推荐的"首次启动定制"方式，干净、不碰源码、可移植。
# ======================================================================









# ====================== 自定义区（改这里就行）======================

# 固件默认 LAN IP（路由器管理地址，刷完后用浏览器访问它进后台）
LAN_IP="192.168.1.1"

# 固件默认 LAN 子网掩码（一般用 255.255.255.0，即 /24）
LAN_NETMASK="255.255.255.0"

# 默认登录账号（OpenWrt 固定用 root，一般不用改）
LAN_USER="root"

# 默认登录密码（lede 官方默认是 password；改成空串 "" 表示无密码）
LAN_PASSWORD="password"

# 管理后台默认语言（zh_cn = 简体中文，en = 英文）
# 注意：中文需要在 config/x86_64.config 里启用 CONFIG_LUCI_LANG_zh_Hans=y
LANGUAGE="zh_cn"

# 系统时区（Asia/Shanghai = 北京时间）
TIMEZONE="Asia/Shanghai"

# 主机名（路由器在网络里的名字）
HOSTNAME="OpenWrt"

# ==================== 自定义区结束，下面一般不用动 ====================

# 接收工作流传进来的 OpenWrt 源码目录路径（第一个参数）
OPENWRT_DIR="${1:-openwrt}"

echo "================ customize.sh 开始执行 ================"
echo "OpenWrt 源码目录: $OPENWRT_DIR"

# ---- 1. 生成"首次启动定制"脚本（uci-defaults 机制）----
# 路径说明：openwrt/files/ 下的文件会按原样复制进固件根目录
#           /etc/uci-defaults/ 里的脚本会在路由器首次启动时自动跑一次
UCI_DEFAULTS_DIR="$OPENWRT_DIR/files/etc/uci-defaults"
mkdir -p "$UCI_DEFAULTS_DIR"

# 这里用 zzz- 前缀，让本脚本在系统自带脚本之后执行（数字/字母序在后）
cat > "$UCI_DEFAULTS_DIR/zzz-custom-settings" <<CUSTOM_EOF
#!/bin/sh
# ===== 本脚本由云编译 customize.sh 自动生成 =====
# 在路由器首次启动时自动执行一次，用于覆盖默认设置

# 修改 LAN 口 IP 地址
uci set network.lan.ipaddr='$LAN_IP'
uci set network.lan.netmask='$LAN_NETMASK'
uci commit network

# 设置管理后台默认语言
uci set luci.main.lang='$LANGUAGE'
# 将 Argon 设为默认主题（注意：光安装主题不会自动启用它，必须写这条才会生效；
# 若固件里没装 argon，LuCI 会自动回退到默认主题，不影响使用）
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci

# 设置系统时区为北京时间
uci set system.@system[0].timezone='$TIMEZONE'
uci set system.@system[0].zonename='$TIMEZONE'
uci commit system

# 设置主机名
uci set system.@system[0].hostname='$HOSTNAME'
uci commit system

# 设置 root 密码（非空时才改；为空则保持 lede 默认）
CUSTOM_EOF

# 用单独的 echo 追加密码设置行（避免 $LAN_PASSWORD 被 heredoc 当成变量提前展开）
# 如果密码为空，就不写密码行，保持 lede 默认无密码
# 注意：用 printf 而非 echo -e，因为 busybox 的 echo 对 -e 的支持不一致
if [ -n "$LAN_PASSWORD" ]; then
    echo "printf '$LAN_PASSWORD\n$LAN_PASSWORD\n' | passwd root >/dev/null 2>&1" >> "$UCI_DEFAULTS_DIR/zzz-custom-settings"
fi

# uci-defaults 脚本末尾要退出 0，表示执行成功
echo "" >> "$UCI_DEFAULTS_DIR/zzz-custom-settings"
echo "exit 0" >> "$UCI_DEFAULTS_DIR/zzz-custom-settings"
chmod +x "$UCI_DEFAULTS_DIR/zzz-custom-settings"

echo "已生成首次启动定制脚本:"
cat "$UCI_DEFAULTS_DIR/zzz-custom-settings"

# ---- 2. 把自定义值输出给工作流（发布页展示用）----
# 写成 KEY=VALUE 格式，工作流用 source 命令导入即可
INFO_FILE="${GITHUB_WORKSPACE:-$(pwd)}/build_info.env"
cat > "$INFO_FILE" <<ENV_EOF
LAN_IP=$LAN_IP
LAN_USER=$LAN_USER
LAN_PASSWORD=$LAN_PASSWORD
LANGUAGE=$LANGUAGE
TIMEZONE=$TIMEZONE
HOSTNAME=$HOSTNAME
ENV_EOF

echo "已生成 build_info.env（供发布页使用）:"
cat "$INFO_FILE"

echo "================ customize.sh 执行完毕 ================"
