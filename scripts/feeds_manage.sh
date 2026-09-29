#!/bin/bash
# ==============================================================================
# feeds_manage.sh - 第三方插件源管理脚本
# --------------------------------------------------------------------------------
# 脚本职责：
#   - ImmortalWrt 源码自带的官方 feeds 源（packages、luci、routing 等）由
#     ImmortalWrt 源码内 feeds.conf.default 管理，本脚本不改动官方源。
#   - 本脚本仅负责管理外挂第三方插件源：仅当 ImmortalWrt 源码仓库不存在对应
#     软件包时，才从第三方仓库稀疏克隆所需插件目录，不全量拉取整个仓库。
#   - 最后统一执行 ./scripts/feeds update -a && ./scripts/feeds install -a。
# --------------------------------------------------------------------------------
# 修改规则：
#   后续新增/减少第三方插件源，仅修改本脚本顶部 FEED_* 配置区，无需改动 build.yml。
# 运行位置：ImmortalWrt 源码根目录（由 build.yml 指定 working-directory）
# ==============================================================================
set -euo pipefail

# ==============================================================================
# 第三方插件源配置区（新增/修改第三方源只改这里）
# --------------------------------------------------------------------------------
# 每条源定义：
#   FEED_<NAME>_REPO     第三方仓库地址
#   FEED_<NAME>_PACKAGES 需要克隆的插件目录（空格分隔，对应仓库内相对路径）
#   FEED_<NAME>_BRANCH   拉取分支
# 仅当 ImmortalWrt 源码内不存在对应软件包时，才从对应第三方仓库克隆。
# ==============================================================================

# 1. kenzok8/openwrt-packages（TurboAcc、OAF 应用过滤）
FEED_KENZO_REPO="https://github.com/kenzok8/openwrt-packages"
FEED_KENZO_PACKAGES="luci-app-turboacc luci-app-oaf oaf"
FEED_KENZO_BRANCH="master"

# 2. EasyTier/luci-app-easytier（EasyTier 内网穿透，含前端 luci 与后端 easytier）
FEED_EASYTIER_REPO="https://github.com/EasyTier/luci-app-easytier"
FEED_EASYTIER_PACKAGES="luci-app-easytier easytier"
FEED_EASYTIER_BRANCH="main"

# 3.1 linkease/nas-packages-luci（DDNSTO 的 LuCI 前端界面，main 分支）
FEED_NASLUCI_REPO="https://github.com/linkease/nas-packages-luci"
FEED_NASLUCI_PACKAGES="luci-app-ddnsto"
FEED_NASLUCI_BRANCH="main"

# 3.2 linkease/nas-packages（DDNSTO 后端程序包，master 分支）
# 注意：DDNSTO 必须同时拉取 luci 前端与后端程序包，不可仅拉取 luci 页面目录
FEED_NASPACKAGES_REPO="https://github.com/linkease/nas-packages"
FEED_NASPACKAGES_PACKAGES="ddnsto"
FEED_NASPACKAGES_BRANCH="master"

# ==============================================================================
# 工作目录与文件常量
# ==============================================================================
# 第三方源本地稀疏克隆存放目录（位于 ImmortalWrt 源码根目录下）
THIRD_PARTY_DIR="third_party_feeds"
# feeds 配置文件名（ImmortalWrt 优先读取 feeds.conf，不存在则使用 feeds.conf.default）
FEEDS_CONF="feeds.conf"

