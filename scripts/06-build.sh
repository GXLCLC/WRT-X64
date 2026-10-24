#!/usr/bin/env bash
# ==============================================================================
# 步骤六：编译（严格模式：任意包报错立即终止整体编译）
# 失败时只产出精简错误摘要 build-error.log，避免日志过载
# ==============================================================================
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
enter_source

JOBS="$(nproc)"
LOG="build.log"
ERR="build-error.log"
rm -f "$LOG" "$ERR"

step "预下载依赖源码包（配合 DL 缓存加速）"
if ! make download -j"$JOBS" V=s 2>&1 | tee "$LOG"; then
    die "依赖源码下载失败，请检查 build.log 中的 Download failed 条目与网络/上游地址可用性"
fi
# 清理不完整下载（小于 1KB 基本都是下载失败残留），再补一次
find dl -type f -size -1024c -print -delete 2>/dev/null | sed 's/^/  清理不完整下载：/' || true
make download -j"$JOBS" V=s >/dev/null 2>&1 || true

step "开始编译固件（-j${JOBS} V=s，严格模式）"
set +e
make -j"$JOBS" V=s 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[0]}
set -e

if [[ "$RC" -ne 0 ]]; then
    warn "多核编译失败（exit=${RC}），改用单线程复现，精准定位首个出错的包"
    set +e
    make -j1 V=s 2>&1 | tee -a "$LOG"
    RC2=${PIPESTATUS[0]}
    set -e
    [[ "$RC2" -eq 0 ]] && { log "单线程重编通过（多为并发导致的偶发失败）"; exit 0; }
fi

if [[ "$RC" -ne 0 ]]; then
    step "编译失败，生成精简错误摘要"
    {
        echo "========== 编译失败：错误定位摘要 =========="
        echo "时间：$(date '+%F %T %Z')"
        echo "退出码：${RC}"
        echo
        echo "---- 关键错误行（ERROR / error: / 缺失文件 / 缺失规则 / 包冲突）----"
        grep -nE "ERROR[: ]|error:|Error [0-9]+|No such file or directory|No rule to make target|conflicts with|is not installed|failed|make.*\*\*\*" "$LOG" \
            | tail -80
        echo
        echo "---- 最后 60 行日志上下文 ----"
        tail -n 60 "$LOG"
    } > "$ERR"
    cat "$ERR"
    die "编译失败：详情见 ${ERR}（工作流只会上传该文件，不会上传完整日志）"
fi

step "编译成功"
