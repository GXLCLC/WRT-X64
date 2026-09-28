#!/bin/bash
# ==============================================================================
# gen_release_info.sh - Release 信息生成辅助脚本
# --------------------------------------------------------------------------------
# 脚本职责：编译完成自动读取 system_config.sh 内配置、内核版本、插件清单等信息，
#           生成 Release 页面 markdown 正文，输出到标准输出（stdout）。
# 用法：bash scripts/gen_release_info.sh > release_body.md
# 运行位置：仓库根目录（由 build.yml 直接调用，未指定 working-directory）
# 说明：
#   - 从 scripts/system_config.sh 解析系统参数（不执行该脚本，避免修改源码）
#   - 从 openwrt/ 源码目录读取内核版本与固件版本
#   - 从 config/.config 读取已安装插件清单
#   - 优先使用 docs/release_template.md 模板，无模板时输出默认格式
# ==============================================================================
set -e

# ==============================================================================
# 路径与文件常量
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPENWRT_DIR="${REPO_ROOT}/openwrt"
SYSTEM_CONFIG="${SCRIPT_DIR}/system_config.sh"
CONFIG_FILE="${REPO_ROOT}/config/.config"
TEMPLATE_FILE="${REPO_ROOT}/docs/release_template.md"

# ==============================================================================
# 工具函数：从 system_config.sh 中解析变量值（不执行脚本，仅 grep 提取）
# 用法：extract_var <变量名>
# 支持三种赋值语法：VAR="value"、VAR='value'、VAR=value
# ==============================================================================
extract_var() {
    local var="$1"
    grep -E "^${var}=" "${SYSTEM_CONFIG}" 2>/dev/null | head -1 | \
        sed -E "s/^${var}=\"([^\"]*)\".*$/\1/" | \
        sed -E "s/^${var}='([^']*)'.*$/\1/" | \
        sed -E "s/^${var}=([^#]*?)\s*(#.*)?$/\1/"
}

# ==============================================================================
# 读取系统配置参数（从 system_config.sh 顶部参数区解析）
# ==============================================================================
LAN_IP=$(extract_var LAN_IP)
HOST_NAME=$(extract_var HOST_NAME)
LOGIN_USER=$(extract_var LOGIN_USER)
LOGIN_PASSWORD=$(extract_var LOGIN_PASSWORD)

# 提供默认值，避免空值
LAN_IP="${LAN_IP:-192.168.1.1}"
HOST_NAME="${HOST_NAME:-OpenWrt}"
LOGIN_USER="${LOGIN_USER:-root}"
LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"

