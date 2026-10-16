# WRT-X64 云编译

ImmortalWrt **X86_64** 固件的 GitHub Actions 云编译仓库，设计参考 P3TERX 的云编译仓库模式。
所有编译、校验、发布流程全自动，编译成功后自动创建 Release 并上传固件。

## 快速开始

1. 进入仓库的 **Actions** 页，选择「编译 ImmortalWrt X86_64 固件」。
2. 点击 **Run workflow**，按需选择两个输入参数：

   | 输入参数 | 默认值 | 说明 |
   | --- | --- | --- |
   | `include_sfe` | `false` | TurboAcc 是否额外集成 Shortcut-FE。关闭时仅保留软件流量分载 + 全锥型 NAT + BBR（推荐）。 |
   | `upload_artifact` | `true` | 是否同时把固件（`.img.gz`）作为 Actions Artifact 上传（Release 始终只发布 `squashfs-combined.img.gz`）。 |

3. 等待编译完成（首次完整编译约 40~90 分钟），在 **Releases** 页下载固件。

> 仓库已配置 `contents: write` 权限，工作流可自动创建 Release，无需额外配置 Token。

## 编译产物

- 发布文件：`immortalwrt-x86-64-generic-squashfs-combined.img.gz`
- 格式：squashfs，MBR 分区表，GRUB 引导（BIOS + EFI 各一份 combined 镜像）
- rootfs 分区：**2048 MiB**，squashfs 之外的空间即为可写 overlay（约 2G）
- 工作流内部仍生成原始 `.img`（约 2.2 GiB）用于分区/魔数校验；
  由于超过 GitHub Release 单文件 **2 GiB** 硬上限（`HTTP 422 size must be less than 2147483648`），
  校验通过后用 `gzip -9` 压缩为 `.img.gz`（约 200 MiB）再发布。
- 不使用 OpenWrt 内置的 `CONFIG_TARGET_IMAGES_GZIP`：该开关在 x86 `image/Makefile`
  中是 if/else 互斥的，开启后只产出 `.img.gz` 而不再产出 `.img`，会使产物校验失去依据。
- 其余格式（qcow2 / vdi / vmdk / iso）均不生成。

### 使用下载的固件

```bash
sha256sum immortalwrt-x86-64-generic-squashfs-combined.img.gz   # 与 Release 说明中的 SHA256 比对
gunzip -k immortalwrt-x86-64-generic-squashfs-combined.img.gz   # 解压得到 .img
dd if=immortalwrt-x86-64-generic-squashfs-combined.img of=/dev/sdX bs=4M conv=fsync status=progress
```

## 内置软件

| 类别 | 内容 |
| --- | --- |
| LuCI 基础 | `luci` + `luci-light` + `uhttpd` + `luci-app-package-manager` |
| 默认主题 | **argon**（已设为系统默认主题，含 `luci-app-argon-config`） |
| DNS | SmartDNS、AdGuardHome（核心已随固件打包至 `/usr/bin/AdGuardHome`） |
| 穿透 | DDNSTO 内网穿透（中文） |
| 加速 | TurboAcc（firewall4 适配版：软件流量分载 + 全锥型 NAT + BBR） |
| 网络功能 | Mwan3 多拨、nlbwmon 带宽监控、EasyTier 去中心化组网、UPnP 端口自动映射、网络唤醒（WOL） |
| 运维工具 | ttyd 网页终端、定时重启（autoreboot） |
| 应用过滤 | OAF（`kmod-oaf` 内核模块 + `appfilter` 用户态服务 + LuCI 面板） |
| 驱动 | USB 控制器/存储/HID/串口、USB 网卡（asix、rtl8150、rtl8152-vendor、cdc-ether 等）、Intel / Realtek / 其它常见有线网卡 |
| 语言 | 所有自带语言包的插件均已勾选 `zh-cn` 中文语言包 |

所有 kmod 均随 openwrt-24.10 源码树（内核 **6.6.x**）一并编译，不引入任何外部内核模块，保证 ABI 严格匹配。

> 本固件**不包含任何代理类插件**（OpenClash 已按要求移除）。

## 预置配置

除「选中哪些软件包」之外，mwan3 / SmartDNS / AdGuardHome 的**默认配置文件**由仓库
`preset/` 目录整文件覆盖，随固件一起打包（利用 buildroot 在打包阶段后于 ipk 安装
拷贝源码树顶层 `files/` 的机制，优先级高于软件包自带配置）：

| 文件 | 预置内容 |
| --- | --- |
| `preset/etc/config/mwan3` | 接口 / 成员 / 策略**全部留空**，仅保留 mwan3 自带的 3 条默认规则（`https`、`default_rule_v4`、`default_rule_v6`），待用户自行配置 |
| `preset/etc/config/smartdns` | `enabled=0`（不启用）、`auto_set_dnsmasq=0`（不自动设置 dnsmasq）；预写入 5 个上游服务器：`114.114.114.114`（114DNS）、`223.5.5.5`（阿里DNS）、`180.184.1.1`（字节跳动）、`119.29.29.29`（腾讯DNS）、`8.8.8.8`（谷歌DNS），协议类型均为 **UDP**，端口留空不填 |
| `preset/etc/config/AdGuardHome` | `enabled=0`，AdGuardHome **默认不启用**，需用户手动启用 |
| `preset/etc/AdGuardHome.yaml` | 上游 DNS 预填 `114.114.114.114` 与 `223.5.5.5`；DNS 黑名单清单**只保留两条**：`https://anti-ad.net/adguard.txt`（AD 命中率最高列表）、`https://gh-proxy.com/https://raw.githubusercontent.com/2771936993/HG/main/hg1.txt`（海哥的清单） |

