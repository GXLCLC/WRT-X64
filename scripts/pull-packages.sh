#!/usr/bin/env bash
# ============================================================================
#  第三方插件拉取脚本（独立维护）
#  拉取规则：
#    1. 优先使用 ImmortalWrt 源码自带软件包
#    2. 源码仓库不存在的插件，按映射浅克隆第三方仓库
#       （sparse checkout，仅下载插件目录，不拉取完整仓库，节省编译耗时）
#    3. AdGuardHome 按需求强制使用 kenzok8 仓库版本（界面支持 Web UI 端口设置）
#    4. Argon 主题与 argon-config 需版本配套，统一使用 kenzok8 仓库版本
#    5. 中文翻译包由 luci.mk 构建系统在编译时自动生成，无需单独拉取
# ============================================================================
set -e

OPENWRT_DIR="${1:-openwrt}"
PKG_DIR="$OPENWRT_DIR/package/third_party"          # 第三方包统一放置目录
KENZOK8_REPO="https://github.com/kenzok8/openwrt-packages.git"
mkdir -p "$PKG_DIR"

# ---------------- 工具函数 ----------------

# 检查 ImmortalWrt feeds 中是否已存在指定软件包
feed_has() {
    find "$OPENWRT_DIR/feeds" -maxdepth 3 -type d -name "$1" 2>/dev/null | grep -q .
}

# 卸载 feeds 中已安装的同名包（需要用第三方版本覆盖时调用）
uninstall_feed_pkg() {
    local link
    link=$(find "$OPENWRT_DIR/package/feeds" -maxdepth 2 -name "$1" 2>/dev/null | head -n1 || true)
    if [ -n "$link" ]; then
        echo "    ↻ 移除 feeds 重复包: $1（改用第三方版本）"
        (cd "$OPENWRT_DIR" && ./scripts/feeds uninstall "$1" >/dev/null 2>&1) || true
    fi
}

# 浅克隆仓库并仅检出指定目录（不完整拉取整个仓库）
# 用法: sparse_clone <仓库地址> <分支> <目录1> [目录2] ...
sparse_clone() {
    local repo_url="$1" branch="$2"; shift 2
    local tmp
    tmp=$(mktemp -d)
    echo ">>> 浅克隆: $repo_url （分支: $branch）"
    git clone --depth 1 --single-branch --branch "$branch" \
        --filter=blob:none --sparse "$repo_url" "$tmp/repo"
    (
        cd "$tmp/repo"
        # 检出目标目录（仓库中不存在的目录自动跳过，不报错）
        git sparse-checkout set "$@" >/dev/null 2>&1 || true
    )
    for dir in "$@"; do
        if [ -d "$tmp/repo/$dir" ]; then
            uninstall_feed_pkg "$(basename "$dir")"
            rm -rf "${PKG_DIR:?}/$(basename "$dir")"
            mv "$tmp/repo/$dir" "$PKG_DIR/$(basename "$dir")"
            echo "    ✔ 已获取: $dir"
        else
            echo "    - 目录不存在，跳过: $dir"
        fi
    done
    rm -rf "$tmp"
}

echo "============================================"
echo " 第三方插件拉取（优先 ImmortalWrt 自带源码）"
echo "============================================"

# ---------- 1. SmartDNS（核心 + LuCI 管理界面，优先源码自带）----------
for pkg in smartdns luci-app-smartdns; do
    if feed_has "$pkg"; then
        echo "[自带] $pkg —— 使用 ImmortalWrt 源码包"
    else
        sparse_clone "$KENZOK8_REPO" master "$pkg"
    fi
done

# ---------- 2. OAF 应用过滤（luci-app-oaf + kmod-oaf，源码仓库不含）----------
if feed_has luci-app-oaf; then
    echo "[自带] luci-app-oaf —— 使用 ImmortalWrt 源码包"
else
    sparse_clone "$KENZOK8_REPO" master luci-app-oaf kmod-oaf
fi

# ---------- 3. AdGuardHome（按要求强制使用 kenzok8 版 LuCI 界面）----------
# 说明：kenzok8 版界面功能更完整，支持 Web UI 端口显示与设置
sparse_clone "$KENZOK8_REPO" master luci-app-adguardhome AdGuardHome

# ---------- 4. Argon 主题家族（主题 + 配置器，统一 kenzok8 版保证配套）----------
sparse_clone "$KENZOK8_REPO" master luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn

# ---------- 5. EasyTier（官方插件仓库整体浅克隆，含核心包与 LuCI 界面）----------
if feed_has luci-app-easytier; then
    echo "[自带] luci-app-easytier"
else
    git clone --depth 1 https://github.com/EasyTier/luci-app-easytier.git "$PKG_DIR/easytier-luci"
    uninstall_feed_pkg luci-app-easytier
fi

# ---------- 6. DDNSTO（前端 LuCI + 后端服务程序，必须同时拉取，缺一不可）----------
if feed_has luci-app-ddnsto && feed_has ddnsto; then
    echo "[自带] ddnsto / luci-app-ddnsto"
else
    # 前端 LuCI 界面：nas-packages-luci 仓库 main 分支
    sparse_clone https://github.com/linkease/nas-packages-luci.git main luci-app-ddnsto
    # 后端服务程序：nas-packages 仓库 master 分支
    sparse_clone https://github.com/linkease/nas-packages.git master ddnsto
fi

# ---------- 7. 官方源自带插件核对（TurboACC / Mwan3 / nlbwmon / OpenClash）----------
for pkg in luci-app-turboacc mwan3 luci-app-mwan3 nlbwmon luci-app-nlbwmon \
           luci-app-openclash dnsmasq-full; do
    if feed_has "$pkg"; then
        echo "[自带] $pkg —— 使用 ImmortalWrt 源码包"
    else
        echo "[警告] $pkg 在 feeds 中未找到，固件可能缺失该功能，请检查！"
    fi
done

# ---------- 8. 关键包就位检查（提前暴露目录名/分支错误）----------
echo "--------------------------------------------"
echo " 关键包就位情况"
echo "--------------------------------------------"
for pkg in smartdns luci-app-smartdns luci-app-adguardhome luci-app-oaf \
           ddnsto luci-app-ddnsto luci-theme-argon luci-app-argon-config \
           luci-app-openclash luci-app-turboacc luci-app-mwan3 luci-app-nlbwmon; do
    if [ -d "$PKG_DIR/$pkg" ] || \
       [ -n "$(find "$OPENWRT_DIR/feeds" "$OPENWRT_DIR/package/feeds" -maxdepth 3 -type d -name "$pkg" 2>/dev/null | head -n1)" ]; then
        echo "  ✔ $pkg"
    else
        echo "  ✘ $pkg（缺失警告：请核对第三方仓库目录名）"
    fi
done
[ -d "$PKG_DIR/easytier-luci" ] && echo "  ✔ luci-app-easytier（EasyTier 仓库）" \
                                 || echo "  ✘ luci-app-easytier（EasyTier 仓库）"
echo "============================================"
echo " 第三方插件拉取完成"
echo "============================================"
