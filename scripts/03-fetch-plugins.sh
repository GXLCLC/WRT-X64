#!/usr/bin/env bash
# ==============================================================================
# 步骤三：第三方插件拉取
# 策略：Feeds 优先 → 批量预拉（small-package > openwrt-packages）→ 后置差分补漏
#       → 独立维护仓库兜底；全程浅克隆 + 部分克隆 + 稀疏检出
# 依赖：需先执行 01（生成 .feeds-available.list）与 02（内核切换）
# ==============================================================================
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
enter_source

SRC_ROOT="${OPENWRT_ROOT}/../plugin-src"     # 拉取工作区（放在源码树外，避免污染包扫描）
mkdir -p "$SRC_ROOT"

# ------------------------------ 源定义 ----------------------------------------
declare -A SRC_REPO SRC_BRANCH SRC_LOCAL
SRC_REPO[small]="https://github.com/kenzok8/small-package"
SRC_BRANCH[small]="main"
SRC_LOCAL[small]="$SRC_ROOT/small-package"

SRC_REPO[pkgs]="https://github.com/kenzok8/openwrt-packages"
SRC_BRANCH[pkgs]="master"
SRC_LOCAL[pkgs]="$SRC_ROOT/openwrt-packages"

# small-package 优先级更高（补充源），故 small 排在前面
# 格式：包名 | 候选1 | 候选2 ...（候选 = 仓库key:仓库内相对路径）
PKGS=(
  "luci-app-smartdns|small:luci-app-smartdns|pkgs:luci-app-smartdns"
  "smartdns|small:smartdns|pkgs:smartdns"
  "luci-app-ddnsto|small:luci-app-ddnsto|pkgs:luci-app-ddnsto"
  "ddnsto|small:ddnsto|pkgs:ddnsto"
  "luci-app-adguardhome|pkgs:luci-app-adguardhome|small:luci-app-adguardhome"
  "adguardhome|pkgs:adguardhome|small:adguardhome"
  "luci-app-easytier|pkgs:luci-app-easytier|small:luci-app-easytier"
  "easytier|pkgs:easytier|small:easytier"
  "luci-theme-argon|pkgs:luci-theme-argon|small:luci-theme-argon"
  "luci-app-argon-config|pkgs:luci-app-argon-config|small:luci-app-argon-config"
  "luci-app-wol|pkgs:luci-app-wol|small:luci-app-wol"
  "wol|pkgs:wol|small:wol"
  "luci-app-autoreboot|pkgs:luci-app-autoreboot|small:luci-app-autoreboot"
  "luci-app-wechatpush|small:luci-app-wechatpush|pkgs:luci-app-wechatpush"
  "nft-fullcone|small:nft-fullcone|pkgs:nft-fullcone"
  # 以下三项为 Feeds 未收录时的补漏源（Feeds 有则跳过）
  "luci-app-upnp|pkgs:luci-app-upnp|small:luci-app-upnp"
  "luci-app-ttyd|pkgs:luci-app-ttyd|small:luci-app-ttyd"
  "luci-app-nlbwmon|pkgs:luci-app-nlbwmon|small:luci-app-nlbwmon"
  "luci-app-mwan3|pkgs:luci-app-mwan3|small:luci-app-mwan3"
  "luci-app-turboacc|small:others/lean/luci-app-turboacc|pkgs:luci-app-turboacc"
)

declare -A REQ_PATHS   # 仓库key -> 待稀疏检出的路径列表（空格分隔）
CLONE_OK=()            # 克隆成功的仓库 key

add_path() { # key path
    local key="$1" p="$2"
    if [[ -z "${REQ_PATHS[$key]:-}" ]]; then REQ_PATHS[$key]="$p"; else REQ_PATHS[$key]="${REQ_PATHS[$key]} $p"; fi
}
paths_of() { echo "${REQ_PATHS[$1]:-}"; }

# ------------------- 阶段 0：过滤 Feeds 已提供的包 ----------------------------
step "阶段 0：与 Feeds 成果比对，仅对缺失项走第三方源"
TODO=()
for item in "${PKGS[@]}"; do
    name="${item%%|*}"
    if [[ -f .feeds-available.list ]] && grep -qx "$name" .feeds-available.list; then
        log "Feeds 已提供，跳过第三方拉取：$name"
    else
        TODO+=("$item")
    fi
