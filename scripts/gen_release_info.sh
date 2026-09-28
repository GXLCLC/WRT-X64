#!/bin/bash
# ================================================================
# gen_release_info.sh — Release 发布信息生成脚本
# ----------------------------------------------------------------
# 职责说明：
#   编译完成后，自动读取系统配置、内核版本、已安装插件清单等信息，
#   依据 docs/release_template.md 模板，生成 Release 页面 Markdown 正文。
#
# 数据来源：
#   1. 系统参数 -> 从 system_config.sh 中解析（LAN IP、账号密码等）
#   2. 内核版本 -> 从 LEDE 源码 Makefile 中提取
#   3. 固件版本 -> 从 LEDE 源码 Makefile 中提取
#   4. 插件清单 -> 从编译后的 .config 中提取所有已启用的 luci-app 包
# ================================================================

set -e

# 获取 LEDE 源码根目录
LEDE_ROOT="${LEDE_ROOT:-$(pwd)/lede}"

# 获取仓库根目录（本仓库根目录，用于读取模板文件）
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# 输出文件路径（Markdown 正文）
OUTPUT_FILE="${OUTPUT_FILE:-${REPO_ROOT}/release_info.md}"

echo "=========================================="
echo "  开始生成 Release 发布信息"
echo "=========================================="

# ================================================================
# 1. 从 system_config.sh 中解析系统参数
#    通过 grep 提取变量赋值值，避免直接 source 执行整个脚本
# ================================================================
SYSTEM_CONFIG="${REPO_ROOT}/scripts/system_config.sh"

# 提取 LAN IP
LAN_IP=$(grep -E "^LAN_IP=" "${SYSTEM_CONFIG}" | head -1 | sed "s/.*=\"//;s/\"$//")
# 提取主机名
HOSTNAME=$(grep -E "^HOSTNAME=" "${SYSTEM_CONFIG}" | head -1 | sed "s/.*=\"//;s/\"$//")
# 提取登录用户名
ROOT_USERNAME=$(grep -E "^ROOT_USERNAME=" "${SYSTEM_CONFIG}" | head -1 | sed "s/.*=\"//;s/\"$//")
# 提取登录密码
ROOT_PASSWORD=$(grep -E "^ROOT_PASSWORD=" "${SYSTEM_CONFIG}" | head -1 | sed "s/.*=\"//;s/\"$//")
# 提取时区
TIMEZONE_AREA=$(grep -E "^TIMEZONE_AREA=" "${SYSTEM_CONFIG}" | head -1 | sed "s/.*=\"//;s/\"$//")

echo "  LAN IP:    ${LAN_IP}"
echo "  主机名:     ${HOSTNAME}"
echo "  用户名:     ${ROOT_USERNAME}"
echo "  密码:       ${ROOT_PASSWORD}"
echo "  时区:       ${TIMEZONE_AREA}"

# ================================================================
# 2. 从 LEDE 源码 Makefile 中提取内核版本和固件版本
# ================================================================
echo "  正在提取内核版本与固件版本..."

# 固件版本号（OpenWrt/LEDE 版本，如 24.10.0）
FIRMWARE_VERSION=$(grep -E "^VERSION_CODE" "${LEDE_ROOT}/include/version.mk" 2>/dev/null | head -1 | sed "s/.*:=//;s/ //g;s/\"//g" || echo "unknown")

# 若 version.mk 中未找到，尝试从 Makefile 获取
if [ -z "${FIRMWARE_VERSION}" ] || [ "${FIRMWARE_VERSION}" = "unknown" ]; then
    FIRMWARE_VERSION=$(grep -E " '^$" "${LEDE_ROOT}/package/kernel/linux/Makefile" 2>/dev/null | head -1 || echo "unknown")
fi

# 内核版本（从 kernel Makefile 中提取，如 6.6.58）
KERNEL_VERSION=$(grep -E "^LINUX_VERSION" "${LEDE_ROOT}/include/kernel-version.mk" 2>/dev/null | head -1 | sed "s/.*:=//;s/ //g" || echo "unknown")

# 若 kernel-version.mk 中未找到，尝试备用方式
if [ -z "${KERNEL_VERSION}" ] || [ "${KERNEL_VERSION}" = "unknown" ]; then
    KERNEL_VERSION=$(make -C "${LEDE_ROOT}" kernelrelease 2>/dev/null || echo "unknown")
fi

# 目标架构
TARGET_ARCH="x86_64"

# 编译日期
BUILD_DATE=$(TZ="${TIMEZONE_AREA:-Asia/Shanghai}" date "+%Y-%m-%d %H:%M:%S")

echo "  固件版本:   ${FIRMWARE_VERSION}"
echo "  内核版本:   ${KERNEL_VERSION}"
echo "  编译日期:   ${BUILD_DATE}"

