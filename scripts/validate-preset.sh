#!/usr/bin/env bash
# =============================================================================
# 预置内容结构化校验脚本
#
# 由工作流「步骤 10 - 应用固件定制」调用，对 files/ 覆盖层落位后的预置配置
# 做结构化内容校验（防止只"拷过去"而内容不符合需求）。
#
# 背景：本段逻辑原先内联在工作流步骤 10 的 run 块中，导致该 run 块字符数
# 超过 GitHub Actions 单个 run step 21000 字符的硬上限
# （报错 "Exceeded max expression length 21000"，工作流无法被 GitHub 解析，
#   直接 startup_failure）。故抽为独立脚本，由工作流以
#   「bash scripts/validate-preset.sh」调用。
#   注：GitHub 按"原始文件包含缩进的字节数"计 run 块长度，而 PyYAML 解析后
#   去掉缩进的纯字符串更短——之前误以 PyYAML 长度判断，漏掉了真实超限。
#
# 用法：validate-preset.sh <IW源码树绝对路径> <PRESET_DIR绝对路径>
#   环境变量等价：IW_DIR / PRESET_DIR
# 退出码：0 = 全部校验通过；1 = 任一校验失败（已打印 ::error）
# =============================================================================
set -euo pipefail

IW_DIR="${1:-${IW_DIR:-}}"
PRESET_DIR="${2:-${PRESET_DIR:-}}"

if [ -z "$IW_DIR" ] || [ ! -d "$IW_DIR" ]; then
	echo "::error::用法: validate-preset.sh <IW源码树绝对路径> <PRESET_DIR绝对路径>"
	echo "::error::IW 源码树目录不存在或未提供：'${IW_DIR}'"
	exit 1
fi
if [ -z "$PRESET_DIR" ] || [ ! -d "$PRESET_DIR" ]; then
	echo "::error::PRESET_DIR 不存在或未提供：'${PRESET_DIR}'"
	exit 1
fi

FILES_ROOT="$IW_DIR/files"

# --- mwan3：接口 / 成员 / 策略必须为 0 个，默认规则必须为 3 条 ---
MWAN3_F="$FILES_ROOT/etc/config/mwan3"
MWAN3_IFACE="$(grep -cE "^config[[:space:]]+interface[[:space:]]" "$MWAN3_F" || true)"
MWAN3_MEMBER="$(grep -cE "^config[[:space:]]+member[[:space:]]" "$MWAN3_F" || true)"
MWAN3_POLICY="$(grep -cE "^config[[:space:]]+policy[[:space:]]" "$MWAN3_F" || true)"
MWAN3_RULE="$(grep -cE "^config[[:space:]]+rule[[:space:]]" "$MWAN3_F" || true)"
echo "mwan3 预置：interface=${MWAN3_IFACE} member=${MWAN3_MEMBER} policy=${MWAN3_POLICY} rule=${MWAN3_RULE}"
if [ "$MWAN3_IFACE" != "0" ] || [ "$MWAN3_MEMBER" != "0" ] || [ "$MWAN3_POLICY" != "0" ] || [ "$MWAN3_RULE" != "3" ]; then
	echo "==================== 预置配置内容校验失败 ===================="
	echo "定制项       : mwan3 默认配置（接口/成员/策略留空，仅保留默认规则）"
	echo "来源         : ${PRESET_DIR}/etc/config/mwan3"
	echo "期望值       : interface=0 member=0 policy=0 rule=3"
	echo "实际值       : interface=${MWAN3_IFACE} member=${MWAN3_MEMBER} policy=${MWAN3_POLICY} rule=${MWAN3_RULE}"
	echo "可能原因     : preset/etc/config/mwan3 被改动，重新引入了接口/成员/策略。"
	echo "建议修复方向 : 删除 config interface / config member / config policy 段，"
	echo "               只保留 globals 与 https、default_rule_v4、default_rule_v6 三条规则。"
	echo "==============================================================="
	echo "::error::mwan3 预置配置不符合需求"
	exit 1
fi

