#!/usr/bin/env bash
# ================================================================
# scripts/feeds_update.sh —— feeds 源更新 + 第三方插件拉取（唯二维护点之一）
#
#【职责】本脚本只干两件事：
#   1. 更新并安装 ImmortalWrt 官方 feeds（luci / packages / routing ...）；
#   2. 按下方来源表拉取第三方插件到 package/thirdparty/。
#
#【拉取规则（严格遵守）】
#   · 优先使用 ImmortalWrt 源码自带软件包（feeds / package 目录）；
#   · 仅当源码中不存在对应软件包时，才从第三方仓库浅克隆「所需的那几个
#     目录」（git clone --depth 1 --filter=blob:none --sparse），
#     绝不整仓拉取，节省编译时长；
#   · FORCE_SOURCES 表里的包无论源码是否自带，一律以第三方版本为准
#     （OAF / TurboAcc / AdGuardHome 三个必须是第三方版本）；
#   · 插件前后端必须成套拉取（DDNSTO、AdGuardHome、OAF、EasyTier），
#     少一个都会导致编译失败，故本脚本对每个包都校验 Makefile 是否存在；
#   · 任何一步拉取失败 → 立刻 exit 1 终止，并打印
#     「缺失包名 / 来源仓库 / 指定分支 / 期望路径 / 处理建议」，
#     便于直接定位是上游改分支名还是改了目录结构。
#
#【用法】在 ImmortalWrt 源码树根目录执行：
#   cd immortalwrt
#   bash scripts/feeds_update.sh
# ================================================================
set -euo pipefail

DEST_DIR="package/thirdparty"

# ----------------------------------------------------------------
# 强制第三方表（优先于源码自带版）
#   格式：包名|仓库地址|分支|仓库内的插件目录
#
#   · luci-app-adguardhome + adguardhome —— ImmortalWrt 自带的是精简 JS 版
#     LuCI，缺少「网页管理端口 / 重定向模式」等配置界面；kenzok8 版是功能
#     完整的 Lua CBI 面板，且核心程序与面板成套，故前后端全部改用 kenzok8。
#   · luci-app-turboacc —— 只有 chenmozhijin 的 luci 分支适配 firewall4
#     (nftables)，ImmortalWrt 源码不含该插件。
#   · OAF —— destan19/OpenAppFilter 一个仓库含三个子包，必须全拉：
#       oaf/             → 包名 kmod-oaf   内核模块（KernelPackage/oaf）
#       open-app-filter/ → 包名 appfilter  用户态服务
#       luci-app-oaf/    → 包名 luci-app-oaf  LuCI 面板（依赖前两者）
#     注意落地目录名一律用「包名」，不要沿用上游目录名 ——
#     目录名与包名不一致会让同名包校验失效，进而出现重复定义。
# ----------------------------------------------------------------
FORCE_SOURCES=(
  "luci-app-adguardhome|https://github.com/kenzok8/openwrt-packages|master|luci-app-adguardhome"
  "adguardhome|https://github.com/kenzok8/openwrt-packages|master|adguardhome"
  "luci-app-turboacc|https://github.com/chenmozhijin/turboacc|luci|luci-app-turboacc"
  "kmod-oaf|https://github.com/destan19/OpenAppFilter|master|oaf"
  "appfilter|https://github.com/destan19/OpenAppFilter|master|open-app-filter"
  "luci-app-oaf|https://github.com/destan19/OpenAppFilter|master|luci-app-oaf"
)

# ----------------------------------------------------------------
# 常规第三方表（源码自带则跳过，缺失才拉）
#   格式同上。分支名均已实测核对（2026-10 确认）：
#     EasyTier/luci-app-easytier  默认 main
#     linkease/nas-packages-luci  默认 main   （luci 前端）
#     linkease/nas-packages       默认 master （后端程序）
#     vernesong/OpenClash         默认 master
#     kenzok8/openwrt-packages    默认 master
# ----------------------------------------------------------------
SOURCES=(
  # ---- 必需：ImmortalWrt 源码不含，必须从第三方拉 ----
  # EasyTier：核心程序 easytier + Web 控制台面板，成套拉取
  "easytier|https://github.com/EasyTier/luci-app-easytier|main|easytier"
  "luci-app-easytier|https://github.com/EasyTier/luci-app-easytier|main|luci-app-easytier"
  # DDNSTO：前端(main) 与 后端(master) 分属两个仓库，缺一不可
  "ddnsto|https://github.com/linkease/nas-packages|master|network/services/ddnsto"
  "luci-app-ddnsto|https://github.com/linkease/nas-packages-luci|main|luci/luci-app-ddnsto"

  # ---- 备用：openwrt-24.10 已自带，正常不会触发；仅在上游移除时兜底 ----
  "luci-app-openclash|https://github.com/vernesong/OpenClash|master|luci-app-openclash"
  "luci-app-smartdns|https://github.com/kenzok8/openwrt-packages|master|luci-app-smartdns"
  "smartdns|https://github.com/kenzok8/openwrt-packages|master|smartdns"
  "luci-theme-argon|https://github.com/kenzok8/openwrt-packages|master|luci-theme-argon"
  "luci-app-argon-config|https://github.com/kenzok8/openwrt-packages|master|luci-app-argon-config"
)

