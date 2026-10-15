#!/usr/bin/env bash
# ================================================================
# scripts/system-config.sh —— 系统参数唯一维护点
#
#【这个脚本解决什么问题】
#   后台登录密码、LAN 口 IP、主机名、时区、默认主题这类「系统级
#   参数」如果散落在 workflow.yml 和各个 uci-defaults 文件里，
#   改一次要动好几处，还容易漏。
#   本脚本把全部系统参数收敛到下面的「配置块」里 ——
#   以后要改系统参数，只改这一处，workflow.yml 一个字都不用动。
#
#【工作原理】
#   在编译机上运行本脚本，它会根据配置块生成一个 uci-defaults
#   脚本（默认名为 99-90-custom-settings），放进 ImmortalWrt 源码树
#   的 files/etc/uci-defaults/ 目录，随固件一起打包。
#   该脚本在路由器「首次启动」时由 /etc/init.d/boot 自动执行一次
#   （见 ImmortalWrt 源码 base-files 的 uci_apply_defaults，它是
#   `ls` 后逐个 `. "./$file"` source 执行，不检查可执行位），执行成功
#   后自动删除，不会重复执行、也不会覆盖用户后期的修改。
#
#【执行顺序】uci-defaults 按文件名排序执行，本文件是 99-90：
#     40_luci-AdGuardHome      （kenzok8 面板自带，先跑）
#     99-20-service-defaults   （服务默认状态）
#     99-90-custom-settings    （本脚本生成，最后跑，优先级最高）
#   故本脚本写入的值一定是最终生效值。
#
#【用法】
#   # 在 ImmortalWrt 源码树根目录执行（工作流里就是这么调的）
#   bash scripts/system-config.sh .
#   # 或者显式指定源码树路径
#   bash scripts/system-config.sh /path/to/immortalwrt
#
#【输出】
#   <源码树>/files/etc/uci-defaults/99-90-custom-settings
#
#【注意】scripts/firmware-info.sh 会读取下面配置块里的 LAN_IP /
#   ROOT_PASSWORD / HOSTNAME 来生成 Release 说明，改完这里
#   Release 页面会自动跟着变，不会出现「说明书和固件不一致」。
# ================================================================
set -euo pipefail

# ================================================================
#                       ↓↓↓ 配置块 ↓↓↓
#   只改这里。左边是参数名，右边引号内是取值。
# ================================================================

# ---- 主机名（路由器名字，会显示在 LuCI 顶部与 shell 提示符） ----
HOSTNAME="ImmortalWrt"

# ---- 时区 ----
#   TIMEZONE 是 POSIX 时区串，ZONENAME 是标准时区名，两者必须对应；
#   北京时间固定为 Asia/Shanghai / CST-8，无需修改。
TIMEZONE="CST-8"
ZONENAME="Asia/Shanghai"

# ---- 上游 NTP 服务器（空格分隔，写在 /etc/config/system 的 ntp 段） ----
NTP_SERVERS="ntp.aliyun.com time1.cloud.tencent.com cn.pool.ntp.org"

# ---- LAN 口 IP / 子网掩码 ----
LAN_IP="192.168.2.1"
LAN_NETMASK="255.255.255.0"

# ---- LAN 口 DHCP 地址池（起始地址 / 池容量 / 租期） ----
#   起始地址必须落在上面的网段内，且不能与 LAN_IP 相同。
LAN_DHCP_START="192.168.2.100"
LAN_DHCP_LIMIT="150"
LAN_DHCP_LEASETIME="12h"

# ---- root 后台登录密码 ----
#   仅在固件当前「未设置密码」时写入，用户后期自行改过的密码
#   不会被覆盖（sysupgrade 升级后同样保留）。
ROOT_PASSWORD="12345678"

# ---- 默认 LuCI 主题（需与 .config 中勾选的主题包对应） ----
DEFAULT_THEME="argon"

# ================================================================
#                       ↑↑↑ 配置块结束 ↑↑↑
# ================================================================