# --- SmartDNS：enabled=0、auto_set_dnsmasq=0、server 段 5 个、每段 type=udp ---
SD_F="$FILES_ROOT/etc/config/smartdns"
SD_ENABLED="$(sed -n "s/^[[:space:]]*option enabled '\([01]\)'.*/\1/p" "$SD_F" | head -1)"
SD_AUTODNS="$(sed -n "s/^[[:space:]]*option auto_set_dnsmasq '\([01]\)'.*/\1/p" "$SD_F" | head -1)"
SD_SERVER="$(grep -cE "^config[[:space:]]+server[[:space:]]*$" "$SD_F" || true)"
SD_UDP="$(grep -cE "^[[:space:]]+option type 'udp'" "$SD_F" || true)"
SD_PORT="$(grep -cE "^[[:space:]]+option port " "$SD_F" || true)"
echo "smartdns 预置：enabled=${SD_ENABLED} auto_set_dnsmasq=${SD_AUTODNS} server=${SD_SERVER} type=udp=${SD_UDP} port=${SD_PORT}"
if [ "$SD_ENABLED" != "0" ] || [ "$SD_AUTODNS" != "0" ] || [ "$SD_SERVER" != "5" ] || [ "$SD_UDP" != "5" ] || [ "$SD_PORT" != "0" ]; then
	echo "==================== 预置配置内容校验失败 ===================="
	echo "定制项       : SmartDNS 默认配置（不启用、不自动设置 dnsmasq、5 个上游服务器）"
	echo "来源         : ${PRESET_DIR}/etc/config/smartdns"
	echo "期望值       : enabled=0 auto_set_dnsmasq=0 server=5 type=udp=5 port=0"
	echo "实际值       : enabled=${SD_ENABLED} auto_set_dnsmasq=${SD_AUTODNS} server=${SD_SERVER} type=udp=${SD_UDP} port=${SD_PORT}"
	echo "可能原因     : preset/etc/config/smartdns 被改动，或上游 DNS 条目增减/协议类型被改。"
	echo "建议修复方向 : 保证 config smartdns 段内 enabled='0'、auto_set_dnsmasq='0'，"
	echo "               并保留 5 个 config server 段（type 全为 udp，不写 port）。"
	echo "==============================================================="
	echo "::error::SmartDNS 预置配置不符合需求"
	exit 1
fi
for IP in '114.114.114.114' '223.5.5.5' '180.184.1.1' '119.29.29.29' '8.8.8.8'; do
	if ! grep -qF "option ip '${IP}'" "$SD_F"; then
		echo "::error::SmartDNS 上游服务器缺失：${IP}"
		exit 1
	fi
done

# --- AdGuardHome：官方 schema —— enabled=1（开机自启）、config_file 指向预置 YAML、黑名单恰好 2 条 ---
# 2026-10 起 AGH 改由 ImmortalWrt 官方源提供（immortalwrt/packages 的 net/adguardhome），
# UCI 配置文件为 /etc/config/adguardhome（小写，段名 config adguardhome 'config'），
# 不再有第三方版（kenzok8）的 redirect / httpport / binpath 等选项。
ADG_CFG="$FILES_ROOT/etc/config/adguardhome"
ADG_ENABLED="$(sed -n "s/^[[:space:]]*option enabled '\([01]\)'.*/\1/p" "$ADG_CFG" | head -1)"
ADG_CFGFILE="$(sed -n "s/^[[:space:]]*option config_file '\([^']*\)'.*/\1/p" "$ADG_CFG" | head -1)"
ADG_YAML="$FILES_ROOT/etc/adguardhome/adguardhome.yaml"
ADG_FILTER_N="$(grep -cE '^[[:space:]]+-[[:space:]]+enabled:' "$ADG_YAML" || true)"
echo "AdGuardHome 预置：enabled=${ADG_ENABLED} config_file=${ADG_CFGFILE} filters=${ADG_FILTER_N}"
if [ "$ADG_ENABLED" != "1" ]; then
	echo "==================== 预置配置内容校验失败 ===================="
	echo "定制项       : AdGuardHome 默认配置（官方源 schema，enabled=1 默认开机自启）"
	echo "来源         : ${PRESET_DIR}/etc/config/adguardhome"
	echo "期望值       : enabled=1"
	echo "实际值       : enabled=${ADG_ENABLED}"
	echo "可能原因     : preset/etc/config/adguardhome 被改动，enabled 丢失或写错。"
	echo "建议修复方向 : 在 config adguardhome 'config' 段内补回 option enabled '1'。"
	echo "==============================================================="
	echo "::error::AdGuardHome 预置 config 的 enabled 不为 1（要求默认开机自启）"
	exit 1