工作流在写入后会对上述内容做结构化校验（mwan3 段落计数、SmartDNS 开关与 5 个上游、
AdGuardHome 黑名单条目数），不符合需求立即终止。

> 若用户或上游重新引入 mwan3 默认接口，首次启动的 `99-wrt-x64-defaults` 兜底脚本
> 仍会删除接口 / 成员 / 策略段并提交一次，保证「留空」状态。

## 默认参数

| 项目 | 值 |
| --- | --- |
| 后台登录地址 | <http://192.168.2.1> |
| 登录账号 | `root` |
| 登录密码 | `12345678` |
| 时区 | `Asia/Shanghai`（CST-8，NTP 为国内可达地址） |

> 首次登录后请立即修改默认密码。

## 目录结构

```
.github/workflows/build-x86_64.yml   主工作流（22 个步骤，全中文注释）
config/X86_64.config                 固件配置基线，增减插件改这里
config/required-packages.txt         必选软件包清单（编译前后双重校验）
preset/etc/config/mwan3              mwan3 预置配置（接口/成员/策略留空）
preset/etc/config/smartdns           SmartDNS 预置配置（不启用 + 5 个上游服务器）
preset/etc/config/AdGuardHome        AdGuardHome 预置配置（默认不启用）
preset/etc/AdGuardHome.yaml          AdGuardHome 预置 YAML（上游 DNS + 黑名单清单）
scripts/check-packages.sh            必选包校验（config / manifest 两种模式）
scripts/verify-artifacts.sh          产物校验（存在性/命名/格式/分区/插件完整性）
scripts/gen-release-notes.sh         Release 说明生成
```

### 如何增减插件

编辑 `config/X86_64.config`：

- 选中插件：`CONFIG_PACKAGE_luci-app-xxx=y`
- 取消插件：`# CONFIG_PACKAGE_luci-app-xxx is not set`

同时按下述约定勾选配套语言包：`CONFIG_PACKAGE_luci-i18n-xxx-zh-cn=y`。
如果该插件是「必选」的，请在 `config/required-packages.txt` 中同步增删，否则工作流不会对其做缺失校验。

工作流在 `make defconfig` 之后会立刻用 `required-packages.txt` 做一次编译前校验，
任何必选包被剔除都会立即终止并输出缺失项、期望值、实际值与排查建议。

## 校验与失败定位

工作流在以下各阶段做 fail-fast 校验，失败时均输出「检测命令 / 期望值 / 实际值 / 可能原因 / 建议修复方向」：

| 阶段 | 校验内容 |
| --- | --- |
| 拉取源码 | 上游分支可达性（`git ls-remote`），分支不存在立即终止 |
| 拉取第三方插件 | 分支可达性 + 稀疏检出 + 目标路径存在性 + 落位结果汇总 |
| 集成 TurboAcc | 内核版本支持范围（5.10/5.15/6.1/6.6/6.12/6.18）+ 官方脚本落位校验 + **952 补丁唯一性**（移除 turboacc 注入的重复补丁，避免与 ImmortalWrt 原生 952 补丁冲突） |
| 预置配置 | `preset/` 四个文件落位校验 + 内容结构化校验（mwan3 段落计数 = 0/0/0 且规则 = 3；SmartDNS `enabled=0`/`auto_set_dnsmasq=0`/5 个上游且全为 udp、无 port；AdGuardHome `enabled=0`、黑名单恰好 2 条指定链接） |
| 编译前 | `make defconfig` 后必选包解析校验；`make download` 后 0 字节下载文件校验 |
| 编译后 | 产物存在性、命名唯一性、MBR 分区表、rootfs 2048 MiB、squashfs 魔数、manifest 插件完整性、AdGuardHome 核心存在 |
| 压缩发布 | 压缩前磁盘空间充足性 + 压缩产物体积 < 2 GiB（Release 单文件上限），两道校验在步骤 18 与步骤 22 各执行一次 |

编译失败时，工作流会先以 `-j1 V=s` 串行重跑以暴露真实出错包，再上传完整 `build.log` 作为 Artifact。

## 第三方插件来源

| 插件 | 来源仓库 | 拉取方式 |
| --- | --- | --- |
| luci-app-adguardhome | [kenzok8/openwrt-packages](https://github.com/kenzok8/openwrt-packages) @ master | 稀疏浅克隆 |
| ddnsto / luci-app-ddnsto | [kenzok8/openwrt-packages](https://github.com/kenzok8/openwrt-packages) @ master | 稀疏浅克隆 |
| kmod-oaf / luci-app-oaf | [kenzok8/small-package](https://github.com/kenzok8/small-package) @ main | 稀疏浅克隆 |
| appfilter（OAF 用户态） | [destan19/OpenAppFilter](https://github.com/destan19/OpenAppFilter) @ master | 稀疏浅克隆 `open-app-filter` |
| easytier / luci-app-easytier | [kenzok8/small-package](https://github.com/kenzok8/small-package) @ main | 稀疏浅克隆容器目录 |
| TurboAcc | [chenmozhijin/turboacc](https://github.com/chenmozhijin/turboacc) @ luci | 官方 `add_turboacc.sh` 集成 |

均只拉取所需子目录，不整仓库拉取。