# ==============================================================================
# 工具函数：检测 ImmortalWrt 源码内是否已包含指定软件包
# 用法：iwrt_has_package <软件包名>
# 返回：0 表示已包含（无需从第三方源克隆），1 表示未包含（需要第三方源）
# ==============================================================================
iwrt_has_package() {
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

    # 初始化空仓库并启用稀疏检出
    git init -q
    git remote add origin "${repo_url}"
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
# 用法：register_feed <源名称> <本地稀疏克隆目录>
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

# 基于 ImmortalWrt 原生 feeds.conf.default 创建 feeds.conf（追加自定义源，不改动官方源）
if [ -f "feeds.conf.default" ] && [ ! -f "${FEEDS_CONF}" ]; then
    cp feeds.conf.default "${FEEDS_CONF}"
    echo ">>> 已基于 feeds.conf.default 创建 ${FEEDS_CONF}"
fi

# 先执行一次官方 feeds update，使 ImmortalWrt 自带插件目录可见，
# 便于后续 iwrt_has_package 检测是否需要从第三方源克隆
echo ">>> 执行官方 feeds update -a（使 ImmortalWrt 自带插件目录可见）"
./scripts/feeds update -a

# --------------------------------------------------------------------------------
# 按需拉取第三方插件源（仅克隆 ImmortalWrt 源码不存在的包）
# --------------------------------------------------------------------------------
echo ""
echo ">>> 按需拉取第三方插件源"

# 1. kenzok8/openwrt-packages（TurboAcc、OAF）
KENZO_NEEDED=""
for pkg in ${FEED_KENZO_PACKAGES}; do
    if ! iwrt_has_package "${pkg}"; then
        KENZO_NEEDED="${KENZO_NEEDED} ${pkg}"
    fi
done
if [ -n "${KENZO_NEEDED}" ]; then
    echo ">>> ImmortalWrt 缺少以下包，从 kenzok8 拉取：${KENZO_NEEDED}"
    sparse_clone "${FEED_KENZO_REPO}" "kenzo" "${KENZO_NEEDED}" "${FEED_KENZO_BRANCH}" || true
    register_feed "kenzo" "$(pwd)/${THIRD_PARTY_DIR}/kenzo"
else
    echo ">>> kenzok8 所需包 ImmortalWrt 已自带，跳过"
fi

# 2. EasyTier
EASYTIER_NEEDED=""
for pkg in ${FEED_EASYTIER_PACKAGES}; do
    if ! iwrt_has_package "${pkg}"; then
        EASYTIER_NEEDED="${EASYTIER_NEEDED} ${pkg}"
    fi
done
if [ -n "${EASYTIER_NEEDED}" ]; then
    echo ">>> ImmortalWrt 缺少以下包，从 EasyTier 拉取：${EASYTIER_NEEDED}"
    sparse_clone "${FEED_EASYTIER_REPO}" "easytier" "${EASYTIER_NEEDED}" "${FEED_EASYTIER_BRANCH}" || true
    register_feed "easytier" "$(pwd)/${THIRD_PARTY_DIR}/easytier"
else
    echo ">>> EasyTier 所需包 ImmortalWrt 已自带，跳过"
fi

# 3.1 nas-packages-luci（DDNSTO LuCI 前端）
NASLUCI_NEEDED=""
for pkg in ${FEED_NASLUCI_PACKAGES}; do
    if ! iwrt_has_package "${pkg}"; then
        NASLUCI_NEEDED="${NASLUCI_NEEDED} ${pkg}"
    fi
done
if [ -n "${NASLUCI_NEEDED}" ]; then
    echo ">>> ImmortalWrt 缺少以下包，从 nas-packages-luci 拉取：${NASLUCI_NEEDED}"
    sparse_clone "${FEED_NASLUCI_REPO}" "nasluci" "${NASLUCI_NEEDED}" "${FEED_NASLUCI_BRANCH}" || true
    register_feed "nasluci" "$(pwd)/${THIRD_PARTY_DIR}/nasluci"
else
    echo ">>> nas-packages-luci 所需包 ImmortalWrt 已自带，跳过"
fi

# 3.2 nas-packages（DDNSTO 后端，必须与前端同时拉取）
NASPACKAGES_NEEDED=""
for pkg in ${FEED_NASPACKAGES_PACKAGES}; do
    if ! iwrt_has_package "${pkg}"; then
        NASPACKAGES_NEEDED="${NASPACKAGES_NEEDED} ${pkg}"
    fi
done
if [ -n "${NASPACKAGES_NEEDED}" ]; then
    echo ">>> ImmortalWrt 缺少以下包，从 nas-packages 拉取：${NASPACKAGES_NEEDED}"
    sparse_clone "${FEED_NASPACKAGES_REPO}" "naspackages" "${NASPACKAGES_NEEDED}" "${FEED_NASPACKAGES_BRANCH}" || true
    register_feed "naspackages" "$(pwd)/${THIRD_PARTY_DIR}/naspackages"
else
    echo ">>> nas-packages 所需包 ImmortalWrt 已自带，跳过"
fi

# --------------------------------------------------------------------------------
# 统一执行 feeds update -a && feeds install -a
# --------------------------------------------------------------------------------
echo ""
echo ">>> 统一执行 feeds update -a（官方源 + 自定义第三方源）"
./scripts/feeds update -a

echo ""
echo ">>> 统一执行 feeds install -a（安装全部 feeds 软件包到 package/feeds/）"
./scripts/feeds install -a

echo ""
echo "========================================"
echo ">>> feeds_manage.sh 执行完成"
echo "========================================"
