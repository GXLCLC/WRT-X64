#!/usr/bin/env bash
# =============================================================================
# 首次启动 uci-defaults 生成脚本
#
# 由工作流「步骤 10 - 应用固件定制」调用，生成首次启动兜底脚本
# $IW/files/etc/uci-defaults/99-wrt-x64-defaults（幂等）。
#
# 背景：本文件原先内联在工作流 run 块中，导致该 run 块字符数超过
# GitHub Actions 单个 run step 21000 字符的硬上限（报错
# "Exceeded max expression length 21000"），工作流无法被 GitHub 解析。
# 故抽为独立脚本，由工作流以「bash scripts/write-uci-defaults.sh」调用。
#
# 用法：write-uci-defaults.sh <IW源码树绝对路径> <LAN_IP> <ROOT_PASSWORD>
#   环境变量等价：IW_DIR / LAN_IP / ROOT_PASSWORD
# 退出码：0 = 成功；1 = 参数错误或写入失败
# =============================================================================
set -euo pipefail

IW_DIR="${1:-${IW_DIR:-}}"
LAN_IP="${2:-${LAN_IP:-192.168.2.1}}"
ROOT_PASSWORD="${3:-${ROOT_PASSWORD:-12345678}}"

if [ -z "$IW_DIR" ] || [ ! -d "$IW_DIR" ]; then
	echo "::error::用法: write-uci-defaults.sh <IW源码树绝对路径> <LAN_IP> <ROOT_PASSWORD>"
	echo "::error::IW 源码树目录不存在或未提供：'${IW_DIR}'"
	exit 1
fi

OUT_DIR="$IW_DIR/files/etc/uci-defaults"
OUT_FILE="$OUT_DIR/99-wrt-x64-defaults"

mkdir -p "$OUT_DIR"

# -----------------------------------------------------------------------------
# 生成首次启动兜底脚本。内容说明（逐段）：
#   1. 时区 / LAN 地址：与步骤 10.1 的 config_generate 改写保持一致，
#      作为运行期二次兜底
#   2. AdGuardHome 核心位置显式指向随固件打包的二进制
#   3. AdGuardHome 重定向状态机初始化：init 脚本（_do_redirect）用
#      old_redirect / old_port / old_enabled 三个「上一次生效值」与当前值
#      比对来决定是否执行清理 / 应用动作。首次启动这三项不存在时
#      config_get 会取默认值 "none"/"0"/"0"，与用户真实配置不一致会
#      导致模式判断错乱，因此首次启动时显式初始化为与 preset 一致的值
#   4. dnsmasq DNS 端口基准值：preset/etc/config/dhcp 已显式写入
#      option port '53'，此处再兜底一次，保证 uci get
#      dhcp.@dnsmasq[0].port 恒有值可读（luci-app-adguardhome 的
#      use_port53 / set_forward_dnsmasq / exchange 模式判断全部依赖该值）
#   5. 防火墙路由/NAT 卸载默认改为「软件流量卸载」：X86_64 平台没有硬件
#      NAT 引擎，硬件流量卸载（flow_offloading_hw）对该架构无效；
#      fw4 上游默认两个开关均为 0（不启用），这里显式写为软件卸载开、
#      硬件卸载关。kmod-nft-offload 已由 firewall4 的 DEPENDS 与
#      config/required-packages.txt 保证随固件打包
#   6. opkg 软件源列表兜底：正常流程由 base-files 的 FeedSourcesAppendOPKG
#      在镜像打包时写入 /etc/opkg/distfeeds.conf；若该文件缺失或为空，
#      「软件包 - 更新列表」会因无任何可用源而失败。这里按当前 24.10
#      官方源结构重建，保证首次开机即可更新列表
#   7. mwan3：清空接口 / 成员 / 策略，仅保留默认规则（待用户自行配置）
#   8. root 默认密码兜底设置
# -----------------------------------------------------------------------------
cat > "$OUT_FILE" <<UCI
#!/bin/sh
# 由 WRT-X64 云编译工作流写入的首次启动默认值（二次兜底，幂等）
uci -q set system.@system[0].timezone='CST-8'
uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q commit system
uci -q set network.lan.ipaddr='${LAN_IP}'
uci -q commit network
# AdGuardHome 核心位置显式指向随固件打包的二进制（luci-app-adguardhome 默认值即为此路径，
# 这里显式写一次是为了在上游默认值变更时仍能保证核心被找到）
uci -q get AdGuardHome.AdGuardHome >/dev/null 2>&1 && {
  uci -q set AdGuardHome.AdGuardHome.binpath='/usr/bin/AdGuardHome'
  uci -q commit AdGuardHome
}
# AdGuardHome 重定向状态机初始化：
#   init 脚本（/etc/init.d/AdGuardHome 的 _do_redirect）用 old_redirect /
#   old_port / old_enabled 三个"上一次生效值"与当前值比对来决定是否执行
#   清理 / 应用动作。首次启动这三项不存在时 config_get 会取默认值
#   "none"/"0"/"0"，与用户真实配置不一致会导致模式判断错乱，
#   因此首次启动时显式初始化为与 preset 一致的值。
if uci -q get AdGuardHome.AdGuardHome >/dev/null 2>&1; then
  AGH_REDIR="\$(uci -q get AdGuardHome.AdGuardHome.redirect || echo none)"
  AGH_EN="\$(uci -q get AdGuardHome.AdGuardHome.enabled || echo 0)"
  AGH_PORT="\$(sed -n "s/^[[:space:]]*port:[[:space:]]*//p" /etc/AdGuardHome.yaml 2>/dev/null | head -1)"
  [ -n "\$AGH_PORT" ] || AGH_PORT='5553'
  uci -q delete AdGuardHome.AdGuardHome.old_redirect >/dev/null 2>&1
  uci -q delete AdGuardHome.AdGuardHome.old_port >/dev/null 2>&1
  uci -q delete AdGuardHome.AdGuardHome.old_enabled >/dev/null 2>&1
  uci -q add_list AdGuardHome.AdGuardHome.old_redirect="\$AGH_REDIR"
  uci -q add_list AdGuardHome.AdGuardHome.old_port="\$AGH_PORT"
  uci -q add_list AdGuardHome.AdGuardHome.old_enabled="\$AGH_EN"
  uci -q commit AdGuardHome