fi
if [ "$ADG_CFGFILE" != "/etc/adguardhome/adguardhome.yaml" ]; then
	echo "==================== 预置配置内容校验失败 ===================="
	echo "定制项       : AdGuardHome 配置文件路径（须与 preset 的 YAML 落位一致）"
	echo "来源         : ${PRESET_DIR}/etc/config/adguardhome"
	echo "期望值       : config_file=/etc/adguardhome/adguardhome.yaml"
	echo "实际值       : config_file=${ADG_CFGFILE}"
	echo "可能原因     : config_file 选项被改动，或 preset/etc/adguardhome/adguardhome.yaml 未落位。"
	echo "建议修复方向 : 保持 config adguardhome 'config' 段内"
	echo "               option config_file '/etc/adguardhome/adguardhome.yaml'。"
	echo "==============================================================="
	echo "::error::AdGuardHome 预置 config 的 config_file 路径不符"
	exit 1
fi
if [ "$ADG_FILTER_N" != "2" ]; then
	echo "==================== 预置配置内容校验失败 ===================="
	echo "定制项       : AdGuardHome DNS 黑名单清单（仅保留 2 条）"
	echo "来源         : ${PRESET_DIR}/etc/adguardhome/adguardhome.yaml"
	echo "期望值       : filters 条目数 = 2"
	echo "实际值       : ${ADG_FILTER_N}"
	echo "可能原因     : preset/etc/adguardhome/adguardhome.yaml 的 filters 段被改动。"
	echo "建议修复方向 : 只保留 https://anti-ad.net/adguard.txt 与"
	echo "               https://gh-proxy.com/https://raw.githubusercontent.com/2771936993/HG/main/hg1.txt。"
	echo "==============================================================="
	echo "::error::AdGuardHome 黑名单清单不符合需求"
	exit 1
fi
for CHK in \
	'    - 114.114.114.114' \
	'    - 223.5.5.5' \
	'    url: https://anti-ad.net/adguard.txt' \
	'    url: https://gh-proxy.com/https://raw.githubusercontent.com/2771936993/HG/main/hg1.txt'; do
	if ! grep -qF "$CHK" "$ADG_YAML"; then
		echo "::error::AdGuardHome 预置内容缺失：$CHK"
		exit 1
	fi
done

# --- dhcp：dnsmasq 段必须显式声明 option port '53' ---
DHCP_F="$FILES_ROOT/etc/config/dhcp"
DHCP_PORT_N="$(grep -cE "^[[:space:]]*option[[:space:]]+port[[:space:]]+'?53'?[[:space:]]*$" "$DHCP_F" || true)"
DHCP_CFG_N="$(grep -cE "^config[[:space:]]+dnsmasq" "$DHCP_F" || true)"
echo "dhcp 预置：dnsmasq 段=${DHCP_CFG_N} port=53 声明数=${DHCP_PORT_N}"
if [ "$DHCP_CFG_N" != "1" ] || [ "$DHCP_PORT_N" != "1" ]; then
	echo "==================== 预置配置内容校验失败 ===================="
	echo "定制项       : dnsmasq DNS 端口基准值（固化 53 端口，与 AGH 的 5553 分工明确）"
	echo "来源         : ${PRESET_DIR}/etc/config/dhcp"
	echo "期望值       : config dnsmasq 段 = 1 且 option port '53' 声明 = 1"
	echo "实际值       : dnsmasq 段=${DHCP_CFG_N} port=53 声明数=${DHCP_PORT_N}"
	echo "可能原因     : preset/etc/config/dhcp 被改动，port 选项丢失或写错。"
	echo "建议修复方向 : 在 config dnsmasq 段内补回 option port '53'。"
	echo "==============================================================="
	echo "::error::dhcp 预置配置缺少 dnsmasq 端口声明"
	exit 1
fi

# --- opkg 软件源：6 个 src/gz 源且 URL 指向 25.12 发布目录 ---
FEEDS_F="$FILES_ROOT/etc/opkg/distfeeds.conf"
FEEDS_N="$(grep -cE '^[[:space:]]*src/gz[[:space:]]' "$FEEDS_F" || true)"
echo "opkg distfeeds 预置：src/gz 源数量=${FEEDS_N}"
if [ "$FEEDS_N" != "6" ]; then
	echo "==================== 预置配置内容校验失败 ===================="
	echo "定制项       : opkg 软件源列表（修复 LuCI 更新列表失败）"
	echo "来源         : ${PRESET_DIR}/etc/opkg/distfeeds.conf"
	echo "期望值       : src/gz 源数量 = 6（core/base/luci/packages/routing/telephony）"
	echo "实际值       : ${FEEDS_N}"
	echo "可能原因     : preset/etc/opkg/distfeeds.conf 被改动，源条目增减或被注释。"
	echo "建议修复方向 : 保持 6 条 src/gz 行，URL 指向"
	echo "               https://downloads.immortalwrt.org/releases/25.12.2/... 。"
	echo "==============================================================="
	echo "::error::opkg distfeeds 预置配置源数量不符"
	exit 1
