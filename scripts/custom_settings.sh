#!/usr/bin/env bash
#
# custom_settings.sh —— 系统配置信息修改脚本
# 职责：独立维护固件的系统级参数（LAN 口 IP、后台登录密码、主机名、时区、默认主题）。
# 后续如需调整这些参数，只需修改本脚本，无需改动 workflow.yml。
#
# 注意：所有 sed 一律使用 "|" 作为分隔符，避免替换值中含有 "/"（如 Asia/Shanghai）
#       触发 "unknown option to `s'" 错误。
# 约定：任意一步失败立即终止（set -e）。

set -euo pipefail

LAN_IP="192.168.2.1"          # LAN 口 IP 地址
ROOT_PASSWORD="12345678"      # 后台登录密码（root）
HOSTNAME="ImmortalWrt"        # 主机名
TIMEZONE="CST-8"              # 系统时区（POSIX TZ 格式，CST-8 即 UTC+8）
ZONENAME="Asia/Shanghai"      # zoneinfo 名称
DEFAULT_THEME="argon"         # 系统默认主题

CONFIG_GENERATE="package/base-files/files/bin/config_generate"
SHADOW_FILE="package/base-files/files/etc/shadow"

log() { echo -e "\033[1;32m[settings]\033[0m $*"; }

# ---------------------------------------------------------------------------
# 1. 修改 LAN 口 IP（config_generate 中 LAN 口默认地址为 192.168.1.1）
# ---------------------------------------------------------------------------
if [ ! -f "${CONFIG_GENERATE}" ]; then
    echo "[error] 未找到 ${CONFIG_GENERATE}，请在 OpenWrt 源码根目录执行本脚本" >&2
    exit 1
fi
log "设置 LAN 口 IP 为 ${LAN_IP}"
sed -i "s|192\.168\.1\.1|${LAN_IP}|g" "${CONFIG_GENERATE}"

# ---------------------------------------------------------------------------
# 2. 修改后台登录密码（生成 $1$ 前缀的 MD5 crypt 哈希写入 /etc/shadow）
# ---------------------------------------------------------------------------
log "设置 root 登录密码（MD5 crypt）"
PASSWORD_HASH="$(openssl passwd -1 "${ROOT_PASSWORD}")"
if [ -z "${PASSWORD_HASH}" ]; then
    echo "[error] openssl passwd 生成密码哈希失败" >&2
    exit 1
fi
sed -i "s|^root::|root:${PASSWORD_HASH}:|" "${SHADOW_FILE}"

# ---------------------------------------------------------------------------
# 3. 修改主机名（config_generate 默认写入 hostname='ImmortalWrt'）
# ---------------------------------------------------------------------------
log "设置主机名为 ${HOSTNAME}"
sed -i "s|hostname='ImmortalWrt'|hostname='${HOSTNAME}'|" "${CONFIG_GENERATE}"

# ---------------------------------------------------------------------------
# 4/5. 时区、默认主题、界面语言 —— 通过 files/etc/uci-defaults 注入
#      首次启动时由系统自动执行，可靠且不受 sed 分隔符影响
# ---------------------------------------------------------------------------
log "写入 uci-defaults：时区 ${ZONENAME} / 默认主题 ${DEFAULT_THEME}"
UCI_DEFAULTS_DIR="files/etc/uci-defaults"
mkdir -p "${UCI_DEFAULTS_DIR}"
cat > "${UCI_DEFAULTS_DIR}/99-custom-settings" <<UCIEOF
#!/bin/sh
# 首次启动自动应用的系统配置（由 scripts/custom_settings.sh 生成）
uci -q set system.@system[0].timezone='${TIMEZONE}'
uci -q set system.@system[0].zonename='${ZONENAME}'
uci -q set system.@system[0].hostname='${HOSTNAME}'
uci -q set luci.main.mediaurlbase='/luci-static/${DEFAULT_THEME}'
uci -q set luci.main.lang='zh_cn'
uci -q commit system
uci -q commit luci
exit 0
UCIEOF
chmod 755 "${UCI_DEFAULTS_DIR}/99-custom-settings"

log "系统配置修改完成：LAN=${LAN_IP} / 主机名=${HOSTNAME} / 时区=${ZONENAME}(${TIMEZONE}) / 主题=${DEFAULT_THEME}"