# ================================================================
# 以下为逻辑实现，正常维护插件清单时不需要改动
# ================================================================

# ---------- 依赖检查 ----------
for cmd in git awk find; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "错误: 缺少命令 $cmd，无法继续" >&2
    exit 1
  }
done
[ -f "rules.mk" ] || {
  echo "错误: 当前目录不是 ImmortalWrt 源码树根目录（缺少 rules.mk）" >&2
  echo "用法: cd <ImmortalWrt 源码树> && bash scripts/feeds_update.sh" >&2
  exit 1
}

# ---------- 统一风格的失败终止函数 ----------
# 上游改分支名、改目录结构、仓库被删，都会走到这里，
# 输出必须让人一眼看出「谁缺了 / 从哪来 / 该去哪改」。
fail() {
  local pkg="$1" repo="$2" branch="$3" subdir="$4" reason="$5"
  echo "" >&2
  echo "===================================================================" >&2
  echo "  依赖拉取失败，编译流程立即终止（不会产出不完整的固件）" >&2
  echo "-------------------------------------------------------------------" >&2
  echo "  缺失项    : $pkg" >&2
  echo "  失败原因  : $reason" >&2
  echo "  来源仓库  : $repo" >&2
  echo "  指定分支  : $branch" >&2
  echo "  仓库内路径: $subdir" >&2
  echo "-------------------------------------------------------------------" >&2
  echo "  排查建议：" >&2
  echo "    1. 打开 $repo 确认仓库是否改名/归档；" >&2
  echo "    2. 确认分支 '$branch' 是否还存在（上游可能改成 main/master）；" >&2
  echo "    3. 确认目录 '$subdir' 是否被移动或重命名；" >&2
  echo "    4. 修正 scripts/feeds_update.sh 顶部的来源表后重新触发编译。" >&2
  echo "===================================================================" >&2
  exit 1
}

# ---------- 判断包是否已存在于 ImmortalWrt 源码（package/ 或 feeds/） ----------
pkg_exists() {
  local found
  found=$(find package feeds -maxdepth 4 -type d -name "$1" -print -quit 2>/dev/null || true)
  [ -n "$found" ]
}

# ---------- 移除 feeds 已安装到 package/feeds/ 的同名软链接 ----------
# 只删软链接、不动 feeds 源仓库本身，保证 feeds 缓存完整性。
# 同时清理该插件配套的 i18n 语言包链接：LuCI 生成的 i18n 包名会
# 去掉 'luci-app-' 前缀（如 luci-app-adguardhome → luci-i18n-adguardhome-*），
# 两种命名都清一遍，避免与第三方版本撞名。
remove_feed_links() {
  local pkg=$1 short link
  short="${pkg#luci-app-}"
  find package/feeds -maxdepth 2 \( -name "$pkg" -o -name "luci-i18n-$pkg-*" \
    -o -name "luci-i18n-$short-*" \) -print 2>/dev/null | while read -r link; do
    rm -rf "$link"
    echo "    已移除 feeds 软链接: $link"
  done
}

# ---------- 读取 Makefile 里真实声明的包名 ----------
# 第三方仓库的「目录名」与「包名」经常不一致，destan19/OpenAppFilter
# 就是典型：oaf/ → 包名 kmod-oaf，open-app-filter/ → 包名 appfilter。
# 校验同名包必须按 Makefile 里声明的 PKG_NAME 来，取不到再退回目录名。
declared_pkgname() {
  local mk=$1 fallback=$2 name
  name=$(grep -ohE '^PKG_NAME[[:space:]]*:=[[:space:]]*[^[:space:]]+' "$mk" 2>/dev/null |
    head -n1 | sed -E 's/^PKG_NAME[[:space:]]*:=[[:space:]]*//')
  # 含 $(...) 变量引用的不作数（如 luci.mk 的 PKG_NAME?=$(LUCI_NAME)）
  case "$name" in *'$'*) name="" ;; esac
  [ -n "$name" ] || name="$fallback"
  printf '%s' "$name"
}

