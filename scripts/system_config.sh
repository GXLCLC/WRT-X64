#!/bin/bash
# ==============================================================================
# system_config.sh - OpenWrt 基础系统参数配置脚本
# --------------------------------------------------------------------------------
# 脚本职责：专门修改 OpenWrt 基础系统参数，在 LEDE 源码的对应配置文件中写入参数
# 修改范围：LAN 口 IP 地址、主机名称、后台登录用户名、登录密码、时区等
# --------------------------------------------------------------------------------
# 修改规则：
#   后续想要修改 LAN IP、主机名、账号密码，【只修改本脚本顶部参数区】，
#   不需要改动 build.yml，也不需要修改其他脚本。
# 运行位置：LEDE 源码根目录（由 build.yml 指定 working-directory: openwrt）
# 工作流拉取 LEDE 源码并完成 feeds 管理后调用本脚本。
# ==============================================================================
set -e

# ==============================================================================
# ★★★ 系统基础参数区（修改此处即可，无需改动 build.yml 与其他脚本）★★★
# ==============================================================================

# LAN 口 IP 地址（后台访问地址，浏览器输入此 IP 进入 LuCI 后台）
LAN_IP="192.168.1.1"

# 主机名称（系统 hostname）
HOST_NAME="OpenWrt"

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

# base-files 配置生成脚本路径（LEDE 中 LAN/hostname 默认在此文件设置）
CONFIG_GENERATE="package/base-files/files/bin/config_generate"
# base-files 中的 shadow 文件路径（用于写入登录密码）
SHADOW_FILE="package/base-files/files/etc/shadow"
# base-files 中的系统配置文件路径
SYSTEM_CONFIG_FILE="package/base-files/files/etc/config/system"

# ------------------------------------------------------------------------------
# 工具函数：安全地修改文件（避免 sed 特殊字符问题，使用 awk 替换）
# 用法：safe_replace_shadow <shadow文件> <加密密码>
# shadow 文件格式：用户名:加密密码:...（密码为第二个字段）
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
        # shadow 文件不存在则创建（OpenWrt shadow 行格式：用户:密码:LAST:MIN:MAX:WARN:INACTIVE:EXPIRE:RESERVED）
        echo "root:${encrypted_pwd}:17000:0:99999:7:::" > "${shadow_file}"
    fi
}

# ==============================================================================
# 步骤 1：修改 LAN 口 IP 地址
# 在 config_generate 中将默认 LAN IP 替换为自定义 IP
# ==============================================================================
echo ">>> [1/5] 修改 LAN 口 IP 地址为：${LAN_IP}"
if [ -f "${CONFIG_GENERATE}" ]; then
    # config_generate 中默认 LAN IP 为 192.168.1.1
    sed -i "s/192\.168\.1\.1/${LAN_IP}/g" "${CONFIG_GENERATE}"
    echo "    LAN IP 已写入 ${CONFIG_GENERATE}"
else
    echo "    警告：未找到 ${CONFIG_GENERATE}，跳过 LAN IP 修改"
fi

# ==============================================================================
# 步骤 2：修改主机名称
# ==============================================================================
echo ">>> [2/5] 修改主机名为：${HOST_NAME}"
if [ -f "${CONFIG_GENERATE}" ]; then
    # config_generate 中 hostname 通过 set_system_setting hostname 设置，默认值 OpenWrt
    sed -i "s/hostname='OpenWrt'/hostname='${HOST_NAME}'/g" "${CONFIG_GENERATE}"
    sed -i "s/set_system_setting hostname 'OpenWrt'/set_system_setting hostname '${HOST_NAME}'/g" "${CONFIG_GENERATE}" 2>/dev/null || true
    echo "    主机名已写入 ${CONFIG_GENERATE}"
fi
if [ -f "${SYSTEM_CONFIG_FILE}" ]; then
    # 修改 /etc/config/system 中的 hostname 字段
    sed -i "s/option hostname .*/option hostname '${HOST_NAME}'/g" "${SYSTEM_CONFIG_FILE}" 2>/dev/null || true
    echo "    主机名已写入 ${SYSTEM_CONFIG_FILE}"
fi

# ==============================================================================
# 步骤 3：设置后台登录用户名
# OpenWrt 后台默认使用 root 账户，此处通过注释说明，
# 并在 base-files 的 /etc/passwd 中确保 root 账户未锁定
# ==============================================================================
echo ">>> [3/5] 设置后台登录用户名为：${LOGIN_USER}"
PASSWD_FILE="package/base-files/files/etc/passwd"
mkdir -p "$(dirname "${PASSWD_FILE}")"
if [ -f "${PASSWD_FILE}" ]; then
    # 确保 root 行存在且未被锁定（移除可能的 ! 锁定标记）
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
# 步骤 4：设置后台登录密码
# 使用 openssl 生成 MD5 加密密码串（OpenWrt shadow 兼容 $1$ MD5 格式）
# ==============================================================================
echo ">>> [4/5] 设置后台登录密码"
if command -v openssl > /dev/null 2>&1; then
    ENCRYPTED_PASSWORD=$(openssl passwd -1 "${LOGIN_PASSWORD}")
    echo "    使用 openssl 生成加密密码"
else
    # 兜底：使用 mkpasswd
    ENCRYPTED_PASSWORD=$(mkpasswd -m md5 "${LOGIN_PASSWORD}" 2>/dev/null || echo "${LOGIN_PASSWORD}")
    echo "    使用 mkpasswd 生成加密密码"
fi
set_shadow_password "${SHADOW_FILE}" "${ENCRYPTED_PASSWORD}"
echo "    登录密码已写入 ${SHADOW_FILE}"

# ==============================================================================
# 步骤 5：设置时区
# ==============================================================================
echo ">>> [5/5] 设置时区为：${TIMEZONE_DESC}"
if [ -f "${CONFIG_GENERATE}" ]; then
    # config_generate 中默认时区为 UTC，set_system_setting timezone 'UTC'
    sed -i "s/'UTC'/'${TIMEZONE}'/g" "${CONFIG_GENERATE}"
    sed -i "s/'UTC, +00:00'/'${TIMEZONE_DESC}'/g" "${CONFIG_GENERATE}" 2>/dev/null || true
    echo "    时区已写入 ${CONFIG_GENERATE}"
fi

# ==============================================================================
# 将配置参数导出到 .system_config.env，供 gen_release_info.sh 读取
# 这样 Release 页面可自动填充 LAN IP、账号密码等信息
# ==============================================================================
cat > .system_config.env <<EOF
# 由 system_config.sh 自动生成，供 gen_release_info.sh 读取
LAN_IP="${LAN_IP}"
HOST_NAME="${HOST_NAME}"
LOGIN_USER="${LOGIN_USER}"
LOGIN_PASSWORD="${LOGIN_PASSWORD}"
TIMEZONE_DESC="${TIMEZONE_DESC}"
EOF
echo ">>> 系统配置参数已导出到 .system_config.env（供 Release 信息生成使用）"

echo ""
echo "========================================"
echo ">>> system_config.sh 执行完成"
echo "    LAN IP:    ${LAN_IP}"
echo "    主机名:    ${HOST_NAME}"
echo "    用户名:    ${LOGIN_USER}"
echo "    密码:      ${LOGIN_PASSWORD}"
echo "    时区:      ${TIMEZONE_DESC}"
echo "========================================"
