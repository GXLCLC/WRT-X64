#!/usr/bin/env bash
# ==============================================================================
# 步骤七：编译产物校验（文件 / 格式 / 分区容量 / 内核版本）
#         通过后生成 Release 说明并整理上传目录
# 任何一项不达标 -> 直接终止，判定编译失败
# ==============================================================================
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
enter_source

BIN_DIR="bin/targets/x86/64"
STAMP="$(date '+%Y%m%d-%H%M%S')"
UPLOAD="upload"
rm -rf "$UPLOAD"; mkdir -p "$UPLOAD"

step "校验 1：目标镜像是否存在（x86/64 generic squashfs-combined）"
mapfile -t IMGS < <(find "$BIN_DIR" -maxdepth 1 -type f -name "*generic-squashfs-combined*.img.gz" 2>/dev/null | sort)
[[ "${#IMGS[@]}" -gt 0 ]] || die "未生成目标镜像：${BIN_DIR}/*generic-squashfs-combined*.img.gz
  定位信息：$(ls -1 "$BIN_DIR" 2>/dev/null | tr '\n' ' ')
  修复建议：检查 .config 中 CONFIG_GRUB_IMAGES / CONFIG_TARGET_ROOTFS_SQUASHFS / CONFIG_TARGET_IMAGES_GZIP 是否为 y"
IMG_GZ="${IMGS[0]}"
log "目标镜像：${IMG_GZ}（$(du -h "$IMG_GZ" | cut -f1)）"

step "校验 2：镜像格式（gzip + squashfs）"
file "$IMG_GZ" | grep -qi "gzip" || die "镜像不是 gzip 压缩包：$(file "$IMG_GZ")"
WORK_IMG="/tmp/verify-$$.img"
gunzip -c "$IMG_GZ" > "$WORK_IMG"
IMG_INFO="$(file -b "$WORK_IMG")"
log "解压后镜像类型：${IMG_INFO}"
echo "$IMG_INFO" | grep -qiE "MBR|boot sector|GPT|partition" \
    || die "镜像分区表异常（既非 MBR 也非 GPT）：${IMG_INFO}"

step "校验 3：squashfs 文件系统特征"
grep -qa "hsquashfs" "$WORK_IMG" || die "镜像内未检测到 squashfs 文件系统标识（hsquashfs）"
log "已检测到 squashfs 文件系统标识"

step "校验 4：分区容量（要求 >= 2G，即 2048 MiB）"
ROOTFS_IMG="$(find "$BIN_DIR" -maxdepth 1 -type f -name "*squashfs-rootfs.img" | head -1)"
if [[ -n "$ROOTFS_IMG" ]]; then
    RSIZE=$(stat -c%s "$ROOTFS_IMG")
    RMIN=$((2000 * 1024 * 1024))
    log "根文件系统镜像：${ROOTFS_IMG}  大小=$((RSIZE / 1024 / 1024)) MiB"
    [[ "$RSIZE" -ge "$RMIN" ]] || die "根分区容量不达标：${RSIZE} 字节 < 2G（检查 CONFIG_TARGET_ROOTFS_PARTSIZE=2048 是否生效）"
fi
MAXPART=$(fdisk -l "$WORK_IMG" 2>/dev/null | awk '/img[0-9]/ {v=$(NF-2); if (v ~ /G$/) {sub("G","",v); s=v*1024} else if (v ~ /M$/) {sub("M","",v); s=v} else {s=0}; if (s>m) m=s} END {print int(m)}')
log "分区表中最大分区：${MAXPART} MiB"
[[ "${MAXPART:-0}" -ge 2000 ]] || die "分区容量不达标：最大分区仅 ${MAXPART} MiB，不足 2G"
rm -f "$WORK_IMG"

step "校验 5：内核版本必须为 6.12"
KVER="$(ls "$BIN_DIR"/packages/ 2>/dev/null | grep -oE '6\.[0-9]+\.[0-9]+' | sort -u | head -1)"
if [[ -z "$KVER" ]]; then
    KVER="$(find build_dir -maxdepth 4 -type d -name "linux-6.*" 2>/dev/null | grep -oE '6\.[0-9]+\.[0-9]+' | sort -u | head -1)"
