#!/usr/bin/env bash
# ================================================================
# scripts/patch-plugins.sh —— 插件编译兼容补丁（唯一维护点）
#
#【这个脚本解决什么问题】
#   第三方插件是活的上游仓库，它会随着自己的发版不断提高对
#   编译环境的要求（最典型的就是 Go 语言版本）。而 ImmortalWrt
#   openwrt-24.10 内置的 Go 工具链是固定的（Go 1.23.12），
#   并且 golang-package.mk 里写死了：
#         GOTOOLCHAIN=local
#   意思是「只能用本机这套 Go，禁止自动下载新工具链」。
#   于是「新插件 + 老工具链」必然编译失败。
#
#   本脚本就是这一层适配器：所有插件编译兼容 / 源码适配问题，
#   全部集中到这里统一处理，以后遇到新的兼容坑，
#   只在本脚本里加一条规则即可，不用动 workflow.yml、不用动 config。
#
#【执行时机】必须紧跟 scripts/feeds_update.sh 之后：
#   1. feeds_update.sh 先把 ImmortalWrt 官方 feeds 与第三方插件就位；
#   2. 本脚本再对就位后的插件做编译兼容处理；
#   3. 之后才允许 make download / make。
#
#【用法】
#   cd immortalwrt
#   bash scripts/patch-plugins.sh
#
#【可选环境变量】
#   ADGUARDHOME_VERSION  强制指定 AdGuardHome 版本（跳过敏捷探测）
#   GITHUB_TOKEN         传入后 GitHub API 限额从 60 次/时提到 5000 次/时
#   PATCH_DRY_RUN=1      只打印将要做的改动，不落盘
# ================================================================
set -euo pipefail

TARGET_DIR="${1:-.}"
DRY_RUN="${PATCH_DRY_RUN:-0}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# ----------------------------------------------------------------
# AdGuardHome 兼容参数
#
#  · AGH_KNOWN_GOOD      实测可用、与 Go 1.23 完全兼容的版本。
#                       它是 ImmortalWrt 24.10 源码树里同样在用的版本
#                       （immortalwrt/packages@openwrt-24.10 的
#                        net/adguardhome 就锁在 0.107.57），
#                        go.mod 声明 go 1.23.6，依赖里 quic-go 只有
#                        v0.49.0，全部落在 Go 1.23 能力范围内。
#  · AGH_PROBE_PAGES     向上探测时最多翻几页 tag（每页 100 个）
#  · AGH_MAX_PROBE       最多探测多少个候选版本，防止无限循环
# ----------------------------------------------------------------
AGH_KNOWN_GOOD="0.107.57"
AGH_PROBE_PAGES=3
AGH_MAX_PROBE=40

DL_DIR_REL="dl"
GOMOD_FIXUP_NAME="wrt-gomod-fixup.sh"
HOOK_NAME="WrtGomodFixup"

# ================================================================
# 通用工具函数
# ================================================================
info() { echo "==> $*"; }
step() { echo "    $*"; }
warn() { echo "!!! $*" >&2; }

# 统一风格的失败终止：任何一处修不了，立刻停，绝不带病编译
fail() {
  echo "" >&2
  echo "===================================================================" >&2
  echo "  插件编译兼容处理失败，编译流程立即终止" >&2
  echo "-------------------------------------------------------------------" >&2
  echo "  处理对象  : $1" >&2
  echo "  失败环节  : $2" >&2
  echo "  详细信息  : $3" >&2
  echo "-------------------------------------------------------------------" >&2
  echo "  排查建议：" >&2
  echo "    1. 打开该插件对应的上游仓库，确认版本/分支/目录是否变化；" >&2
  echo "    2. 确认 ImmortalWrt 内置 Go 工具链版本（见下方日志）；" >&2
  echo "    3. 在 scripts/patch-plugins.sh 顶部的参数表里调整兼容版本，" >&2
  echo "       或设置环境变量 ADGUARDHOME_VERSION 手动指定可用版本；" >&2
  echo "===================================================================" >&2
  exit 1
}

# 版本号比较：ver_gt "a" "b" → a > b 时返回 0（真）
ver_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN{
    n = split(a, A, "."); m = split(b, B, ".");
    k = (n > m ? n : m);
    for (i = 1; i <= k; i++) {
      x = A[i] + 0; y = B[i] + 0;
      if (x > y) exit 0;
      if (x < y) exit 1;
    }
    exit 1;
  }'
}

