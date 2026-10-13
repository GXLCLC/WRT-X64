#!/bin/bash
#
# release-info.sh —— 独立 Release 信息生成脚本（由工作流编译成功后调用）
# 用途：自动汇总固件信息并输出 Markdown 格式的 Release 正文，包含：
#       LAN IP、后台账号密码、内核版本、固件版本、已安装插件清单（每行一个）
# 注意：以下账号信息请与 scripts/system-config.sh 保持一致
#

set -e

# ================== Release 页面展示配置（与 system-config.sh 同步维护） ==================
LAN_IP="192.168.2.1"
ROOT_PASSWORD="asdfghjkL666666"
# ========================================================================================

SRC_DIR="${1:-.}"    # 参数：ImmortalWrt 源码根目录（默认当前目录）
cd "$SRC_DIR"
TARGET_DIR="bin/targets/x86/64"

# ---------- 提取固件版本（从镜像文件名解析，如 24.10.x-r28121-abcdef01）----------
FW_FILE="$(ls "${TARGET_DIR}"/*squashfs-combined*.img.gz 2>/dev/null | head -n 1)"
FW_NAME="$(basename "${FW_FILE:-unknown.img.gz}")"
FW_VERSION="$(echo "$FW_NAME" | grep -oP 'immortalwrt-\K[0-9]+\.[0-9]+(\.[0-9]+)?(-rc[0-9]+)?-r[0-9]+-[0-9a-f]+' || true)"

# ---------- 提取内核版本（从编译目录 linux-x.y.z 目录名解析，失败则回退）----------
KERNEL_VERSION="$(ls -d build_dir/target-*/linux-*/linux-[0-9]* 2>/dev/null | head -n 1 | grep -oP 'linux-\K[0-9]+\.[0-9]+\.[0-9]+' || true)"
if [ -z "$KERNEL_VERSION" ]; then
  KERNEL_VERSION="$(grep -oP 'KERNEL_PATCHVER:=\K[0-9.]+' target/linux/x86/Makefile 2>/dev/null || echo unknown)"
fi

# ---------- 提取已安装软件包清单（来自固件 rootfs 内 opkg 状态文件，结果最准确）----------
STATUS_FILE="$(ls build_dir/target-*/root-*/usr/lib/opkg/status 2>/dev/null | head -n 1)"
ALL_PKGS=""
if [ -n "$STATUS_FILE" ]; then
  ALL_PKGS="$(grep '^Package:' "$STATUS_FILE" | awk '{print $2}' | sort -u)"
fi

# 过滤规则：仅展示 LuCI 应用插件、主题与功能主程序；
#           kmod 内核模块、依赖库等底层信息自动过滤，方便用户快速查阅
PLUGIN_LIST="$(
  {
    echo "$ALL_PKGS" | grep -E '^luci-app-' || true
    echo "$ALL_PKGS" | grep -E '^luci-theme-' || true
    echo "$ALL_PKGS" | grep -E '^(smartdns|adguardhome|ddnsto|easytier|mwan3|nlbwmon)$' || true
  } | sed '/^$/d' | sort -u
)"

# ---------- 输出 Markdown 正文 ----------
echo "## 📦 ImmortalWrt X86_64 定制固件"
echo ""
echo "| 项目 | 信息 |"
echo | awk '{print "| ---- | ---- |"}'
echo "| 固件版本 | ImmortalWrt ${FW_VERSION:-unknown} |"
echo "| 内核版本 | Linux ${KERNEL_VERSION} |"
echo "| 目标架构 | x86_64（squashfs-combined 镜像，overlay 可写空间约 2GB） |"
echo "| LAN IP | ${LAN_IP} |"
echo "| 管理地址 | http://${LAN_IP} |"
echo "| 后台账号 | root |"
echo "| 后台密码 | ${ROOT_PASSWORD} |"
echo ""
echo "### 🧩 已集成插件清单"
echo ""
if [ -n "$PLUGIN_LIST" ]; then
  echo "$PLUGIN_LIST" | sed 's/^/- /'
else
  echo "- （未能自动提取插件清单，请以上方配置为准）"
fi
echo ""
echo "> 说明：以上清单自动从固件 rootfs 提取，仅展示功能插件与主题；"
echo "> kmod 内核模块及底层依赖库已自动过滤；所有 LuCI 插件均内置中文语言包（zh-Hans）。"
echo ""
echo "### 🚀 刷机与使用说明"
echo "- 镜像为 squashfs-combined 格式（含 BIOS 与 EFI 两种启动版本），使用 balenaEtcher / dd 写入磁盘或导入虚拟机即可"
echo "- 首次启动后浏览器访问 **http://${LAN_IP}**，使用 **root / ${ROOT_PASSWORD}** 登录后台"
echo "- squashfs 只读系统 + 约 2GB overlay 可写空间，支持在线安装软件包并保存配置"
echo "- OpenClash 为唯一集成的代理插件，内核文件请在插件 Web 界面内首次使用时下载"
