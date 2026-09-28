#!/bin/bash
# ================================================================
# system_config.sh — OpenWrt 基础系统参数配置脚本
# ----------------------------------------------------------------
# 职责说明：
#   本脚本专门负责修改 OpenWrt（LEDE）基础系统参数，包括：
#     1. LAN 口 IP 地址
#     2. 主机名称（hostname）
#     3. 后台登录用户名（OpenWrt 默认 root，此处可自定义显示名）
#     4. 登录密码
#
# 修改规则：
#   后续如需修改 LAN IP、主机名、账号密码，
#   【仅需修改本文件中的参数区】，无需改动 build.yml 或其他脚本。
#
# 调用时机：
#   工作流拉取 LEDE 源码后、编译前调用。
# ================================================================

set -e  # 任何命令返回非零值立即退出，确保配置失败时终止编译

# ================================================================
# >>>>>>>>>>  参数区（使用者自行修改此处即可）  <<<<<<<<<<
# ================================================================

# LAN 口 IP 地址 —— 路由器管理后台访问地址
LAN_IP="192.168.1.1"

# LAN 口子网掩码
LAN_NETMASK="255.255.255.0"

# 主机名称 —— 显示在 LuCI 后台及终端提示符
HOSTNAME="OpenWrt"

# 后台登录用户名 —— OpenWrt 系统默认 root 账户
# 注意：OpenWrt 基于 root 用户运行，修改用户名需调整多项系统文件，
#       此处保留 root，仅作为 Release 信息展示用。
ROOT_USERNAME="root"

# 登录密码 —— 用于 SSH 登录及 LuCI 后台登录
ROOT_PASSWORD="password"

# 时区设置
TIMEZONE="CST-8"      # 东八区（中国标准时间）
TIMEZONE_AREA="Asia/Shanghai"

# 默认主题设置 —— Argon 主题
DEFAULT_THEME="argon"

# ================================================================
# >>>>>>>>>>  参数区结束（以下为执行逻辑，一般无需修改）  <<<<<<<<<<
# ================================================================

# 获取 LEDE 源码根目录（由工作流通过环境变量传入，默认 ./lede）
LEDE_ROOT="${LEDE_ROOT:-$(pwd)/lede}"

echo "=========================================="
echo "  开始配置 OpenWrt 系统参数"
echo "=========================================="
echo "  LAN IP:     ${LAN_IP}"
echo "  子网掩码:    ${LAN_NETMASK}"
echo "  主机名:      ${HOSTNAME}"
echo "  登录用户:    ${ROOT_USERNAME}"
echo "  时区:        ${TIMEZONE_AREA}"
echo "=========================================="

# ----------------------------------------------------------------
# 1. 修改 LAN 口 IP 地址
#    目标文件：package/base-files/files/etc/config/network
#    该文件定义了 OpenWrt 默认网络接口配置
# ----------------------------------------------------------------
NETWORK_CONF="${LEDE_ROOT}/package/base-files/files/etc/config/network"

if [ -f "${NETWORK_CONF}" ]; then
    echo "[1/5] 正在修改 LAN 口 IP 地址 -> ${LAN_IP}"
    # 替换 lan 接口的 ipaddr 字段
    sed -i "/config interface 'lan'/,/^\s*$/ s|option ipaddr .*|option ipaddr '${LAN_IP}'|" "${NETWORK_CONF}"
    # 替换 lan 接口的 netmask 字段
    sed -i "/config interface 'lan'/,/^\s*$/ s|option netmask .*|option netmask '${LAN_NETMASK}'|" "${NETWORK_CONF}"
    echo "      LAN 口 IP 配置完成"
else
    echo "[警告] 未找到 network 配置文件: ${NETWORK_CONF}"
fi

# ----------------------------------------------------------------
# 2. 修改主机名称
#    目标文件：package/base-files/files/etc/config/system
# ----------------------------------------------------------------
SYSTEM_CONF="${LEDE_ROOT}/package/base-files/files/etc/config/system"

if [ -f "${SYSTEM_CONF}" ]; then
    echo "[2/5] 正在修改主机名 -> ${HOSTNAME}"
    # 替换 hostname 字段
    sed -i "s|option hostname .*|option hostname '${HOSTNAME}'|" "${SYSTEM_CONF}"
    echo "      主机名配置完成"
else
    echo "[警告] 未找到 system 配置文件: ${SYSTEM_CONF}"
fi

# ----------------------------------------------------------------
# 3. 设置 root 登录密码
#    目标文件：package/base-files/files/etc/shadow
#    使用 openssl 生成 SHA-512 密码哈希，写入 shadow 文件
# ----------------------------------------------------------------
SHADOW_CONF="${LEDE_ROOT}/package/base-files/files/etc/shadow"

