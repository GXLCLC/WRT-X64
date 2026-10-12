#!/usr/bin/env bash
# ============================================================================
#  Release 发布信息生成脚本（独立维护）
#  用途：编译成功后汇总固件信息与插件清单，生成 release-notes.md
#  说明：LAN IP / 密码 / 主机名等直接读取 system-config.sh，保持数据同源，
#        修改 system-config.sh 一处即可，发布说明自动同步
# ============================================================================
set -e

OPENWRT_DIR="${1:-openwrt}"            # OpenWrt 源码目录
FIRMWARE_DIR="${2:-firmware}"          # 固件产物目录
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTES="release-notes.md"
CFG="$OPENWRT_DIR/.config"

# ===== 从 system-config.sh 提取系统配置（数据同源）=====
SRC="$SCRIPTS_DIR/system-config.sh"
LAN_IP=$(grep -oP '^LAN_IP="\K[^"]+'        "$SRC")
ROOT_PASSWD=$(grep -oP '^ROOT_PASSWORD="\K[^"]+' "$SRC")
HOSTNAME=$(grep -oP '^HOSTNAME="\K[^"]+'    "$SRC")
THEME=$(grep -oP '^DEFAULT_THEME="\K[^"]+'  "$SRC")

# ===== 固件版本信息 =====
FW_VERSION=$(grep -oP 'CONFIG_VERSION_NUMBER="\K[^"]+' "$CFG" 2>/dev/null || true)
[ -z "$FW_VERSION" ] && FW_VERSION="24.10"
KERNEL=$(sed -n 's/^LINUX_KERNEL_HASH-\([0-9][0-9.]*\)[[:space:]]*=.*/\1/p' \
        "$OPENWRT_DIR/include/kernel-version.mk" | tail -n1)
[ -z "$KERNEL" ] && KERNEL="6.6"
SRC_COMMIT=$(cd "$OPENWRT_DIR" && git log -1 --format=%h 2>/dev/null || echo "unknown")
BUILD_DATE=$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S')

# ===== 插件清单（仅 LuCI 应用与主题；kmod/依赖库/i18n 翻译包不展示）=====
LUCI_PKGS=$(grep -oP '^CONFIG_PACKAGE_(luci-(app|theme)-[a-zA-Z0-9-]+)=y' "$CFG" \
            | sed 's/^CONFIG_PACKAGE_//; s/=y$//' | sort -u)
PLUGIN_COUNT=$(echo "$LUCI_PKGS" | grep -c . || true)

# ===== 后端核心组件（与插件对应的服务程序）=====
CORE_PKGS=""
for p in smartdns AdGuardHome easytier ddnsto mwan3 nlbwmon; do
    grep -q "^CONFIG_PACKAGE_${p}=y" "$CFG" && CORE_PKGS="$CORE_PKGS $p"
done

# ===== 生成发布说明 =====
cat > "$NOTES" <<EOF
## 📋 固件信息

| 项目 | 内容 |
| --- | --- |
| 固件版本 | ImmortalWrt ${FW_VERSION} |
| 内核版本 | Linux ${KERNEL} |
| 目标架构 | x86_64（generic） |
| 源码提交 | openwrt-24.10 @ ${SRC_COMMIT} |
| 编译时间 | ${BUILD_DATE} |

## 🔑 后台登录信息

| 项目 | 内容 |
| --- | --- |
| **LAN IP** | **${LAN_IP}** |
| 管理入口 | http://${LAN_IP} |
| 登录账号 | root |
| **登录密码** | **${ROOT_PASSWD}** |
| 主机名 | ${HOSTNAME} |
| 默认主题 | ${THEME} |

## 💿 镜像说明

- 格式：squashfs combined（.img.gz，EFI / BIOS 双引导 IMG 镜像）
- 分区：内核分区 32MB，rootfs 分区 2048MB（扣除只读层后为可写 overlay 空间）
- 仅输出 IMG 镜像，未生成 VMDK / VHDX / VDI 等其他格式
- 附带 .sha256 校验文件，刷写前请校验完整性

## 🧩 已集成插件清单（共 ${PLUGIN_COUNT} 个 LuCI 应用 / 主题，每行一个）

$( [ -n "$LUCI_PKGS" ] && echo "$LUCI_PKGS" | sed 's/^/- /' )

**后端核心组件**：${CORE_PKGS}

## ⚠️ 使用提示

1. 首次启动需 1~3 分钟初始化，请耐心等待后再访问后台。
2. SmartDNS、AdGuardHome、OpenClash 均涉及 DNS 接管，请按需择一启用，避免端口冲突。
3. AdGuardHome 的 Web UI 端口可在其 LuCI 界面中查看与修改（默认 3000）。
4. 本固件仅内置 OpenClash 一个代理类插件。
EOF

echo ">>> 已生成发布说明: $NOTES"
