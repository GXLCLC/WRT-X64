#!/bin/bash
# ============================================================================
# 第三方插件拉取脚本（独立维护）
# ----------------------------------------------------------------------------
# 拉取规则：
#   1. 优先使用 ImmortalWrt 源码自带软件包（检测到自带即跳过第三方拉取）；
#   2. 仅当源码仓库不存在对应软件包时，才从第三方仓库浅克隆“所需插件目录”，
#      不完整拉取整个仓库，节省编译耗时；
#   3. AdGuardHome：按要求强制使用 kenzok8 仓库版本，核心程序与 LuCI 面板
#      必须同时拉取（避免只拉 LuCI 面板导致核心缺失），并移除源码自带版本；
#   4. DDNSTO：若需第三方拉取，则必须同时拉取
#      linkease/nas-packages-luci（main 分支，LuCI 前端页面）与
#      linkease/nas-packages（master 分支，后端程序），两者缺一不可；
#   5. OAF：luci-app-oaf 与 open-app-filter（kmod-oaf）来自 destan19 独立仓库。
# 执行时机：需在 “./scripts/feeds update -a” 之后调用（用于检测自带包）。
# ============================================================================
set -e

# 第三方插件统一存放目录（package/ 目录的优先级高于 feeds）
THIRD_PARTY_DIR="package/third-party"

# ------------------------------ 第三方仓库地址 ------------------------------
KENSOK8_REPO="https://github.com/kenzok8/openwrt-packages"        # kenzok8 软件包仓库
EASYTIER_REPO="https://github.com/EasyTier/luci-app-easytier"     # EasyTier 官方 LuCI 插件
DDNSTO_LUCI_REPO="https://github.com/linkease/nas-packages-luci"  # DDNSTO 前端（main 分支）
DDNSTO_BACKEND_REPO="https://github.com/linkease/nas-packages"    # DDNSTO 后端（master 分支）
OAF_REPO="https://github.com/destan19/OpenAppFilter"              # OAF 应用过滤
# ----------------------------------------------------------------------------

mkdir -p "$THIRD_PARTY_DIR"

# 检测 ImmortalWrt 源码（package/ 或 feeds/）中是否已自带指定软件包目录
has_native() {
    find package feeds -maxdepth 5 -type d -name "$1" \
        ! -path "package/third-party/*" 2>/dev/null | grep -q .
}

# 移除源码自带的同名软件包（用于强制启用第三方版本，防止包名冲突）
remove_native() {
    find package feeds -maxdepth 5 -type d -name "$1" \
        ! -path "package/third-party/*" -exec rm -rf {} + 2>/dev/null || true
    echo ">>> [第三方] 已移除源码自带软件包: $1（改用第三方版本）"
}

# 从第三方仓库浅克隆并仅拷贝目标插件目录
# 用法: fetch_pkg <仓库地址> <分支(留空使用默认分支)> <插件目录名>
fetch_pkg() {
    local repo="$1" branch="$2" pkg="$3"
    local tmp branch_opt=()
    [ -n "$branch" ] && branch_opt=(-b "$branch")
    tmp="$(mktemp -d)"

    echo ">>> [第三方] 拉取: $pkg <- $repo ${branch:+(分支: $branch)}"
    # 浅克隆 + 按需加载文件内容 + 仅检出根目录，最大限度减少网络传输量
    if ! git clone -q --depth 1 --filter=blob:none --sparse "${branch_opt[@]}" \
            "$repo" "$tmp/repo"; then
        echo "!!! [第三方] 仓库克隆失败: $repo"
        rm -rf "$tmp"; exit 1
    fi

    # 通过 ls-tree 在“不下载文件内容”的前提下定位插件目录（含 Makefile 的目录）
    local dir
    dir="$(cd "$tmp/repo" && git ls-tree -r --name-only HEAD \
        | grep -E "(^|/)${pkg}/Makefile$" | head -n1 | xargs -r dirname)"
    # 精确匹配失败时，改用前缀匹配（兼容目录名带后缀的情况）
    if [ -z "$dir" ]; then
        dir="$(cd "$tmp/repo" && git ls-tree -r --name-only HEAD \
            | grep -E "(^|/)${pkg}[^/]*/Makefile$" | head -n1 | xargs -r dirname)"
    fi
    if [ -z "$dir" ]; then
        echo "!!! [第三方] 仓库中未找到插件目录: $pkg"
        rm -rf "$tmp"; exit 1
    fi

    # sparse-checkout 仅检出目标插件目录，然后拷贝进 ImmortalWrt 编译树
    (cd "$tmp/repo" && git sparse-checkout set "$dir")
    rm -rf "$THIRD_PARTY_DIR/$pkg"
    cp -rf "$tmp/repo/$dir" "$THIRD_PARTY_DIR/$pkg"
    rm -rf "$tmp"
    echo ">>> [第三方] 拉取完成: $pkg -> $THIRD_PARTY_DIR/$pkg"
}