TARGET_DIR="${1:-.}"

if [ ! -f "$TARGET_DIR/rules.mk" ]; then
  echo "错误: '$TARGET_DIR' 不是 ImmortalWrt 源码树根目录（缺少 rules.mk）" >&2
  echo "用法: $0 <ImmortalWrt 源码树路径>" >&2
  exit 1
fi

OUT_DIR="$TARGET_DIR/files/etc/uci-defaults"
OUT_FILE="$OUT_DIR/99-90-custom-settings"

# ---------- 参数自检：单引号会破坏 uci 语法，提前拦下 ----------
validate() {
  local name="$1" value="$2"
  case "$value" in
  *"'"*)
    echo "错误: 配置项 $name 的值中不允许出现单引号: $value" >&2
    exit 1
    ;;
  esac
}
validate HOSTNAME            "$HOSTNAME"
validate TIMEZONE            "$TIMEZONE"
validate ZONENAME            "$ZONENAME"
validate LAN_IP              "$LAN_IP"
validate LAN_NETMASK         "$LAN_NETMASK"
validate LAN_DHCP_START      "$LAN_DHCP_START"
validate LAN_DHCP_LIMIT      "$LAN_DHCP_LIMIT"
validate LAN_DHCP_LEASETIME  "$LAN_DHCP_LEASETIME"
validate ROOT_PASSWORD       "$ROOT_PASSWORD"
validate DEFAULT_THEME       "$DEFAULT_THEME"

case "$LAN_DHCP_LIMIT" in
'' | *[!0-9]*)
  echo "错误: LAN_DHCP_LIMIT 必须为正整数: $LAN_DHCP_LIMIT" >&2
  exit 1
  ;;
esac

# ---- 主题名只能是小写字母数字与连字符，避免拼出错误路径 ----
case "$DEFAULT_THEME" in
*[!a-z0-9-]*)
  echo "错误: DEFAULT_THEME 只能包含小写字母/数字/连字符: $DEFAULT_THEME" >&2
  exit 1
  ;;
esac

echo "==> [system-config] 生成系统参数脚本: $OUT_FILE"
echo "    主机名    : $HOSTNAME"
echo "    时区      : $ZONENAME ($TIMEZONE)"
echo "    LAN IP    : $LAN_IP / $LAN_NETMASK"
echo "    DHCP 池   : $LAN_DHCP_START +$LAN_DHCP_LIMIT 租期 $LAN_DHCP_LEASETIME"
echo "    默认主题  : $DEFAULT_THEME"
echo "    root 密码 : 已设置（长度 ${#ROOT_PASSWORD}）"

mkdir -p "$OUT_DIR"

# ---------- 第一部分：把配置值固化成 shell 变量（带引号，安全） ----------
{
  printf '%s\n' '#!/bin/sh'
  printf '%s\n' '# ================================================================'
  printf '%s\n' '# 本文件由 scripts/system-config.sh 自动生成，请勿手工编辑！'
  printf '%s\n' '# 要修改主机名 / LAN IP / 登录密码 / 时区 / 默认主题，'
  printf '%s\n' '# 请编辑 scripts/system-config.sh 顶部的配置块后重新编译。'
  printf '%s\n' '# ================================================================'
  printf '\n'
  printf 'HOSTNAME=%s\n' "'$HOSTNAME'"
  printf 'TIMEZONE=%s\n' "'$TIMEZONE'"
  printf 'ZONENAME=%s\n' "'$ZONENAME'"
  printf 'NTP_SERVERS=%s\n' "'$NTP_SERVERS'"
  printf 'LAN_IP=%s\n' "'$LAN_IP'"
  printf 'LAN_NETMASK=%s\n' "'$LAN_NETMASK'"
  printf 'LAN_DHCP_START=%s\n' "'$LAN_DHCP_START'"
  printf 'LAN_DHCP_LIMIT=%s\n' "'$LAN_DHCP_LIMIT'"
  printf 'LAN_DHCP_LEASETIME=%s\n' "'$LAN_DHCP_LEASETIME'"
  printf 'ROOT_PASSWORD=%s\n' "'$ROOT_PASSWORD'"
  printf 'DEFAULT_THEME=%s\n' "'$DEFAULT_THEME'"
  printf '\n'
} >"$OUT_FILE"

