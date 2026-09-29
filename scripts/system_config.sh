#!/bin/bash
# ==============================================================================
# system_config.sh - ImmortalWrt 基础系统参数配置脚本
# --------------------------------------------------------------------------------
# 脚本职责：修改 ImmortalWrt 基础系统参数，在源码对应配置文件中写入参数
# 修改范围：LAN 口 IP 地址、主机名称、后台登录用户名、登录密码、时区、默认主题
# --------------------------------------------------------------------------------
# 修改规则：
#   后续想要修改 LAN IP、主机名、账号密码，【只修改本脚本顶部参数区】，
#   不需要改动 build.yml，也不需要修改其他脚本。
# 运行位置：ImmortalWrt 源码根目录（由 build.yml 指定 working-directory）
# ==============================================================================
set -euo pipefail

# ==============================================================================
# ★★★ 系统基础参数区（修改此处即可，无需改动 build.yml 与其他脚本）★★★
# ==============================================================================

# LAN 口 IP 地址（后台访问地址，浏览器输入此 IP 进入 LuCI 后台）
LAN_IP="192.168.1.1"

# 主机名称（系统 hostname）
HOST_NAME="ImmortalWrt"

# 后台登录用户名（OpenWrt 默认 root）
LOGIN_USER="root"

# 后台登录密码（明文，脚本会自动使用 openssl 加密后写入 shadow）
LOGIN_PASSWORD="password"

# 时区设置
TIMEZONE="CST-8"
TIMEZONE_DESC="Asia/Shanghai"

# ==============================================================================
# 以下为脚本实现，一般无需修改
# ==============================================================================

# base-files 配置生成脚本路径（LAN/hostname 默认在此文件设置）
CONFIG_GENERATE="package/base-files/files/bin/config_generate"
# base-files 中的 shadow 文件路径（用于写入登录密码）
SHADOW_FILE="package/base-files/files/etc/shadow"
# base-files 中的系统配置文件路径
SYSTEM_CONFIG_FILE="package/base-files/files/etc/config/system"

# ------------------------------------------------------------------------------
# 工具函数：安全地修改 shadow 文件密码字段
# ------------------------------------------------------------------------------
set_shadow_password() {
    local shadow_file="$1"
    local encrypted_pwd="$2"
    mkdir -p "$(dirname "${shadow_file}")"
    if [ -f "${shadow_file}" ]; then
        # 使用 awk 安全替换 root 行的密码字段，避免 sed 对 $ / 等字符的解析问题
        awk -v passwd="${encrypted_pwd}" -F: 'BEGIN{OFS=":"} {
            if ($1 == "root") { $2 = passwd }
            print
        }' "${shadow_file}" > "${shadow_file}.tmp" && mv "${shadow_file}.tmp" "${shadow_file}"
    else
        # shadow 行格式：用户:密码:LAST:MIN:MAX:WARN:INACTIVE:EXPIRE:RESERVED
        echo "root:${encrypted_pwd}:17000:0:99999:7:::" > "${shadow_file}"
    fi
}

# ==============================================================================
# 步骤 1：修改 LAN 口 IP 地址
# ==============================================================================
echo ">>> [1/6] 修改 LAN 口 IP 地址为：${LAN_IP}"
if [ -f "${CONFIG_GENERATE}" ]; then
    # config_generate 中默认 LAN IP 为 192.168.1.1
    sed -i "s/192\.168\.1\.1/${LAN_IP}/g" "${CONFIG_GENERATE}"
    echo "    LAN IP 已写入 ${CONFIG_GENERATE}"
else
    echo "    警告：未找到 ${CONFIG_GENERATE}，跳过 LAN IP 修改"
fi

# ==============================================================================
# 步骤 2：修改主机名称
# ImmortalWrt 默认主机名可能是 'ImmortalWrt' 或 'OpenWrt'，同时匹配两种写法
# ==============================================================================
echo ">>> [2/6] 修改主机名为：${HOST_NAME}"
if [ -f "${CONFIG_GENERATE}" ]; then
    sed -i "s/hostname='ImmortalWrt'/hostname='${HOST_NAME}'/g" "${CONFIG_GENERATE}"
    sed -i "s/hostname='OpenWrt'/hostname='${HOST_NAME}'/g" "${CONFIG_GENERATE}"
    sed -i "s/hostname='LEDE'/hostname='${HOST_NAME}'/g" "${CONFIG_GENERATE}"
    sed -i "s/set_system_setting hostname 'ImmortalWrt'/set_system_setting hostname '${HOST_NAME}'/g" "${CONFIG_GENERATE}" 2>/dev/null || true
    sed -i "s/set_system_setting hostname 'OpenWrt'/set_system_setting hostname '${HOST_NAME}'/g" "${CONFIG_GENERATE}" 2>/dev/null || true
    echo "    主机名已写入 ${CONFIG_GENERATE}"
