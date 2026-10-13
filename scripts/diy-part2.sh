#!/bin/bash
#
# diy-part2.sh —— feeds 安装完成后的自定义脚本（修正版）
# 执行时机：./scripts/feeds install -a 之后，make defconfig 之前
#
# 【本次修正】
#   1.（致命）函数定义补上圆括号，修复 "command not found" 导致步骤 6 失败
#   2. 指定分支克隆失败时自动回退仓库默认分支，避免上游分支改名导致中断
#   3. luci-app-argon-config 兜底仓库改为 kenzok8（jerrykuku 主题仓库内无此目录）
#

set -e

# ---------------------------------------------------------------------------
# 工具函数：从第三方仓库浅克隆并复制所需软件包目录到 package/ 下
# 用法：copy_pkg_dirs <仓库地址> <分支> <包目录名1> [包目录名2 ...]
# ---------------------------------------------------------------------------
copy_pkg_dirs() {
    local repo="$1"
    local branch="$2"
    shift 2
    local tmp
    tmp="$(mktemp -d)"

    echo "[diy-part2] 克隆 ${repo}（分支: ${branch}），目标目录: $*"
    # 先按指定分支浅克隆；分支不存在则回退默认分支
    if ! git clone -q --depth 1 --branch "$branch" "$repo" "$tmp" 2>/dev/null; then
        echo "[diy-part2] 分支 ${branch} 不存在，回退默认分支重试..."
        if ! git clone -q --depth 1 "$repo" "$tmp"; then
            echo "[diy-part2] 警告: 克隆失败 ${repo}，跳过"
            rm -rf "$tmp"
            return 0
        fi
    fi

    local name src
    for name in "$@"; do
        # 按目录名定位包目录（兼容仓库的多级目录结构）
        src="$(find "$tmp" -maxdepth 4 -type d -name "$name" | head -n 1)"
        if [ -n "$src" ]; then
            rm -rf "package/$name"
            cp -rf "$src" "package/$name"
            echo "[diy-part2] 已安装第三方包: package/$name"
        else
            echo "[diy-part2] 警告: ${repo} 中未找到目录 ${name}，已跳过"
        fi
    done
    rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# 工具函数：从 kenzok8/openwrt-packages 稀疏检出单个插件目录
# 该仓库体积大，必须用 sparse-checkout 只取目标目录，不整仓拉取
# ---------------------------------------------------------------------------
clone_kenzok8() {
    local pkg_dir="$1"
    local tmp
    tmp="$(mktemp -d)"
    if ! git clone -q --depth 1 --filter=blob:none --sparse \
        https://github.com/kenzok8/openwrt-packages "$tmp"; then
        echo "[diy-part2] 警告: 克隆 kenzok8 仓库失败，跳过 ${pkg_dir}"
        rm -rf "$tmp"
        return 0
    fi
    git -C "$tmp" sparse-checkout set "$pkg_dir"
    if [ -d "$tmp/$pkg_dir" ]; then
        rm -rf "package/$pkg_dir"
        cp -rf "$tmp/$pkg_dir" "package/$pkg_dir"
        echo "[diy-part2] 已从 kenzok8 仓库安装: package/$pkg_dir"
    else
        echo "[diy-part2] 警告: kenzok8 仓库中不存在目录 ${pkg_dir}，跳过"
    fi
    rm -rf "$tmp"
}

# ====================== 插件拉取规则（优先源码自带） ======================

# 1. AdGuardHome 的 LuCI 界面 —— 使用 kenzok8 版本（可显示 Web UI 端口）
#    后端 adguardhome 程序由官方 packages feed 提供，无需第三方拉取
#    先删除 feeds 自带的同名包，避免包名冲突
rm -rf feeds/luci/applications/luci-app-adguardhome
rm -rf package/feeds/luci/luci-app-adguardhome
clone_kenzok8 luci-app-adguardhome

# 2. DDNSTO —— 前端 luci 界面 + 后端 ddnsto 程序必须同时拉取，缺一不可
rm -rf feeds/luci/applications/luci-app-ddnsto
rm -rf package/feeds/luci/luci-app-ddnsto
copy_pkg_dirs https://github.com/linkease/nas-packages-luci main luci-app-ddnsto
copy_pkg_dirs https://github.com/linkease/nas-packages master ddnsto

# 3. OAF 应用过滤 —— luci-app-oaf（界面）+ open-app-filter（kmod-oaf 内核模块）
copy_pkg_dirs https://github.com/destan19/OpenAppFilter master luci-app-oaf open-app-filter

# 4. EasyTier —— 源码自带则优先使用；否则从官方插件仓库拉取，再兜底 kenzok8
if ! find feeds package -maxdepth 4 -type d -name easytier 2>/dev/null | grep -q .; then
    copy_pkg_dirs https://github.com/EasyTier/luci-app-easytier main luci-app-easytier easytier
    if ! find package -maxdepth 1 -type d -name easytier 2>/dev/null | grep -q .; then
        clone_kenzok8 easytier
    fi
else
    echo "[diy-part2] 检测到源码已自带 easytier，优先使用源码版本"
fi

# 5. luci-app-argon-config 主题配置器 —— 源码自带则跳过，否则从 kenzok8 检出
if ! find feeds/luci/applications -maxdepth 1 -type d -name 'luci-app-argon-config' 2>/dev/null | grep -q .; then
    clone_kenzok8 luci-app-argon-config
else
    echo "[diy-part2] 源码已自带 luci-app-argon-config，跳过第三方拉取"
fi

# 6. 其余插件（SmartDNS / Turbo ACC / Mwan3 / nlbwmon / Argon 主题 / OpenClash）
#    ImmortalWrt 源码或官方 feeds 均已自带，按优先级规则不再拉取

echo "[diy-part2] 全部第三方软件包处理完成"