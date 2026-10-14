#!/usr/bin/env bash
#
# feeds_update.sh —— 第三方插件仓库拉取与 feeds 源更新脚本
# 用途：在 OpenWrt 源码根目录内执行，负责：
#   1. 更新 ImmortalWrt 官方 feeds（packages / luci / routing / telephony）
#   2. 安装 feeds 到 feeds/ 目录
#   3. 仅当 ImmortalWrt 源码不存在对应软件包时，才从第三方仓库"浅克隆"所需插件目录，
#      并放入 package/ 目录参与编译（不完整拉取整个仓库，节省耗时与流量）
#
# 约定：任意一步失败立即终止（set -e），并输出明确的缺失项与来源仓库信息，便于排错。

set -euo pipefail

# ---------------------------------------------------------------------------
# 第三方仓库常量（浅克隆深度、分支均显式指定）
# ---------------------------------------------------------------------------
KENZOK8_URL="https://github.com/kenzok8/openwrt-packages"          # kenzok8 软件包集合（master 分支）
EASYTIER_URL="https://github.com/EasyTier/luci-app-easytier"         # EasyTier 的 luci 面板（main 分支）
DDNSTO_LUCI_URL="https://github.com/linkease/nas-packages-luci"      # ddnsto luci 前端（main 分支）
DDNSTO_PKG_URL="https://github.com/linkease/nas-packages"            # ddnsto 后端程序（master 分支）
OAF_URL="https://github.com/destan19/OpenAppFilter"                  # OAF 应用过滤（master 分支，含 kmod-oaf + luci-app-oaf）
TURBOACC_URL="https://github.com/chenmozhijin/turboacc"              # TurboAcc 加速（luci 分支，适配 firewall4）

CLONE_DEPTH="--depth=1"

log()  { echo -e "\033[1;32m[feeds]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[error]\033[0m $*" >&2; exit 1; }

# 从第三方仓库稀疏检出指定子目录到 package/<dest>
# 参数：$1=仓库URL  $2=分支  $3=仓库内子目录  $4=目标目录名
clone_sparse_dir() {
    local url="$1" branch="$2" subdir="$3" dest="$4"
    local tmpdir
    tmpdir="$(mktemp -d)"

    log "浅克隆 ${url} (分支 ${branch}) 的 ${subdir} -> package/${dest}"
    if ! git clone --depth=1 --single-branch --branch "${branch}" \
             --filter=blob:none --sparse "${url}" "${tmpdir}"; then
        rm -rf "${tmpdir}"
        die "克隆失败：${url} 分支 ${branch}。请检查上游仓库是否存在、分支名是否正确或网络是否可达。"
    fi
    (
        cd "${tmpdir}"
        if ! git sparse-checkout set "${subdir}"; then
            cd /
            rm -rf "${tmpdir}"
            die "稀疏检出失败：仓库 ${url} 分支 ${branch} 中不存在目录 ${subdir}。请核对上游路径是否已调整。"
        fi
    )

    if [ ! -d "${tmpdir}/${subdir}" ]; then
        rm -rf "${tmpdir}"
        die "目录缺失：仓库 ${url} 分支 ${branch} 拉取后未找到 ${subdir}。上游路径可能已变更。"
    fi

    # 目标目录若已存在（可能来自 ImmortalWrt 自带同名包），则移除以避免冲突
    if [ -e "package/${dest}" ]; then
        warn "package/${dest} 已存在，将移除后使用第三方版本。"
        rm -rf "package/${dest}"
    fi
    mkdir -p "package/$(dirname "${dest}")"
    cp -r "${tmpdir}/${subdir}" "package/${dest}"

    rm -rf "${tmpdir}"
    log "已放置 package/${dest}"
}

# ---------------------------------------------------------------------------
# 1. 更新官方 feeds 源
# ---------------------------------------------------------------------------
log "更新官方 feeds 源（./scripts/feeds update -a）"
./scripts/feeds update -a

log "安装官方 feeds（./scripts/feeds install -a）"
./scripts/feeds install -a

# ---------------------------------------------------------------------------
# 清理与第三方插件重名的官方 feed 包，避免 "recursive dependency detected!"
# （同名包在 package/ 与 package/feeds/ 中重复定义会导致 kconfig 递归依赖错误）
# ---------------------------------------------------------------------------
for conflict in package/feeds/packages/adguardhome package/feeds/luci/luci-app-appfilter; do
    if [ -e "${conflict}" ]; then
        warn "移除与第三方插件重名的官方 feed 包：${conflict}"
        rm -rf "${conflict}"
    fi
done

