#!/bin/bash
# ================================================================
# feeds_manage.sh — 第三方插件源管理脚本
# ----------------------------------------------------------------
# 职责说明：
#   管理外挂第三方插件源，采用稀疏克隆（sparse checkout）方式，
#   仅拉取所需的插件目录，不全量克隆整个仓库，节省编译耗时。
#
#   LEDE 源码自带的官方 feeds（base、packages、luci 等）由
#   feeds.conf.default 管理，本脚本不重复处理。
#
# 拉取规则：
#   对于每个第三方插件，先检查 LEDE 源码内是否已存在同名软件包；
#   仅当不存在时，才从第三方仓库稀疏克隆对应目录到 package/ 下。
#
# 后续增减第三方插件源：
#   【仅需修改本文件中的"第三方插件源定义区"】，无需改动 build.yml。
# ================================================================

set -e  # 任何命令失败立即终止

# 获取 LEDE 源码根目录
LEDE_ROOT="${LEDE_ROOT:-$(pwd)/lede}"

echo "=========================================="
echo "  开始管理第三方插件源"
echo "=========================================="

# ================================================================
# >>>>>>>>>>  第三方插件源定义区（增减插件源改这里）  <<<<<<<<<<
# ================================================================

# 定义第三方插件源数组
# 格式："仓库名|仓库URL|仓库内插件目录路径|目标放置目录"
#   - 仓库名：仅用于日志显示
#   - 仓库URL：GitHub 仓库地址
#   - 仓库内插件目录路径：该插件在仓库中的相对路径
#   - 目标放置目录：克隆到 LEDE 源码中的目标路径（通常在 package/ 下）
THIRD_PARTY_FEEDS=(
    # kenzok8 仓库 —— 提供 SmartDNS、AdGuardHome、OFA 应用过滤等插件
    "kenzok8-packages|https://github.com/kenzok8/openwrt-packages|luci-app-smartdns|${LEDE_ROOT}/package/feeds/kenzok8/luci-app-smartdns"
    "kenzok8-smartdns|https://github.com/kenzok8/openwrt-packages|smartdns|${LEDE_ROOT}/package/feeds/kenzok8/smartdns"
    "kenzok8-adguardhome|https://github.com/kenzok8/openwrt-packages|luci-app-adguardhome|${LEDE_ROOT}/package/feeds/kenzok8/luci-app-adguardhome"
    "kenzok8-adguardhome-bin|https://github.com/kenzok8/openwrt-packages|adguardhome|${LEDE_ROOT}/package/feeds/kenzok8/adguardhome"
    "kenzok8-oaf|https://github.com/kenzok8/openwrt-packages|luci-app-oaf|${LEDE_ROOT}/package/feeds/kenzok8/luci-app-oaf"
    "kenzok8-openappfilter|https://github.com/kenzok8/openwrt-packages|open-appfilter|${LEDE_ROOT}/package/feeds/kenzok8/open-appfilter"
    "kenzok8-argon-theme|https://github.com/kenzok8/openwrt-packages|luci-theme-argon|${LEDE_ROOT}/package/feeds/kenzok8/luci-theme-argon"
    "kenzok8-argon-config|https://github.com/kenzok8/openwrt-packages|luci-app-argon-config|${LEDE_ROOT}/package/feeds/kenzok8/luci-app-argon-config"

    # EasyTier 内网穿透插件
    "easytier|https://github.com/EasyTier/luci-app-easytier|luci-app-easytier|${LEDE_ROOT}/package/feeds/easytier/luci-app-easytier"
    "easytier-core|https://github.com/EasyTier/luci-app-easytier|easytier|${LEDE_ROOT}/package/feeds/easytier/easytier"

    # DDNSTO 插件 —— 依赖 nas-packages-luci 和 nas-packages 两个仓库
    "nas-luci-ddnsto|https://github.com/linkease/nas-packages-luci|luci-app-ddnsto|${LEDE_ROOT}/package/feeds/nas/luci-app-ddnsto"
    "nas-ddnsto|https://github.com/linkease/nas-packages|ddnsto|${LEDE_ROOT}/package/feeds/nas/ddnsto"
)

# ================================================================
# >>>>>>>>>>  定义区结束（以下为执行逻辑，一般无需修改）  <<<<<<<<<<
# ================================================================

