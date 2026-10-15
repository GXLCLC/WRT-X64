#!/usr/bin/env bash
# ================================================================
# scripts/firmware-info.sh —— 收集固件信息，生成 Release 正文文件
#
#【职责（只干这一件事）】
#   编译成功后，从编译产物目录里把固件信息收集出来，写成
#   Markdown 文件（默认 release_info.md），供工作流用
#   `gh release create --notes-file release_info.md` 直接发布。
#
#【Release 页面内容（按需求逐项对应）】
#   1. LAN IP              （默认 192.168.2.1）
#   2. 后台登录账号密码     （默认 root / 12345678）
#   3. 内核版本
#   4. 固件版本
#   5. 已安装插件清单       —— 每行一个插件；只列应用类插件，
#                              kmod / lib / i18n 依赖一律不展示
#   另外附带：镜像文件列表与 SHA-256、刷机使用说明、默认服务状态。
#
#【信息来源】
#   profiles.json    —— 固件版本 / 内核版本 / 源码时间（构建必生成）
#   *.manifest       —— 固件真实安装软件包清单（插件列表用这个，
#                       这是唯一可信来源：它就是固件里实际打进去的包）
#   config.buildinfo —— 兜底：manifest 缺失时改用 .config 启用的包
#
#【关于 LAN IP / 登录密码 / 主机名】
#   这三个值不在本脚本里硬编码，而是从 scripts/system-config.sh 的
#   配置块里实时读取 —— 保证「改系统参数只改一处」，Release 页面
#   自动跟着变，绝不会出现说明书与固件不一致。
#
#【用法】
#   bash scripts/firmware-info.sh [bin_dir] [输出文件] [system-config.sh]
#   默认: bin/targets/x86/64  →  release_info.md  →  scripts/system-config.sh
# ================================================================
set -euo pipefail

BIN_DIR="${1:-bin/targets/x86/64}"
OUT_FILE="${2:-release_info.md}"
CONFIG_SCRIPT="${3:-scripts/system-config.sh}"

if [ ! -d "$BIN_DIR" ]; then
  echo "错误: 编译产物目录不存在: $BIN_DIR" >&2
  exit 1
fi

# ----------------------------------------------------------------
# 一、从 system-config.sh 的配置块读取系统参数
#     只认「顶格 NAME="值"」形式的行，忽略注释与正文代码
# ----------------------------------------------------------------
LAN_IP="未设置"
ROOT_PASSWORD="未设置"
HOSTNAME_VAL="未设置"

if [ -f "$CONFIG_SCRIPT" ]; then
  while IFS= read -r line; do
    case "$line" in
    [A-Z_]*=\"*\") ;;
    *) continue ;;
    esac
    name="${line%%=*}"
    case "$name" in
    *[!A-Z0-9_]*) continue ;;
    esac
    value="${line#*=}"
    value="${value#\"}"
    value="${value%\"}"
    printf -v "$name" '%s' "$value" 2>/dev/null || continue
  done < <(sed -n '/配置块 ↓↓↓/,/配置块结束/p' "$CONFIG_SCRIPT" | sed -e 's/\r$//')
  LAN_IP="${LAN_IP:-未设置}"
  ROOT_PASSWORD="${ROOT_PASSWORD:-未设置}"
  HOSTNAME_VAL="${HOSTNAME:-未设置}"
else
  echo "警告: 未找到 $CONFIG_SCRIPT，Release 说明中的 LAN IP / 密码将显示为「未设置」" >&2
fi

# ----------------------------------------------------------------
# 二、从 profiles.json 提取固件版本 / 内核版本 / 源码时间
# ----------------------------------------------------------------
VERSION_NUMBER=""
VERSION_CODE=""
KERNEL_VERSION=""
SOURCE_DATE=""
if [ -f "$BIN_DIR/profiles.json" ] && command -v python3 >/dev/null 2>&1; then
  read -r VERSION_NUMBER VERSION_CODE KERNEL_VERSION SOURCE_DATE <<EOF
$(python3 - "$BIN_DIR/profiles.json" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("-", "-", "-", "-")
    raise SystemExit
print(d.get("version_number") or "-",
      d.get("version_code") or "-",
      (d.get("linux_kernel") or {}).get("version") or "-",
      d.get("source_date_epoch") or "-")
PYEOF
)
EOF
fi
[ -n "$VERSION_NUMBER" ] || VERSION_NUMBER="未知"
[ -n "$VERSION_CODE" ] || VERSION_CODE="未知"
[ -n "$KERNEL_VERSION" ] || KERNEL_VERSION="未知"