# 带 token 的 GitHub API 读取（仅在设置了 GITHUB_TOKEN 时带认证头）
gh_api() {
  if [ -n "$GITHUB_TOKEN" ]; then
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" "$1" 2>/dev/null
  else
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 \
      -H "Accept: application/vnd.github+json" "$1" 2>/dev/null
  fi
}

# 定位插件目录（feeds_update.sh 会把第三方插件放到 package/thirdparty/）
find_pkg_dir() {
  find package -maxdepth 3 -type f -name Makefile -path "*/$1/Makefile" -print -quit 2>/dev/null || true
}

# 安全改写 Makefile 里的 VAR:=value（要求该变量恰好出现 1 次）
set_makefile_var() {
  local mk="$1" var="$2" val="$3" cnt
  cnt=$(grep -cE "^${var}:=" "$mk" || true)
  if [ "$cnt" -ne 1 ]; then
    fail "$(basename "$(dirname "$mk")")" "改写 Makefile 变量 $var" \
      "$mk 中 ${var}:= 出现 ${cnt} 次（期望 1 次），不敢盲目改写"
  fi
  sed -i "s|^${var}:=.*$|${var}:=${val}|" "$mk"
}

# 下载文件到 dl/（已存在则复用，天然配合 GitHub Actions 的 dl 缓存）
fetch_to_dl() {
  local url="$1" name="$2" out="$DL_DIR_REL/$2"
  if [ -s "$out" ]; then
    step "dl/$name 已存在，复用缓存（不重复下载）"
    return 0
  fi
  mkdir -p "$DL_DIR_REL"
  step "下载 $name"
  if ! curl -fSL --retry 3 --retry-delay 3 --connect-timeout 30 \
    "$url" -o "$out.part" 2>/dev/null; then
    rm -f "$out.part"
    return 1
  fi
  mv "$out.part" "$out"
  return 0
}

# 读取 tarball 内 go.mod 的 go 指令（用于自校验，不落盘解包）
tarball_go_directive() {
  local tgz="$1"
  tar -xzOf "$tgz" --wildcards '*/go.mod' 2>/dev/null |
    sed -n 's/^go \([0-9][0-9.]*\).*$/\1/p' | head -n1
}

# ================================================================
# 补丁一：go.mod 归一化（通用能力，任何 Go 插件都能复用）
#
# 作用：把「老 Go 工具链读不懂的 go.mod」改写成读得懂的：
#   1. 删除 tool / ignore / godebug 这些新指令
#      （tool 是 Go 1.24 引入，ignore 是 Go 1.25 引入，
#        godebug 是 Go 1.23 引入——1.23 之前都读不懂，
#        报错信息就是 "unknown directive: tool"）
#   2. 把 go 指令夹到工具链支持的上限
#      （go 指令高于本机版本时，GOTOOLCHAIN=local 会直接报
#        "go.mod requires go >= x.y.z"）
#
# 实现方式：往包 Makefile 里注入 Hooks/Prepare/Post。
#   Hooks/Prepare/Post 是 OpenWrt 官方支持的挂钩点，由
#   include/package.mk 在 Build/Prepare 之后调用
#   （见 package.mk: $(foreach hook,$(Hooks/Prepare/Post),...)），
#   而 Build/Prepare 正好是源码解包完成的时刻 —— 此时 go.mod
#   已经躺在 $(PKG_BUILD_DIR) 里，改它最合适。
# ================================================================
write_gomod_fixup_script() {
  local pkgdir="$1" dst="$pkgdir/$GOMOD_FIXUP_NAME"
  cat >"$dst" <<'INNER'
#!/bin/sh
# ================================================================
# 本文件由 scripts/patch-plugins.sh 自动生成，请勿手工编辑！
#
# 用法: wrt-gomod-fixup.sh <源码解包目录> <工具链Go版本>
# 作用: 把源码里的 go.mod 改写成当前 Go 工具链读得懂的形态
# ================================================================
set -e

DIR="$1"
COMPAT_GO="$2"

[ -n "$DIR" ] && [ -d "$DIR" ] || exit 0

GM="$DIR/go.mod"
if [ ! -f "$GM" ]; then
	echo "      [gomod-fixup] $GM 不存在，跳过（不是 Go 包）"
	exit 0
fi

# 版本比较：a > b 时返回 0
ver_gt() {
	awk -v a="$1" -v b="$2" 'BEGIN{
		n = split(a, A, "."); m = split(b, B, ".");
		k = (n > m ? n : m);
		for (i = 1; i <= k; i++) {
			x = A[i] + 0; y = B[i] + 0;
			if (x > y) exit 0;
			if (x < y) exit 1;
		}
		exit 1;
	}'
}

