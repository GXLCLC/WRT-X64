#!/bin/bash
# ============================================================
# 第三方插件拉取脚本
# 拉取规则：
#   1. 优先使用 ImmortalWrt 源码及官方 feeds 自带的软件包
#   2. 仅当本地不存在对应包时，才从第三方仓库拉取
#   3. 使用稀疏检出，只拉取所需子目录，不完整克隆整个仓库，
#      节省下载时间与磁盘空间
# ============================================================
set -u

# 第三方包定义表，格式：
#   包目录名|仓库地址|分支(留空=仓库默认分支)|仓库内子目录(留空=整仓库即一个包)
THIRD_PARTY_PACKAGES=(
  # ---- kenzok8 / openwrt-packages ----
  "smartdns|https://github.com/kenzok8/openwrt-packages|master|smartdns"
  "luci-app-smartdns|https://github.com/kenzok8/openwrt-packages|master|luci-app-smartdns"
  "luci-app-openclash|https://github.com/kenzok8/openwrt-packages|master|luci-app-openclash"
  "luci-app-turboacc|https://github.com/kenzok8/openwrt-packages|master|luci-app-turboacc"
  "luci-app-argon-config|https://github.com/kenzok8/openwrt-packages|master|luci-app-argon-config"
  "luci-app-oaf|https://github.com/kenzok8/openwrt-packages|master|luci-app-oaf"
  "oaf|https://github.com/kenzok8/openwrt-packages|master|oaf"
  "luci-app-adguardhome|https://github.com/kenzok8/openwrt-packages|master|luci-app-adguardhome"
  "adguardhome|https://github.com/kenzok8/openwrt-packages|master|adguardhome"
  "easytier|https://github.com/kenzok8/openwrt-packages|master|easytier"
  # ---- DDNSTO：luci 前端 + 后端程序，必须双仓库同时拉取 ----
  "luci-app-ddnsto|https://github.com/linkease/nas-packages-luci|main|luci-app-ddnsto"
  "ddnsto|https://github.com/linkease/nas-packages|master|ddnsto"
  # ---- EasyTier：整个仓库即一个软件包，浅克隆整仓 ----
  "luci-app-easytier|https://github.com/EasyTier/luci-app-easytier||"
)

# 检测包是否已存在于源码自带目录或 feeds 安装目录（package/feeds/*/*）
package_exists() {
    find package -maxdepth 3 -type d -name "$1" 2>/dev/null | grep -q .
}

# 拉取单个第三方包到 package/ 目录
fetch_package() {
    local name="$1" url="$2" branch="$3" subdir="$4"
    local tmpdir="/tmp/third_party/${name}"
    local branch_opt=()
    # 未指定分支时使用仓库默认分支
    [ -n "${branch}" ] && branch_opt=(-b "${branch}")

    rm -rf "${tmpdir}" && mkdir -p /tmp/third_party

    if [ -n "${subdir}" ]; then
        # 稀疏检出：--filter=blob:none 不下载无关文件，--sparse 仅检出仓库根
        git clone --depth=1 --filter=blob:none --sparse \
            ${branch_opt[@]+"${branch_opt[@]}"} "${url}" "${tmpdir}" || return 1
        # 设置稀疏检出目录，只下载该子目录的文件
        ( cd "${tmpdir}" && git sparse-checkout set "${subdir}" ) || return 1
        [ -d "${tmpdir}/${subdir}" ] || {
            echo "    仓库中不存在子目录 ${subdir}"; return 1; }
        rm -rf "package/${name}"
        cp -r "${tmpdir}/${subdir}" "package/${name}"
    else
        # 整个仓库即为一个软件包
        git clone --depth=1 ${branch_opt[@]+"${branch_opt[@]}"} \
            "${url}" "${tmpdir}" || return 1
        if [ -f "${tmpdir}/Makefile" ]; then
            # 仓库根目录就是软件包，直接放入 package/
            rm -rf "package/${name}"
            cp -r "${tmpdir}" "package/${name}"
        else
            # 仓库为多包集合：将其中每个含 Makefile 的子目录平铺到 package/
            local d basename_
            for d in "${tmpdir}"/*/; do
                [ -f "${d}Makefile" ] || continue
                basename_="$(basename "${d}")"
                rm -rf "package/${basename_}"
                cp -r "${d}" "package/${basename_}"
            done
        fi
    fi
    rm -rf "${tmpdir}"
    return 0
}

# ---------------- 主流程 ----------------
FAILED=()
for entry in "${THIRD_PARTY_PACKAGES[@]}"; do
    # 按 | 拆分定义表字段
    IFS='|' read -r name url branch subdir <<< "${entry}"
    if package_exists "${name}"; then
        # 规则 1：ImmortalWrt 源码自带，无需第三方拉取
        echo "[跳过] ${name} ：ImmortalWrt 源码/feeds 已自带，直接使用"
        continue
    fi
    echo "[拉取] ${name} ：${url}"
    if fetch_package "${name}" "${url}" "${branch}" "${subdir}"; then
        echo "[完成] ${name} 已放入 package/ 目录"
    else
        # 单个包失败不中断整体流程，仅记录并在最后汇总提示
        echo "[警告] ${name} 拉取失败！请检查仓库地址或子目录名"
        FAILED+=("${name}")
    fi
done

# 汇总拉取失败的包，提示处理方式
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "======================================================"
    echo "以下插件未能从第三方仓库拉取（源码中也无此包）："
    printf '  - %s\n' "${FAILED[@]}"
    echo "固件将缺少上述插件；如非必需可忽略，"
    echo "或在 config/x86-64.config 中注释对应 CONFIG_PACKAGE 行。"
    echo "======================================================"
fi