fi
for FEED in \
	'src/gz immortalwrt_core https://downloads.immortalwrt.org/releases/25.12.2/targets/x86/64/packages' \
	'src/gz immortalwrt_base https://downloads.immortalwrt.org/releases/25.12.2/packages/x86_64/base' \
	'src/gz immortalwrt_luci https://downloads.immortalwrt.org/releases/25.12.2/packages/x86_64/luci' \
	'src/gz immortalwrt_packages https://downloads.immortalwrt.org/releases/25.12.2/packages/x86_64/packages' \
	'src/gz immortalwrt_routing https://downloads.immortalwrt.org/releases/25.12.2/packages/x86_64/routing' \
	'src/gz immortalwrt_telephony https://downloads.immortalwrt.org/releases/25.12.2/packages/x86_64/telephony'; do
	if ! grep -qF "$FEED" "$FEEDS_F"; then
		echo "::error::opkg distfeeds 预置内容缺失：$FEED"
		exit 1
	fi
done

# --- firewall：flow_offloading=1 / flow_offloading_hw=0 / fullcone=1 ---
FW_F="$FILES_ROOT/etc/config/firewall"
FW_SW="$(sed -n "s/^[[:space:]]*option[[:space:]]\+flow_offloading[[:space:]]\+'\{0,1\}\([01]\)'\{0,1\}[[:space:]]*$/\1/p" "$FW_F" | head -1)"
FW_HW="$(sed -n "s/^[[:space:]]*option[[:space:]]\+flow_offloading_hw[[:space:]]\+'\{0,1\}\([01]\)'\{0,1\}[[:space:]]*$/\1/p" "$FW_F" | head -1)"
FW_FC="$(sed -n "s/^[[:space:]]*option[[:space:]]\+fullcone[[:space:]]\+'\{0,1\}\([01]\)'\{0,1\}[[:space:]]*$/\1/p" "$FW_F" | head -1)"
echo "firewall 预置：flow_offloading=${FW_SW} flow_offloading_hw=${FW_HW} fullcone=${FW_FC}"
if [ "$FW_SW" != "1" ] || [ "$FW_HW" != "0" ] || [ "$FW_FC" != "1" ]; then
	echo "==================== 预置配置内容校验失败 ===================="
	echo "定制项       : 防火墙路由/NAT 卸载默认值（软件卸载 + 全锥 NAT）"
	echo "来源         : ${PRESET_DIR}/etc/config/firewall"
	echo "期望值       : flow_offloading=1（软件卸载） flow_offloading_hw=0（硬件卸载关） fullcone=1（全锥 NAT）"
	echo "实际值       : flow_offloading=${FW_SW} flow_offloading_hw=${FW_HW} fullcone=${FW_FC}"
	echo "可能原因     : preset/etc/config/firewall 被改动，或 defaults 段丢失这些选项。"
	echo "建议修复方向 : 在 config defaults 段内补回 option flow_offloading '1'、"
	echo "               option flow_offloading_hw '0' 与 option fullcone '1'。"
	echo "==============================================================="
	echo "::error::firewall 预置配置未默认软件流量卸载/全锥 NAT"
	exit 1
fi

# --- argon：登录界面在线壁纸必须为 bing ---
ARGON_F="$FILES_ROOT/etc/config/argon"
ARGON_WP="$(sed -n "s/^[[:space:]]*option[[:space:]]\+online_wallpaper[[:space:]]\+'\([a-z]*\)'.*/\1/p" "$ARGON_F" | head -1)"
echo "argon 预置：online_wallpaper=${ARGON_WP}"
if [ "$ARGON_WP" != "bing" ]; then
	echo "==================== 预置配置内容校验失败 ===================="
	echo "定制项       : argon 主题登录界面在线壁纸（Bing 每日图片）"
	echo "来源         : ${PRESET_DIR}/etc/config/argon"
	echo "期望值       : online_wallpaper=bing"
	echo "实际值       : online_wallpaper=${ARGON_WP}"
	echo "可能原因     : preset/etc/config/argon 被改动，online_wallpaper 不是 bing。"
	echo "建议修复方向 : 在 config global 段内补回 option online_wallpaper 'bing'。"
	echo "==============================================================="
	echo "::error::argon 预置配置未默认展示 Bing 每日图片"
	exit 1
fi

echo "预置内容结构化校验全部通过"
