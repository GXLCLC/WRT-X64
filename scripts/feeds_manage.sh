#!/bin/bash
# ==============================================================================
# feeds_manage.sh - 第三方插件源管理脚本
# --------------------------------------------------------------------------------
# 脚本职责划分：
#   - LEDE 源码自带的官方 feeds 源（base、packages、luci 等）由 LEDE 源码内的
#     feeds.conf.default 管理，本脚本不处理官方 feeds。
#   - 本脚本仅负责管理外挂第三方插件源：读取 LEDE 原生 feeds 配置，追加自定义
#     第三方插件源地址，执行插件目录稀疏克隆；仅当 LEDE 源码内不存在对应软件包时，
#     才克隆对应插件目录，不全量拉取整个仓库；最后统一执行 feeds update && feeds install。
# --------------------------------------------------------------------------------
# 修改规则：
#   后续新增/减少第三方插件源，仅修改本脚本顶部 FEED_* 配置区，无需改动 build.yml
# 运行位置：LEDE 源码根目录（由 build.yml 指定 working-directory: openwrt）
# ==============================================================================
set -e

# ==============================================================================
# 第三方插件源配置区（新增/修改第三方源只改这里）
# --------------------------------------------------------------------------------
# 格式说明：每条源定义
#   FEED_<NAME>_REPO     第三方仓库地址
#   FEED_<NAME>_PACKAGES 需要克隆的插件目录（空格分隔，对应仓库内相对路径）
#   FEED_<NAME>_BRANCH   默认拉取分支（失败时自动回退到 main/master）
# 仅当 LEDE 源码内不存在对应软件包时，才会从对应第三方仓库克隆所需插件目录
# ==============================================================================

# 1. kenzok8/openwrt-packages（含 SmartDNS、应用过滤 OAF、Argon 主题、argon-config 等）
FEED_KENZO_REPO="https://github.com/kenzok8/openwrt-packages"
FEED_KENZO_PACKAGES="luci-app-smartdns smartdns luci-app-oaf luci-theme-argon luci-app-argon-config"
FEED_KENZO_BRANCH="master"

# 2. EasyTier/luci-app-easytier（EasyTier 内网穿透）
FEED_EASYTIER_REPO="https://github.com/EasyTier/luci-app-easytier"
FEED_EASYTIER_PACKAGES="luci-app-easytier"
FEED_EASYTIER_BRANCH="main"

# 3.1 linkease/nas-packages-luci（DDNSTO 的 LuCI 界面）
FEED_NASLUCI_REPO="https://github.com/linkease/nas-packages-luci"
FEED_NASLUCI_PACKAGES="luci-app-ddnsto"
FEED_NASLUCI_BRANCH="main"

# 3.2 linkease/nas-packages（DDNSTO 后端依赖）
FEED_NASPACKAGES_REPO="https://github.com/linkease/nas-packages"
FEED_NASPACKAGES_PACKAGES="ddnsto"
FEED_NASPACKAGES_BRANCH="main"

# ==============================================================================
# 工作目录与文件常量
# ==============================================================================
# 第三方源本地稀疏克隆存放目录（位于 LEDE 源码根目录下）
THIRD_PARTY_DIR="third_party_feeds"
# feeds 配置文件名（LEDE 优先读取 feeds.conf，不存在则使用 feeds.conf.default）
FEEDS_CONF="feeds.conf"

