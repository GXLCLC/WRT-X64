#!/usr/bin/env bash
# =============================================================================
# 固件产物校验脚本（文件存在性 / 命名 / 镜像格式 / 分区信息）
#
# 校验项：
#   1. 产物目录存在，且能在其中匹配到 squashfs-combined.img
#   2. 匹配结果唯一（排除 combined-efi.img 等多余产物）
#   3. 文件名以 "-squashfs-combined.img" 结尾（命名检查）
#   4. 文件非空（存在性检查）
#   5. 镜像内 rootfs 分区的文件系统魔数为 squashfs 的 "hsqs"（镜像格式检查）
#   6. rootfs 分区大小已扩增至 2048 MiB，即 2G overlay 可写空间（分区信息检查）
#   7. 必选软件包全部打进固件 manifest（插件完整性检查）
#   8. AdGuardHome 核心二进制已随固件打包
#
# 用法：verify-artifacts.sh <bin目录> <固件源码根目录> <仓库根目录>
# 成功：退出码 0，并输出 IMAGE_PATH=<绝对路径>、IMAGE_NAME=<文件名>
# 失败：退出码 1，并输出「检测命令 / 期望值 / 实际值 / 可能原因」
# =============================================================================
set -uo pipefail

BIN_DIR="${1:-bin/targets/x86/64}"
SRC_DIR="${2:-immortalwrt}"
REPO_DIR="${3:-$(pwd)}"

EXPECTED_SUFFIX="squashfs-combined.img"	# 期望的镜像命名后缀
EXPECTED_ROOTFS_MIB=2048		# 期望的 rootfs 分区大小（MiB）= 2G overlay 可写空间
EXPECTED_MAGIC="hsqs"			# squashfs 文件系统魔数
SIZE_TOLERANCE_MIB=1			# 分区大小允许的误差（MiB）
REQUIRED_LIST="$REPO_DIR/config/required-packages.txt"

FAILED=0
fail() {
	printf '%s\n' "$1"
	FAILED=1
}

echo "==================== 固件产物校验开始 ===================="
echo "产物目录   : $BIN_DIR"
echo "源码目录   : $SRC_DIR"
echo "期望命名   : *-${EXPECTED_SUFFIX}"
echo "期望分区   : rootfs = ${EXPECTED_ROOTFS_MIB} MiB"
echo "期望格式   : squashfs（魔数 ${EXPECTED_MAGIC}）"
echo "----------------------------------------------------------"

# ---------- 检查 1：产物目录存在 ----------
if [ ! -d "$BIN_DIR" ]; then
	echo "【检查 1】产物目录存在性 —— 失败"
	echo "  检测命令 : test -d $BIN_DIR"
	echo "  期望值   : 目录存在"
	echo "  实际值   : 目录不存在"
	echo "  可能原因 : 编译在生成镜像阶段之前就中断；或 TARGET 配置不是 x86/64。"
	echo "  建议修复 : 检查编译日志中 'Configuring...' / 'Generating images' 阶段是否报错。"
	echo "::error::产物目录不存在：$BIN_DIR"
	exit 1
fi
echo "【检查 1】产物目录存在性 —— 通过"

# ---------- 检查 2/3：镜像匹配与命名 ----------
echo "【检查 2】产物匹配 —— 检测中"
echo "  检测命令 : find $BIN_DIR -maxdepth 1 -type f -name '*-${EXPECTED_SUFFIX}'"
echo "  目录实际内容："
find "$BIN_DIR" -maxdepth 1 -type f -printf '      %f  (%s bytes)\n' 2>/dev/null | sort

mapfile -t IMAGES < <(find "$BIN_DIR" -maxdepth 1 -type f -name "*-${EXPECTED_SUFFIX}" | sort)

if [ "${#IMAGES[@]}" -eq 0 ]; then
	echo "  期望值   : 匹配到至少 1 个 *-${EXPECTED_SUFFIX}"
	echo "  实际值   : 匹配到 0 个"
	echo "  可能原因 :"
	echo "             1) rootfs 格式未选中 squashfs（CONFIG_TARGET_ROOTFS_SQUASHFS 未生效）；"
	echo "             2) 未选中 GRUB_IMAGES，导致没有 combined 分区镜像；"
	echo "             3) 镜像生成阶段失败，产物未落盘。"
	echo "  建议修复 : 检查 config/X86_64.config 中 TARGET_ROOTFS_SQUASHFS / GRUB_IMAGES 设置，"
	echo "             并在日志中搜索 'Image generation' / 'gen_image_generic' 相关报错。"
	echo "::error::未找到 ${EXPECTED_SUFFIX} 产物"
	exit 1