echo "[3/5] 正在设置 root 登录密码"
# 使用 openssl 生成 SHA-512 加密哈希（-6 表示 SHA-512 方法）
PASSWORD_HASH=$(openssl passwd -6 "${ROOT_PASSWORD}")

if [ -f "${SHADOW_CONF}" ]; then
    # 替换 shadow 文件中 root 行的密码哈希字段
    # shadow 格式：username:password_hash:lastchange:min:max:warn:inactive:expire:reserved
    sed -i "s|^root:[^:]*:|root:${PASSWORD_HASH}:|" "${SHADOW_CONF}"
    echo "      root 密码配置完成"
else
    # 若 shadow 文件不存在，直接创建
    mkdir -p "$(dirname "${SHADOW_CONF}")"
    echo "root:${PASSWORD_HASH}:19000:0:99999:7:::" > "${SHADOW_CONF}"
    echo "      已创建 shadow 文件并写入 root 密码"
fi

# ----------------------------------------------------------------
# 4. 设置系统时区
#    目标文件：package/base-files/files/etc/config/system
# ----------------------------------------------------------------
echo "[4/5] 正在配置系统时区 -> ${TIMEZONE_AREA}"
if [ -f "${SYSTEM_CONF}" ]; then
    # 检查是否已存在 zonename 配置，存在则替换，不存在则追加
    if grep -q "option zonename" "${SYSTEM_CONF}"; then
        sed -i "s|option zonename .*|option zonename '${TIMEZONE_AREA}'|" "${SYSTEM_CONF}"
    else
        # 在 system 配置块的末尾追加时区设置
        sed -i "/^config system/a\\	option zonename '${TIMEZONE_AREA}'" "${SYSTEM_CONF}"
    fi
    # 同步修改 timezone（POSIX 格式时区）
    if grep -q "option timezone" "${SYSTEM_CONF}"; then
        sed -i "s|option timezone .*|option timezone '${TIMEZONE}'|" "${SYSTEM_CONF}"
    else
        sed -i "/^config system/a\\	option timezone '${TIMEZONE}'" "${SYSTEM_CONF}"
    fi
    echo "      时区配置完成"
fi

# ----------------------------------------------------------------
# 5. 设置 Argon 为系统默认主题
#    目标文件：package/base-files/files/etc/config/luci
#    通过修改 mediaurlbase 指向 argon 主题静态资源路径
# ----------------------------------------------------------------
LUCI_CONF="${LEDE_ROOT}/package/base-files/files/etc/config/luci"

echo "[5/5] 正在设置默认主题 -> ${DEFAULT_THEME}"
# 确定主题静态资源路径
case "${DEFAULT_THEME}" in
    argon)
        THEME_URLBASE="/luci-static/argon"
        ;;
    bootstrap)
        THEME_URLBASE="/luci-static/bootstrap"
        ;;
    *)
        THEME_URLBASE="/luci-static/${DEFAULT_THEME}"
        ;;
esac

if [ -f "${LUCI_CONF}" ]; then
    # 若 luci 配置文件已存在 mediaurlbase，则替换
    if grep -q "option mediaurlbase" "${LUCI_CONF}"; then
        sed -i "s|option mediaurlbase .*|option mediaurlbase '${THEME_URLBASE}'|" "${LUCI_CONF}"
    else
        # 不存在则在 config core 'main' 块下追加
        sed -i "/^config core 'main'/a\\	option mediaurlbase '${THEME_URLBASE}'" "${LUCI_CONF}"
    fi
    echo "      默认主题配置完成: ${DEFAULT_THEME} (${THEME_URLBASE})"
else
    # 配置文件不存在则创建
    mkdir -p "$(dirname "${LUCI_CONF}")"
    cat > "${LUCI_CONF}" <<LUCIEOF
config core 'main'
	option lang 'zh_cn'
	option mediaurlbase '${THEME_URLBASE}'
	option resourcebase '/luci-static/resources'
	option ubuspath '/ubus/'

config internal 'themes'
	option Argon '/luci-static/argon'
	option Bootstrap '/luci-static/bootstrap'
LUCIEOF
    echo "      已创建 luci 配置文件并设置默认主题"
fi

# 创建 UCI 默认脚本，确保首次启动时主题生效
UCI_DEFAULTS_DIR="${LEDE_ROOT}/package/base-files/files/etc/uci-defaults"
mkdir -p "${UCI_DEFAULTS_DIR}"
cat > "${UCI_DEFAULTS_DIR}/99-default-theme" <<'UCIEOF'
# 设置默认主题为 Argon
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci
exit 0
UCIEOF
echo "      UCI 默认主题脚本已写入"

echo "=========================================="
echo "  OpenWrt 系统参数配置全部完成！"
echo "=========================================="