# ---------- 清除源码树里重复声明的同名包 ----------
# 同一个包名在 package/ 下出现两份时，kconfig 会生成「自己 select 自己」
# 的依赖，报：
#   error: recursive dependency detected!
#   symbol PACKAGE_xxx is selected by PACKAGE_xxx
# 而 make defconfig 对此的反应是「退出码 0 + 把 .config 里的包选择整体
# 重置为默认值」—— 现象就是「用户清单里的插件全部消失，但仍然能编译成功」。
# FORCE_SOURCES 的语义是「以第三方版本为唯一实现」，所以这里把其它位置
# 的同名实现直接删掉；feeds 源仓库本身不受影响（只删软链接/落地副本）。
purge_duplicate_pkgname() {
  local pkg=$1 keep=$2 mf d
  [ -n "$pkg" ] || return 0
  {
    # 真实目录：ImmortalWrt 源码自带 / 已落地的第三方插件
    grep -rlE "^PKG_NAME[[:space:]]*:=[[:space:]]*${pkg}[[:space:]]*\$" package 2>/dev/null || true
    # feeds 软链接：grep -r 不跟随软链接，必须用通配符显式展开
    grep -lE "^PKG_NAME[[:space:]]*:=[[:space:]]*${pkg}[[:space:]]*\$" \
      package/feeds/*/*/Makefile 2>/dev/null || true
  } | sed '/^$/d' | sort -u | while read -r mf; do
    d=$(dirname "$mf")
    if [ "$d" = "$keep" ]; then
      continue
    fi
    echo "    清除重复的同名包（包名 $pkg）: $d"
    rm -rf "$d"
  done
}

# ---------- 浅克隆单个仓库并稀疏检出指定目录 ----------
# 指定分支不存在时自动回退到仓库默认分支，避免上游改分支名直接炸掉。
clone_repo() {
  local repo=$1 branch=$2 dest=$3 def
  if git clone -q --depth 1 --no-tags --filter=blob:none --sparse \
    -b "$branch" "$repo" "$dest" 2>/dev/null; then
    return 0
  fi
  def=$(git ls-remote --symref "$repo" HEAD 2>/dev/null |
    awk '/^ref:/ { sub(".*refs/heads/", ""); print $1 }' | head -n 1)
  if [ -n "$def" ] && [ "$def" != "$branch" ]; then
    echo "    提示: 分支 '$branch' 不存在，自动回退到默认分支 '$def'"
    git clone -q --depth 1 --no-tags --filter=blob:none --sparse \
      -b "$def" "$repo" "$dest" 2>/dev/null && return 0
  fi
  return 1
}

mkdir -p "$DEST_DIR"

# ================================================================
# 第一步：updates feeds 源并安装全部软件包
# ================================================================
echo "==================================================================="
echo "==> [1/3] 更新 ImmortalWrt feeds 源（feeds update -a）"
echo "==================================================================="
./scripts/feeds update -a

echo ""
echo "==> [1/3] 安装 feeds 全部软件包（feeds install -a）"
./scripts/feeds install -a

# ================================================================
# 第二步：筛选需要拉取的包，按「仓库 + 分支」分组，同一仓库只克隆一次
# ================================================================
echo ""
echo "==================================================================="
echo "==> [2/3] 筛选第三方插件（源码自带优先，缺失才拉）"
echo "==================================================================="

declare -A REPO_PKGS # 键: 仓库|分支   值: 「包名:子目录」空格分隔
declare -A REPO_SUBDIR
declare -A PKG_REPO_REF # 键: 包名  值: 仓库|分支|子目录（出错时报出来）

# 2a. 强制第三方包：先摘掉 feeds 版软链接，再登记克隆
for line in "${FORCE_SOURCES[@]}"; do
  IFS='|' read -r pkg repo branch subdir <<<"$line"
  echo "[强制第三方] $pkg  ←  $repo ($branch) :: $subdir"
  remove_feed_links "$pkg"
  REPO_PKGS["$repo|$branch"]+="$pkg:$subdir "
  PKG_REPO_REF["$pkg"]="$repo|$branch|$subdir"
done

