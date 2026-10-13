#!/bin/bash
# ============================================================================
# 固件信息收集脚本（独立维护）
# ----------------------------------------------------------------------------
# 用途：编译成功后收集固件信息，生成 Release 页面内容文件 release_info.md，
#       内容包含：固件版本、内核版本、LAN IP、登录账号密码、已安装插件清单
#       （插件清单每行一个，不展示 kmod 等内核模块驱动依赖）。
# 注意：LAN_IP / ROOT_PASSWORD 请与 scripts/system-config.sh 中的值保持一致。
# ============================================================================
set -e

# =========【发布信息配置区（与 system-config.sh 保持一致）】=========
LAN_IP="192.168.2.1"
ROOT_USER="root"
ROOT_PASSWORD="12345678"
# ==================================================================

# 定位仓库根目录与固件输出目录
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${BASE_DIR}/openwrt/bin/targets/x86/64"
INFO_FILE="${BASE_DIR}/release_info.md"

echo ">>> [发布信息] 开始收集固件信息..."

# ---------- 1. 提取内核版本 ----------
KERNEL_VERSION=""
# 优先从 profiles.json 读取（OpenWrt 24.10 标准输出文件）
if [ -f "${TARGET_DIR}/profiles.json" ]; then
    KERNEL_VERSION=$(grep -o '"release"[[:space:]]*:[[:space:]]*"[^"]*"' \
        "${TARGET_DIR}/profiles.json" | head -n1 \
        | sed 's/.*"release"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi
# 备用方案：从 build