# ---------------------------------------------------------------------------
# 2. SmartDNS —— 优先使用 ImmortalWrt 自带包
#    luci-app-smartdns 已存在于 ImmortalWrt luci 源，无需从第三方拉取。
# ---------------------------------------------------------------------------
if [ -d "feeds/luci/applications/luci-app-smartdns" ] || [ -d "package/feeds/luci/luci-app-smartdns" ]; then
    log "SmartDNS：使用 ImmortalWrt 自带 luci-app-smartdns，跳过第三方拉取。"
else
    warn "未在 ImmortalWrt 源中找到 luci-app-smartdns，改为从 kenzok8 拉取。"
    clone_sparse_dir "${KENZOK8_URL}" "master" "luci-app-smartdns" "luci-app-smartdns"
    clone_sparse_dir "${KENZOK8_URL}" "master" "smartdns" "smartdns"
fi

# ---------------------------------------------------------------------------
# 3. AdGuardHome —— 按需求使用 kenzok8 版本（核心 + luci 面板），不使用 ImmortalWrt 自带包
# ---------------------------------------------------------------------------
log "AdGuardHome：使用 kenzok8 仓库（核心程序 + luci 面板）。"
clone_sparse_dir "${KENZOK8_URL}" "master" "adguardhome" "adguardhome"
clone_sparse_dir "${KENZOK8_URL}" "master" "luci-app-adguardhome" "luci-app-adguardhome"

# ---------------------------------------------------------------------------
# 4. DDNSTO 内网穿透 —— 依赖两个仓库，前后端配套、缺一不可，分支显式指定
#    luci 前端：linkease/nas-packages-luci  main 分支
#    后端程序：linkease/nas-packages       master 分支
# ---------------------------------------------------------------------------
log "DDNSTO：拉取 luci 前端（main 分支）+ 后端程序（master 分支）。"
clone_sparse_dir "${DDNSTO_LUCI_URL}" "main"   "luci/luci-app-ddnsto" "luci-app-ddnsto"
clone_sparse_dir "${DDNSTO_PKG_URL}"  "master" "network/services/ddnsto" "ddnsto"

# ---------------------------------------------------------------------------
# 5. OAF 应用过滤 —— luci-app-oaf 来自独立仓库 destan19/OpenAppFilter
#    说明：kmod-oaf 与 appfilter 由 ImmortalWrt 自带的 open-app-filter 包提供
#    （该包同样是从 destan19/OpenAppFilter 拉取源码编译，且与 24.10 内核 6.6 匹配）；
#    切勿再克隆 destan19 的 oaf/ 目录，否则 kmod-oaf 重复定义会触发
#    "recursive dependency detected! symbol PACKAGE_kmod-oaf is selected by
#     PACKAGE_kmod-oaf" 编译错误。
# ---------------------------------------------------------------------------
log "OAF：拉取 luci-app-oaf（destan19/OpenAppFilter master 分支），kmod-oaf 由自带 open-app-filter 提供。"
if [ -e "package/feeds/packages/open-app-filter" ]; then
    log "已确认官方 open-app-filter（kmod-oaf + appfilter）存在。"
else
    die "缺少 open-app-filter（kmod-oaf/appfilter 提供者），luci-app-oaf 依赖将无法满足。请检查官方 feeds 是否完整。"
fi
clone_sparse_dir "${OAF_URL}" "master" "luci-app-oaf" "luci-app-oaf"

# ---------------------------------------------------------------------------
# 6. TurboAcc 加速 —— ImmortalWrt 源不含，拉取 chenmozhijin/turboacc 适配 firewall4 的版本
#    luci-app-turboacc 依赖 nft-fullcone（ImmortalWrt 自带 kmod-nft-fullcone），
#    且依赖已打补丁的 firewall4/libnftnl/nftables。这里拉取 luci-app-turboacc 本体，
#    nft-fullcone 由 ImmortalWrt 自带；firewall4 补丁在 workflow 中另行应用。
# ---------------------------------------------------------------------------
log "TurboAcc：拉取 chenmozhijin/turboacc（luci 分支）的 luci-app-turboacc。"
clone_sparse_dir "${TURBOACC_URL}" "luci" "luci-app-turboacc" "luci-app-turboacc"

# ---------------------------------------------------------------------------
# 7. EasyTier 异地组网 —— 独立仓库 luci-app-easytier（含 core 程序与 luci 面板）
# ---------------------------------------------------------------------------
log "EasyTier：拉取 luci-app-easytier（EasyTier/luci-app-easytier main 分支）。"
clone_sparse_dir "${EASYTIER_URL}" "main" "luci-app-easytier" "luci-app-easytier"
clone_sparse_dir "${EASYTIER_URL}" "main" "easytier" "easytier"

log "全部第三方插件与 feeds 源更新完成。"