fi
if [ -f "${SYSTEM_CONFIG_FILE}" ]; then
    sed -i "s/option hostname .*/option hostname '${HOST_NAME}'/g" "${SYSTEM_CONFIG_FILE}" 2>/dev/null || true
    echo "    主机名已写入 ${SYSTEM_CONFIG_FILE}"
fi

# ==============================================================================
# 步骤 3：设置后台登录用户名（确保 root 账户未锁定）
# ==============================================================================
echo ">>> [3/6] 设置后台登录用户名为：${LOGIN_USER}"
PASSWD_FILE="package/base-files/files/etc/passwd"
mkdir -p "$(dirname "${PASSWD_FILE}")"
if [ -f "${PASSWD_FILE}" ]; then
    if grep -q "^${LOGIN_USER}:" "${PASSWD_FILE}"; then
        sed -i "s|^${LOGIN_USER}:x:|${LOGIN_USER}:x:|" "${PASSWD_FILE}"
        echo "    用户 ${LOGIN_USER} 已存在且已启用"
    else
        echo "${LOGIN_USER}:x:0:0:${LOGIN_USER}:/root:/bin/ash" >> "${PASSWD_FILE}"
        echo "    已添加用户 ${LOGIN_USER}"
    fi
else
    echo "${LOGIN_USER}:x:0:0:${LOGIN_USER}:/root:/bin/ash" > "${PASSWD_FILE}"
    echo "    已创建 passwd 文件并添加用户 ${LOGIN_USER}"
fi

# ==============================================================================
# 步骤 4：设置后台登录密码（openssl MD5 加密）
# ==============================================================================
echo ">>> [4/6] 设置后台登录密码"
if command -v openssl > /dev/null 2>&1; then
    ENCRYPTED_PASSWORD=$(openssl passwd -1 "${LOGIN_PASSWORD}")
    echo "    使用 openssl 生成加密密码"
else
    ENCRYPTED_PASSWORD=$(mkpasswd -m md5 "${LOGIN_PASSWORD}" 2>/dev/null || echo "${LOGIN_PASSWORD}")
    echo "    使用 mkpasswd 生成加密密码"
fi
set_shadow_password "${SHADOW_FILE}" "${ENCRYPTED_PASSWORD}"
echo "    登录密码已写入 ${SHADOW_FILE}"

# ==============================================================================
# 步骤 5：设置时区
# ==============================================================================
echo ">>> [5/6] 设置时区为：${TIMEZONE_DESC}"
if [ -f "${CONFIG_GENERATE}" ]; then
    sed -i "s/'UTC'/'${TIMEZONE}'/g" "${CONFIG_GENERATE}"
    sed -i "s/'UTC, +00:00'/'${TIMEZONE_DESC}'/g" "${CONFIG_GENERATE}" 2>/dev/null || true
    echo "    时区已写入 ${CONFIG_GENERATE}"
fi

# ==============================================================================
# 步骤 6：设置 Argon 为 LuCI 默认主题
# 仅安装 luci-theme-argon 包不会自动切换主题，需要在 /etc/config/luci 中
# 指定 mediaurlbase 为 /luci-static/argon 才会生效。
# 采用 uci-defaults 脚本方式：首次启动时自动执行 uci set 命令。
# ==============================================================================
echo ">>> [6/6] 设置 Argon 为 LuCI 默认主题"
UCI_DEFAULTS_DIR="package/base-files/files/etc/uci-defaults"
mkdir -p "${UCI_DEFAULTS_DIR}"
cat > "${UCI_DEFAULTS_DIR}/99-set-argon-theme" <<'UCIEOF'
#!/bin/sh
# 由 system_config.sh 自动生成：首次启动时将 LuCI 默认主题设为 Argon
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci
exit 0
UCIEOF
chmod +x "${UCI_DEFAULTS_DIR}/99-set-argon-theme"
echo "    已创建 uci-defaults 脚本：${UCI_DEFAULTS_DIR}/99-set-argon-theme"
echo "    Argon 主题将在首次启动时自动设为默认"

# ==============================================================================
# 导出配置参数到 .system_config.env，供 gen_release_info.sh 读取
# ==============================================================================
cat > .system_config.env <<EOF
# 由 system_config.sh 自动生成，供 gen_release_info.sh 读取
LAN_IP="${LAN_IP}"
HOST_NAME="${HOST_NAME}"
LOGIN_USER="${LOGIN_USER}"
LOGIN_PASSWORD="${LOGIN_PASSWORD}"
TIMEZONE_DESC="${TIMEZONE_DESC}"
EOF
echo ">>> 系统配置参数已导出到 .system_config.env"

echo ""
echo "========================================"
echo ">>> system_config.sh 执行完成"
echo "    LAN IP:    ${LAN_IP}"
echo "    主机名:    ${HOST_NAME}"
echo "    用户名:    ${LOGIN_USER}"
echo "    密码:      ${LOGIN_PASSWORD}"
echo "    时区:      ${TIMEZONE_DESC}"
echo "    默认主题:  Argon"
echo "========================================"
