#!/bin/bash
# ==============================================================================
# resize_overlay.sh - 后置扩容 rootfs_data（/overlay）分区脚本
# --------------------------------------------------------------------------------
# 脚本职责：编译完成后，对生成的 squashfs combined IMG 镜像进行分区扩容，
#           将 rootfs 分区（overlay 所在分区）扩容至指定大小（默认 2G），
#           使系统运行时有足够可写空间用于安装软件包、存放缓存与保存配置。
# --------------------------------------------------------------------------------
# 原理：
#   ImmortalWrt combined 镜像包含两个分区：
#     - 分区 1：boot（grub + kernel）
#     - 分区 2：rootfs（squashfs 只读 + overlay 可写层）
#   overlay 可写空间 = rootfs 分区大小 - squashfs 实际占用大小
#   因此扩容 rootfs 分区即可增加 overlay 可写空间。
#
# 操作步骤：
#   1. 找到 combined-squashfs.img.gz 镜像
#   2. 解压得到 .img
#   3. 用 truncate 扩容镜像文件
#   4. 用 parted 扩展 rootfs 分区到目标大小
#   5. 重新 gzip 压缩
# --------------------------------------------------------------------------------
# 用法：bash resize_overlay.sh <镜像目录> [目标大小MB，默认2048]
# 运行位置：仓库根目录（由 build.yml 调用，传入 openwrt/bin/targets/x86/64）
# ==============================================================================
set -euo pipefail

# 镜像目录（由 build.yml 传入 openwrt/bin/targets/x86/64）
IMG_DIR="${1:?用法: resize_overlay.sh <镜像目录> [目标大小MB]}"
# 目标 rootfs 分区大小（MB），默认 2G = 2048MB
TARGET_SIZE_MB="${2:-2048}"

echo "========================================"
echo ">>> resize_overlay.sh 开始执行"
echo "    镜像目录：${IMG_DIR}"
echo "    目标 rootfs 分区大小：${TARGET_SIZE_MB} MB"
echo "========================================"

# 检查 parted 是否可用（扩容分区需要）
if ! command -v parted > /dev/null 2>&1; then
    echo ">>> 安装 parted（分区扩容所需）"
    sudo apt-get update -qq && sudo apt-get install -y -qq parted
fi

# 找到 combined squashfs 镜像（支持 .img 和 .img.gz）
IMG_FILE=$(find "${IMG_DIR}" -maxdepth 1 -name "*combined*squashfs*.img*" ! -name "*.vmdk*" ! -name "*.vhdx*" | head -1)

if [ -z "${IMG_FILE}" ]; then
    echo ">>> 错误：未找到 combined squashfs 镜像"
    ls -lh "${IMG_DIR}" 2>/dev/null || true
    exit 1
fi

echo ">>> 找到镜像：${IMG_FILE}"

# 如果是 .img.gz 则先解压
ORIG_FILE="${IMG_FILE}"
if [[ "${IMG_FILE}" == *.gz ]]; then
    echo ">>> 解压 ${IMG_FILE}"
    gunzip -k -f "${IMG_FILE}"
    IMG_FILE="${IMG_FILE%.gz}"
    echo "    解压完成：${IMG_FILE}"
fi

# 查看当前分区信息
echo ">>> 当前分区信息："
parted -s "${IMG_FILE}" unit MB print 2>/dev/null || true

# 获取 rootfs 分区号（通常是第 2 分区）
# ImmortalWrt x86 combined 镜像：分区 1 = boot，分区 2 = rootfs
ROOTFS_PART="2"

# 获取当前镜像大小（MB）
CURRENT_SIZE_MB=$(du -m "${IMG_FILE}" | cut -f1)
echo ">>> 当前镜像大小：${CURRENT_SIZE_MB} MB"

# 获取当前 rootfs 分区结束位置（MB）
ROOTFS_END_MB=$(parted -s "${IMG_FILE}" unit MB print 2>/dev/null | awk -v p="${ROOTFS_PART}" '$1==p {print $3}' | tr -d 'MB')
echo ">>> 当前 rootfs 分区结束位置：${ROOTFS_END_MB} MB"

# 计算新的镜像总大小 = boot分区 + 目标rootfs + 少量余量
# boot 分区一般 32MB，rootfs 目标 TARGET_SIZE_MB，总大小 = 32 + TARGET_SIZE_MB + 1（余量）
NEW_SIZE_MB=$((32 + TARGET_SIZE_MB + 1))
echo ">>> 新镜像总大小：${NEW_SIZE_MB} MB"

# 1. 扩容镜像文件
echo ">>> 扩容镜像文件至 ${NEW_SIZE_MB} MB"
truncate -s "${NEW_SIZE_MB}M" "${IMG_FILE}"

# 2. 扩展 rootfs 分区到目标大小
# parted resizepart 需要交互，用 -s 和 yes 管道
echo ">>> 扩展 rootfs 分区（分区 ${ROOTFS_PART}）至 ${TARGET_SIZE_MB} MB"
ROOTFS_NEW_END=$((32 + TARGET_SIZE_MB))
parted -s "${IMG_FILE}" resizepart "${ROOTFS_PART}" "${ROOTFS_NEW_END}MB" 2>/dev/null || \
    echo "yes" | parted "${IMG_FILE}" resizepart "${ROOTFS_PART}" "${ROOTFS_NEW_END}MB" 2>/dev/null || true

# 3. 验证分区信息
echo ">>> 扩容后分区信息："
parted -s "${IMG_FILE}" unit MB print 2>/dev/null || true

# 4. 重新 gzip 压缩（如果原来是 .gz）
if [[ "${ORIG_FILE}" == *.gz ]]; then
    echo ">>> 重新 gzip 压缩镜像"
    gzip -9 -f "${IMG_FILE}"
    echo "    压缩完成：${ORIG_FILE}"
    ls -lh "${ORIG_FILE}"
else
    echo ">>> 镜像未压缩，保持原样"
    ls -lh "${IMG_FILE}"
fi

echo ""
echo "========================================"
echo ">>> resize_overlay.sh 执行完成"
echo "    rootfs 分区已扩容至约 ${TARGET_SIZE_MB} MB（overlay 可写空间约 2G）"
echo "========================================"