changed=0

# ---- 1. 剥离 tool / ignore / godebug 指令（块形式 + 单行形式） ----
if grep -qE '^(tool|ignore|godebug)([[:space:]]|$)' "$GM"; then
	awk '
		/^(tool|ignore|godebug)[[:space:]]*\($/ { skip = 1; next }
		skip { if ($0 ~ /^\)/) skip = 0; next }
		/^(tool|ignore|godebug)[[:space:]]/ { next }
		{ print }
	' "$GM" > "$GM.wrt-tmp"
	mv "$GM.wrt-tmp" "$GM"
	echo "      [gomod-fixup] 已剥离 tool/ignore/godebug 指令"
	changed=1
fi

# ---- 2. 把 go 指令夹到工具链支持的上限 ----
cur="$(sed -n 's/^go \([0-9][0-9.]*\).*$/\1/p' "$GM" | head -n1)"
if [ -n "$cur" ] && [ -n "$COMPAT_GO" ] && ver_gt "$cur" "$COMPAT_GO"; then
	sed -i "s|^go .*$|go $COMPAT_GO|" "$GM"
	echo "      [gomod-fixup] go 指令 $cur -> $COMPAT_GO"
	changed=1
fi

if [ "$changed" -eq 0 ]; then
	echo "      [gomod-fixup] go.mod 已兼容，无需修改"
fi

exit 0
INNER
  chmod 0755 "$dst"
}