fi
[[ -n "$KVER" ]] || die "无法解析内核版本（packages 目录与 build_dir 均未找到内核痕迹）"
log "固件内核版本：${KVER}"
[[ "$KVER" == 6.12.* ]] || die "内核版本校验失败：${KVER} 不是 6.12 内核（检查 scripts/02-kernel-6.12.sh 是否被覆盖执行）"

step "整理上传产物（仅保留 img.gz，多余产物全部过滤）"
OUT_NAME="${STAMP}-$(basename "$IMG_GZ")"
cp "$IMG_GZ" "${UPLOAD}/${OUT_NAME}"
echo "$OUT_NAME" > .upload-name
ls -lh "$UPLOAD"

step "生成 Release 说明"
MANIFEST="$(find "$BIN_DIR" -maxdepth 1 -name "*generic.manifest" | head -1)"
FIRMWARE_VER="unknown"
if [[ -f "$MANIFEST" ]]; then
    DIST="$(find build_dir -maxdepth 3 -type f -path "*root-x86/etc/openwrt_release" | head -1)"
    [[ -f "$DIST" ]] && FIRMWARE_VER="$(grep -m1 'DISTRIB_DESCRIPTION' "$DIST" | cut -d= -f2 | tr -d "'\"")"
fi
COMMIT="$(git -C "$OPENWRT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHA256="$(sha256sum "${UPLOAD}/${OUT_NAME}" | awk '{print $1}')"

{
    echo "## LEDE X86_64 自动编译固件"
    echo
    echo "| 项目 | 值 |"
    echo "|---|---|"
    echo "| 编译时间 | $(date '+%Y-%m-%d %H:%M:%S %Z') |"
    echo "| 源码分支 | coolsnowwolf/lede @ master |"
    echo "| 源码提交 | ${COMMIT} |"
    echo "| 内核版本 | **${KVER}** |"
    echo "| 固件版本 | ${FIRMWARE_VER} |"
    echo "| 目标平台 | x86/64 Generic（squashfs-combined） |"
    echo "| Overlay/根分区 | 2048 MiB（2G） |"
    echo "| 默认后台 IP | 192.168.2.1 |"
    echo "| 默认密码 | 空（首次登录无需密码，请尽快自行设置） |"
    echo "| 默认主题 | Argon |"
    echo "| 时区 | Asia/Shanghai (CST-8) |"
    echo "| SHA256 | \`${SHA256}\` |"
    echo
    echo "### 集成插件清单（已过滤 kmod 内核模块）"
    if [[ -f "$MANIFEST" ]]; then
        echo
        echo "**LuCI 面板 / 主题**"
        echo
        awk '{print $1}' "$MANIFEST" | grep -E '^(luci-app-|luci-theme-)' | sort | sed 's/^/- /'
        echo
        echo "**核心程序 / 服务**"
        echo
        awk '{print $1}' "$MANIFEST" \
            | grep -vE '^(kmod-|kernel|libc|lib|luci-app-|luci-theme-|luci-i18n-|base-files|busybox|ca-|dnsmasq|dropbear|firewall|fstools|fwtool|getrandom|hostapd|ip6tables|iptables|iwinfo|jansson|jsonfilter|kmod|lib|logd|mkf2fs|mtd|netifd|odhcp|opkg|partx-utils|ppp|procd|rpcd|swconfig|ubi|uboot|ubox|ubus|uci|uclient|uhttpd|urandom-seed|urngd|usign|wireguard|wpad|zlib)' \
            | sort | sed 's/^/- /'
    else
        echo "- 未找到 manifest 文件"
    fi
    echo
    echo "### 说明"
    echo "- Turbo ACC 仅启用：软件流量分载、全锥形 NAT、BBR；Shortcut-FE（SFE）已移除。"
    echo "- 插件预设配置已清空（如 mwan3 多接口模板），首次启动后需自行配置。"
    echo "- 仅上传 squashfs 格式的 img.gz 镜像，其余产物已过滤。"
} > release-notes.md

log "Release 说明已生成：release-notes.md"
step "全部校验通过"
