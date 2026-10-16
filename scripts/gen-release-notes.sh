#!/usr/bin/env bash
# =============================================================================
# 生成 GitHub Release 说明文件
#
# 自动填充：后台登录 IP / 登录账号 / 登录密码 / 内核版本 / 固件版本 / 已安装插件清单
# 插件清单只列应用插件与主题，不列 kmod 内核模块驱动与语言包。
#
# 用法：gen-release-notes.sh <bin目录> <源码根目录> <输出文件> <镜像文件名> <Tag> <仓库> <源码提交SHA> [发布文件名(gz)]
#      第 8 个参数为实际上传到 Release 的压缩文件名（通常为 <镜像名>.gz）；
#      省略时退化为直接发布原始 .img，并自动隐藏解压相关说明。
# =============================================================================
set -uo pipefail

BIN_DIR="${1:?缺少 bin 目录}"
SRC_DIR="${2:?缺少源码根目录}"
OUT_FILE="${3:?缺少输出文件路径}"
IMAGE_NAME="${4:-未知}"
TAG="${5:-未知}"
REPO="${6:-未知}"
SOURCE_SHA="${7:-未知}"
PUBLISH_NAME="${8:-$IMAGE_NAME}"

LAN_IP="${LAN_IP:-192.168.2.1}"
LAN_USER="root"
LAN_PASS="${ROOT_PASSWORD:-12345678}"

MANIFEST="$(find "$BIN_DIR" -maxdepth 1 -type f -name '*.manifest' | sort | head -1)"
PROFILES_JSON="$BIN_DIR/profiles.json"

# ---------- 内核版本 ----------
# manifest 中形如 "kernel - 6.6.157-1-<短哈希>"，这里只取 X.Y.Z 部分
KERNEL_VER=""
if [ -n "${MANIFEST:-}" ] && [ -f "$MANIFEST" ]; then
	KERNEL_VER="$(sed -n 's/^kernel[[:space:]]*-[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "$MANIFEST" | head -1)"
fi
if [ -z "$KERNEL_VER" ]; then
	# 兜底：从源码 include/kernel-<patchver> 中解析
	KPATCH="$(sed -n 's/^KERNEL_PATCHVER:=\(.*\)$/\1/p' "$SRC_DIR/target/linux/x86/Makefile" | tr -d ' \r')"
	if [ -n "$KPATCH" ] && [ -f "$SRC_DIR/include/kernel-$KPATCH" ]; then
		KSUF="$(grep -m1 -E "^LINUX_VERSION-$KPATCH[ \t]*=" "$SRC_DIR/include/kernel-$KPATCH" | sed 's/.*=[ \t]*//' | tr -d ' \r')"
		KERNEL_VER="${KPATCH}${KSUF}"
	fi
fi
KERNEL_VER="${KERNEL_VER:-未知}"

# ---------- 固件版本 ----------
FW_VER=""
FW_CODE=""
if [ -f "$PROFILES_JSON" ]; then
	FW_VER="$(jq -r '.version_number // empty' "$PROFILES_JSON" 2>/dev/null)"
	FW_CODE="$(jq -r '.version_code // empty' "$PROFILES_JSON" 2>/dev/null)"
fi
if [ -z "$FW_VER" ]; then
	FW_VER="$(awk -F'VERSION_NUMBER),' '/VERSION_NUMBER:.*VERSION_NUMBER),/ {print $2}' "$SRC_DIR/include/version.mk" 2>/dev/null | tr -d ')' | tr -d ' \r' | head -1)"
fi
FW_VER="${FW_VER:-24.10-SNAPSHOT}"
if [ -z "$FW_CODE" ]; then
	FW_CODE="$(git -C "$SRC_DIR" rev-parse --short HEAD 2>/dev/null || echo '')"
fi

# ---------- 已安装插件清单（仅应用插件，排除 kmod / 语言包 / 基础库） ----------
PLUGINS=""
if [ -n "${MANIFEST:-}" ] && [ -f "$MANIFEST" ]; then
	PLUGINS="$(
		awk '{print $1}' "$MANIFEST" |
			grep -E '^(luci-app-|luci-theme-)' |
			sort -u
	)"
	# 追加随固件打包的独立程序核心（非 LuCI 插件形态的应用）
	for core in smartdns ddnsto easytier mwan3 nlbwmon appfilter; do
		if grep -q "^${core} - " "$MANIFEST"; then
			PLUGINS="$(printf '%s\n%s' "$PLUGINS" "$core")"
		fi
	done
	PLUGINS="$(printf '%s\n' "$PLUGINS" | sed '/^$/d' | sort -u)"
