#!/usr/bin/env bash
# =============================================================================
# 必选软件包校验脚本
#
# 两种模式：
#   config   —— 编译前检查 .config，确认所需包已被 defconfig 成功解析（依赖可达）
#   manifest —— 编译后检查固件 manifest，确认所需包真的被打进了固件
#
# 用法：check-packages.sh <config|manifest> <待检查文件> [必选清单文件]
# 退出码：0 = 全部命中；1 = 有缺失（打印缺失项/期望值/实际值/可能原因）
# =============================================================================
set -uo pipefail

MODE="${1:-config}"
TARGET_FILE="${2:-}"
LIST_FILE="${3:-config/required-packages.txt}"

if [ -z "$TARGET_FILE" ]; then
	echo "::error::用法: check-packages.sh <config|manifest> <待检查文件> [必选清单]"
	exit 1
fi
if [ ! -f "$TARGET_FILE" ]; then
	echo "::error::待检查文件不存在：$TARGET_FILE"
	exit 1
fi
if [ ! -f "$LIST_FILE" ]; then
	echo "::error::必选包清单不存在：$LIST_FILE"
	exit 1
fi

missing=()
total=0

while IFS= read -r line; do
	# 去掉注释与空白，得到纯包名
	pkg="${line%%#*}"
	pkg="$(printf '%s' "$pkg" | tr -d ' \t\r')"
	[ -z "$pkg" ] && continue
	total=$((total + 1))

	case "$MODE" in
		config)
			# .config 中形如 CONFIG_PACKAGE_<包名>=y
			grep -q "^CONFIG_PACKAGE_${pkg}=y\$" "$TARGET_FILE" || missing+=("$pkg")
			;;
		manifest)
			# 固件 manifest 中形如 <包名> - <版本>
			grep -q "^${pkg} - " "$TARGET_FILE" || missing+=("$pkg")
			;;
		*)
			echo "::error::未知校验模式：$MODE（仅支持 config / manifest）"
			exit 1
			;;
	esac
done <"$LIST_FILE"

if [ "${#missing[@]}" -gt 0 ]; then
	echo ""
	echo "==================== 必选软件包校验失败 ===================="
	printf '校验模式   : %s\n' "$MODE"
	printf '校验文件   : %s\n' "$TARGET_FILE"
	printf '必选清单   : %s\n' "$LIST_FILE"
	if [ "$MODE" = "config" ]; then
		printf '检测命令   : grep -E "^CONFIG_PACKAGE_<包名>=y$" %s\n' "$TARGET_FILE"
	else
		printf '检测命令   : grep -E "^<包名> - " %s\n' "$TARGET_FILE"
	fi
	printf '期望值     : %s 个必选包全部命中\n' "$total"
	printf '实际值     : 命中 %s 个，缺失 %s 个\n' "$((total - ${#missing[@]}))" "${#missing[@]}"
	echo "缺失清单   :"
	for m in "${missing[@]}"; do
		printf '             - %s\n' "$m"
	done
	echo "可能原因   :"
	echo "             1) 上游仓库分支/路径变更，或第三方插件未成功拉取到预期目录；"
	echo "             2) 依赖不满足，被 defconfig 自动剔除（例如 kmod 与源码内核不兼容）；"
	echo "             3) package 名与清单不一致（清单里写的是源码目录名或旧包名）。"
	echo "建议修复   :"
	echo "             1) 打开本次运行的日志，查看“拉取第三方插件”步骤的路径校验输出；"
	echo "             2) 核对 config/X86_64.config 与 config/required-packages.txt 的包名；"
	echo "             3) 若确实不再需要该包，请同步修改 required-packages.txt。"
	echo "==========================================================="
	echo "::error::必选软件包校验失败，缺失：${missing[*]}"
	exit 1
fi

printf '必选软件包校验通过：模式=%s，共 %s 个包全部命中（文件=%s）\n' "$MODE" "$total" "$TARGET_FILE"
exit 0
