#!/usr/bin/env bash
# ================================================================
# scripts/verify-packages.sh —— 编译产物严格校验（防止「假成功」）
#
#【为什么需要这个脚本】
#   OpenWrt 的 `make defconfig` 对「写进 .config 但实际不存在的包」是
#   静默丢弃的：配置里写了 CONFIG_PACKAGE_xxx=y，包名拼错或上游改了
#   包名，defconfig 不报错、编译也不报错，最后固件里就是没这个插件 ——
#   工作流一片绿，装到机器上才发现少了东西。
#   本脚本就是堵这个洞：把 config/X86_64.config 里声明过的每一个
#   CONFIG_PACKAGE_xxx=y 拿去和固件真实清单（*.manifest）逐条对账，
#   少一个就直接让工作流失败。
#
#【校验内容】
#   1. 配置里声明的每个软件包都真实打进了固件；
#   2. 关键运行时二进制/组件在固件里存在（见 CRITICAL_PACKAGES）；
#   3. squashfs combined IMG（BIOS + UEFI）两个镜像文件都已生成。
#
#【用法】
#   bash scripts/verify-packages.sh <编译产物目录> [配置文件]
#   例: bash scripts/verify-packages.sh bin/targets/x86/64 config/X86_64.config
# ================================================================
set -euo pipefail

BIN_DIR="${1:-bin/targets/x86/64}"
CONFIG_FILE="${2:-config/X86_64.config}"

# 路径归一化：CI 上是 Linux 正斜杠；本机 Windows/Git Bash 调试时可能传进来
# 反斜杠路径（如 C:\xxx\bin\targets\x86\64），bash 的 glob 不认反斜杠，
# 会导致 *.manifest 匹配不到而误报「固件为空」。这里统一换成正斜杠。
BIN_DIR="${BIN_DIR//\\//}"
CONFIG_FILE="${CONFIG_FILE//\\//}"

if [ ! -d "$BIN_DIR" ]; then
  echo "错误: 编译产物目录不存在: $BIN_DIR" >&2
  exit 1
fi
if [ ! -f "$CONFIG_FILE" ]; then
  echo "错误: 配置文件不存在: $CONFIG_FILE" >&2
  exit 1
fi

# ----------------------------------------------------------------
# 关键组件硬清单：不管 .config 怎么写，这些必须有。
# 这是插件清单的「底线」，防止有人误删配置行却没人发现。
# ----------------------------------------------------------------
CRITICAL_PACKAGES=(
  luci
  luci-app-openclash
  luci-app-smartdns
  luci-app-ddnsto
  ddnsto
  luci-app-adguardhome
  adguardhome
  luci-app-oaf
  kmod-oaf
  appfilter
  luci-app-turboacc
  luci-app-mwan3
  luci-app-nlbwmon
  luci-app-easytier
  easytier
  luci-theme-argon
  luci-app-argon-config
  dnsmasq-full
)

# ----------------------------------------------------------------
# 取出固件真实软件包清单
#   manifest 每行格式: "包名 - 版本"，取第一列
# ----------------------------------------------------------------
MANIFESTS=$(ls "$BIN_DIR"/*.manifest 2>/dev/null || true)
if [ -z "$MANIFESTS" ]; then
  echo "错误: 未找到固件软件包清单 *.manifest（位于 $BIN_DIR），无法校验" >&2
  ls -l "$BIN_DIR" >&2 || true
  exit 1
fi
# shellcheck disable=SC2086
INSTALLED=$(cat $MANIFESTS | awk 'NF {print $1}' | sort -u)
INSTALLED_COUNT=$(printf '%s\n' "$INSTALLED" | grep -c . || true)
echo "==> 固件实际安装软件包数量: $INSTALLED_COUNT"

# ----------------------------------------------------------------
# 从 .config 提取所有 CONFIG_PACKAGE_xxx=y
#   排除 luci-app-xxx_INCLUDE_yyy 这类「插件子选项」—— 它们是编译开关，
#   不是独立软件包，拿去做清单核对必然误报。
# ----------------------------------------------------------------
EXPECTED=$(grep -oE '^CONFIG_PACKAGE_[A-Za-z0-9._+-]+=y$' "$CONFIG_FILE" |
  sed -e 's/^CONFIG_PACKAGE_//' -e 's/=y$//' |
  grep -v '_INCLUDE_' | sort -u || true)

if [ -z "$EXPECTED" ]; then
  echo "错误: 从 $CONFIG_FILE 中未解析出任何 CONFIG_PACKAGE_xxx=y" >&2
  exit 1
fi

MISSING=()
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  if ! printf '%s\n' "$INSTALLED" | grep -qxF "$pkg"; then
    MISSING+=("$pkg")
  fi
done <<<"$EXPECTED"

# ----------------------------------------------------------------
# 关键组件再单独核一遍（去重）
# ----------------------------------------------------------------
CRITICAL_MISSING=()
for pkg in "${CRITICAL_PACKAGES[@]}"; do
  if ! printf '%s\n' "$INSTALLED" | grep -qxF "$pkg"; then
    CRITICAL_MISSING+=("$pkg")
  fi
done

# ----------------------------------------------------------------
# 镜像文件校验
# ----------------------------------------------------------------
IMG_BIOS=$(ls "$BIN_DIR"/*squashfs-combined.img 2>/dev/null | head -n1 || true)
IMG_EFI=$(ls "$BIN_DIR"/*squashfs-combined-efi.img 2>/dev/null | head -n1 || true)
IMG_PROBLEMS=()
[ -f "$IMG_BIOS" ] || IMG_PROBLEMS+=("缺少 BIOS 镜像 *squashfs-combined.img")
[ -f "$IMG_EFI" ] || IMG_PROBLEMS+=("缺少 UEFI 镜像 *squashfs-combined-efi.img")

# ----------------------------------------------------------------
# 汇总判定
# ----------------------------------------------------------------
ERRORS=0

if [ ${#IMG_PROBLEMS[@]} -gt 0 ]; then
  ERRORS=1
  echo "" >&2
  echo "!!! 镜像文件缺失：" >&2
  for m in "${IMG_PROBLEMS[@]}"; do echo "      - $m" >&2; done
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  ERRORS=1
  echo "" >&2
  echo "!!! 以下软件包在 config/X86_64.config 中声明为 =y，但没有进固件：" >&2
  for m in "${MISSING[@]}"; do echo "      - $m" >&2; done
  echo "      常见原因：包名拼写错误、上游改名、第三方拉取失败、依赖不满足被丢弃。" >&2
fi

if [ ${#CRITICAL_MISSING[@]} -gt 0 ]; then
  ERRORS=1
  echo "" >&2
  echo "!!! 以下关键组件缺失（插件清单底线被破坏）：" >&2
  for m in "${CRITICAL_MISSING[@]}"; do echo "      - $m" >&2; done
fi

if [ "$ERRORS" -ne 0 ]; then
  echo "" >&2
  echo "===================================================================" >&2
  echo "  编译产物校验失败 —— 固件不完整，已阻止后续发布流程" >&2
  echo "  请按上面的清单修正 config/X86_64.config 或 scripts/feeds_update.sh" >&2
  echo "===================================================================" >&2
  exit 1
fi

echo ""
echo "==> 校验通过："
echo "    · 配置声明的 $(printf '%s\n' "$EXPECTED" | grep -c .) 个软件包全部在固件中"
echo "    · $((${#CRITICAL_PACKAGES[@]})) 个关键组件全部就位"
echo "    · BIOS 镜像: $(basename "$IMG_BIOS")"
echo "    · UEFI 镜像: $(basename "$IMG_EFI")"