BUILD_DATE="未知"
if [ -n "$SOURCE_DATE" ] && [ "$SOURCE_DATE" != "-" ]; then
  BUILD_DATE=$(TZ=Asia/Shanghai date -d "@$SOURCE_DATE" "+%Y-%m-%d %H:%M" 2>/dev/null ||
    date -r "$SOURCE_DATE" "+%Y-%m-%d %H:%M" 2>/dev/null ||
    echo "未知")
fi

# ----------------------------------------------------------------
# 三、已安装软件包清单（manifest 优先，config.buildinfo 兜底）
# ----------------------------------------------------------------
get_pkg_names() {
  local manifests
  manifests=$(ls "$BIN_DIR"/*.manifest 2>/dev/null || true)
  if [ -n "$manifests" ]; then
    # manifest 每行格式: "包名 - 版本"，取第一列
    # shellcheck disable=SC2086
    cat $manifests | awk 'NF {print $1}'
  elif [ -f "$BIN_DIR/config.buildinfo" ]; then
    grep -E '^CONFIG_PACKAGE_[A-Za-z0-9._+-]+=y$' "$BIN_DIR/config.buildinfo" |
      sed -e 's/^CONFIG_PACKAGE_//' -e 's/=y$//'
  elif [ -f "$BIN_DIR/profiles.json" ]; then
    python3 - "$BIN_DIR/profiles.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
pk = set(d.get("default_packages") or [])
for p in d.get("profiles", {}).values():
    pk.update(p.get("device_packages") or [])
for name in sorted(pk):
    print(name)
PYEOF
  fi
}

# 插件友好名称：Release 页面按这一份映射逐行展示。
# 未收录的插件直接显示原始包名，绝不隐藏、绝不臆造。
friendly_name() {
  case "$1" in
  luci-app-openclash) echo "OpenClash（代理客户端，固件内唯一代理插件）" ;;
  luci-app-smartdns) echo "SmartDNS（DNS 分流解析）" ;;
  luci-app-ddnsto) echo "DDNSTO（内网穿透 / 远程控制）" ;;
  luci-app-adguardhome) echo "AdGuard Home（去广告 DNS，Web 管理端口 3000）" ;;
  luci-app-oaf) echo "OAF 应用过滤（应用过滤 / 上网管控）" ;;
  luci-app-turboacc) echo "TurboAcc（Flow Offload 流量分载 + BBR）" ;;
  luci-app-mwan3) echo "Mwan3（多线多拨 / 负载均衡）" ;;
  luci-app-nlbwmon) echo "带宽监控（nlbwmon）" ;;
  luci-app-easytier) echo "EasyTier（去中心化异地组网）" ;;
  luci-theme-argon) echo "Argon 主题（系统默认主题）" ;;
  luci-app-argon-config) echo "Argon 主题设置（argon-config）" ;;
  luci-app-firewall) echo "防火墙（firewall4）" ;;
  luci-app-opkg | luci-app-package-manager) echo "软件包管理器" ;;
  luci-app-ttyd) echo "TTYD 终端" ;;
  luci-app-commands) echo "自定义命令" ;;
  luci-app-uhttpd) echo "uHTTPd 网页服务器设置" ;;
  luci-app-attendedsysupgrade) echo "在线升级（Attended Sysupgrade）" ;;
  luci-app-filebrowser) echo "文件管理器" ;;
  *) echo "$1" ;;
  esac
}

# 镜像文件说明
image_desc() {
  case "$1" in
  *squashfs-combined-efi*) echo "UEFI 引导（新式主板 / 虚拟机选此文件）" ;;
  *squashfs-combined*) echo "BIOS 引导（Legacy 引导的老主板）" ;;
  *) echo "固件镜像" ;;
  esac
}

# ----------------------------------------------------------------
# 四、输出 Markdown 正文到文件
# ----------------------------------------------------------------
{

  cat <<EOF
# ImmortalWrt X86_64 固件（openwrt-24.10）

> 基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) \`openwrt-24.10\` 分支全自动云编译，仅 X86_64 架构，仅产出 squashfs combined IMG 镜像。

## 固件信息

| 项目 | 内容 |
| --- | --- |
| 目标平台 | x86/64（仅 64 位，BIOS / UEFI 通用） |
| 固件版本 | ImmortalWrt ${VERSION_NUMBER}（${VERSION_CODE}） |
| 内核版本 | ${KERNEL_VERSION} |
| 镜像格式 | squashfs combined（BIOS + UEFI 两个 IMG） |
| 主机名 | ${HOSTNAME_VAL} |
| 时区 | Asia/Shanghai（CST-8） |
| 默认主题 | Argon |
| rootfs_data | 已扩容 ≥2048 MiB（首次启动自动格式化为 f2fs） |
| 编译时间 | ${BUILD_DATE} |

## 后台登录

| 项目 | 内容 |
| --- | --- |
| 管理地址 | http://${LAN_IP} |
| LAN IP | ${LAN_IP} |
| 用户名 | root |
| 密码 | ${ROOT_PASSWORD} |

> LAN IP 与登录密码由仓库内 \`scripts/system-config.sh\` 统一维护，上面显示的就是真正编进固件的值。

## AdGuard Home 去广告

| 项目 | 内容 |
| --- | --- |
| 管理页面 | http://${LAN_IP}:3000 |
| 用户名 / 密码 | admin / admin |
| 重定向模式 | dnsmasq 上游（LAN DNS :53 → AdGuardHome :5553 → 公网 DNS） |
| 过滤规则 | 内置 AdGuard DNS filter / EasyList / EasyList China / anti-AD 等中文优化规则，每 24 小时自动更新 |

> 广告过滤默认开箱即用；如需停止过滤，在「服务 → AdGuard Home → 基础设置」把重定向模式改为「不启用」即可。
> 注意：AdGuard Home 与 OpenClash 的 DNS 劫持不建议同时开启，以免互相干扰。

## 默认服务状态

- **Turbo ACC**：默认开启 BBR 拥塞控制与 FullCone NAT；软件流量分载默认关闭（分载流量走内核快速路径、绕过 conntrack 计数，与带宽监控互斥），需要时可在「网络 → Turbo ACC」自行开启；
- **带宽监控（nlbwmon）**：开机自启，按主机/协议统计流量（首次需产生流量后才有数据）；
- **Mwan3 多线多拨**：默认未配置（无接口/成员/策略/规则），需要多线负载时在「网络 → 多线多拨」中自行添加；
- **EasyTier**：核心与 Web 控制台默认启用，Web 管理页 http://${LAN_IP}:11211 。

## 已安装插件

EOF

  # 只列出「应用类插件」（luci-app-* / luci-theme-*），每行一个。
  # kmod-*（内核驱动）、lib*（依赖库）、luci-i18n-*（翻译包）等依赖
  # 一律不展示 —— 满足「插件清单每行一个、kmod 不展示」的要求。
  get_pkg_names | sort -u | while read -r pkg; do
    case "$pkg" in
    luci-app-* | luci-theme-*)
      case "$pkg" in
      luci-i18n-*) ;; # 双保险：翻译包不列
      *) echo "- $(friendly_name "$pkg")" ;;
      esac
      ;;
    esac
  done

  echo ""
  echo "## 镜像文件（含 SHA-256）"
  echo ""
  echo "| 文件 | 说明 | 大小 | SHA-256 |"
  echo "| --- | --- | --- | --- |"

  # 优先列压缩后的 .img.gz（Release 实际上传的文件），
  # 未压缩的 .img 若被清理则自动跳过
  for img in "$BIN_DIR"/*combined*.img.gz "$BIN_DIR"/*combined*.img; do
    [ -f "$img" ] || continue
    base=$(basename "$img")
    size=$(du -h "$img" | cut -f1)
    sha=$(sha256sum "$img" | cut -d' ' -f1)
    echo "| \`${base}\` | $(image_desc "$base") | ${size} | \`${sha:0:16}…\` |"
  done

  cat <<EOF

## 使用说明

1. 下载镜像：UEFI 主板 / 虚拟机选 \`combined-efi\`，Legacy 老主板选 \`combined\`；
2. 解压得到 \`.img\` 文件：

\`\`\`bash
gunzip immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz
\`\`\`

3. 用 balenaEtcher / Rufus（DD 模式）或 \`dd\` 写入磁盘：

\`\`\`bash
sudo dd if=immortalwrt-x86-64-generic-squashfs-combined-efi.img of=/dev/sdX bs=4M conv=fsync status=progress
\`\`\`

4. 启动后浏览器访问 http://${LAN_IP} 进入管理后台（root / ${ROOT_PASSWORD}）；
5. rootfs_data（/overlay）已预扩容 ≥2GiB，可直接安装软件包、存放缓存与配置。

> 完整校验值见附件 \`sha256sums\`，本次编译配置见附件 \`config.buildinfo\`。
EOF

} >"$OUT_FILE"

echo "==> [firmware-info] 已生成 Release 正文: $OUT_FILE"
echo "    固件版本  : ImmortalWrt $VERSION_NUMBER ($VERSION_CODE)"
echo "    内核版本  : $KERNEL_VERSION"
echo "    编译时间  : $BUILD_DATE"
echo "    LAN IP    : $LAN_IP"
echo "    应用插件数: $(get_pkg_names | sort -u | grep -cE '^luci-(app|theme)-' || true)"
echo "    文件行数  : $(wc -l <"$OUT_FILE")"