# ================================================================
# 3. 从 .config 中提取已安装的插件清单
#    筛选所有 CONFIG_PACKAGE_luci-app_* = y 的条目
# ================================================================
echo "  正在提取已安装插件清单..."

# 编译后的 .config 文件路径
COMPILED_CONFIG="${LEDE_ROOT}/.config"

# 插件清单临时文件
PLUGIN_LIST_FILE="${REPO_ROOT}/plugin_list.tmp"

# 清空临时文件
> "${PLUGIN_LIST_FILE}"

if [ -f "${COMPILED_CONFIG}" ]; then
    # 提取所有已启用的 luci-app 插件，并格式化为可读名称
    while IFS= read -r line; do
        # 提取包名：CONFIG_PACKAGE_luci-app-xxx=y -> luci-app-xxx
        pkg_name=$(echo "${line}" | sed -E 's/^CONFIG_PACKAGE_(luci-app-[a-zA-Z0-9_-]+)=y$/\1/')
        if [ -n "${pkg_name}" ] && [ "${pkg_name}" != "${line}" ]; then
            echo "${pkg_name}" >> "${PLUGIN_LIST_FILE}"
        fi
    done < "${COMPILED_CONFIG}"

    # 额外提取部分非 luci-app 的核心组件
    # smartdns、adguardhome 等后端程序
    for core_pkg in smartdns adguardhome mwan3 nlbwmon easytier ddnsto; do
        if grep -q "^CONFIG_PACKAGE_${core_pkg}=y" "${COMPILED_CONFIG}" 2>/dev/null; then
            echo "${core_pkg}" >> "${PLUGIN_LIST_FILE}"
        fi
    done

    # 去重并排序
    sort -u "${PLUGIN_LIST_FILE}" -o "${PLUGIN_LIST_FILE}"
fi

# 统计插件数量
PLUGIN_COUNT=$(wc -l < "${PLUGIN_LIST_FILE}" | tr -d ' ')
echo "  已安装插件数量: ${PLUGIN_COUNT}"

# 生成插件清单 Markdown 格式（每行一个插件，以 - 开头）
PLUGIN_MARKDOWN=""
while IFS= read -r pkg; do
    PLUGIN_MARKDOWN+="- ${pkg}"$'\n'
done < "${PLUGIN_LIST_FILE}"

# 清理临时文件
rm -f "${PLUGIN_LIST_FILE}"

# ================================================================
# 4. 提取主题信息
# ================================================================
THEME_INFO="luci-theme-argon（Argon，已设为默认主题）"

# ================================================================
# 5. 依据模板生成 Release Markdown 正文
# ================================================================
TEMPLATE_FILE="${REPO_ROOT}/docs/release_template.md"

echo "  正在依据模板生成 Release 正文..."

if [ ! -f "${TEMPLATE_FILE}" ]; then
    echo "[错误] 模板文件不存在: ${TEMPLATE_FILE}"
    exit 1
fi

# 读取模板内容
TEMPLATE_CONTENT=$(cat "${TEMPLATE_FILE}")

# 生成最终 Markdown（替换模板中的占位符）
# 使用 cat 配合 heredoc，将模板中的占位符替换为实际值
# 注意：使用双引号确保 ${PLUGIN_MARKDOWN} 中的换行符被保留
cat > "${OUTPUT_FILE}" <<EOF
$(echo "${TEMPLATE_CONTENT}" | \
    sed "s|{{FIRMWARE_VERSION}}|${FIRMWARE_VERSION}|g" | \
    sed "s|{{KERNEL_VERSION}}|${KERNEL_VERSION}|g" | \
    sed "s|{{TARGET_ARCH}}|${TARGET_ARCH}|g" | \
    sed "s|{{BUILD_DATE}}|${BUILD_DATE}|g" | \
    sed "s|{{LAN_IP}}|${LAN_IP}|g" | \
    sed "s|{{HOSTNAME}}|${HOSTNAME}|g" | \
    sed "s|{{ROOT_USERNAME}}|${ROOT_USERNAME}|g" | \
    sed "s|{{ROOT_PASSWORD}}|${ROOT_PASSWORD}|g" | \
    sed "s|{{TIMEZONE}}|${TIMEZONE_AREA}|g" | \
    sed "s|{{THEME_INFO}}|${THEME_INFO}|g" | \
    sed "s|{{PLUGIN_COUNT}}|${PLUGIN_COUNT}|g")
EOF

# 替换插件清单占位符（因 sed 不便处理多行替换，改用 awk）
# 将 {{PLUGIN_LIST}} 占位符替换为实际插件清单
awk -v placeholder="{{PLUGIN_LIST}}" -v replacement="${PLUGIN_MARKDOWN}" '
{
    gsub(placeholder, replacement)
    print
}
' "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"

echo ""
echo "=========================================="
echo "  Release 信息生成完成！"
echo "  输出文件: ${OUTPUT_FILE}"
echo "=========================================="
