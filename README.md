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
| 运维工具 | ttyd 网页终端、定时重启（autoreboot）、微信推送（wechatpush） |
| 应用过滤 | OAF（`kmod-oaf` 内核模块 + `appfilter` 用户态服务 + LuCI 面板） |
| 驱动 | USB 控制器/存储/HID/串口、USB 网卡（asix、rtl8150、rtl8152-vendor、cdc-ether 等）、Intel / Realtek / 其它常见有线网卡 |
| 语言 | 所有自带语言包的插件均已勾选 `zh-cn` 中文语言包 |

所有 kmod 均随 openwrt-25.12 源码树（内核 **6.12.x**）一并编译，不引入任何外部内核模块，保证 ABI 严格匹配。

> 本固件**不包含任何代理类插件**（OpenClash 已按要求移除）。

## 预置配置

除「选中哪些软件包」之外，mwan3 / SmartDNS / AdGuardHome / dhcp / firewall / opkg 的
**默认配置文件**由仓库 `preset/` 目录整文件覆盖，随固件一起打包（利用 buildroot 在打包
阶段后于 ipk 安装拷贝源码树顶层 `files/` 的机制，优先级高于软件包自带配置）：

| 文件 | 预置内容 |
| --- | --- |
| `preset/etc/config/mwan3` | 接口 / 成员 / 策略**全部留空**，仅保留 mwan3 自带的 3 条默认规则（`https`、`default_rule_v4`、`default_rule_v6`），待用户自行配置 |
| `preset/etc/config/smartdns` | `enabled=0`（不启用）、`auto_set_dnsmasq=0`（不自动设置 dnsmasq）；预写入 5 个上游服务器：`114.114.114.114`（114DNS）、`223.5.5.5`（阿里DNS）、`180.184.1.1`（字节跳动）、`119.29.29.29`（腾讯DNS）、`8.8.8.8`（谷歌DNS），协议类型均为 **UDP**，端口留空不填 |
| `preset/etc/config/adguardhome` | `enabled=1`，AdGuardHome **默认开机自启**（25.12 起改由 ImmortalWrt 官方源提供，官方 schema：段名 `config adguardhome 'config'`，`config_file` 指向 `/etc/adguardhome/adguardhome.yaml`，核心已随固件打包，Web 后台 3000 端口可直接访问） |
| `preset/etc/adguardhome/adguardhome.yaml` | 上游 DNS 预填 `114.114.114.114` 与 `223.5.5.5`；DNS 黑名单清单**只保留两条**：`https://anti-ad.net/adguard.txt`（AD 命中率最高列表）、`https://gh-proxy.com/https://raw.githubusercontent.com/2771936993/HG/main/hg1.txt`（海哥的清单） |
| `preset/etc/config/dhcp` | dnsmasq 段显式写入 `option port '53'`。**这是修复 AdGuardHome 重定向模式失效的关键**：`luci-app-adguardhome` 的 `use_port53()` / `set_forward_dnsmasq()` / `exchange` 三种重定向模式全部依赖 `uci get dhcp.@dnsmasq[0].port`，而上游 `dhcp.conf` 与 `odhcpd.defaults` 均不写该选项，取空值会导致三种模式全部失效（界面显示「未定向」、后台无查询/拦截信息） |
| `preset/etc/config/firewall` | `config defaults` 段显式写入 `flow_offloading='1'`（**软件流量卸载**）、`flow_offloading_hw='0'`（硬件卸载关闭）、`fullcone='1'`（**全锥型 NAT**）。X86_64 平台没有硬件 NAT 引擎，硬件流量卸载对该架构无效，故默认走软件卸载（由 `kmod-nft-offload` 提供）；TurboAcc 开机回写 `flow_offloading_hw=1` 与全锥开关，由首次启动兜底脚本再次强制写回 |
| `preset/etc/opkg/distfeeds.conf` | opkg 软件源列表（core / base / luci / packages / routing / telephony 六个源，URL 指向 `releases/25.12.2`）。修复 LuCI「软件包 - 更新列表」失败问题——当 `CONFIG_CLEAN_IPKG` 开启时上游 `base-files` 不再生成该文件，固件会因无任何可用源而无法更新列表 |

工作流在写入后会对上述内容做结构化校验（mwan3 段落计数、SmartDNS 开关与 5 个上游、
AdGuardHome 开关与 2 条黑名单、dhcp 的 `port '53'` 声明、firewall 的三个开关、
argon 的 Bing 壁纸、opkg 六源完整性与 URL），不符合需求立即终止。

