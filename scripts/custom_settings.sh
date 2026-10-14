#!/usr/bin/env bash
#
# custom_settings.sh —— 系统配置信息修改脚本
# 职责：独立维护固件的系统级参数（LAN 口 IP、后台登录密码、主机名、时区、默认主题）。
# 后续如需调整这些参数，只需修改本脚本，无需改动 workflow.yml。
#
# 约定：任意一步失败立即终止。

set -euo pipefail

LAN_IP="192.168.2.1"          # LAN 口 IP 地址
ROOT_PASSWORD="12345678"      # 后台登录密码（root）
HOSTNAME="ImmortalWrt"        # 主机名
TIMEZONE="Asia/Shanghai"      # 系统时区
ZONENAME="Asia/Shanghai"      # zoneinfo 名称
DEFAULT_THEME="argon"         # 系统默认主题

log() { echo -e "\033[1;32m[settings]\033[0m $*"; }

# ---------------------------------------------------------------------------
# 1. 修改 LAN 口 IP
# ---------------------------------------------------------------------------
log "设置 LAN 口 IP 为 ${LAN_IP}"
sed -i "s/192\.168\.[0-9]*\.[0-9]*/${LAN_IP}/g" package/base-files/files/bin/config_generate

# ---------------------------------------------------------------------------
# 2. 修改后台登录密码（生成 $1$ 前缀的 MD5 crypt 哈希写入 /etc/shadow）
# ---------------------------------------------------------------------------
log "设置 root 登录密码（MD5 crypt）"
PASSWORD_HASH="$(openssl passwd -1 "${ROOT_PASSWORD}")"
if [ -z "${PASSWORD_HASH}" ]; then
    echo "[error] openssl passwd 生成密码哈希失败" >&2
    exit 1
fi
sed -i "s|^root::|root:${PASSWORD_HASH}:|" package/base-files/files/etc/shadow

# ---------------------------------------------------------------------------
# 3. 修改主机名
# ---------------------------------------------------------------------------
log "设置主机名为 ${HOSTNAME}"
sed -i "s/set system\.@system\[-1\]\.hostname='.*'/set system.@system[-1].hostname='${HOSTNAME}'/" package/base-files/files/bin/config_generate

# ---------------------------------------------------------------------------
# 4. 修改系统时区为 Asia/Shanghai
# ---------------------------------------------------------------------------
log "设置系统时区为 ${TIMEZONE}"
sed -i "s/set system\.@system\[-1\]\.timezone='.*'/set system.@system[-1].timezone='${TIMEZONE}'/" package/base-files/files/bin/config_generate
sed -i "s/set system\.@system\[-1\]\.zonename='.*'/set system.@system[-1].zonename='${ZONENAME}'/" package/base-files/files/bin/config_generate

# ---------------------------------------------------------------------------
# 5. 设置默认主题为 argon
#    在 config_generate 的 luci 段中写入默认主题配置
# ---------------------------------------------------------------------------
log "设置默认主题为 ${DEFAULT_THEME}"
if grep -q "luci.main.lang" package/base-files/files/bin/config_generate 2>/dev/null; then
    sed -i "s/set luci\.main\.lang='.*'/set luci.main.lang='zh_cn'/" package/base-files/files/bin/config_generate
fi
sed -i "s/option mediaurlbase .*/option mediaurlbase '\/luci-static\/${DEFAULT_THEME}'/" package/base-files/files/bin/config_generate 2>/dev/null || true

log "系统配置信息修改完成：LAN=${LAN_IP} / 密码=${ROOT_PASSWORD} / 主机名=${HOSTNAME} / 时区=${TIMEZONE} / 主题=${DEFAULT_THEME}"