fi

# ---------- 必选插件落地情况 ----------
REQUIRED_APPS="luci-app-smartdns luci-app-ddnsto luci-app-adguardhome luci-app-oaf luci-app-turboacc luci-app-mwan3 luci-theme-argon luci-app-argon-config luci-app-nlbwmon luci-app-easytier luci-app-openclash"
CHECK_TABLE=""
for app in $REQUIRED_APPS; do
	if [ -n "${MANIFEST:-}" ] && [ -f "$MANIFEST" ] && grep -q "^${app} - " "$MANIFEST"; then
		CHECK_TABLE="${CHECK_TABLE}| \`${app}\` | ✅ 已集成 |\n"
	else
		CHECK_TABLE="${CHECK_TABLE}| \`${app}\` | ❌ 缺失 |\n"
	fi
done

# ---------- 镜像校验值 ----------
# 校验值针对「用户实际下载到的文件」计算：
#   发布 .img.gz 时 -> 计算 .img.gz 的 sha256 与体积；
#   直接发布 .img 时 -> 计算 .img 的 sha256 与体积。
# 同时给出解压后 .img 的原始体积，便于用户确认磁盘空间。
#
# 体积一律用 stat 取「表观大小」(apparent size) 再换算 MiB，
# 不用 du —— du 返回的是实际占用块数，遇到稀疏文件会严重低估，
# 导致说明中出现“体积小于上限却提示超限”的自相矛盾文案。
mib_of() {
	stat -c '%s' "$1" 2>/dev/null | awk '{ printf "%d", $1 / 1048576 }'
}
if [ "$PUBLISH_NAME" != "$IMAGE_NAME" ]; then
	IS_GZIP=1
	SHA256="$(sha256sum "$BIN_DIR/$PUBLISH_NAME" 2>/dev/null | awk '{print $1}')"
	PUB_MIB="$(mib_of "$BIN_DIR/$PUBLISH_NAME")"
	RAW_MIB="$(mib_of "$BIN_DIR/$IMAGE_NAME")"
else
	IS_GZIP=0
	SHA256="$(sha256sum "$BIN_DIR/$IMAGE_NAME" 2>/dev/null | awk '{print $1}')"
	PUB_MIB="$(mib_of "$BIN_DIR/$IMAGE_NAME")"
	RAW_MIB="$PUB_MIB"