echo "==================================================="
echo " 第三方插件处理（优先使用 ImmortalWrt 源码自带包）"
echo "==================================================="

# ---------- AdGuardHome（强制 kenzok8 版本：核心程序 + LuCI 面板） ----------
# 需求说明：不使用 ImmortalWrt 自带的 AdGuardHome；
#           kenzok8 版 LuCI 面板可显示 AdGuardHome Web UI 端口；
#           核心与面板必须同时拉取，避免“只拉面板”导致功能不完整
remove_native "AdGuardHome"
remove_native "luci-app-adguardhome"
fetch_pkg "$KENSOK8_REPO" "" "AdGuardHome"
fetch_pkg "$KENSOK8_REPO" "" "luci-app-adguardhome"

# ---------- DDNSTO（源码自带则直接使用，否则拉取 linkease 前端 + 后端） ----------
if has_native "luci-app-ddnsto" && has_native "ddnsto"; then
    echo ">>> [第三方] DDNSTO 使用 ImmortalWrt 源码自带版本"
else
    # 前端（LuCI 页面）：nas-packages-luci 仓库 main 分支
    fetch_pkg "$DDNSTO_LUCI_REPO" "main" "luci-app-ddnsto"
    # 后端（ddnsto 程序本体）：nas-packages 仓库 master 分支，与前端缺一不可
    fetch_pkg "$DDNSTO_BACKEND_REPO" "master" "ddnsto"
fi

# ---------- OAF 应用过滤（luci-app-oaf + kmod-oaf，独立仓库编译） ----------
if has_native "luci-app-oaf"; then
    echo ">>> [第三方] OAF 使用 ImmortalWrt 源码自带版本"
else
    fetch_pkg "$OAF_REPO" "" "luci-app-oaf"       # LuCI 界面
    fetch_pkg "$OAF_REPO" "" "open-app-filter"    # 内核模块源码（编译产出 kmod-oaf）
fi

# ---------- EasyTier 内网穿透（官方独立仓库） ----------
if has_native "luci-app-easytier"; then
    echo ">>> [第三方] EasyTier 使用 ImmortalWrt 源码自带版本"
else
    fetch_pkg "$EASYTIER_REPO" "" "luci-app-easytier"
fi

# ---------- Argon 主题配置工具 ----------
if has_native "luci-theme-argon-config"; then
    echo ">>> [第三方] Argon 主题配置工具 使用源码自带版本"
else
    fetch_pkg "$KENSOK8_REPO" "" "luci-theme-argon-config"
fi

# ---------- Argon 主题本体（源码自带则跳过） ----------
if has_native "luci-theme-argon"; then
    echo ">>> [第三方] Argon 主题 使用 ImmortalWrt 源码自带版本"
else
    fetch_pkg "$KENSOK8_REPO" "" "luci-theme-argon"
fi

# ---------- OpenClash（源码自带则跳过；本固件仅集成这一个代理插件） ----------
if has_native "luci-app-openclash"; then
    echo ">>> [第三方] OpenClash 使用 ImmortalWrt 源码自带版本"
else
    fetch_pkg "$KENSOK8_REPO" "" "luci-app-openclash"
fi

# ---------- SmartDNS（源码自带则跳过，否则拉取 kenzok8 版核心与界面） ----------
if has_native "smartdns" && has_native "luci-app-smartdns"; then
    echo ">>> [第三方] SmartDNS 使用 ImmortalWrt 源码自带版本"
else
    fetch_pkg "$KENSOK8_REPO" "" "smartdns"
    fetch_pkg "$KENSOK8_REPO" "" "luci-app-smartdns"
fi

# ---------- TurboACC / Mwan3 / Nlbwmon（官方 feeds 常见包，缺失时才补充） ----------
for pkg_name in luci-app-turboacc mwan3 luci-app-mwan3 nlbwmon luci-app-nlbwmon; do
    if ! has_native "$pkg_name"; then
        fetch_pkg "$KENSOK8_REPO" "" "$pkg_name"
    else
        echo ">>> [第三方] $pkg_name 使用源码自带版本"
    fi
done

echo "==================================================="
echo " 第三方插件处理完成，已就绪的第三方插件目录："
find "$THIRD_PARTY_DIR" -maxdepth 1 -mindepth 1 -type d -printf "  - %f\n" 2>/dev/null || true
echo "==================================================="