# ==============================================================================
# 读取内核版本（从 LEDE 源码 include/kernel-version.mk 或 .config）
# ==============================================================================
KERNEL_VERSION="未知"
# 优先从 .config 中读取（make defconfig 后会写入 CONFIG_LINUX_*_VERSION）
if [ -f "${OPENWRT_DIR}/.config" ]; then
    KV_MAJOR=$(grep -E "^CONFIG_LINUX_KERNEL_MAJOR_VERSION=" "${OPENWRT_DIR}/.config" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    KV_MINOR=$(grep -E "^CONFIG_LINUX_KERNEL_MINOR_VERSION=" "${OPENWRT_DIR}/.config" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    KV_PATCH=$(grep -E "^CONFIG_LINUX_KERNEL_PATCH=" "${OPENWRT_DIR}/.config" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    if [ -n "${KV_MAJOR}" ] && [ -n "${KV_MINOR}" ]; then
        KERNEL_VERSION="${KV_MAJOR}.${KV_MINOR}"
        [ -n "${KV_PATCH}" ] && KERNEL_VERSION="${KERNEL_VERSION}.${KV_PATCH}"
    fi
fi
# 兜底：从 include/kernel-version.mk 读取
if [ "${KERNEL_VERSION}" = "未知" ] && [ -f "${OPENWRT_DIR}/include/kernel-version.mk" ]; then
    KV=$(grep -E "^LINUX_VERSION[[:space:]]*[:?]?=" "${OPENWRT_DIR}/include/kernel-version.mk" 2>/dev/null | \
         head -1 | sed -E 's/.*=\s*//' | tr -d '"' | tr -d "'" | sed 's/[[:space:]]*$//')
    [ -n "${KV}" ] && KERNEL_VERSION="${KV}"
fi

# ==============================================================================
# 读取固件版本（从 LEDE 源码 git 信息）
# ==============================================================================
FIRMWARE_VERSION="未知"
if [ -d "${OPENWRT_DIR}/.git" ]; then
    # 优先使用 tag，无 tag 则使用 commit hash + 日期
    FIRMWARE_VERSION=$(cd "${OPENWRT_DIR}" && git describe --tags --always 2>/dev/null || \
                       git log -1 --format='%h %ci' 2>/dev/null || echo "未知")
fi

# 编译日期
BUILD_DATE=$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')

# ==============================================================================
# 读取 LEDE commit 信息（步骤 5 中生成）
# ==============================================================================
LEDE_COMMIT="未知"
if [ -f "${OPENWRT_DIR}/LEDE_COMMIT_INFO.txt" ]; then
    LEDE_COMMIT=$(cat "${OPENWRT_DIR}/LEDE_COMMIT_INFO.txt" | tr '\n' ' ')
fi

# ==============================================================================
# 读取已安装插件清单（从 config/.config 中提取 CONFIG_PACKAGE_*=y 的行）
# 每行展示一个插件，方便使用者快速查阅
# 注意：仅输出用户可见的 LuCI 应用与核心服务包，
#       不输出 kmod-* 内核驱动、lib-* 库依赖等底层包（用户不需要关心）
# ==============================================================================
generate_package_list() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "（未找到 config/.config 配置文件）"
        return
    fi
    # 提取 =y 的 CONFIG_PACKAGE_ 行，去掉前缀与后缀
    # 白名单：仅输出用户指定的插件（及其 LuCI 界面对应包），不输出依赖与驱动
    grep -E "^CONFIG_PACKAGE_" "${CONFIG_FILE}" | grep "=y$" | \
        sed -E 's/^CONFIG_PACKAGE_([^=]*)=y.*$/\1/' | \
        grep -E "^(luci-theme-argon|luci-app-argon-config|smartdns|luci-app-smartdns|adguardhome|luci-app-adguardhome|ddnsto|luci-app-ddnsto|easytier|luci-app-easytier|turboacc|luci-app-turboacc|mwan3|luci-app-mwan3|nlbwmon|luci-app-nlbwmon|oaf|luci-app-oaf)$" | \
        sort -u
}

PACKAGES=$(generate_package_list)

# ==============================================================================
# 输出 Release markdown 正文
# 优先使用模板（替换占位符），无模板时输出默认格式
# --------------------------------------------------------------------------------
# 实现说明：使用 bash 参数扩展 ${var//pattern/replacement} 替换占位符，
#           避免 sed 在替换多行 PACKAGES 内容时因换行符导致命令异常中断，
#           同时规避 sed/awk 对 & / \ 等特殊字符的解析问题。
# ==============================================================================
if [ -f "${TEMPLATE_FILE}" ]; then
    # 逐行读取模板，对每行执行占位符替换后输出
    # 支持多行内容（如 {{PACKAGES}}）安全替换
    while IFS= read -r line || [ -n "${line}" ]; do
        line="${line//\{\{LAN_IP\}\}/${LAN_IP}}"
        line="${line//\{\{HOST_NAME\}\}/${HOST_NAME}}"
        line="${line//\{\{LOGIN_USER\}\}/${LOGIN_USER}}"
        line="${line//\{\{LOGIN_PASSWORD\}\}/${LOGIN_PASSWORD}}"
        line="${line//\{\{KERNEL_VERSION\}\}/${KERNEL_VERSION}}"
        line="${line//\{\{FIRMWARE_VERSION\}\}/${FIRMWARE_VERSION}}"
        line="${line//\{\{BUILD_DATE\}\}/${BUILD_DATE}}"
        line="${line//\{\{LEDE_COMMIT\}\}/${LEDE_COMMIT}}"
        line="${line//\{\{PACKAGES\}\}/${PACKAGES}}"
        printf '%s\n' "${line}"
    done < "${TEMPLATE_FILE}"
else
    # 无模板时输出默认格式
    cat <<EOF
# OpenWrt X86_64 固件发布

## 固件信息
- 编译日期：${BUILD_DATE}
- 固件版本：${FIRMWARE_VERSION}
- LEDE 源码：${LEDE_COMMIT}
- 内核版本：${KERNEL_VERSION}
- 目标架构：X86_64
- 镜像格式：squashfs combined
- overlay 分区：2G 可写空间

## 后台登录信息
- LAN IP：${LAN_IP}
- 主机名：${HOST_NAME}
- 用户名：${LOGIN_USER}
- 密码：${LOGIN_PASSWORD}

## 已安装插件清单
${PACKAGES}
EOF
fi
