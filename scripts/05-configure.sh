#!/usr/bin/env bash
# ==============================================================================
# 步骤五：生成 .config → 冲突处理 → defconfig → 硬/软依赖严格校验
# 任何必需插件未进入 .config 即终止，杜绝「假成功 / 缺插件」固件
# ==============================================================================
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
enter_source

CONFIG_FILE="${BUILDER_ROOT}/config/X86_64.config"
[[ -f "$CONFIG_FILE" ]] || die "未找到内置配置文件：$CONFIG_FILE"

step "载入内置配置 config/X86_64.config"
cp "$CONFIG_FILE" .config
log "已载入 $(grep -c 'CONFIG_' .config) 条配置项"

# ---------------------- 依赖冲突处理 ------------------------------------------
step "冲突处理：与 Feeds 官方包重名的第三方副本一律移除（保留官方）"
mapfile -t FEED_NAMES < <(find package/feeds -maxdepth 2 -mindepth 2 -type d -printf '%f\n' 2>/dev/null | sort -u)
for d in package/custom/*; do
    [[ -d "$d" ]] || continue
    n=$(basename "$d")
    if printf '%s\n' "${FEED_NAMES[@]}" | grep -qx "$n"; then
        warn "发现重名冲突，移除第三方副本：package/custom/$n（保留 Feeds 官方版本）"
        rm -rf "$d"
    fi
done

# ---------------------- 追加第三方插件开关 ------------------------------------
step "追加第三方插件编译开关（确保面板 / 核心 / 依赖全部打包）"
cat >> .config <<'EOF'
# ===== 第三方插件：LuCI 面板 =====
CONFIG_PACKAGE_luci-app-smartdns=y
CONFIG_PACKAGE_luci-app-ddnsto=y
CONFIG_PACKAGE_luci-app-adguardhome=y
CONFIG_PACKAGE_luci-app-oaf=y
CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_luci-app-mwan3=y
CONFIG_PACKAGE_luci-app-argon-config=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-bandix=y
CONFIG_PACKAGE_luci-app-easytier=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-app-autoreboot=y
CONFIG_PACKAGE_luci-app-wechatpush=y
CONFIG_PACKAGE_luci-app-nlbwmon=y
# ===== 第三方插件：核心程序 / 服务 =====
CONFIG_PACKAGE_smartdns=y
CONFIG_PACKAGE_adguardhome=y
CONFIG_PACKAGE_oaf=y
CONFIG_PACKAGE_open-app-filter=y
CONFIG_PACKAGE_openwrt-bandix=y
CONFIG_PACKAGE_easytier=y
CONFIG_PACKAGE_nft-fullcone=y
CONFIG_PACKAGE_kmod-nft-fullcone=y
CONFIG_PACKAGE_mwan3=y
CONFIG_PACKAGE_nlbwmon=y
CONFIG_PACKAGE_miniupnpd=y
CONFIG_PACKAGE_ttyd=y
EOF

step "执行 make defconfig（解析依赖、自动补齐）"
make defconfig

# ---------------------- 严格校验 ----------------------------------------------
step "严格校验：必需插件是否全部进入 .config"
REQUIRED=(
  luci-app-smartdns smartdns
  luci-app-ddnsto
  luci-app-adguardhome adguardhome
  luci-app-oaf oaf open-app-filter
  luci-app-turboacc nft-fullcone
  luci-app-mwan3 mwan3
  luci-app-argon-config luci-theme-argon
  luci-app-bandix openwrt-bandix
  luci-app-easytier easytier
  luci-app-wol
  luci-app-upnp miniupnpd
  luci-app-ttyd ttyd
  luci-app-autoreboot
  luci-app-wechatpush
  luci-app-nlbwmon nlbwmon
  # 内核能力
  kmod-nft-offload kmod-tcp-bbr
  # 网卡与存储驱动
  kmod-igb kmod-r8169 kmod-usb-net-rtl8152 kmod-usb-storage block-mount
)
SOFT=( ddnsto wol etherwake kmod-nft-fullcone )

MISSING=()
for p in "${REQUIRED[@]}"; do
    grep -qx "CONFIG_PACKAGE_${p}=y" .config || MISSING+=("$p")
done

if [[ "${#MISSING[@]}" -gt 0 ]]; then
    err "以下必需组件未能进入 .config（缺失依赖 / 路径错误 / 模块冲突）："
    for m in "${MISSING[@]}"; do
        loc=$(find package -maxdepth 4 -type d -name "$m" 2>/dev/null | head -1)
        if [[ -n "$loc" ]]; then
            err "  - $m  （目录存在：$loc，多为依赖未满足或与其它包冲突，检查其 Makefile 的 DEPENDS）"
        else
            err "  - $m  （源码树中不存在该包目录：拉取失败或路径错误，请检查 scripts/03-fetch-plugins.sh）"
        fi
    done
    die "配置校验未通过，终止编译。"
fi

for p in "${SOFT[@]}"; do
    grep -qx "CONFIG_PACKAGE_${p}=y" .config || warn "可选组件未纳入：$p（不影响编译，如确需请手动加入 config/X86_64.config）"
done

step "校验 i18n 中文语言包"
for app in smartdns ddnsto adguardhome oaf turboacc mwan3 easytier wol upnp ttyd autoreboot wechatpush nlbwmon argon-config; do
    if grep -qx "CONFIG_PACKAGE_luci-i18n-${app}-zh-cn=y" .config; then
        log "已含中文包：luci-i18n-${app}-zh-cn"
    else
        warn "未匹配到 luci-i18n-${app}-zh-cn（该插件可能已内置中文，或源中未提供独立语言包）"
    fi
done

step "校验目标与镜像格式"
grep -qx "CONFIG_TARGET_x86=y"        .config || die "目标平台不是 x86"
grep -qx "CONFIG_TARGET_x86_64=y"      .config || die "目标子架构不是 x86_64"
grep -qx "CONFIG_TARGET_ROOTFS_SQUASHFS=y" .config || die "未启用 squashfs 根文件系统"
PART=$(grep -m1 '^CONFIG_TARGET_ROOTFS_PARTSIZE=' .config | cut -d= -f2)
[[ "${PART:-0}" -ge 2048 ]] || die "overlay/根分区容量未达标：CONFIG_TARGET_ROOTFS_PARTSIZE=${PART}（要求 >= 2048，即 2G）"
log "目标：x86/64 generic · squashfs · 根分区 ${PART} MiB"

log "配置校验通过，进入编译阶段"
