#!/usr/bin/env bash
# ==============================================================================
# 步骤一：写入 Feeds 源 → 批量更新 → 批量安装 → 扫描可用包清单
# 策略：优先官方/大雕 Feeds 批量拉取，只把「Feeds 里没有的」交给第三方源补漏
# ==============================================================================
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
enter_source

step "写入 feeds.conf（固定大雕软件源与分支）"
cat > feeds.conf.default <<'EOF'
# 大雕 LEDE 配套软件源（分支由本工程固定，勿随意改动）
src-git packages https://github.com/coolsnowwolf/packages.git;master
src-git luci https://github.com/coolsnowwolf/luci.git;openwrt-25.12
src-git routing https://github.com/coolsnowwolf/routing.git;master
EOF
cat feeds.conf.default

step "前置校验：Feeds 仓库连通性与分支存在性"
require_repo "https://github.com/coolsnowwolf/packages.git" "master"
require_repo "https://github.com/coolsnowwolf/luci.git"      "openwrt-25.12"
require_repo "https://github.com/coolsnowwolf/routing.git"   "master"

step "批量更新 Feeds（失败立即终止，输出分支/网络定位信息）"
./scripts/feeds clean
if ! ./scripts/feeds update -a; then
    die "Feeds 更新失败：请检查上方输出中具体是哪个源报 'fatal:'，
  常见原因：分支名不存在、GitHub 临时限流、源码树不干净。修复后重新手动触发工作流。"
fi

step "批量安装 Feeds 中所有软件包定义"
./scripts/feeds install -a

step "扫描 Feeds 成果，生成可用包清单（供第三方补漏判断）"
{
    ./scripts/feeds list 2>/dev/null | awk '{print $1}'
    find package/feeds -maxdepth 2 -mindepth 2 -type d -printf '%f\n' 2>/dev/null
} | sort -u > .feeds-available.list

COUNT=$(wc -l < .feeds-available.list)
[[ "$COUNT" -gt 0 ]] || die "Feeds 可用包清单为空，说明 feeds install 未生效（分支异常或源内容为空）"
log "Feeds 可用软件包数量：${COUNT}（清单已写入 .feeds-available.list）"

# 快速自查：把用户点名的、期望由 Feeds 提供的包打印出来，便于排查缺失
for p in luci-app-upnp miniupnpd luci-app-ttyd ttyd luci-app-nlbwmon nlbwmon \
         luci-app-mwan3 mwan3 luci-app-smartdns smartdns; do
    if grep -qx "$p" .feeds-available.list; then
        log "Feeds 已提供：$p"
    else
        warn "Feeds 未提供：$p —— 将交由第三方源补漏"
    fi
done