> 若用户或上游重新引入 mwan3 默认接口，首次启动的 `99-wrt-x64-defaults` 兜底脚本
> 仍会删除接口 / 成员 / 策略段并提交一次，保证「留空」状态。
>
> 同一脚本还会在首次启动时兜底 AdGuardHome 开机自启（官方 schema：
> `adguardhome.config.enabled=1`），并再次确保 `dhcp.@dnsmasq[0].port='53'`、
> `flow_offloading='1'` / `flow_offloading_hw='0'` / `fullcone='1'`、
> `argon.@global[0].online_wallpaper='bing'`，以及
> `/etc/opkg/distfeeds.conf` 非空。
>
> 该兜底脚本由 `scripts/write-uci-defaults.sh` 生成（工作流步骤 10.5 调用）。
> 之所以抽成独立脚本：GitHub Actions 对单个 `run` 步骤有 21000 字符的硬上限，
> 内联写法超出后工作流无法被 GitHub 解析（三次运行均以 `startup_failure` 秒挂）。
> 脚本内部自带语法校验与关键定制项复核，生成失败同样立即终止。

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
.github/workflows/build-x86_64.yml   主工作流（21 个步骤，全中文注释）
config/X86_64.config                 固件配置基线，增减插件改这里
config/required-packages.txt         必选软件包清单（编译前后双重校验）
preset/etc/config/mwan3              mwan3 预置配置（接口/成员/策略留空）
preset/etc/config/smartdns           SmartDNS 预置配置（不启用 + 5 个上游服务器）
preset/etc/config/adguardhome        AdGuardHome 预置配置（官方源 schema，默认开机自启）
preset/etc/adguardhome/adguardhome.yaml  AdGuardHome 预置 YAML（上游 DNS + 黑名单清单）
preset/etc/config/dhcp               dnsmasq 预置配置（显式 port '53'，修复 AGH 重定向）
preset/etc/config/firewall           防火墙预置配置（软件流量卸载 + 全锥 NAT）
preset/etc/config/argon              argon 主题预置配置（登录界面展示 Bing 每日图片）
preset/etc/opkg/distfeeds.conf       opkg 软件源列表（修复更新列表失败）
scripts/check-packages.sh            必选包校验（config / manifest 两种模式）
scripts/verify-artifacts.sh          产物校验（存在性/命名/格式/分区/插件完整性）
scripts/gen-release-notes.sh         Release 说明生成
scripts/write-uci-defaults.sh        生成首次启动兜底脚本 99-wrt-x64-defaults（时区/AGH 状态机/dhcp port/防火墙卸载/opkg 源/mwan3/root 密码）
scripts/validate-preset.sh            预置内容结构化校验（mwan3/SmartDNS/AdGuardHome/dhcp/opkg/firewall/argon 逐项校验）
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
| 预置配置 | `preset/` 八个文件落位校验 + 内容结构化校验（由 `scripts/validate-preset.sh` 执行：mwan3 段落计数 = 0/0/0 且规则 = 3；SmartDNS `enabled=0`/`auto_set_dnsmasq=0`/5 个上游且全为 udp、无 port；AdGuardHome `enabled=1`、`config_file` 指向预置 YAML、黑名单恰好 2 条指定链接；dhcp 的 `config dnsmasq` 段含 `option port '53'`；firewall 的 `flow_offloading=1`/`flow_offloading_hw=0`/`fullcone=1`；argon 的 `online_wallpaper=bing`；opkg 恰好 6 个 `src/gz` 源且 URL 指向 25.12.2 发布目录） |
| 编译前 | `make defconfig` 后必选包解析校验；`make download` 后 0 字节下载文件校验（自动排除 cargo 在 `dl/cargo` 下创建的 `.package-cache` 等天然为空的隐藏锁标记文件，避免误判） |
| 编译后 | 产物存在性、命名唯一性、MBR 分区表、rootfs 2048 MiB、squashfs 魔数、manifest 插件完整性、AdGuardHome 核心存在 |
| 压缩发布 | 压缩前磁盘空间充足性 + 压缩产物体积 < 2 GiB（Release 单文件上限），两道校验在步骤 17 与步骤 21 各执行一次 |

编译失败时，工作流会先以 `-j1 V=s` 串行续建：并行编译失败多见于 25.12 的 `package/install` 高并发竞态（错误输出被并行模式吞掉，只剩 "build failed. Please re-run make with -j1 V=s"），此时串行续建通常数分钟即可完成剩余安装并产出镜像，工作流继续走校验/发布全流程；若为真实编译错误，串行同样失败，且 `V=s` 全量输出会暴露确切出错包，步骤以失败告终（严格模式不被削弱）。随后上传日志 Artifact（`build.log` / `download.log` / `verify.log`，按实际执行到的阶段收录）。

## 第三方插件来源

> **AdGuardHome 例外**：25.12 起改由 ImmortalWrt 官方源提供——`immortalwrt/packages @ openwrt-25.12` 的 `net/adguardhome`（v0.107.79）与 `immortalwrt/luci @ openwrt-25.12` 的 `applications/luci-app-adguardhome`，随 feeds 自动拉取、由 `config/X86_64.config` 选中，不走第三方仓库。（24.10 时代官方 feeds 无此包，曾回退 kenzok8/openwrt-packages。）

| 插件 | 来源仓库 | 拉取方式 |
| --- | --- | --- |
| ddnsto / luci-app-ddnsto | [kenzok8/openwrt-packages](https://github.com/kenzok8/openwrt-packages) @ master | 稀疏浅克隆 |
| kmod-oaf / luci-app-oaf | [kenzok8/small-package](https://github.com/kenzok8/small-package) @ main | 稀疏浅克隆 |
| appfilter（OAF 用户态） | [destan19/OpenAppFilter](https://github.com/destan19/OpenAppFilter) @ master | 稀疏浅克隆 `open-app-filter` |
| easytier / luci-app-easytier | [kenzok8/small-package](https://github.com/kenzok8/small-package) @ main | 稀疏浅克隆容器目录 |
| luci-app-wechatpush | [tty228/luci-app-wechatpush](https://github.com/tty228/luci-app-wechatpush) @ master | 稀疏浅克隆（Makefile + `po/zh_Hans` 中文语言包） |
| TurboAcc | [chenmozhijin/turboacc](https://github.com/chenmozhijin/turboacc) @ luci | 官方 `add_turboacc.sh` 集成 |

均只拉取所需子目录，不整仓库拉取。