fi

if [ "${#IMAGES[@]}" -gt 1 ]; then
	echo "  期望值   : 匹配结果唯一（1 个）"
	echo "  实际值   : 匹配到 ${#IMAGES[@]} 个 —— 无法确定唯一发布对象"
	echo "  可能原因 : 产物目录中存在历史残留文件（例如上一次编译未清理）。"
	echo "  建议修复 : 在编译前执行 make clean / 删除 bin 目录后重试。"
	echo "::error::匹配到多个 ${EXPECTED_SUFFIX} 产物，无法确定唯一发布对象"
	for i in "${IMAGES[@]}"; do echo "         - $i"; done
	exit 1
fi

IMAGE_PATH="${IMAGES[0]}"
IMAGE_NAME="$(basename "$IMAGE_PATH")"
case "$IMAGE_NAME" in
	*"-${EXPECTED_SUFFIX}")
		echo "【检查 3】镜像命名 —— 通过（$IMAGE_NAME）"
		;;
	*)
		echo "【检查 3】镜像命名 —— 失败"
		echo "  检测命令 : case \$IMAGE_NAME in *-${EXPECTED_SUFFIX}) ;;"
		echo "  期望值   : 文件名以 -${EXPECTED_SUFFIX} 结尾"
		echo "  实际值   : $IMAGE_NAME"
		echo "  可能原因 : 上游镜像命名规则变更。"
		echo "::error::镜像命名不符合期望：$IMAGE_NAME"
		exit 1
		;;
esac

# ---------- 检查 4：文件非空 ----------
IMAGE_SIZE="$(stat -c '%s' "$IMAGE_PATH" 2>/dev/null || echo 0)"
if [ "${IMAGE_SIZE:-0}" -le 0 ]; then
	echo "【检查 4】文件存在性与大小 —— 失败"
	echo "  检测命令 : stat -c '%s' $IMAGE_PATH"
	echo "  期望值   : 文件大小 > 0 字节"
	echo "  实际值   : ${IMAGE_SIZE} 字节"
	echo "::error::镜像文件为空：$IMAGE_PATH"
	exit 1
fi
echo "【检查 4】文件存在性与大小 —— 通过（${IMAGE_SIZE} 字节）"

# ---------- 检查 5/6：分区表与 rootfs 分区 ----------
echo "【检查 5】镜像内分区信息与文件系统格式 —— 检测中"
echo "  检测命令 : 解析镜像首扇区 MBR 分区表 + 读取 rootfs 分区起始 4 字节魔数"

PT_INFO="$(python3 - "$IMAGE_PATH" <<'PY'
import struct
import sys