done
log "需要走第三方源的条目：${#TODO[@]} 个"

# ------------------- 阶段 1：前置校验 + 批量预拉 ------------------------------
step "阶段 1：前置校验（仓库连通性 / 分支存在）"
for key in small pkgs; do
    require_repo "${SRC_REPO[$key]}" "${SRC_BRANCH[$key]}"
done

step "阶段 1：批量预拉（--depth=1 + --filter=blob:none + sparse-checkout 按需检出）"
for item in "${TODO[@]}"; do
    IFS='|' read -r _name c1 c2 <<< "$item"
    for c in "$c1" "$c2"; do
        [[ -z "$c" ]] && continue
        key="${c%%:*}"; p="${c#*:}"
        add_path "$key" "$p"
    done
done
for key in small pkgs; do
    paths=$(paths_of "$key")
    [[ -z "$paths" ]] && continue
    # shellcheck disable=SC2206
    arr=($paths)
    log "预拉 ${SRC_REPO[$key]} @ ${SRC_BRANCH[$key]}  目录数=${#arr[@]}"
    if sparse_clone "${SRC_REPO[$key]}" "${SRC_BRANCH[$key]}" "${SRC_LOCAL[$key]}" "${arr[@]}"; then
        CLONE_OK+=("$key")
        log "预拉完成：$key"
    else
        warn "预拉失败（将在补漏阶段重试）：$key"
    fi
done

# ------------------- 阶段 2：逐个落地 + 后置差分补漏 --------------------------
step "阶段 2：按优先级落地软件包，失败项自动补漏"
FAILED=()
for item in "${TODO[@]}"; do
    IFS='|' read -r name c1 c2 <<< "$item"
    got=0
    for c in "$c1" "$c2"; do
        [[ -z "$c" ]] && continue
        key="${c%%:*}"; p="${c#*:}"
        base="${SRC_LOCAL[$key]}/$p"

        # 补漏：该仓库此前克隆失败 → 仅为此包重试一次
        if [[ ! -d "${SRC_LOCAL[$key]}/.git" ]]; then
            warn "[$name] 源 $key 不可用，尝试单独重试…"
            sparse_clone "${SRC_REPO[$key]}" "${SRC_BRANCH[$key]}" "${SRC_LOCAL[$key]}" "$p" || continue
            CLONE_OK+=("$key")
        fi

        if valid_pkg "$base"; then
            if install_pkg "$base" "custom/$name"; then got=1; break; fi
        else
            # 补漏：目录不在稀疏列表内 → 追加检出后重试
            old=$(paths_of "$key")
            if [[ -n "$old" ]] && ! [[ " $old " == *" $p "* ]]; then
                warn "[$name] 目录不在稀疏列表，追加检出：$key:$p"
                # shellcheck disable=SC2206
                sparse_add "${SRC_LOCAL[$key]}" ${old} "$p" || true
            fi
            if valid_pkg "$base"; then
                if install_pkg "$base" "custom/$name"; then got=1; break; fi
            fi
        fi
    done
    [[ "$got" -eq 1 ]] || FAILED+=("$name|$c1|$c2")
done

# ------------------- 阶段 3：独立维护仓库（OAF / Bandix） ---------------------
step "阶段 3：独立维护仓库兜底拉取"

# 3.1 OpenAppFilter（应用过滤）：三个模块必须齐全
OAF_REPO="https://github.com/destan19/OpenAppFilter"; OAF_BRANCH="master"
require_repo "$OAF_REPO" "$OAF_BRANCH"
OAF_SUBS=("luci-app-oaf" "oaf" "open-app-filter")
if sparse_clone "$OAF_REPO" "$OAF_BRANCH" "$SRC_ROOT/OpenAppFilter" "${OAF_SUBS[@]}"; then
    for sub in "${OAF_SUBS[@]}"; do
        install_pkg "$SRC_ROOT/OpenAppFilter/$sub" "OpenAppFilter/$sub" \
            || die "OpenAppFilter 子模块缺失：$sub（仓库结构变更，请修正脚本中的 OAF_SUBS）"
    done
