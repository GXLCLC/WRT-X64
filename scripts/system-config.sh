#!/bin/bash
# ============================================================================
# 系统配置定制脚本（独立维护）
# ----------------------------------------------------------------------------
# 用途：集中修改固件的默认系统信息。工作流仅负责调用本脚本，
#       后续如需调整 LAN IP、后台登录密码、主机名、时区、默认主题等，
#       只需修改本脚本后重新触发编译，无需改动 GitHub Actions 工作流。
# 执行方式：在 openwrt 源码根目录下执行（由工作流自动调用）
# ============================================================================
set -e

# =====================【可自行修改的配置区】=====================
LAN_IP="192.168.2.1"            # 固件默认 LAN IP（即管理地址）
LAN_NETMASK="255.255.255.0"     # LAN 子网掩码
ROOT_USER="root"                # 后台登录用户名
ROOT_PASSWORD="12345678"        # 后台登录密码（需求默认值）
HOSTNAME="ImmortalWrt-X86"      # 系统主机名
TIMEZONE="CST-8"                # 系统时区（POSIX 格式）
TIMEZONE_NAME="Asia/Shanghai"   # 系统时区名称
DEFAULT_THEME="argon"           # LuCI 默认主题（配合 luci-theme-argon 使用）
# ================================================================

# 固件首次开机自动执行的 uci-defaults 脚本路径（执行成功后系统自动删除）
UCIDEFAULTS_FILE="package/base-files/files/etc/uci-defaults/99-custom-system-config"

echo ">>> [系统配置] 开始写入自定义系统配置..."
echo ">>> [系统配置] LAN IP=${LAN_IP} | 用户名=${ROOT_USER} | 密码=${ROOT_PASSWORD} | 主机名=${HOSTNAME}"

# ---------- 1. 编译期固化默认 LAN IP（修改 network 配置生成器） ----------
CONFIG_GENERATE="package/base-files/files/bin/config_generate"
if [ -f "$CONFIG_GENERATE" ]; then
    # 将 config_generate 中默认的 192.168.1.1 全部替换为自定义 LAN IP
    sed -i "s/192\.168\.1\.1/${LAN_IP}/g" "$CONFIG_GENERATE"
    echo ">>> [系统配置] 默认 LAN IP 已在编译期固化为: ${LAN_IP}"
fi

# ---------- 2. 生成首次开机 uci-defaults 脚本（IP/密码/主机名/时区/默认主题） ----------
mkdir -p "$(dirname "$UCIDEFAULTS_FILE")"
cat > "$UCIDEFAULTS_FILE" <<EOF
#!/bin/sh
# 由 scripts/system-config.sh 自动生成的系统定制脚本（首次开机执行，成功后自动删除）

# 设置 LAN 口 IP、主机名、时区、LuCI 默认主题
uci -q batch <<UCI_EOF
set network.lan.ipaddr='${LAN_IP}'
set network.lan.netmask='${LAN_NETMASK}'
commit network
set system.@system[0].hostname='${HOSTNAME}'
set system.@system[0].timezone='${TIMEZONE}'
set system.@system[0].zonename='${TIMEZONE_NAME}'
commit system
set luci.main.mediaurlbase='/luci-static/${DEFAULT_THEME}'
commit luci
UCI_EOF

# 设置 root 后台登录密码
echo '${ROOT_USER}:${ROOT_PASSWORD}' | chpasswd

exit 0
EOF
chmod +x "$UCIDEFAULTS_FILE"

echo ">>> [系统配置] uci-defaults 定制脚本已生成: ${UCIDEFAULTS_FILE}"
echo ">>> [系统配置] 系统配置写入完成。"