path = sys.argv[1]
with open(path, 'rb') as fh:
    mbr = fh.read(512)
    if len(mbr) != 512 or mbr[510:512] != b'\x55\xAA':
        print("MBR_SIGNATURE=missing")
        sys.exit(0)
    print("MBR_SIGNATURE=present")

    parts = []
    for i in range(4):
        entry = mbr[0x1BE + i * 16: 0x1BE + (i + 1) * 16]
        ptype = entry[4]
        start = struct.unpack('<I', entry[8:12])[0]
        count = struct.unpack('<I', entry[12:16])[0]
        if count:
            parts.append((i + 1, ptype, start, count))

    print("PARTITION_COUNT=%d" % len(parts))
    for idx, ptype, start, count in parts:
        print("PARTITION_%d_TYPE=0x%02X" % (idx, ptype))
        print("PARTITION_%d_START_LBA=%d" % (idx, start))
        print("PARTITION_%d_SIZE_MIB=%d" % (idx, count * 512 // (1024 * 1024)))

    if parts:
        idx, _ptype, start, count = max(parts, key=lambda p: p[3])
        fh.seek(start * 512)
        magic = fh.read(4)
        print("ROOTFS_PARTITION_INDEX=%d" % idx)
        print("ROOTFS_PARTITION_SIZE_MIB=%d" % (count * 512 // (1024 * 1024)))
        # 魔数按「可打印 ASCII / 非可打印」双格式输出：
        # ASCII 形式用于字符串比较，HEX 形式用于失败时定位真实字节，避免把二进制字节
        # 直接 eval 进 shell 环境导致解析异常。
        magic_ascii = "".join(chr(b) if 32 <= b < 127 else "." for b in magic)
        print("ROOTFS_PARTITION_MAGIC=%s" % magic_ascii)
        print("ROOTFS_PARTITION_MAGIC_HEX=%s" % magic.hex())
PY
)"

eval "$PT_INFO"

if [ "${MBR_SIGNATURE:-missing}" != "present" ]; then
	echo "  期望值   : 镜像首扇区含合法 MBR 签名 0x55AA"
	echo "  实际值   : MBR_SIGNATURE=${MBR_SIGNATURE:-missing}"
	echo "  可能原因 : 该文件不是磁盘镜像（例如误取到 tar.gz 或 zImage）。"
	echo "::error::镜像缺少 MBR 签名，格式不符合期望"
	exit 1
fi

echo "  分区表解析结果："
echo "    MBR 签名            : ${MBR_SIGNATURE}（通过）"
echo "    分区数量            : ${PARTITION_COUNT:-0}"
for i in $(seq 1 "${PARTITION_COUNT:-0}"); do
	eval "ptype=\${PARTITION_${i}_TYPE:-?}; pstart=\${PARTITION_${i}_START_LBA:-?}; psize=\${PARTITION_${i}_SIZE_MIB:-?}"
	echo "    分区 ${i}              : type=${ptype} start_lba=${pstart} size=${psize} MiB"
done
echo "    rootfs 分区序号     : ${ROOTFS_PARTITION_INDEX:-?}"
echo "    rootfs 分区大小     : ${ROOTFS_PARTITION_SIZE_MIB:-?} MiB"
echo "    rootfs 分区魔数     : ${ROOTFS_PARTITION_MAGIC:-?}（hex: ${ROOTFS_PARTITION_MAGIC_HEX:-?}）"

# ---------- 检查 6 前置：源码 .config 里的 rootfs 分区大小是否按预期配置 ----------
# 这是「分区信息检查」的配置侧依据：先确认编译参数真的写成了 2048，
# 再去核对镜像里分区表解析出来的实际值，两侧都满足才算 overlay 扩至 2G。
SRC_CONFIG="$SRC_DIR/.config"
CFG_ROOTFS_MIB=""
if [ -f "$SRC_CONFIG" ]; then
	CFG_ROOTFS_MIB="$(sed -n 's/^CONFIG_TARGET_ROOTFS_PARTSIZE=//p' "$SRC_CONFIG" | tr -d ' \r' | head -1)"
fi
if [ "$CFG_ROOTFS_MIB" != "$EXPECTED_ROOTFS_MIB" ]; then
	fail "【检查 6-0】源码 rootfs 分区大小配置 —— 失败
  检测命令 : sed -n 's/^CONFIG_TARGET_ROOTFS_PARTSIZE=//p' $SRC_CONFIG
  期望值   : CONFIG_TARGET_ROOTFS_PARTSIZE=${EXPECTED_ROOTFS_MIB}
  实际值   : CONFIG_TARGET_ROOTFS_PARTSIZE=${CFG_ROOTFS_MIB:-<未设置>}
  可能原因 : defconfig 覆盖了 config/X86_64.config 中的设置，或该行被误删。
  建议修复 : 确认 config/X86_64.config 中 CONFIG_TARGET_ROOTFS_PARTSIZE=2048。"
else
	echo "【检查 6-0】源码 rootfs 分区大小配置 —— 通过（${CFG_ROOTFS_MIB} MiB）"
fi

# 分区大小检查（对应 2G overlay 可写空间）
ACTUAL_ROOTFS_MIB="${ROOTFS_PARTITION_SIZE_MIB:-0}"
if [ $((ACTUAL_ROOTFS_MIB - EXPECTED_ROOTFS_MIB)) -gt $SIZE_TOLERANCE_MIB ] ||
   [ $((EXPECTED_ROOTFS_MIB - ACTUAL_ROOTFS_MIB)) -gt $SIZE_TOLERANCE_MIB ]; then
	fail "【检查 6】overlay 可写分区大小 —— 失败
  检测命令 : 解析 MBR 分区表中 rootfs 分区的扇区数 x 512
  期望值   : ${EXPECTED_ROOTFS_MIB} MiB（允许误差 ±${SIZE_TOLERANCE_MIB} MiB）
  实际值   : ${ACTUAL_ROOTFS_MIB} MiB
  可能原因 : CONFIG_TARGET_ROOTFS_PARTSIZE 未生效（被 defconfig 覆盖或值写错）。
  建议修复 : 确认 config/X86_64.config 中 CONFIG_TARGET_ROOTFS_PARTSIZE=2048 且未被其它配置项覆盖。"
else
	echo "【检查 6】overlay 可写分区大小 —— 通过（${ACTUAL_ROOTFS_MIB} MiB）"
fi

# 文件系统魔数检查（镜像格式）
if [ "${ROOTFS_PARTITION_MAGIC:-}" != "$EXPECTED_MAGIC" ]; then
	fail "【检查 5】镜像内 rootfs 文件系统格式 —— 失败
  检测命令 : 读取 rootfs 分区起始 4 字节
  期望值   : ${EXPECTED_MAGIC}（squashfs 魔数）
  实际值   : ${ROOTFS_PARTITION_MAGIC:-<空>}（hex: ${ROOTFS_PARTITION_MAGIC_HEX:-<空>}）
  可能原因 : 1) 固件实际为 ext4 格式；2) 分区偏移解析错误；3) 镜像被额外压缩过。
  建议修复 : 确认 CONFIG_TARGET_ROOTFS_SQUASHFS=y 且未选 ext4fs。"
