#!/bin/bash
#
# diy-part1.sh —— feeds 更新前的自定义脚本
# 执行时机：./scripts/feeds update -a 之前
# 用途：调整 feeds.conf.default 软件源等 feed 级自定义操作
# 原则：优先使用 ImmortalWrt 源码自带软件包，因此默认不添加任何第三方 feed
#

set -e

echo "[diy-part1] 当前 feeds.conf.default 软件源："
cat feeds.conf.default

# 如需添加完整第三方 feed，可参考下方示例（默认注释，按需开启）：
# 注意：feed 方式会拉取整个仓库，耗时较长；
#       本项目仅在 diy-part2.sh 中按需浅克隆单个插件目录，更省时省流量。
#
# echo "src-git kenzok8_packages https://github.com/kenzok8/openwrt-packages.git" >> feeds.conf.default

# 位于国内网络环境时，可取消注释以下代理前缀以加速 GitHub 拉取：
# sed -i 's|https://github.com|https://ghproxy.com/https://github.com|g' feeds.conf.default

echo "[diy-part1] 处理完成"