# 2a-2. OAF 三件套的目录名与包名不一致的补漏清理（必须放在这里，
# remove_feed_links 的定义在下方逻辑区）：
#   oaf/             包名是 kmod-oaf
#   open-app-filter/ 包名是 appfilter
# feeds install 生成的软链接按「上游目录名」命名，只按包名删会漏，
# 残留的 feeds 版与第三方版构成「同一个包名两份定义」，
# kconfig 会报 recursive dependency，并把 .config 的包选择整体重置。
for alias in oaf kmod-oaf open-app-filter appfilter luci-app-oaf \
             luci-i18n-oaf-zh-cn luci-i18n-appfilter-zh-cn; do
  remove_feed_links "$alias"
done

# 2b. 常规第三方包：源码已存在则跳过
for line in "${SOURCES[@]}"; do
  IFS='|' read -r pkg repo branch subdir <<<"$line"
  if pkg_exists "$pkg"; then
    echo "[使用源码自带] $pkg  —— 已在 ImmortalWrt 源码/feeds 中，跳过第三方拉取"
  else
    echo "[拉取第三方] $pkg  ←  $repo ($branch) :: $subdir"
    REPO_PKGS["$repo|$branch"]+="$pkg:$subdir "
    PKG_REPO_REF["$pkg"]="$repo|$branch|$subdir"
  fi
done

# ================================================================
# 第三步：逐仓库浅克隆并拷贝所需目录到 package/thirdparty/
# ================================================================
echo ""
echo "==================================================================="
echo "==> [3/3] 浅克隆第三方插件仓库（只检出所需目录）"
echo "==================================================================="

for key in "${!REPO_PKGS[@]}"; do
  IFS='|' read -r repo branch <<<"$key"
  read -r -a entries <<<"${REPO_PKGS[$key]}"

  # 收集该仓库本次要检出的全部子目录
  dirs=()
  for e in "${entries[@]}"; do
    subdir="${e#*:}"
    dirs+=("$subdir")
  done

  echo "==> 克隆 $repo (分支 $branch)"
  tmp="$(mktemp -d)"
  if ! clone_repo "$repo" "$branch" "$tmp/src"; then
    first_pkg="${entries[0]%%:*}"
    fail "$first_pkg（同仓库共 ${#entries[@]} 个包）" "$repo" "$branch" \
      "${dirs[*]}" "git clone 失败：分支不存在或仓库不可访问"
  fi

  ## 稀疏检出所需目录（--no-cone 支持一次指定多个子目录）
  if ! git -C "$tmp/src" sparse-checkout set --no-cone "${dirs[@]}" 2>/dev/null; then
    first_pkg="${entries[0]%%:*}"
    fail "$first_pkg（同仓库共 ${#entries[@]} 个包）" "$repo" "$branch" \
      "${dirs[*]}" "稀疏检出失败：仓库内不存在上述目录"
  fi

  # 逐个拷贝到 package/thirdparty/<包名>
  for e in "${entries[@]}"; do
    pkg="${e%%:*}"
    subdir="${e#*:}"
    rm -rf "$DEST_DIR/$pkg"
    if [ ! -d "$tmp/src/$subdir" ]; then
      fail "$pkg" "$repo" "$branch" "$subdir" "仓库中不存在该目录"
    fi
    cp -a "$tmp/src/$subdir" "$DEST_DIR/$pkg"
    if [ ! -f "$DEST_DIR/$pkg/Makefile" ]; then
      fail "$pkg" "$repo" "$branch" "$subdir" "目录内没有 Makefile，不是有效的 OpenWrt 软件包"
    fi
    echo "    已就位: $DEST_DIR/$pkg"

    # 以落地目录里 Makefile 声明的真实包名为准，清掉源码树中其它同名实现，
    # 保证「一个包名在 package/ 下只有一份定义」。
    # 这是防止 kconfig 报 recursive dependency（自己 select 自己）的
    # 最后一道闸门；报错后 defconfig 会把 .config 的包选择整体重置，
    # 表现为「插件全丢但仍然编译成功」。
    purge_duplicate_pkgname "$(declared_pkgname "$DEST_DIR/$pkg/Makefile" "$pkg")" "$DEST_DIR/$pkg"
  done
  rm -rf "$tmp"
done

# ================================================================
# 收尾：输出本次实际使用的第三方插件清单
# ================================================================
echo ""
echo "==================================================================="
echo "==> 第三方插件处理完成，package/thirdparty/ 内容如下："
echo "==================================================================="
if [ -n "$(ls -A "$DEST_DIR" 2>/dev/null)" ]; then
  for d in "$DEST_DIR"/*/; do
    [ -d "$d" ] || continue
    echo "  - $(basename "$d")"
  done
else
  echo "  （无第三方插件，全部使用 ImmortalWrt 源码自带版本）"
fi
echo ""
echo "==> feeds 更新与第三方插件拉取全部成功"