else
	echo "【检查 5】镜像内 rootfs 文件系统格式 —— 通过（squashfs）"
fi

# ---------- 检查 7：必选软件包是否真的打进固件 ----------
echo "【检查 7】固件内必选软件包清单 —— 检测中"
MANIFESTS=("$BIN_DIR"/*.manifest)
if [ ! -f "${MANIFESTS[0]}" ]; then
	echo "  检测命令 : ls $BIN_DIR/*.manifest"
	echo "  期望值   : 存在固件 manifest（软件包清单）"
	echo "  实际值   : 未找到"
	echo "  可能原因 : 镜像生成阶段未产出 manifest，或产物目录被清理。"
	echo "::error::未找到固件 manifest，无法核对插件完整性"
	FAILED=1
else
	MANIFEST="${MANIFESTS[0]}"
	printf '  manifest   : %s\n' "$(basename "$MANIFEST")"
	if ! bash "$REPO_DIR/scripts/check-packages.sh" manifest "$MANIFEST" "$REQUIRED_LIST"; then
		fail "【检查 7】固件内必选软件包清单 —— 失败（详见上方输出）"
	else
		echo "【检查 7】固件内必选软件包清单 —— 通过"
	fi
fi

# ---------- 检查 8：AdGuardHome 核心是否随固件打包 ----------
echo "【检查 8】AdGuardHome 核心二进制随固件打包 —— 检测中"
ADG_BIN="$SRC_DIR/files/usr/bin/AdGuardHome"
echo "  检测命令 : test -x $ADG_BIN"
if [ ! -f "$ADG_BIN" ]; then
	fail "【检查 8】AdGuardHome 核心 —— 失败
  期望值   : 源码树 files/usr/bin/AdGuardHome 存在且可执行（会被并入固件 rootfs）
  实际值   : 文件不存在
  可能原因 : 核心下载步骤被跳过或下载失败。
  建议修复 : 查看工作流“预置 AdGuardHome 核心”步骤的日志。"
else
	printf '  实际值   : %s（%s 字节）\n' "$ADG_BIN" "$(stat -c '%s' "$ADG_BIN")"
	if [ ! -x "$ADG_BIN" ]; then
		fail "【检查 8】AdGuardHome 核心 —— 文件存在但不可执行，期望权限 0755"
	else
		echo "【检查 8】AdGuardHome 核心二进制随固件打包 —— 通过"
	fi
fi

# ---------- 汇总 ----------
echo "----------------------------------------------------------"
if [ "$FAILED" -ne 0 ]; then
	echo "==================== 固件产物校验失败 ===================="
	echo "::error::固件产物校验未全部通过，工作流终止"
	exit 1
fi

echo "==================== 固件产物校验全部通过 ===================="
printf 'IMAGE_PATH=%s\n' "$(readlink -f "$IMAGE_PATH")"
printf 'IMAGE_NAME=%s\n' "$IMAGE_NAME"
printf 'ROOTFS_PARTITION_MIB=%s\n' "$ACTUAL_ROOTFS_MIB"
exit 0