# ==============================================================================
# 工具函数：检测 LEDE 源码内是否已包含指定软件包
# --------------------------------------------------------------------------------
# 用法：lede_has_package <软件包名>
# 返回：0 表示已包含（无需从第三方源克隆），1 表示未包含（需要第三方源）
# ==============================================================================
lede_has_package() {
    local pkg="$1"
    # 1. 在 package/ 下查找同名目录
    if find package -maxdepth 4 -name "${pkg}" -type d 2>/dev/null | grep -q .; then
        return 0
    fi
    # 2. 在 feeds/ 下查找（feeds 已 update 的情况下）
    if find feeds -maxdepth 4 -name "${pkg}" -type d 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

# ==============================================================================
# 工具函数：稀疏克隆指定插件目录
# --------------------------------------------------------------------------------
# 用法：sparse_clone <仓库地址> <本地目录名> <插件目录列表> [分支]
# 实现要点：仅克隆所需插件目录，不完整拉取整个仓库，节省编译耗时
# ==============================================================================
sparse_clone() {
    local repo_url="$1"
    local local_name="$2"
    local packages="$3"
    local branch="${4:-master}"
    local target_dir="${THIRD_PARTY_DIR}/${local_name}"

    echo "--------------------------------------------------"
    echo ">>> 稀疏克隆 ${repo_url}"
    echo "    目标目录：${target_dir}"
    echo "    插件目录：${packages}"
    echo "    拉取分支：${branch}"

    # 已存在且已克隆则跳过
    if [ -d "${target_dir}/.git" ]; then
        echo "    目录已存在，跳过克隆"
        return 0
    fi

    rm -rf "${target_dir}"
    mkdir -p "${target_dir}"
    cd "${target_dir}"

    # 初始化空仓库
    git init -q
    git remote add origin "${repo_url}"
    # 启用稀疏检出（sparse-checkout）
    git config core.sparseCheckout true

    # 写入需要检出的插件目录路径
    : > .git/info/sparse-checkout
    local pkg
    for pkg in ${packages}; do
        echo "${pkg}" >> .git/info/sparse-checkout
    done

    # 尝试拉取指定分支，失败则按 main -> master 顺序回退
    local fetched=0
    if git fetch --depth 1 origin "${branch}" 2>/dev/null; then
        fetched=1
        git checkout -q "origin/${branch}" 2>/dev/null || git checkout -q FETCH_HEAD
    elif git fetch --depth 1 origin main 2>/dev/null; then
        fetched=1
        git checkout -q "origin/main" 2>/dev/null || git checkout -q FETCH_HEAD
    elif git fetch --depth 1 origin master 2>/dev/null; then
        fetched=1
        git checkout -q "origin/master" 2>/dev/null || git checkout -q FETCH_HEAD
    else
        # 兜底：拉取默认分支
        git fetch --depth 1 origin 2>/dev/null && git checkout -q FETCH_HEAD
        fetched=1
    fi

    cd - > /dev/null

    if [ "${fetched}" -ne 1 ]; then
        echo ">>> 警告：${repo_url} 拉取失败，请检查仓库地址与分支"
        return 1
    fi

    echo "    克隆完成：${target_dir}"
    echo "    检出内容："
    find "${target_dir}" -maxdepth 2 -type d | sed 's/^/      /'
}

# ==============================================================================
# 工具函数：将第三方源注册到 feeds.conf（src-link 指向本地稀疏克隆目录）
# --------------------------------------------------------------------------------
# 用法：register_feed <源名称> <本地稀疏克隆目录>
# 说明：src-link 表示 feeds 直接读取本地目录，不会再克隆整个仓库
# ==============================================================================
register_feed() {
    local feed_name="$1"
    local feed_dir="$2"
    # 若已注册则跳过
    if grep -q "src-link ${feed_name} " "${FEEDS_CONF}" 2>/dev/null; then
        echo ">>> feeds.conf 已包含 src-link ${feed_name}，跳过注册"
        return 0
    fi
    echo ">>> 注册到 feeds.conf：src-link ${feed_name} ${feed_dir}"
    echo "src-link ${feed_name} ${feed_dir}" >> "${FEEDS_CONF}"
}

# ==============================================================================
# 主流程开始
# ==============================================================================
echo "========================================"
echo ">>> feeds_manage.sh 开始执行"
echo "========================================"

# 准备工作目录
mkdir -p "${THIRD_PARTY_DIR}"

# 基于 LEDE 原生 feeds.conf.default 创建 feeds.conf（追加自定义源，不改动官方源）
if [ -f "feeds.conf.default" ] && [ ! -f "${FEEDS_CONF}" ]; then
    cp feeds.conf.default "${FEEDS_CONF}"
    echo ">>> 已基于 feeds.conf.default 创建 ${FEEDS_CONF}"
fi

# 先执行一次官方 feeds update，使 LEDE 自带插件目录可见，
# 便于后续 lede_has_package 检测是否需要从第三方源克隆
echo ">>> 执行官方 feeds update -a（使 LEDE 自带插件目录可见）"
./scripts/feeds update -a

# --------------------------------------------------------------------------------
# 拉取各第三方插件源（稀疏克隆，仅克隆所需插件目录）
# --------------------------------------------------------------------------------

echo ""
echo ">>> 开始拉取第三方插件源"

# 1. kenzok8/openwrt-packages
sparse_clone "${FEED_KENZO_REPO}" "kenzo" "${FEED_KENZO_PACKAGES}" "${FEED_KENZO_BRANCH}" || true
register_feed "kenzo" "$(pwd)/${THIRD_PARTY_DIR}/kenzo"

# 2. luci-app-easytier
sparse_clone "${FEED_EASYTIER_REPO}" "easytier" "${FEED_EASYTIER_PACKAGES}" "${FEED_EASYTIER_BRANCH}" || true
register_feed "easytier" "$(pwd)/${THIRD_PARTY_DIR}/easytier"

# 3.1 nas-packages-luci（DDNSTO LuCI）
sparse_clone "${FEED_NASLUCI_REPO}" "nasluci" "${FEED_NASLUCI_PACKAGES}" "${FEED_NASLUCI_BRANCH}" || true
register_feed "nasluci" "$(pwd)/${THIRD_PARTY_DIR}/nasluci"

# 3.2 nas-packages（DDNSTO 后端）
sparse_clone "${FEED_NASPACKAGES_REPO}" "naspackages" "${FEED_NASPACKAGES_PACKAGES}" "${FEED_NASPACKAGES_BRANCH}" || true
register_feed "naspackages" "$(pwd)/${THIRD_PARTY_DIR}/naspackages"

# --------------------------------------------------------------------------------
# 统一执行 feeds update && feeds install
# --------------------------------------------------------------------------------
echo ""
echo ">>> 统一执行 feeds update -a（包含官方源 + 自定义第三方源）"
./scripts/feeds update -a

echo ""
echo ">>> 统一执行 feeds install -a（安装全部 feeds 软件包到 package/）"
./scripts/feeds install -a

# --------------------------------------------------------------------------------
# 清除代理类插件目录（仓库规则：不添加任何代理类插件）
# LEDE 官方 packages feed 自带 ssr-plus / v2ray / shadowsocksr 等代理包，
# feeds install -a 会把它们装到 package/ 下；make defconfig 可能因依赖链
# 自动启用，导致编译失败。这里从 package/ 目录物理删除，彻底杜绝。
# --------------------------------------------------------------------------------
PROXY_PKG_DIRS=(
    "package/luci-app-ssr-plus"
    "package/luci-app-ssr-plus_INCLUDE_Shadowsocks"
    "package/luci-app-ssr-plus_INCLUDE_V2ray"
    "package/luci-app-ssr-plus_INCLUDE_Xray"
    "package/luci-app-ssr-plus_INCLUDE_Trojan"
    "package/luci-app-ssr-plus_INCLUDE_NaiveProxy"
    "package/luci-app-ssr-plus_INCLUDE_Hysteria2"
    "package/luci-app-ssr-plus_INCLUDE_Kcptun"
    "package/luci-app-ssr-plus_INCLUDE_Redsocks2"
    "package/luci-app-ssr-plus_INCLUDE_ShadowSocks"
    "package/luci-app-ssr-plus_INCLUDE_ShadowSocksR"
    "package/luci-app-shadowsocks-libev"
    "package/luci-app-shadowsocksr-libev"
    "package/luci-app-trojan"
    "package/luci-app-hysteria"
    "package/luci-app-hysteria2"
    "package/luci-app-openvpn"
    "package/shadowsocks-libev"
    "package/shadowsocksr-libev"
    "package/v2ray-core"
    "package/v2ray-geoip"
    "package/v2ray-geosite"
    "package/xray-core"
    "package/trojan"
    "package/naiveproxy"
    "package/hysteria"
    "package/hysteria2"
    "package/kcptun-client"
    "package/kcptun-server"
    "package/redsocks2"
    "package/microsocks"
    "package/openvpn"
    "package/openvpn-openssl"
)
# 同时清理 feeds/ 下的代理包源，避免被重新 install
PROXY_FEED_DIRS=(
    "packages/luci-app-ssr-plus"
    "packages/luci-app-shadowsocks-libev"
    "packages/luci-app-shadowsocksr-libev"
    "packages/luci-app-trojan"
    "packages/luci-app-openvpn"
    "packages/shadowsocks-libev"
    "packages/shadowsocksr-libev"
    "packages/v2ray-core"
    "packages/v2ray-geoip"
    "packages/v2ray-geosite"
    "packages/xray-core"
    "packages/trojan"
    "packages/naiveproxy"
    "packages/hysteria"
    "packages/hysteria2"
    "packages/kcptun-client"
    "packages/kcptun-server"
    "packages/redsocks2"
    "packages/microsocks"
    "packages/openvpn"
    "packages/openvpn-openssl"
    "packages/tproxy"
    "packages/iptables2socks"
)

echo ""
echo ">>> 清除 package/ 下的代理类插件目录（防止 make defconfig 自动启用）"
removed=0
for dir in "${PROXY_PKG_DIRS[@]}"; do
    if [ -d "${dir}" ]; then
        rm -rf "${dir}"
        echo "    已删除：${dir}"
        removed=$((removed + 1))
    fi
done
echo "    共清除 ${removed} 个代理包目录"

echo ">>> 清除 feeds/ 下的代理包源（防止 feeds install 重新拉取）"
for dir in "${PROXY_FEED_DIRS[@]}"; do
    if [ -d "${dir}" ]; then
        rm -rf "${dir}"
    fi
done

# --------------------------------------------------------------------------------
# 输出已注册的 feeds 列表，便于确认
# --------------------------------------------------------------------------------
echo ""
echo "========================================"
echo ">>> 当前 feeds.conf 内容："
cat "${FEEDS_CONF}"
echo "========================================"
echo ">>> feeds_manage.sh 执行完成"
