#!/bin/bash
# ============================================================
# Release 发布信息生成脚本
# 功能：
#   1. 从编译产物目录复制 squashfs combined IMG 镜像
#   2. 生成 SHA256 校验文件
#   3. 汇总固件版本 / 内核版本 / 登录信息 / 插件清单，
#      生成 Markdown 格式 Release 说明
# ============================================================
set -euo pipefail

# 入参：ImmortalWrt 源码目录、Release 输出目录
SRC_DIR="${1:?用法: generate-release-info.sh <源码目录> <输出目录>}"
OUT_DIR="${2:?用法: generate-release-info.sh <源码目录> <输出目录>}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # 本仓库根目录

TARGET_DIR="${SRC_DIR}/bin/targets/x86/64"
mkdir -p "${OUT_DIR}"

# ---------- 1. 复制固件镜像（仅 squashfs combined 的 IMG 格式） ----------
echo ">>> 复制 squashfs combined 镜像（EFI + BIOS）..."
cp -v "${TARGET_DIR}"/*squashfs-combined*.img.gz "${OUT_DIR}/"

# ---------- 2. 生成 SHA256 校验文件，方便用户校验下载完整性 ----------
echo ">>> 生成 SHA256 校验文件..."
( cd "${OUT_DIR}" && sha256sum *.img.gz > sha256sums )

# ---------- 3. 提取固件版本与内核版本（优先读 profiles.json） ----------
FIRMWARE_VERSION="$(jq -r '.version_number // "snapshot"' \
    "${TARGET_DIR}/profiles.json" 2>/dev/null || echo 'snapshot')"
KERNEL_VERSION="$(jq -r '.linux_version // "unknown"' \
    "${TARGET_DIR}/profiles.json" 2>/dev/null || echo 'unknown')"

# ---------- 4. 读取系统配置（仅提取变量定义行，不执行脚本主体） ----------
source <(grep -E '^(LAN_IP|ROOT_PASSWORD|HOSTNAME)=' \
    "${REPO_DIR}/scripts/modify_system_config.sh" || true)

# ---------- 5. 提取插件清单 ----------
# 从 .config 筛选已启用的 LuCI 应用与主题；
# 排除 kmod 驱动依赖与 luci-i18n 翻译包，每行一个插件名
PLUGIN_LIST="$(
    grep -E '^CONFIG_PACKAGE_(luci-app|luci-theme)-[a-zA-Z0-9._-]+=y$' \
        "${SRC_DIR}/.config" \
    | sed -E 's/^CONFIG_PACKAGE_([a-zA-Z0-9._-]+)=y$/\1/' \
    | grep -v 'luci-theme-bootstrap' \
    | sort -u
)"

# ---------- 6. 生成 Markdown 说明文件 ----------
NOTES="${OUT_DIR}/release_notes.md"
{
    echo "# ImmortalWrt x86_64 固件发布说明"
    echo ""
    echo "## 固件信息"
    echo ""
    echo "| 项目 | 内容 |"
    echo "| --- | --- |"
    echo "| 固件版本 | ImmortalWrt ${FIRMWARE_VERSION} |"
    echo "| 内核版本 | Linux ${KERNEL_VERSION} |"
    echo "| 目标架构 | x86_64（软路由 / 工控机 / 虚拟机） |"
    echo "| 镜像格式 | squashfs combined（EFI + BIOS 双版本，gzip 压缩） |"
    echo "| Overlay 可写空间 | 约 2GB（rootfs 分区 3072MB） |"
    echo "| 源码分支 | ImmortalWrt master |"
    echo ""
    echo "## 后台登录信息"
    echo ""
    echo "| 项目 | 内容 |"
    echo "| --- | --- |"
    echo "| 管理地址 | http://${LAN_IP} |"
    echo "| 用户名 | root |"
    echo "| 密码 | ${ROOT_PASSWORD} |"
    echo "| 主机名 | ${HOSTNAME} |"
    echo ""
    echo "> 首次开机后请及时修改默认密码！"
    echo ""
    echo "## 已安装插件清单"
    echo ""
    echo '```'
    while read -r pkg; do
        [ -n "${pkg}" ] && echo "${pkg}"
    done <<< "${PLUGIN_LIST}"
    echo '```'
    echo ""
    echo "> 说明：仅列出 LuCI 应用与主题名称；kmod 驱动、依赖库及"
    echo "> luci-i18n 中文翻译包已自动集成，不在清单中展示。"
    echo ""
    echo "## 使用提示"
    echo ""
    echo "- **AdGuardHome**：LuCI 页面内置「重定向」功能，可将 53 端口 DNS 请求重定向至 AdGuardHome，避免与 dnsmasq 冲突。"
    echo "- **EasyTier / OpenClash**：TUN 模式所需 kmod-tun 已内置。"
    echo "- **刷机方式**：解压 .img.gz 后用 dd 或写盘工具写入磁盘；UEFI 设备使用 combined-efi 镜像。"
} > "${NOTES}"

echo ">>> Release 说明已生成: ${NOTES}"
echo "===== 插件清单预览 ====="
echo "${PLUGIN_LIST}"