# ---------- 第二部分：固定逻辑（与配置值无关，原样追加） ----------
cat >>"$OUT_FILE" <<'SHEOF'
# ----------------------------------------------------------------
# 1. 主机名 / 时区（LuCI「系统 → 系统」里看到的就是这几项）
# ----------------------------------------------------------------
uci -q set system.@system[0].hostname="$HOSTNAME"
uci -q set system.@system[0].timezone="$TIMEZONE"
uci -q set system.@system[0].zonename="$ZONENAME"
uci -q commit system

# ----------------------------------------------------------------
# 2. NTP 时间同步服务器（重建 ntp 段，保证取到干净的一组地址）
# ----------------------------------------------------------------
uci -q delete system.ntp 2>/dev/null
uci -q set system.ntp='timeserver'
uci -q set system.ntp.enabled='1'
# enable_server=0：本机只做客户端，不向 LAN 提供 NTP 服务
uci -q set system.ntp.enable_server='0'
for _s in $NTP_SERVERS; do
	uci -q add_list system.ntp.server="$_s"
done
unset _s
uci -q commit system

# ----------------------------------------------------------------
# 3. LAN 口 IP / 掩码
#    x86 默认网络配置里 lan 已是 static proto，这里只是改写地址；
#    网关与 DNS 交给上游 WAN 下发，故一并清掉，避免残留旧值。
# ----------------------------------------------------------------
uci -q set network.lan.proto='static'
uci -q set network.lan.ipaddr="$LAN_IP"
uci -q set network.lan.netmask="$LAN_NETMASK"
uci -q delete network.lan.gateway 2>/dev/null
uci -q delete network.lan.dns 2>/dev/null
uci -q commit network

# ----------------------------------------------------------------
# 4. LAN 口 DHCP 地址池（跟着 LAN 网段一起改，否则客户端拿不到地址）
# ----------------------------------------------------------------
uci -q set dhcp.lan.start="$LAN_DHCP_START"
uci -q set dhcp.lan.limit="$LAN_DHCP_LIMIT"
uci -q set dhcp.lan.leasetime="$LAN_DHCP_LEASETIME"
uci -q commit dhcp

# ----------------------------------------------------------------
# 5. root 后台登录密码
#    仅当 /etc/shadow 中 root 的密码字段为空时才写入，
#    用户后期自行修改过的密码不会被覆盖。
# ----------------------------------------------------------------
_hash="$(awk -F: '$1 == "root" { print $2 }' /etc/shadow 2>/dev/null)"
if [ -z "$_hash" ]; then
	printf '%s\n%s\n' "$ROOT_PASSWORD" "$ROOT_PASSWORD" | passwd root >/dev/null 2>&1
fi
unset _hash

# ----------------------------------------------------------------
# 6. 默认 LuCI 主题
#    仅在出厂默认（bootstrap）或未设置时才改为目标主题；
#    用户自己换过的主题一律保留，sysupgrade 升级后同样保留。
# ----------------------------------------------------------------
_current_theme="$(uci -q get luci.main.mediaurlbase)"
case "$_current_theme" in
"/luci-static/$DEFAULT_THEME")
	# 已经是目标主题，无需处理
	;;
"/luci-static/bootstrap" | "")
	uci -q set luci.main.mediaurlbase="/luci-static/$DEFAULT_THEME"
	uci -q commit luci
	;;
*)
	# 用户已自行选择其它主题，保留用户设置
	;;
esac
unset _current_theme

exit 0
SHEOF

chmod 0755 "$OUT_FILE"

echo "==> [system-config] 完成，首启脚本已就位（$(wc -l <"$OUT_FILE") 行）"
