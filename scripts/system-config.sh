#!/bin/bash
#
# system-config.sh —— 独立系统配置脚本（由工作流在 ImmortalWrt 源码根目录内调用）
# 用途：集中修改固件系统级默认配置；后续想改 LAN 口 IP、后台登录密码、
#       主机名、时区、默认主题等，只需维护本脚本，无需改动工作流。
#

set -e

# ============================ 可自定义配置区 ============================
LAN_IP="192.168.2.1"              # LAN 口默认 IP（即后台管理地址）
ROOT_PASSWORD="asdfghjkL666666"   # root 后台登录密码
HOSTNAME="ImmortalWrt"            # 路由器主机名
TIMEZONE_NAME="Asia/Shanghai"     # 时区名称
TIMEZONE_POSIX="CST-8"            # POSIX 时区格式
DEFAULT_THEME="argon"             # 系统默认 LuCI 主题
# =======================================================================

echo "[system-config] LAN IP=${LAN_IP} | 主机名=${HOSTNAME} | 时区=${TIMEZONE_NAME} | 默认主题=${DEFAULT_THEME}"

# ---------------------------------------------------------------------------
# 1. 修改 LAN 口默认 IP（修改 config_generate，首次启动时生成网络配置）
# ---------------------------------------------------------------------------
sed -i "s/192\.168\.1\.1/${LAN_IP}/g" package/base-files/files/bin/config_generate
echo "[system-config] LAN IP 已设置为 ${LAN_IP}"

# ---------------------------------------------------------------------------
# 2. 设置 root 登录密码（openssl 动态生成 SHA-512 哈希写入 shadow）
# ---------------------------------------------------------------------------
PASSWORD_HASH="$(openssl passwd -6 "${ROOT_PASSWORD}")"
sed -i "s|^root:[^:]*:|root:${PASSWORD_HASH}:|" package/base-files/files/etc/shadow
echo "[system-config] root 登录密码已更新"

# ---------------------------------------------------------------------------
# 3. 修改主机名（兼容 ImmortalWrt / OpenWrt 两种默认写法）
# ---------------------------------------------------------------------------
sed -i "s/hostname='ImmortalWrt'/hostname='${HOSTNAME}'/g" package/base-files/files/bin/config_generate
sed -i "s/hostname='OpenWrt'/hostname='${HOSTNAME}'/g" package/base-files/files/bin/config_generate
echo "[system-config] 主机名已设置为 ${HOSTNAME}"

# ---------------------------------------------------------------------------
# 4. 设置固件时区为 Asia/Shanghai（ImmortalWrt 默认即上海时区，此处确保万无一失）
# ---------------------------------------------------------------------------
sed -i "s/zonename='[^']*'/zonename='${TIMEZONE_NAME}'/g" package/base-files/files/bin/config_generate
sed -i "s/timezone='[^']*'/timezone='${TIMEZONE_POSIX}'/g" package/base-files/files/bin/config_generate
echo "[system-config] 时区已设置为 ${TIMEZONE_NAME}"

# ---------------------------------------------------------------------------
# 5. 将 Argon 设为系统默认主题（双保险机制）
#    5.1 修改 luci 集合包的默认主题依赖：bootstrap → argon（编译期生效）
# ---------------------------------------------------------------------------
LUCI_MAKEFILE="feeds/luci/collections/luci/Makefile"
if [ -f "$LUCI_MAKEFILE" ]; then
  sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' "$LUCI_MAKEFILE"
  echo "[system-config] LuCI 默认主题依赖已替换为 luci-theme-argon"
fi

# 5.2 写入 uci-defaults 脚本，首次启动时强制应用 Argon 主题（运行期生效）
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-default-theme <<EOF
# 首次启动时将 LuCI 默认主题设置为 Argon
uci -q set luci.main.mediaurlbase='/luci-static/${DEFAULT_THEME}/'
uci -q commit luci
exit 0
EOF
chmod +x files/etc/uci-defaults/99-custom-default-theme
echo "[system-config] 默认主题 uci-defaults 脚本已写入"

echo "[system-config] 全部系统配置应用完成！"