else
    die "OpenAppFilter 拉取失败：请检查仓库/分支连通性"
fi

# 3.2 Bandix 流量监控（前端 + 后端，仓库根目录即软件包）
require_repo "https://github.com/timsaya/luci-app-bandix"  "main"
require_repo "https://github.com/timsaya/openwrt-bandix"   "main"
shallow_clone "https://github.com/timsaya/luci-app-bandix" "main" "$SRC_ROOT/luci-app-bandix"
install_pkg "$SRC_ROOT/luci-app-bandix" "custom/luci-app-bandix" \
    || die "luci-app-bandix 拉取失败（仓库结构可能已调整为子目录，请修正脚本）"
shallow_clone "https://github.com/timsaya/openwrt-bandix" "main" "$SRC_ROOT/openwrt-bandix"
install_pkg "$SRC_ROOT/openwrt-bandix" "custom/openwrt-bandix" \
    || die "openwrt-bandix（后端服务）拉取失败"

# ------------------- 阶段 4：Turbo ACC（官方脚本，不带 SFE） ------------------
step "阶段 4：Turbo ACC 接入（chenmozhijin 官方脚本，--no-sfe）"
TURBO_REPO="https://github.com/chenmozhijin/turboacc"; TURBO_BRANCH="luci"
require_repo "$TURBO_REPO" "$TURBO_BRANCH"

rm -rf package/turboacc package/custom/luci-app-turboacc
TURBO_OK=0
if curl -fsSL "https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh" -o add_turboacc.sh; then
    # --no-sfe：仅流量分载 + 全锥形 NAT + BBR，不打 613/953 补丁、不引入 Shortcut-FE
    if printf 'y\n' | bash add_turboacc.sh --no-sfe; then TURBO_OK=1; fi
fi

if [[ "$TURBO_OK" -ne 1 ]]; then
    warn "官方脚本接入失败，回退到 small-package 的 others/lean/luci-app-turboacc"
    sparse_add "${SRC_LOCAL[small]}" $(paths_of small) "others/lean/luci-app-turboacc" >/dev/null 2>&1 || \
        sparse_clone "${SRC_REPO[small]}" "${SRC_BRANCH[small]}" "${SRC_LOCAL[small]}" "others/lean/luci-app-turboacc" || true
    install_pkg "${SRC_LOCAL[small]}/others/lean/luci-app-turboacc" "custom/luci-app-turboacc" \
        || die "Turbo ACC 拉取失败：官方脚本与回退源均不可用"
fi

# 依赖补齐：nft-fullcone（全锥形 NAT 必需，唯一允许的外部内核模块）
if ! find package -maxdepth 4 -type d -name "nft-fullcone" | grep -q .; then
    warn "未检测到 nft-fullcone，从 turboacc package 分支补齐"
    sparse_clone "$TURBO_REPO" "package" "$SRC_ROOT/turboacc-pkg" "nft-fullcone" || true
    install_pkg "$SRC_ROOT/turboacc-pkg/nft-fullcone" "custom/nft-fullcone" \
        || die "nft-fullcone 缺失，全锥形 NAT 无法启用"
fi

# 严格移除 Shortcut-FE 相关模块（与 6.12 内核冲突风险高，且本工程明确不需要）
find package -maxdepth 4 -type d -name "shortcut-fe" -print -exec rm -rf {} + | sed 's/^/  移除 SFE 模块：/' || true
rm -f add_turboacc.sh

# ------------------- 阶段 5：结果汇总 ----------------------------------------
step "阶段 5：拉取结果汇总"
if [[ "${#FAILED[@]}" -gt 0 ]]; then
    for f in "${FAILED[@]}"; do
        IFS='|' read -r n a b <<< "$f"
        suggest "$n" "${a/@/}" "${b/@/}"
    done
    die "共 ${#FAILED[@]} 个插件拉取失败，已终止（不进入编译，避免产出缺插件的假成功固件）"
fi
log "全部第三方插件拉取完成，集成路径：package/custom/ 与 package/OpenAppFilter/"
