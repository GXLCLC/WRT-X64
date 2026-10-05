#!/bin/bash
# ============================================================
# 系统配置修改脚本（独立维护）
# ------------------------------------------------------------
# 用途：集中定义固件的 LAN IP、后台登录密码、主机名、默认主题
#       等系统信息，由工作流在编译前自动调用，以 uci-defaults
#       形式打包进固件，首次开机自动生效。
# 使用：修改下方变量 → 保存 → 重新触发工作流即可。
# ============================================================

# ==================== 可修改的配置项 ====================
LAN_IP="192.168.1.1"          # LAN 口 IP 地址（后台管理地址）
LAN_NETMASK="255.255.255.0"   # LAN 口子网掩码
ROOT_PASSWORD="password"      # 后台登录密码（root 账户，首次登录后请修改）
HOSTNAME="ImmortalWrt"        # 系统主机名
DEFAULT_LANG="zh_cn"          # LuCI 界面默认语言（简体中文）
DEFAULT_THEME="argon"         # LuCI 默认主题（argon）
TIMEZONE="CST-8"              # 时区
ZONENAME="Asia/Shanghai"      # 时区区域
# ========================================================

# ---------- 以下为自动执行部分，通常无需修改 ----------

# 1. 将 LuCI 默认集合主题由 bootstrap 替换为 argon（默认主题双保险之一）
if [ -f feeds/luci/collections/luci/Makefile ]; then
    sed -i "s/luci-theme-bootstrap/luci-theme-${DEFAULT_THEME}/g" \
        feeds/luci/collections/luci/Makefile
    echo ">>> LuCI 集合默认主题已替换为 ${DEFAULT_THEME}"
fi

# 2. 生成首次启动自动执行的 uci-defaults 脚本（打包进固件 files 目录）
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-system-config <<EOF
#!/bin/sh
# ===== 由 modify_system_config.sh 自动生成，请勿手工编辑 =====
# 首次开机自动执行一次，执行成功后由系统自动删除

# --- 网络配置：LAN 口 IP 与子网掩码 ---
uci set network.lan.proto='static'
uci set network.lan.ipaddr='${LAN_IP}'
uci set network.lan.netmask='${LAN_NETMASK}'
uci commit network

# --- 系统配置：主机名与时区 ---
uci set system.@system[0].hostname='${HOSTNAME}'
uci set system.@system[0].timezone='${TIMEZONE}'
uci set system.@system[0].zonename='${ZONENAME}'
uci commit system

# --- LuCI 配置：默认语言与默认主题（双保险之二）---
uci set luci.main.lang='${DEFAULT_LANG}'
uci set luci.main.mediaurlbase='/luci-static/${DEFAULT_THEME}'
uci commit luci

# --- 账户配置：设置 root 登录密码 ---
echo -e "${ROOT_PASSWORD}\n${ROOT_PASSWORD}" | passwd root

exit 0
EOF

echo ">>> 系统配置已写入 files/etc/uci-defaults/99-custom-system-config"
echo ">>> LAN IP: ${LAN_IP} | 主机名: ${HOSTNAME} | 默认主题: ${DEFAULT_THEME}"