fi
BUILD_TIME="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# ---------- 输出 ----------
{
	echo "# ImmortalWrt X86_64 固件（${TAG}）"
	echo ""
	echo "> 源码分支：\`immortalwrt/immortalwrt @ openwrt-24.10\`"
	echo "> 源码提交：\`${SOURCE_SHA}\`"
	echo "> 编译时间：${BUILD_TIME}"
	echo ""
	if [ "$IS_GZIP" = "1" ]; then
		echo "> **注意**：本固件 overlay 可写分区为 2 GiB，未压缩镜像 \`.img\` 约 ${RAW_MIB:-?} MiB，"
		echo "> 超过 GitHub Release 单文件 2 GiB 上限，故以 gzip 压缩包形式发布"
		echo "> （压缩后约 ${PUB_MIB:-?} MiB）。下载后请先 \`gunzip\` 解压，再按下方「刷写与升级」操作。"
		echo ""
	fi
	echo "## 一、固件信息"
	echo ""
	echo "| 项目 | 内容 |"
	echo "| --- | --- |"
	echo "| 后台登录地址 | http://${LAN_IP} |"
	echo "| 后台登录账号 | ${LAN_USER} |"
	echo "| 后台登录密码 | ${LAN_PASS} |"
	echo "| 内核版本 | ${KERNEL_VER} |"
	echo "| 固件版本 | ImmortalWrt ${FW_VER}${FW_CODE:+ (${FW_CODE})} |"
	echo "| 适用架构 | X86_64（x86/64 generic） |"
	echo "| 镜像格式 | squashfs-combined.img（rootfs 分区 2048 MiB，约 2G 可写 overlay） |"
	if [ "$IS_GZIP" = "1" ]; then
		echo "| 固件文件（下载） | \`${PUBLISH_NAME}\`（${PUB_MIB:-?} MiB，gzip 压缩包） |"
		echo "| 解压后镜像 | \`${IMAGE_NAME}\`（${RAW_MIB:-?} MiB） |"
		echo "| SHA256（压缩包） | \`${SHA256:-未计算}\` |"
	else
		echo "| 固件文件 | \`${IMAGE_NAME}\`（${PUB_MIB:-?} MiB） |"
		echo "| SHA256 | \`${SHA256:-未计算}\` |"
	fi
	echo ""
	echo "## 二、已安装插件清单"
	echo ""
	if [ -n "$PLUGINS" ]; then
		printf '%s\n' "$PLUGINS" | while IFS= read -r p; do
			[ -n "$p" ] && echo "- ${p}"
		done
	else
		echo "- （未能读取固件 manifest，请查看工作流日志）"
	fi
	echo ""
	echo "### 必选插件落地核对"
	echo ""
	echo "| 插件 | 状态 |"
	echo "| --- | --- |"
	printf '%b' "$CHECK_TABLE"
	echo ""
	echo "## 三、刷写与升级"
	echo ""
	if [ "$IS_GZIP" = "1" ]; then
		echo "1. 下载 \`${PUBLISH_NAME}\` 并校验完整性（可选）："
		echo ""
		echo "   \`\`\`bash"
		echo "   sha256sum ${PUBLISH_NAME}   # 应等于本页 SHA256"
		echo "   \`\`\`"
		echo ""
		echo "2. 解压得到原始镜像（2G overlay 使 .img 约 ${RAW_MIB:-?} MiB，请预留足够磁盘空间）："
		echo ""
		echo "   \`\`\`bash"
		echo "   gunzip -k ${PUBLISH_NAME}    # 得到 ${IMAGE_NAME}"
		echo "   \`\`\`"
		echo ""
		echo "3. 将 \`${IMAGE_NAME}\` 写入目标磁盘（整盘写入，不要只写某个分区），例如："
		echo ""
		echo "   \`\`\`bash"
		echo "   dd if=${IMAGE_NAME} of=/dev/sdX bs=4M conv=fsync status=progress"
		echo "   \`\`\`"
		echo ""
		echo "4. 首次启动约 1-2 分钟，浏览器访问 http://${LAN_IP} ，账号 ${LAN_USER} / 密码 ${LAN_PASS}。"
		echo "5. 首次登录后请立即修改默认密码，并在「系统 - 备份/升级」中确认 overlay 剩余空间。"
	else
		echo "1. 将 \`${IMAGE_NAME}\` 写入目标磁盘（整盘写入，不要只写某个分区），例如："
		echo ""
		echo "   \`\`\`bash"
		echo "   dd if=${IMAGE_NAME} of=/dev/sdX bs=4M conv=fsync status=progress"
		echo "   \`\`\`"
		echo ""
		echo "2. 首次启动约 1-2 分钟，浏览器访问 http://${LAN_IP} ，账号 ${LAN_USER} / 密码 ${LAN_PASS}。"
		echo "3. 首次登录后请立即修改默认密码，并在「系统 - 备份/升级」中确认 overlay 剩余空间。"
	fi
	echo ""
	echo "## 四、已集成能力速览"
	echo ""
	echo "- SmartDNS：DNS 加速与分流，与 AdGuardHome 可组合使用（注意 53 端口占用）"
	echo "- DDNSTO：内网穿透（中文界面）"
	echo "- AdGuardHome：DNS 级广告过滤，核心已随固件打包（\`/usr/bin/AdGuardHome\`）"
	echo "- OAF：应用识别与上网行为管控（含 kmod-oaf 内核模块）"
	echo "- TurboAcc：软件流量分载 + 全锥型 NAT + BBR 拥塞控制（firewall4 适配版）"
	echo "- Mwan3：多线负载均衡与故障切换"
	echo "- nlbwmon：按主机/协议统计的带宽监控"
	echo "- EasyTier：去中心化异地组网"
	echo "- OpenClash：代理插件（本固件仅集成此一个代理类插件）"
	echo "- argon：系统默认 LuCI 主题（含 luci-app-argon-config 外观配置）"
	echo "- 时区：Asia/Shanghai（CST-8）"
	echo ""
} >"$OUT_FILE"

echo "Release 说明已生成：$OUT_FILE"