fi
# dnsmasq DNS 端口基准值：
#   preset/etc/config/dhcp 已显式写入 option port '53'，
#   此处再兜底一次，保证 uci get dhcp.@dnsmasq[0].port 恒有值可读
#   （luci-app-adguardhome 的 use_port53 / set_forward_dnsmasq /
#    exchange 模式判断全部依赖该值）。
if uci -q get dhcp.@dnsmasq[0] >/dev/null 2>&1; then
  uci -q set dhcp.@dnsmasq[0].port='53'
  uci -q commit dhcp
fi
# 防火墙路由/NAT 卸载默认改为「软件流量卸载」+ 全锥形 NAT：
#   X86_64 平台没有硬件 NAT 引擎，硬件流量卸载（flow_offloading_hw）
#   对该架构无效；fw4 上游默认两个开关均为 0（不启用），
#   这里显式写为软件卸载开、硬件卸载关，LuCI「防火墙 - 一般设置」
#   的「Routing/NAT Offloading」即显示「Software flow offloading」。
#   kmod-nft-offload 已由 firewall4 的 DEPENDS 与
#   config/required-packages.txt 保证随固件打包。
#   注意：TurboAcc 的 /etc/init.d/turboacc 开机时会把
#   firewall.@defaults[0].flow_offloading_hw 写回其配置值（默认 1），
#   因此必须在「首次启动兜底」脚本里再次强制写回 0，才能彻底覆盖它；
#   全锥型 NAT（fullcone=1）同理，TurboAcc 开机也会写入，这里再写一次兜底。
if uci -q get firewall.@defaults[0] >/dev/null 2>&1; then
  uci -q set firewall.@defaults[0].flow_offloading='1'
  uci -q set firewall.@defaults[0].flow_offloading_hw='0'
  uci -q set firewall.@defaults[0].fullcone='1'
  uci -q commit firewall