# 往包 Makefile 注入 Hooks/Prepare/Post（幂等）
#   锚点选「BuildPackage 调用行」之前 —— 因为
#   $(eval $(call BuildPackage,...)) 展开时才会去读 Hooks/Prepare/Post，
#   钩子必须定义在它前面才生效。
#   生成到 Makefile 里的内容形如：
#       define WrtGomodFixup
#       	$(SHELL) $(TOPDIR)/package/thirdparty/adguardhome/<脚本> \
#       		"$(PKG_BUILD_DIR)" "1.23.12"
#       endef
#       Hooks/Prepare/Post += WrtGomodFixup
inject_prepare_hook() {
  local pkgdir="$1" hookscript_rel="$2" compat_go="$3"
  local mk="$pkgdir/Makefile"

  if grep -q "WRT-PATCH-BEGIN" "$mk"; then
    step "Makefile 已注入过 Prepare 钩子，跳过"
    return 0
  fi

  if ! grep -qE '^\$\(eval \$\(call BuildPackage,' "$mk"; then
    fail "$(basename "$pkgdir")" "注入 Prepare 钩子" \
      "$mk 中没有找到 \$(eval \$(call BuildPackage,...)) 调用行，无法确定注入位置"
  fi

  if [ "$DRY_RUN" = "1" ]; then
    step "[DRY-RUN] 将在 $mk 中注入 Hooks/Prepare/Post（兼容上限 go$compat_go）"
    return 0
  fi

  if ! awk -v hookname="$HOOK_NAME" \
    -v hookscript="$hookscript_rel" \
    -v compatgo="$compat_go" '
      BEGIN { done = 0 }
      !done && /^\$\(eval \$\(call BuildPackage,/ {
        print "# --- WRT-PATCH-BEGIN（由 scripts/patch-plugins.sh 注入，勿手工改动）---"
        print "define " hookname
        print "\t$(SHELL) $(TOPDIR)/" hookscript " \"$(PKG_BUILD_DIR)\" \"" compatgo "\""
        print "endef"
        print "Hooks/Prepare/Post += " hookname
        print "# --- WRT-PATCH-END ---"
        done = 1
      }
      { print }
      END { if (!done) exit 3 }
    ' "$mk" >"$mk.wrt-tmp"; then
    rm -f "$mk.wrt-tmp"
    fail "$(basename "$pkgdir")" "注入 Prepare 钩子" \
      "写入 $mk 失败（未能定位 BuildPackage 调用行）"
  fi
  mv "$mk.wrt-tmp" "$mk"
}

# ================================================================
# 补丁二：AdGuardHome 的 Go 工具链适配
#
#【为什么不能只删 go.mod 里的指令就完事】
#   AdGuardHome 0.107.79 的 go.mod 很"新"：
#       go 1.26.6
#       ignore ( ... )
#       tool ( ... )
#   但即使把这三处都改掉，仍然编译不过 —— 因为它的**依赖**也提高了门槛：
#       github.com/quic-go/quic-go v0.60.0  →  要求 go >= 1.25.0
#       golang.org/x/net v0.57.0            →  要求 go >= 1.24.0
#   依赖模块的 go.mod 由 module cache 提供，我们不改（也改不动），
#   GOTOOLCHAIN=local 下 Go 1.23 只会直接报错：
#       go: golang.org/x/net@v0.57.0 requires go >= 1.24.0
#           (running go 1.23.12; GOTOOLCHAIN=local)
#
#【所以正确的解法：把版本对齐到工具链能力范围内】
#   本脚本自动向上探测，取「当前 Go 工具链能编译的最新稳定版」，
#   并把 PKG_VERSION / PKG_HASH / FRONTEND_HASH 三处一起改到位。
#   哈希不是写死的：直接下载对应文件算出来，同时放进 dl/ 预热缓存，
#   这样既不会因为上游重打包而哈希失效，又省掉一次重复下载。
#
#【两层保险】
#   第一层：版本对齐（上面这套，解决依赖门槛问题）
#   第二层：go.mod 归一化（补丁一，解决残留的新指令问题）
#   两层都做过之后，还会从 tarball 里把 go.mod 读出来复核一遍。
# ================================================================
fix_adguardhome() {
  local pkgdir mk toolchain_full toolchain_mm
  pkgdir="$(find_pkg_dir adguardhome)"
  if [ -z "$pkgdir" ]; then
    fail "adguardhome" "定位插件目录" \
      "在 package/ 下找不到 adguardhome/Makefile（feeds_update.sh 是否已成功执行？）"
  fi
  # find_pkg_dir 返回的是 Makefile 的路径，这里拆成「目录」与「Makefile」
  mk="$pkgdir"
  case "$pkgdir" in
  */Makefile) pkgdir="${pkgdir%/Makefile}" ;;
  esac

  info "[1/4] AdGuardHome：读取当前 Go 工具链版本"
  toolchain_full="$(get_go_toolchain_version)" ||
    fail "adguardhome" "读取 Go 工具链版本" "无法从 feeds 里解析出 Go 版本，请确认 feeds_update.sh 已执行"
  toolchain_mm="${toolchain_full%.*}"
  step "ImmortalWrt 内置 Go 工具链: go$toolchain_full（语言版本上限 $toolchain_mm）"

  local agh_repo agh_api
  agh_repo="AdguardTeam/AdGuardHome"
  agh_api="https://api.github.com/repos/$agh_repo"

  # ------------------------------------------------------------
  # 第一步：确定可用版本
  # ------------------------------------------------------------
  local chosen=""
  if [ -n "${ADGUARDHOME_VERSION:-}" ]; then
    info "[2/4] AdGuardHome：使用环境变量指定的版本 $ADGUARDHOME_VERSION"
    chosen="$ADGUARDHOME_VERSION"
  else
    info "[2/4] AdGuardHome：探测与 Go $toolchain_full 兼容的最新稳定版"
    chosen="$(probe_agh_version "$agh_api" "$toolchain_full" "$agh_repo")"
  fi

  # 版本号合法性校验：探测环节任何异常（API 限额、网络抖动）都不允许
  # 把一个脏值写进 Makefile，一律回退到实测可用版本。
  chosen="$(printf '%s' "$chosen" | head -n1 | tr -d '[:space:]')"
  case "$chosen" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *)
    if [ -n "$chosen" ]; then
      warn "探测结果 '$chosen' 不是合法版本号，忽略"
    fi
    warn "回退到实测可用版本 $AGH_KNOWN_GOOD"
    chosen="$AGH_KNOWN_GOOD"
    ;;
  esac
  step "选定版本: $chosen"

  # ------------------------------------------------------------
  # 第二步：下载并计算哈希（顺带预热 dl/ 缓存）
  # ------------------------------------------------------------
  info "[3/4] AdGuardHome：下载源码与前端并计算哈希（同时预热 dl/ 缓存）"
  local src_name fe_name src_file
  src_name="adguardhome-${chosen}.tar.gz"
  fe_name="adguardhome-frontend-${chosen}.tar.gz"
  src_file="$DL_DIR_REL/$src_name"

  if ! fetch_to_dl "https://codeload.github.com/$agh_repo/tar.gz/v${chosen}" "$src_name"; then
    fail "adguardhome $chosen" "下载源码包" \
      "无法下载 https://codeload.github.com/$agh_repo/tar.gz/v${chosen}（版本可能不存在）"
  fi
  if ! fetch_to_dl "https://github.com/$agh_repo/releases/download/v${chosen}/AdGuardHome_frontend.tar.gz" "$fe_name"; then
    fail "adguardhome $chosen" "下载前端资源包" \
      "无法下载 releases/download/v${chosen}/AdGuardHome_frontend.tar.gz（该版本可能没有发布前端资源）"
  fi

  # 自校验：源码包内 go.mod 的 go 指令必须落在工具链能力内
  local pkg_go
  pkg_go="$(tarball_go_directive "$src_file")"
  if [ -z "$pkg_go" ]; then
    warn "无法从 $src_name 读取 go.mod 的 go 指令，跳过版本复核"
  elif ver_gt "$pkg_go" "$toolchain_full"; then
    fail "adguardhome $chosen" "版本复核" \
      "该版本 go.mod 要求 go $pkg_go，高于内置工具链 go $toolchain_full，编译必然失败"
  else
    step "版本复核通过: go.mod 要求 go $pkg_go ≤ 工具链 go $toolchain_full"
  fi

  local src_hash fe_hash
  src_hash="$(sha256sum "$src_file" | awk '{print $1}')"
  fe_hash="$(sha256sum "$DL_DIR_REL/$fe_name" | awk '{print $1}')"
  step "PKG_HASH      = $src_hash"
  step "FRONTEND_HASH = $fe_hash"

  # ------------------------------------------------------------
  # 第三步：改写 Makefile 的版本与哈希
  # ------------------------------------------------------------
  info "[4/4] AdGuardHome：改写 Makefile（PKG_VERSION / PKG_HASH / FRONTEND_HASH）"
  if [ "$DRY_RUN" = "1" ]; then
    step "[DRY-RUN] 将把 $mk 改为 PKG_VERSION:=${chosen}"
    step "[DRY-RUN] 将注入 Prepare 钩子（go.mod 归一化）"
    return 0
  fi

  set_makefile_var "$mk" "PKG_VERSION" "$chosen"
  set_makefile_var "$mk" "PKG_HASH" "$src_hash"
  # FRONTEND_HASH 只在本包确实带前端下载宏时才改
  if grep -qE '^FRONTEND_HASH:=' "$mk"; then
    set_makefile_var "$mk" "FRONTEND_HASH" "$fe_hash"
  else
    warn "$mk 中没有 FRONTEND_HASH:= ，跳过（该版本可能不再单独下载前端）"
  fi
  step "已改写: PKG_VERSION=$chosen"

  # ------------------------------------------------------------
  # 第四步：注入 go.mod 归一化钩子（第二层保险）
  # ------------------------------------------------------------
  write_gomod_fixup_script "$pkgdir"
  # 钩子里写的是相对源码树根（$(TOPDIR)）的路径，
  # 用实际定位到的目录，避免 feeds_update.sh 改了放置位置后失配
  inject_prepare_hook "$pkgdir" "$pkgdir/$GOMOD_FIXUP_NAME" "$toolchain_full"
  step "已注入 Prepare 钩子: $HOOK_NAME（go.mod 归一化，兼容上限 go$toolchain_full）"
}

