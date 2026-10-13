#!/bin/bash
#
# diy-part2.sh —— feeds 安装完成后的自定义脚本
# 执行时机：./scripts/feeds install -a 之后，make defconfig 之前
# 作用：仅当 ImmortalWrt 源码中不存在对应软件包时，
#       才从第三方仓库"浅克隆所需的插件目录"（不完整拉取整个仓库，节省耗时）
#

set -e

# ---------------------------------------------------------------------------
# 工具函数：从指定第三方仓库浅克隆并复制所需软件包目录到 package/ 下
# 参数：copy_pkg_dirs <仓库地址> <分支> <包目录名1> [包目录名2 ...]
# 实现：--depth 1 仅拉取最新一次提交；find 兼容不同仓库的目录层级
# ---------------------------------------------------------------------------
copy_pkg_dirs() {
  local repo="$1"
  local branch="$2"
  shift 2
  local tmp
  tmp="$(mktemp -d)"

  echo "[diy-part2] 克隆 $repo（分支: $branch），目标目录: $*"
  if ! git clone -q --depth 1 --branch "$branch" "$repo" "$tmp"; then
    echo "[diy-part2] 警告: 克隆失败 $repo，跳过"
    rm -rf "$tmp"
    return 0
  fi

  local name src
  for name in "$@"; do
    src="$(find "$tmp" -maxdepth 4 -type d -name "$name" | head -n 1)"
    if [ -n "$src" ]; then
      rm -rf "package/$name"
      cp -rf "$src" "package/$name"
      echo "[diy-part2] 已安装第三方包: package/$name"
    else
      echo "[diy-part2] 警告: $repo 中未找到目录 $name，已跳过"
    fi
  done
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# 工具函数：从 kenzok8/openwrt-packages 按需检出单个插件目录
# 说明：该仓库体积较大，必须使用 sparse-checkout 仅检出目标目录
# ---------------------------------------------------------------------------
clone_kenzok8() {
  local pkg_dir="$1"
  local tmp
  tmp="$(mktemp -d)"
  if ! git clone -q --depth 1 --filter=blob:none --sparse https://github.com/kenzok8/openwrt-packages "$tmp"; then
    echo "[diy-part2] 警告: 克隆 kenzok8 仓库失败，跳过 $pkg_dir"
    rm -rf "$tmp"
    return 0
  fi
  git -C "$tmp" sparse-checkout set "$pkg_dir"
  if [ -d "$tmp/$pkg_dir" ]; then
    rm -rf "package/$pkg_dir"
    cp -rf "$tmp/$pkg_dir" "package/$pkg_dir"
    echo "[diy-part2] 已从 kenzok8 仓库安装: package/$pkg_dir"
  else
    echo "[diy-part2] 警告: kenzok8 仓库中不存在目录 $pkg_dir，跳过"
  fi
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# 1. AdGuardHome —— Luci 界面使用 kenzok8 仓库版本（支持显示 Web UI 端口）
#    后端 adguardhome 程序由 ImmortalWrt 官方 packages feed 提供，无需第三方
#    先删除 feeds 中可能存在的同名包，避免包名冲突
# ---------------------------------------------------------------------------
rm -rf feeds/luci/applications/luci-app-adguardhome
rm -rf package/feeds/luci/luci-app-adguardhome
clone_kenzok8 luci-app-adguardhome

# ---------------------------------------------------------------------------
# 2. DDNSTO —— 远程控制（前端与后端必须同时拉取，缺一不可）
#    Luci 前端：linkease/nas-packages-luci（main 分支）
#    后端程序：linkease/nas-packages（master 分支）
# ---------------------------------------------------------------------------
rm -rf feeds/luci/applications/luci-app-ddnsto
rm -rf package/feeds/luci/luci-app-ddnsto
copy_pkg_dirs https://github.com/linkease/nas-packages-luci main luci-app-ddnsto
copy_pkg_dirs https://github.com/linkease/nas-packages master ddnsto

# ---------------------------------------------------------------------------
# 3. OAF 应用过滤 —— luci-app-oaf（界面）+ open-app-filter（kmod-oaf 内核模块）
# ---------------------------------------------------------------------------
copy_pkg_dirs https://github.com/destan19/OpenAppFilter master luci-app-oaf open-app-filter

# ---------------------------------------------------------------------------
# 4. EasyTier —— 内网穿透（luci-app-easytier 界面 + easytier 后端）
#    优先使用 ImmortalWrt 源码自带的 easytier；源码不存在时才从官方插件仓库拉取
# ---------------------------------------------------------------------------
if ! find feeds package -maxdepth 4 -type d -name easytier 2>/dev/null | grep -q .; then
  copy_pkg_dirs https://github.com/EasyTier/luci-app-easytier main luci-app-easytier easytier
  # 兜底：若 EasyTier 仓库未包含 easytier 后端目录，再从 kenzok8 仓库检出
  if ! find package -maxdepth 1 -type d -name easytier 2>/dev/null | grep -q .; then
    clone_kenzok8 easytier
  fi
else
  echo "[diy-part2] 检测到源码已自带 easytier，优先使用源码版本"
fi

# ---------------------------------------------------------------------------
# 5. argon-config 主题配置器兜底：源码自带则跳过，否则从官方主题仓库检出
# ---------------------------------------------------------------------------
if ! find feeds/luci/applications -maxdepth 1 -type d -name luci-app-argon-config 2>/dev/null | grep -q .; then
  copy_pkg_dirs https://github.com/jerrykuku/luci-theme-argon master luci-app-argon-config
else
  echo "[diy-part2] 源码已自带 luci-app-argon-config，跳过第三方拉取"
fi

# ---------------------------------------------------------------------------
# 6. 其余插件（SmartDNS / Turbo ACC / Mwan3 / nlbwmon / Argon 主题 /
#    OpenClash 等）ImmortalWrt 源码或官方 feeds 均已自带，按优先级规则不再拉取
# ---------------------------------------------------------------------------

echo "[diy-part2] 全部第三方软件包处理完成"