fi
# argon 主题登录界面展示 Bing 每日图片：
#   luci-theme-argon 基础主题自带的 /etc/config/argon 默认
#   online_wallpaper='none'，会覆盖 luci-app-argon-config 的 'bing'，
#   导致登录界面不显示 Bing 图片。这里显式写回 'bing' 作为兜底。
if uci -q get argon.@global[0] >/dev/null 2>&1; then
  uci -q set argon.@global[0].online_wallpaper='bing'
  uci -q commit argon
fi
# opkg 软件源列表兜底：
#   正常流程由 base-files 的 FeedSourcesAppendOPKG 在镜像打包时
#   写入 /etc/opkg/distfeeds.conf；若该文件缺失或为空，
#   「软件包 - 更新列表」会因无任何可用源而失败。
#   这里按当前 24.10 官方源结构重建，保证首次开机即可更新列表。
if [ ! -s /etc/opkg/distfeeds.conf ]; then
  mkdir -p /etc/opkg
  cat > /etc/opkg/distfeeds.conf <<'FEEDS'
src/gz immortalwrt_core https://downloads.immortalwrt.org/releases/24.10.0/targets/x86/64/packages
src/gz immortalwrt_base https://downloads.immortalwrt.org/releases/24.10.0/packages/x86_64/base
src/gz immortalwrt_luci https://downloads.immortalwrt.org/releases/24.10.0/packages/x86_64/luci
src/gz immortalwrt_packages https://downloads.immortalwrt.org/releases/24.10.0/packages/x86_64/packages
src/gz immortalwrt_routing https://downloads.immortalwrt.org/releases/24.10.0/packages/x86_64/routing
src/gz immortalwrt_telephony https://downloads.immortalwrt.org/releases/24.10.0/packages/x86_64/telephony
FEEDS
fi
# mwan3：清空接口 / 成员 / 策略，仅保留默认规则（待用户自行配置）
# 说明：兼容用户或上游重新引入默认项的情况，逐条删除后再提交。
if uci -q get mwan3.globals >/dev/null 2>&1; then
  for s in \$(uci -q show mwan3 | sed -n "s/^mwan3\.\([^.=]*\)=interface\$/\\1/p"); do
    uci -q delete "mwan3.\$s"
  done
  for s in \$(uci -q show mwan3 | sed -n "s/^mwan3\.\([^.=]*\)=member\$/\\1/p"); do
    uci -q delete "mwan3.\$s"
  done
  for s in \$(uci -q show mwan3 | sed -n "s/^mwan3\.\([^.=]*\)=policy\$/\\1/p"); do
    uci -q delete "mwan3.\$s"
  done
  uci -q commit mwan3
fi
# root 默认密码兜底设置
echo 'root:${ROOT_PASSWORD}' | chpasswd 2>/dev/null || \
  printf '%s\n%s\n' '${ROOT_PASSWORD}' '${ROOT_PASSWORD}' | passwd root >/dev/null 2>&1
exit 0
UCI

chmod 0755 "$OUT_FILE"

# -----------------------------------------------------------------------------
# 落位与语法自检
# -----------------------------------------------------------------------------
if [ ! -s "$OUT_FILE" ]; then
	echo "::error::uci-defaults 脚本生成失败或为空：$OUT_FILE"
	exit 1
fi
if ! head -1 "$OUT_FILE" | grep -q '^#!/bin/sh'; then
	echo "::error::uci-defaults 脚本缺少 shebang：$OUT_FILE"
	exit 1
fi
if ! sh -n "$OUT_FILE"; then
	echo "::error::uci-defaults 脚本语法校验失败：$OUT_FILE"
	exit 1
fi
# 关键定制项落位复核（防止 heredoc 内容被意外改动）
for check in "timezone='CST-8'" "zonename='Asia/Shanghai'" \
	"old_redirect" "old_port" "old_enabled" \
	"dhcp.@dnsmasq[0].port='53'" \
	"flow_offloading='1'" "flow_offloading_hw='0'" \
	"fullcone='1'" "online_wallpaper='bing'" \
	"src/gz immortalwrt_core" "mwan3"; do
	if ! grep -qF "$check" "$OUT_FILE"; then
		echo "::error::uci-defaults 脚本缺少关键定制项：$check"
		exit 1
	fi
done

echo "uci-defaults 脚本已生成并通过语法/内容校验："
find "$OUT_DIR" -type f -printf '  %p (%s 字节)\n' | sort
