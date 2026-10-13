#!/usr/bin/env bash
# ============================================================================
#  第三方插件拉取脚本（严格模式·修正版）
#  旧版问题：sparse_clone 指定分支/目录名错误时静默跳过 → 包未就位
#            → make defconfig 静默删除 CONFIG_PACKAGE_xxx=y
#            → 编译成功但固件缺包（DDNSTO / OAF 缺失的根本原因）
#  新版策略：
#    1. 完整浅克隆（--depth 1，Runner 拉取 GitHub 仓库走内网，速度可忽略）
#       后用 find 自动探测包目录，不怕仓库调整目录层级 / 改默认分支
#    2. 每个关键包拉取后立即校验 Makefile，任何失败立即 exit 1
#    3. 与工作流第 9 步「关键包强校验」构成双保险
# ============================================================================
set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"
PKG_DIR="$OPENWRT_DIR/package/thirdparty"
KENZOK8_REPO="https://github.com/kenzok8/openwrt-packages.git"
mkdir -p "$PKG_DIR"

# ----------------工具函数 ----------------

# feeds 中是否已存在同名包
feed_has() {
    find "$OPENWRT_DIR/feeds" "$OPENWRT_DIR/package/feeds" -maxdepth 4 \
        -type d -name "$1" 2>/dev/null | grep -q .
}

# 移除 feeds 已安装的同名包符号链接（让第三方版本生效）
uninstall_feed_pkg() {
    local link
    link=$(find "$OPENWRT_DIR/package/feeds" -maxdepth 3 -name "$1" 2>/dev/null | head -n1 || true)
    if [ -n "$link" ]; then
        echo "    ↻ 移除 feeds 重复包: $1（改用第三方版本）"
        (cd "$OPENWRT_DIR" && ./scripts/feeds uninstall "$1" >/dev/null 2>&1) || true
    fi
}

# 拉取一个包目录（严格模式：找不到目录或缺少 Makefile 即失败）
# 用法: fetch_pkg <仓库地址> <包目录名>
fetch_pkg() {
    local repo_url="$1" pkg="$2"
    local tmp dir
    tmp=$(mktemp -d)
    echo "  → 拉取 $pkg （$repo_url，默认分支）"
    # 不指定分支，永远跟随仓库默认分支，规避 main/master 猜错问题
    git clone --quiet --depth 1 "$repo_url" "$tmp/repo"
    # 自动探测包目录（最多 4 层，兼容仓库目录层级调整）
    dir=$(find "$tmp/repo" -maxdepth 4 -type d -name "$pkg" ! -path '*/.git*' | head -n1)
    if [ -z "$dir" ]; then
        echo "::error::仓库 $repo_url 中未找到包目录 $pkg，终止！（请到仓库页面核对实际目录名）"
        rm -rf "$tmp"
        return 1
    fi
    if [ ! -f "$dir/Makefile" ]; then
        echo "::error::$pkg 目录缺少 Makefile（$dir），终止！"
        rm -rf "$tmp"
        return 1
    fi
    uninstall_feed_pkg "$pkg"
    rm -rf "${PKG_DIR:?}/$pkg"
    cp -r "$dir" "$PKG_DIR/$pkg"
    rm -rf "$tmp"
    echo "    ✔ 就位: $PKG_DIR/$pkg"
}

# feeds 自带则直接用，否则从 kenzok8 拉取
ensure_pkg() {
    if feed_has "$1"; then
        echo "[自带] $1 —— 使用 ImmortalWrt 源码包"
    else
        fetch_pkg "$KENZOK8_REPO" "$1"
    fi
}

echo "============================================"
echo " 第三方插件拉取（严格模式：失败即终止）"
echo "============================================"

# ---------- 1. DDNSTO（前端 LuCI + 后端服务，两者缺一不可）----------
if feed_has ddnsto && feed_has luci-app-ddnsto; then
    echo "[自带] ddnsto / luci-app-ddnsto"
else
    # 前端界面与后端程序分属两个仓库，必须同时拉取
    fetch_pkg https://github.com/linkease/nas-packages-luci.git luci-app-ddnsto
    fetch_pkg https://github.com/linkease/nas-packages.git      ddnsto
fi

# ---------- 2. OAF 应用过滤（luci-app-oaf 依赖 kmod-oaf 内核模块）----------
if feed_has luci-app-oaf && feed_has kmod-oaf; then
    echo "[自带] luci-app-oaf / kmod-oaf"
else
    fetch_pkg "$KENZOK8_REPO" luci-app-oaf
    fetch_pkg "$KENZOK8_REPO" kmod-oaf
fi

# ---------- 3. SmartDNS ----------
ensure_pkg smartdns
ensure_pkg luci-app-smartdns

# ---------- 4. AdGuardHome（kenzok8 版界面 + 后端核心）----------
fetch_pkg "$KENZOK8_REPO" luci-app-adguardhome
fetch_pkg "$KENZOK8_REPO" AdGuardHome

# ---------- 5. Argon 主题家族（统一 kenzok8 版保证版本配套）----------
fetch_pkg "$KENZOK8_REPO" luci-theme-argon
fetch_pkg "$KENZOK8_REPO" luci-app-argon-config
ensure_pkg luci-i18n-argon-config-zh-cn

# ---------- 6. EasyTier（官方仓库，内核包与 LuCI 界面同一仓库）----------
if feed_has easytier && feed_has luci-app-easytier; then
    echo "[自带] easytier / luci-app-easytier"
else
    fetch_pkg https://github.com/EasyTier/luci-app-easytier.git easytier
    fetch_pkg https://github.com/EasyTier/luci-app-easytier.git luci-app-easytier
fi

# ---------- 7. 核对 feeds 自带的关键插件（缺失直接终止，绝不带病编译）----------
for pkg in luci-app-turboacc mwan3 luci-app-mwan3 nlbwmon luci-app-nlbwmon \
           luci-app-openclash dnsmasq-full; do
    if feed_has "$pkg"; then
        echo "[自带] $pkg"
    else
        echo "::error::feeds 中未找到 $pkg，固件将缺失该功能，终止！"
        exit 1
    fi
done

# ---------- 8. 最终就位清单（供人工核对）----------
echo "--------------------------------------------"
echo " 第三方包就位清单（package/thirdparty/）"
echo "--------------------------------------------"
ls -1 "$PKG_DIR"
echo "============================================"
echo " 第三方插件拉取完成（全部通过严格校验）"
echo "============================================"