# 从 feeds 的 golang 包 Makefile 解析工具链版本
get_go_toolchain_version() {
  local gmk mm patch
  gmk="$(find feeds -maxdepth 5 -type f -path '*/lang/golang/golang/Makefile' -print -quit 2>/dev/null || true)"
  if [ -z "$gmk" ]; then
    gmk="$(find feeds -maxdepth 6 -type f -path '*golang*/Makefile' -print -quit 2>/dev/null || true)"
  fi
  [ -n "$gmk" ] || return 1

  mm="$(sed -n 's/^GO_VERSION_MAJOR_MINOR:=\([0-9.]*\).*$/\1/p' "$gmk" | head -n1)"
  patch="$(sed -n 's/^GO_VERSION_PATCH:=\([0-9.]*\).*$/\1/p' "$gmk" | head -n1)"
  [ -n "$mm" ] || return 1
  if [ -n "$patch" ]; then
    echo "${mm}.${patch}"
  else
    echo "$mm"
  fi
}

# 探测「与给定 Go 工具链兼容的最新稳定版 AdGuardHome」
# 【重要】本函数会被 $(...) 捕获，所以：
#   只有「最终版本号」允许写到 stdout，
#   所有诊断信息一律写到 stderr，否则会污染返回值。
probe_agh_version() {
  local api="$1" toolchain="$2" repo="$3"
  local versions="" page json

  # 1) 拉取 tag 列表（多页），只保留形如 x.y.z 的稳定版
  for page in $(seq 1 "$AGH_PROBE_PAGES"); do
    json="$(gh_api "$api/tags?per_page=100&page=$page")" || break
    [ -n "$json" ] || break
    versions="$versions
$(printf '%s' "$json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(d, list) or not d:
    sys.exit(0)
for t in d:
    name = (t.get('name') or '').strip()
    if name.startswith('v'):
        name = name[1:]
    parts = name.split('.')
    if len(parts) != 3:
        continue
    if not all(p.isdigit() for p in parts):
        continue
    print(name)
" 2>/dev/null || true)"
  done

  versions="$(printf '%s' "$versions" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
    sort -t. -k1,1nr -k2,2nr -k3,3nr | awk '!seen[$0]++' || true)"
  if [ -z "$versions" ]; then
    warn "GitHub tag 列表获取失败或为空（可能触发 API 限额）"
    return 0
  fi
  step "候选稳定版本共 $(printf '%s\n' "$versions" | grep -c .) 个，开始逐个核对 go.mod" >&2

  # 2) 从新到旧逐个读 go.mod，第一个满足「go 指令 ≤ 工具链」的即可用
  local n=0 ver gomod gorq
  while IFS= read -r ver; do
    [ -n "$ver" ] || continue
    n=$((n + 1))
    [ "$n" -gt "$AGH_MAX_PROBE" ] && {
      warn "已探测 $AGH_MAX_PROBE 个候选仍未命中，停止探测"
      break
    }
    gomod="$(curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 20 \
      "https://raw.githubusercontent.com/$repo/v${ver}/go.mod" 2>/dev/null || true)"
    if [ -z "$gomod" ]; then
      step "  v$ver  go.mod 读取失败，跳过" >&2
      continue
    fi
    gorq="$(printf '%s\n' "$gomod" | sed -n 's/^go \([0-9][0-9.]*\).*$/\1/p' | head -n1)"
    if [ -z "$gorq" ]; then
      step "  v$ver  go.mod 无 go 指令，跳过" >&2
      continue
    fi
    if ver_gt "$gorq" "$toolchain"; then
      step "  v$ver  要求 go $gorq > $toolchain  → 不兼容，继续向下" >&2
      continue
    fi
    step "  v$ver  要求 go $gorq ≤ $toolchain  → 命中" >&2
    echo "$ver"
    return 0
  done <<<"$versions"

  return 0
}

