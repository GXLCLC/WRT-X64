#!/bin/bash
#
# system-config.sh —— 独立系统配置脚本
# 修改 LAN IP / 密码 / 主机名 / 时区 / 默认主题，只需维护本文件，不动工作流
#
# 【注意】不要修改 files/etc/config/network——编译期不存在该文件，
#         它是设备首次启动后由 uci 生成的；必须改 config_generate 模板
#

set -e

# ============================ 可自定义配置区 ============================
LAN_IP="192.168.2.1"
ROOT_PASSWORD="asdfghjkL666666"
HOSTNAME="ImmortalWrt"
TIMEZONE_NAME="Asia/Shanghai"
TIMEZONE_POSIX="CST-8"
DEFAULT_THEME="argon"
# =======================================================================

# 1. LAN 口默认 IP（config_generate 为首次启动生成网络配置的模板）
#    分隔符用 #，即使以后改成带 CIDR 的写法（192.168.2.1/24）也不会冲突
sed -i "s#192\.168\.1\.1#${LAN_IP}#g" package/base-files/files/bin/config_generate
echo "[system-config] LAN IP 已设置为 ${LAN_IP}"

# 2. root 登录密码：SHA-512 哈希字符集含 "/"，因此分隔符必须用 | 而非 /
PASSWORD_HASH="$(openssl passwd -6 "${ROOT_PASSWORD}")"
sed -i "s|^root:[^:]*:|root:${PASSWORD_HASH}:|" package/base-files/files/etc/shadow
echo "[system-config] root 登录密码已更新"

# 3. 主机名
sed -i "s#hostname='ImmortalWrt'#hostname='${HOSTNAME}'#g" package/base-files/files/bin/config_generate
sed -i "s#hostname='OpenWrt'#hostname='${HOSTNAME}'#g" package/base-files/files/bin/config_generate

# 4. 时区
sed -i "s#zonename='[^']*'#zonename='${TIMEZONE_NAME}'#g" package/base-files/files/bin/config_generate
sed -i "s#timezone='[^']*'#timezone='${TIMEZONE_POSIX}'#g" package/base-files/files/bin/config_generate

# 5. 默认主题 Argon（编译期依赖替换 + 运行期 uci-defaults 双保险）
LUCI_MAKEFILE="feeds/luci/collections/luci/Makefile"
if [ -f "$LUCI_MAKEFILE" ]; then
    sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' "$LUCI_MAKEFILE"
fi
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-default-theme <<EOF
# 首次启动时将 LuCI 默认主题设置为 Argon
uci -q set luci.main.mediaurlbase='/luci-static/${DEFAULT_THEME}/'
uci -q commit luci
exit 0
EOF
chmod +x files/etc/uci-defaults/99-custom-default-theme

echo "[system-config] 全部系统配置应用完成"