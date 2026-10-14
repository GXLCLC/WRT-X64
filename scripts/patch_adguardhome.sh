#!/bin/bash
# scripts/patch_adguardhome.sh
# 独立补丁：移除AdGuardHome go.mod中新语法 tool / ignore，适配ImmortalWrt 24.10 Go1.21
set -e

echo "===== 开始 AdGuardHome go.mod 补丁 ====="
ADG_PATH="package/third-party/adguardhome"
if [ -d "${ADG_PATH}" ]; then
    MOD_FILE="${ADG_PATH}/src/go.mod"
    if [ -f "${MOD_FILE}" ]; then
        echo "删除 go.mod tool 行"
        sed -i '/^tool /d' "${MOD_FILE}"
        echo "删除 go.mod ignore 行"
        sed -i '/^ignore /d' "${MOD_FILE}"
        echo "✅ AdGuardHome补丁完成"
    else
        echo "⚠️ 未找到 src/go.mod，跳过补丁"
    fi
else
    echo "⚠️ adguardhome目录不存在，跳过补丁"
fi
