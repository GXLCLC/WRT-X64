#!/bin/sh
# ============================================================
# iStoreOS 系统配置修改脚本
# 通过 uci-defaults 机制在首次启动时自动执行
# 修改内容：LAN IP、登录密码、主机名
# ============================================================

# 等待网络配置就绪
sleep 5

# 1. 设置 LAN IP 为 192.168.2.1
uci set network.lan.ipaddr='192.168.2.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network

# 2. 设置 root 密码为 asdfghjkL666666
PASSWORD_HASH=$(openssl passwd -1 "asdfghjkL666666")
sed -i "s|^root:.*|root:${PASSWORD_HASH}:0:0:99999:7:::|" /etc/shadow

# 3. 设置主机名
uci set system.@system[0].hostname='iStoreOS-X86'
uci commit system

# 4. 设置时区为 Asia/Shanghai
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system

# 5. 设置 Argon 为默认 LuCI 主题
uci set luci.themes.Argon='/luci-static/argon'
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci

# 6. 重启网络使 LAN IP 生效
/etc/init.d/network restart

echo "=== System config customization applied ==="
exit 0