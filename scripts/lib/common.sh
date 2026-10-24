#!/usr/bin/env bash
# ==============================================================================
# 公共函数库：日志输出 / 前置校验 / 稀疏克隆 / 软件包集成
# 被 scripts 下的所有脚本 source 引用，请勿直接执行
# ==============================================================================
set -Eeuo pipefail

C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_BLUE='\033[34m'; C_OFF='\033[0m'

log()  { echo -e "${C_GREEN}[INFO]${C_OFF}  $*"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_OFF}  $*" >&2; }
err()  { echo -e "${C_RED}[ERROR]${C_OFF} $*" >&2; }
step() { echo -e "\n${C_BLUE}==>${C_OFF} $*"; }
die()  { err "$*"; exit 1; }

# ---- 目录约定 -----------------------------------------------------------------
# OPENWRT_ROOT : LEDE 源码根目录（由工作流注入，默认为脚本所在目录的上级 lede）
# BUILDER_ROOT : 本构建工程（仓库）根目录
OPENWRT_ROOT="${OPENWRT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lede}"
BUILDER_ROOT="${BUILDER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

enter_source() {
    [[ -d "$OPENWRT_ROOT" ]] || die "未找到 LEDE 源码目录：$OPENWRT_ROOT（路径错误 / 源码未拉取）"
    cd "$OPENWRT_ROOT"
}

# ---- 前置校验：仓库连通性 + 分支存在 ------------------------------------------
require_repo() {
    local repo="$1" branch="$2"
    if git ls-remote --exit-code --heads "$repo" "$branch" >/dev/null 2>&1; then
        log "连通性校验通过：$repo @ ${branch}"
    else
        die "仓库不可达或分支不存在：$repo @ ${branch}
  定位信息：git ls-remote --heads $repo $branch 返回失败
  修复建议：
    1) 确认分支名：packages=master / luci=openwrt-25.12 / routing=master / small-package=main / openwrt-packages=master；
    2) 若为网络问题，重新运行 workflow_dispatch 即可（本工程不自动重试）；
    3) 若上游改名或删分支，请同步修改 scripts/01-init-env.sh 与 scripts/03-fetch-plugins.sh 中的源定义。"
    fi
}

# ---- 拉取策略：--depth=1 裁剪历史 + --filter=blob:none 按需取内容 + 稀疏检出 ----
# 用法：sparse_clone <仓库> <分支> <本地目录> <路径1> [路径2 ...]
sparse_clone() {
    local repo="$1" branch="$2" dest="$3"; shift 3
    local paths=("$@")
    rm -rf "$dest"
    git clone --filter=blob:none --no-checkout --depth=1 --branch "$branch" "$repo" "$dest" >/dev/null 2>&1 || return 1
    git -C "$dest" sparse-checkout init --cone >/dev/null 2>&1 || return 1
    git -C "$dest" sparse-checkout set "${paths[@]}" >/dev/null 2>&1 || return 1
    git -C "$dest" checkout >/dev/null 2>&1 || return 1
    return 0
}

# 已克隆仓库追加稀疏路径（差分补漏用，避免重复克隆）
sparse_add() {
    local dest="$1"; shift
    git -C "$dest" sparse-checkout set "$@" >/dev/null 2>&1 || return 1
    git -C "$dest" checkout >/dev/null 2>&1 || return 1
}

# 浅克隆整仓：用于「仓库根目录即软件包」的场景（如 luci-app-bandix）
shallow_clone() {
    local repo="$1" branch="$2" dest="$3"
    rm -rf "$dest"
    git clone --depth=1 --filter=blob:none --branch "$branch" "$repo" "$dest" >/dev/null 2>&1
}

# ---- 软件包完整性校验与集成 ----------------------------------------------------
valid_pkg() { [[ -d "$1" ]] && [[ -f "$1/Makefile" ]]; }

# install_pkg <源目录> <目标路径(相对 $OPENWRT_ROOT/package)>
install_pkg() {
    local src="$1" rel="$2"
    local dest="${OPENWRT_ROOT}/package/${rel}"
    valid_pkg "$src" || { warn "目录不完整（缺少 Makefile）：$src"; return 1; }
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
    log "集成软件包：package/${rel}"
    return 0
}

# 输出标准化「修复建议」块
suggest() {
    local name="$1"; shift
    err "插件【${name}】在所有候选源中均未找到可用目录。
  已尝试的源："
    for s in "$@"; do err "    - $s"; done
    err "  修复建议：
    1) 打开对应仓库确认目录名是否已变更（大小写、重命名、合并到 others/ 等子目录）；
    2) 修正 scripts/03-fetch-plugins.sh 中该包的候选路径；
    3) 若该插件已被 Feeds 收录，请确认 scripts/01-init-env.sh 的 feeds.conf 是否包含对应源。"
}
