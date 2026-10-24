#!/usr/bin/env bash
# ==============================================================================
# 步骤二：强制把 X86 平台内核切换到 6.12 主线（大雕 master 默认可能是 6.18）
# 同时打印内核版本，供工作流与发布说明使用
# ==============================================================================
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
enter_source

KERNEL_WANT="6.12"

step "定位 X86 目标内核定义文件"
mapfile -t MK_FILES < <(find target/linux/x86 -maxdepth 2 -name Makefile -type f | sort)
[[ "${#MK_FILES[@]}" -gt 0 ]] || die "未找到 target/linux/x86 下的 Makefile（源码结构异常或分支不对）"

step "打印切换前的内核版本"
for f in "${MK_FILES[@]}"; do
    v=$(grep -m1 -E '^\s*KERNEL_(TESTING_)?PATCHVER' "$f" 2>/dev/null || true)
    [[ -n "$v" ]] && log "$(printf '%-40s %s' "$f" "$v")"
done

step "执行内核版本切换 -> ${KERNEL_WANT}"
for f in "${MK_FILES[@]}"; do
    if grep -qE '^\s*KERNEL_PATCHVER' "$f"; then
        sed -i -E "s/^(\s*KERNEL_PATCHVER\s*:?=\s*).*/\1${KERNEL_WANT}/" "$f"
    fi
    if grep -qE '^\s*KERNEL_TESTING_PATCHVER' "$f"; then
        sed -i -E "s/^(\s*KERNEL_TESTING_PATCHVER\s*:?=\s*).*/\1${KERNEL_WANT}/" "$f"
    fi
done

step "校验切换结果（任一处不为 6.12 即终止）"
for f in "${MK_FILES[@]}"; do
    while read -r kv; do
        val="${kv##*=}"; val="${val//:/}"; val="${val// /}"
        [[ -z "$val" ]] && continue
        [[ "$val" == "$KERNEL_WANT" ]] || die "内核切换失败：$f -> $kv（期望 ${KERNEL_WANT}）"
        log "$(printf '%-40s = %s' "$f" "$val")"
    done < <(grep -E '^\s*KERNEL_(TESTING_)?PATCHVER' "$f" || true)
done

step "校验源码是否自带 6.12 内核支持文件"
[[ -f "include/kernel-${KERNEL_WANT}" ]] || die "源码缺少 include/kernel-${KERNEL_WANT}，
  说明该分支已不再维护 ${KERNEL_WANT} 内核。修复建议：
    1) 更换 LEDE 分支/提交到仍支持 6.12 的版本；
    2) 或自行补齐 include/kernel-6.12 与 target/linux/x86/config-6.12 后重新触发。"
[[ -f "target/linux/x86/config-${KERNEL_WANT}" ]] || warn "未找到 target/linux/x86/config-${KERNEL_WANT}（x86 可能沿用 generic 配置，如编译报 config 缺失请手动补齐）"

step "解析完整内核版本号（主线 + 补丁级）"
LINUX_SUFFIX=$(grep -m1 -E "^\s*LINUX_VERSION-${KERNEL_WANT}\s*=" "include/kernel-${KERNEL_WANT}" \
                | sed -E 's/.*=\s*//' | tr -d ' ')
KERNEL_FULL="${KERNEL_WANT}${LINUX_SUFFIX}"
echo "$KERNEL_FULL" > .kernel-version

echo
echo "==================================================================="
echo "  当前 X86 源码内核版本： ${KERNEL_FULL}"
echo "  （目标内核主线：${KERNEL_WANT} ；版本文件已写入 .kernel-version）"
echo "==================================================================="
[[ "$KERNEL_FULL" == 6.12.* ]] || die "内核版本校验失败：解析结果为 ${KERNEL_FULL}，不是 6.12 内核"