# ================================================================
# 主流程
# ================================================================
cd "$TARGET_DIR"

# ---------- 前置检查 ----------
for cmd in git awk sed find curl sha256sum python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "错误: 缺少命令 $cmd，无法继续" >&2
    exit 1
  }
done

[ -f "rules.mk" ] || {
  echo "错误: 当前目录不是 ImmortalWrt 源码树根目录（缺少 rules.mk）" >&2
  echo "用法: cd <ImmortalWrt 源码树> && bash scripts/patch-plugins.sh" >&2
  exit 1
}

[ -d "feeds" ] || {
  echo "错误: feeds 目录不存在，请先执行 scripts/feeds_update.sh" >&2
  exit 1
}

echo "==================================================================="
echo "==> 插件编译兼容补丁开始（scripts/patch-plugins.sh）"
echo "==================================================================="
if [ "$DRY_RUN" = "1" ]; then
  warn "DRY-RUN 模式：只打印改动，不落盘"
fi

# ----------------------------------------------------------------
# 逐个执行补丁。以后新增插件兼容修复，只需在这里加一行。
# ----------------------------------------------------------------
fix_adguardhome

echo ""
echo "==================================================================="
echo "==> 插件编译兼容补丁全部完成"
echo "==================================================================="
echo "  · adguardhome —— 已对齐到与内置 Go 工具链兼容的版本，"
echo "                   并注入 go.mod 归一化钩子"
echo ""
echo "  如后续插件出现新的编译兼容问题，统一在 scripts/patch-plugins.sh"
echo "  里新增一条 fix_xxx() 规则，并在上面的主流程中调用它即可。"
