#!/usr/bin/env bash
# ==============================================================================
# 步骤四：固件默认设置（IP / 密码 / 主机名 / 时区 / 主题）+ 清除插件预设配置
# 所有参数均可由工作流环境变量覆盖：LAN_IP / ROOT_PASSWORD / FW_HOSTNAME / TZ_NAME
# ==============================================================================
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
enter_source

LAN_IP="${LAN_IP:-192.168.2.1}"          # 默认后台 IP
ROOT_PASSWORD="${ROOT_PASSWORD:-}"       # 默认留空（首次登录不设密码）
FW_HOSTNAME="${FW_HOSTNAME:-OpenWrt}"    # 默认主机名（避免与系统 HOSTNAME 变量冲突）
TZ_NAME="${TZ_NAME:-Asia/Shanghai}"      # 时区
TZ_CODE="${TZ_CODE:-CST-8}"
DEFAULT_THEME="${DEFAULT_THEME:-argon}"  # 默认 LuCI 主题

# ---------------------- 1. 网络 / 主机名 / 时区 --------------------------------
step "写入默认网络、主机名与时区"
CFG_GEN="package/base-files/files/bin/config_generate"
[[ -f "$CFG_GEN" ]] || die "未找到 $CFG_GEN（源码结构异常或分支错误）"

# 后台 IP：192.168.2.1
sed -i "s#192\.168\.1\.1#${LAN_IP}#g" "$CFG_GEN"
# 主机名
sed -i "s#hostname='OpenWrt'#hostname='${FW_HOSTNAME}'#g" "$CFG_GEN"
# 时区
sed -i "s#timezone='UTC'#timezone='${TZ_CODE}'#g" "$CFG_GEN"
grep -q "zonename" "$CFG_GEN" && sed -i "s#zonename='[^']*'#zonename='${TZ_NAME}'#g" "$CFG_GEN"
log "已写入：IP=${LAN_IP} 主机名=${FW_HOSTNAME} 时区=${TZ_NAME}(${TZ_CODE})"
# zonename 由下方 uci-defaults 兜底写入，避免对 config_generate 做易碎的行内插入

# ---------------------- 2. 密码留空 -------------------------------------------
step "设置 root 密码为空（首次登录无需密码）"
SHADOW="package/base-files/files/etc/shadow"
[[ -f "$SHADOW" ]] || die "未找到 $SHADOW"
# 直接重写：root 密码字段留空 => 空密码
cat > "$SHADOW" <<EOF
root::0:0:99999:7:::
daemon:*:0:0:99999:7:::
ftp:*:0:0:99999:7:::
network:*:0:0:99999:7:::
nobody:*:0:0:99999:7:::
EOF
log "已重置 root 密码为空"

# ---------------------- 3. 默认主题 Argon + 中文 -------------------------------
step "设置默认 LuCI 主题为 ${DEFAULT_THEME}、默认语言简体中文"
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-defaults <<EOF
#!/bin/sh
# 首次启动时执行（编号最大，覆盖 config_generate 的默认值）
uci -q batch <<'UCI'
set system.@system[0].hostname='${FW_HOSTNAME}'
set system.@system[0].timezone='${TZ_CODE}'
set system.@system[0].zonename='${TZ_NAME}'
set network.lan.ipaddr='${LAN_IP}'
set network.lan.netmask='255.255.255.0'
set luci.main.lang='zh_cn'
set luci.main.mediaurlbase='/luci-static/${DEFAULT_THEME}'
set turboacc.config.sfe_flow='0'
set turboacc.config.sw_flow='1'
set turboacc.config.fullcone_nat='1'
set turboacc.config.bbr_cca='1'
commit
UCI
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-defaults

# ---------------------- 4. 清除插件预设配置 -----------------------------------
step "清除插件自带预设配置，保持「未配置」状态（由用户自行配置）"
purge_preset() { # <包目录名> <配置文件名>
    local pkg="$1" cfg="$2" f
    while IFS= read -r f; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            log "已删除预设配置：$f"
        fi
    done < <(find package -type f -path "*/${pkg}/files/etc/config/${cfg}" 2>/dev/null)
    return 0
}

# 多拨负载均衡：默认带多个 interface/member/policy，全部删除 -> 未配置状态
purge_preset "mwan3" "mwan3"
# 其余会预置业务参数的插件，同样清空
purge_preset "smartdns"        "smartdns"
purge_preset "adguardhome"     "adguardhome"
purge_preset "easytier"        "easytier"
purge_preset "ddnsto"          "ddnsto"
purge_preset "wechatpush"      "wechatpush"
purge_preset "openwrt-bandix"  "bandix"
purge_preset "luci-app-bandix" "bandix"
purge_preset "oaf"             "appfilter"
purge_preset "open-app-filter" "appfilter"
purge_preset "appfilter"       "appfilter"
purge_preset "luci-app-oaf"    "appfilter"

# 兜底：任何位置出现的 mwan3 预设配置一律清除（含 luci 包内副本）
find package -type f -name "mwan3" -path "*/etc/config/*" -print -delete 2>/dev/null | sed 's/^/  清除：/' || true

# ---------------------- 5. Turbo ACC：关闭 SFE --------------------------------
step "关闭 Turbo ACC 的 Shortcut-FE 开关（保留分载 / 全锥 NAT / BBR）"
while IFS= read -r f; do
    sed -i -E "s/option[[:space:]]+sfe_flow[[:space:]]+'[01]'/option sfe_flow '0'/" "$f"
    sed -i -E "s/option[[:space:]]+sfe_flow[[:space:]]+[01]/option sfe_flow '0'/" "$f"
    log "已处理：${f}"
done < <(find package -type f -path "*turboacc*" -name "turboacc" -path "*/etc/config/*" 2>/dev/null)

log "默认设置完成"
