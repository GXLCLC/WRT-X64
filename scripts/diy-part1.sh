#!/bin/bash
# 在 feeds 更新前执行：添加第三方源、克隆插件

echo "=== DIY Part 1: Pre-compile Customization ==="

# 1. 添加 iStore 官方源
if ! grep -q "src-git istore" feeds.conf.default; then
    echo "src-git istore https://github.com/linkease/istore;main" >> feeds.conf.default
fi

# 2. 添加 OAf 应用过滤 Feed
if ! grep -q "src-git oaf" feeds.conf.default; then
    echo "src-git oaf https://github.com/jjm2473/OpenAppFilter.git;dev6" >> feeds.conf.default
fi

# 3. 克隆 EasyTier LuCI 插件
rm -rf package/luci-app-easytier
git clone --depth 1 https://github.com/EasyTier/luci-app-easytier.git package/luci-app-easytier

echo "=== DIY Part 1 Completed ==="