# ----------------------------------------------------------------
# 函数：检查 LEDE 源码内是否已存在指定软件包
# 参数：$1 = 软件包名称（目录名）
# 返回：0 = 已存在（跳过克隆），1 = 不存在（需要克隆）
# ----------------------------------------------------------------
check_package_exists() {
    local pkg_name="$1"
    # 在 package/ 目录和 feeds/ 目录下递归查找同名目录
    # 排除我们自己的 feeds/kenzok8、feeds/easytier、feeds/nas 目录
    local found_dir
    found_dir=$(find "${LEDE_ROOT}/package" "${LEDE_ROOT}/feeds" \
        -maxdepth 4 \
        -type d \
        -name "${pkg_name}" \
        ! -path "*/feeds/kenzok8/*" \
        ! -path "*/feeds/easytier/*" \
        ! -path "*/feeds/nas/*" \
        2>/dev/null | head -1)

    if [ -n "${found_dir}" ]; then
        return 0  # 已存在
    else
        return 1  # 不存在
    fi
}

# ----------------------------------------------------------------
# 函数：稀疏克隆单个插件目录
# 参数：$1 = 仓库URL, $2 = 仓库内路径, $3 = 目标路径
# 说明：使用 git sparse-checkout 仅拉取所需目录，避免全量克隆
# ----------------------------------------------------------------
sparse_clone_pkg() {
    local repo_url="$1"
    local src_path="$2"
    local dest_path="$3"
    local pkg_name
    pkg_name=$(basename "${dest_path}")
    local tmp_clone_dir="/tmp/sparse_clone_$$"

    echo "  -> 稀疏克隆: ${pkg_name}"
    echo "     来源: ${repo_url}/${src_path}"

    # 创建临时克隆目录
    rm -rf "${tmp_clone_dir}"
    mkdir -p "${tmp_clone_dir}"

    # 初始化 git 仓库并配置稀疏检出
    cd "${tmp_clone_dir}"
    git init --quiet
    git remote add origin "${repo_url}"
    # 启用 cone 模式稀疏检出（仅拉取所需目录）
    git config core.sparseCheckout true
    git sparse-checkout init --cone
    git sparse-checkout set "${src_path}"

    # 拉取最新代码（仅拉取稀疏检出指定的目录）
    git fetch --depth=1 origin HEAD
    git checkout FETCH_HEAD

    # 将插件目录复制到目标位置
    mkdir -p "$(dirname "${dest_path}")"
    if [ -d "${src_path}" ]; then
        cp -r "${src_path}" "${dest_path}"
        echo "     ✓ 克隆成功 -> ${dest_path}"
    else
        echo "     ✗ 仓库中未找到目录: ${src_path}"
    fi

    # 清理临时目录
    cd "${LEDE_ROOT}"
    rm -rf "${tmp_clone_dir}"
}

# ----------------------------------------------------------------
# 主逻辑：遍历第三方插件源定义，逐个检查并克隆
# ----------------------------------------------------------------
echo ""
echo ">>> 阶段一：检查并稀疏克隆第三方插件"
echo "------------------------------------------"

# 创建第三方 feeds 目录
mkdir -p "${LEDE_ROOT}/package/feeds/kenzok8"
mkdir -p "${LEDE_ROOT}/package/feeds/easytier"
mkdir -p "${LEDE_ROOT}/package/feeds/nas"

CLONE_COUNT=0
SKIP_COUNT=0

for feed_entry in "${THIRD_PARTY_FEEDS[@]}"; do
    # 解析定义字段
    IFS='|' read -r repo_name repo_url src_path dest_path <<< "${feed_entry}"
    pkg_name=$(basename "${dest_path}")

    # 检查目标路径是否已存在（避免重复克隆）
    if [ -d "${dest_path}" ]; then
        echo "  [跳过] ${pkg_name} 目录已存在"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # 检查 LEDE 源码内是否已存在该软件包
    if check_package_exists "${pkg_name}"; then
        echo "  [跳过] ${pkg_name} 已在 LEDE 源码中存在"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # 执行稀疏克隆
    sparse_clone_pkg "${repo_url}" "${src_path}" "${dest_path}"
    CLONE_COUNT=$((CLONE_COUNT + 1))
done

echo "------------------------------------------"
echo "  克隆完成: 新增 ${CLONE_COUNT} 个，跳过 ${SKIP_COUNT} 个"
echo ""

# ----------------------------------------------------------------
# 阶段二：执行官方 feeds 更新与安装
# 这一步会处理 LEDE 自带的 feeds.conf.default 中的官方源
# ----------------------------------------------------------------
echo ">>> 阶段二：更新并安装 LEDE 官方 feeds"
echo "------------------------------------------"
cd "${LEDE_ROOT}"

# 更新 feeds 源码（拉取官方 feeds 仓库到 feeds/ 目录）
echo "  执行 feeds update -a ..."
./scripts/feeds update -a

# 安装所有 feeds 到 package/feeds/ 目录（建立符号链接）
echo "  执行 feeds install -a ..."
./scripts/feeds install -a

echo "------------------------------------------"
echo "  feeds 更新与安装完成"
echo ""

echo "=========================================="
echo "  第三方插件源管理完成！"
echo "=========================================="
