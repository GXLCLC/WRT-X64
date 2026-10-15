# WRT-X64 —— ImmortalWrt X86_64 全自动云编译

基于 GitHub Actions 的 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) **openwrt-24.10 分支**全自动云编译仓库，**仅编译 X86_64 架构固件**。

全程零交互：不需要 SSH 登录编译机。在本仓库点一次 `Run workflow`，云端自动完成「克隆源码 → 拉第三方插件 → 打编译兼容补丁 → 编译 → 分区扩容 → 严格校验 → 压缩 → 生成 Release 说明 → 自动发布 Release」。

---

## 固件出厂默认值

| 项目 | 取值 | 在哪里改 |
| --- | --- | --- |
| 后台地址 | `http://192.168.2.1` | `scripts/system-config.sh` |
| 用户名 / 密码 | `root` / `12345678` | `scripts/system-config.sh` |
| 主机名 | `ImmortalWrt` | `scripts/system-config.sh` |
| 时区 | `Asia/Shanghai` | `scripts/system-config.sh` |
| 默认主题 | Argon | `scripts/system-config.sh` |
| 镜像格式 | squashfs combined IMG（BIOS + UEFI 双镜像） | `config/X86_64.config` |
| `/overlay` 可写空间 | ≥ 2048 MiB（首次启动自动格式化为 f2fs） | `config/X86_64.config` |

> 这三处是**唯一的日常维护点**，改它们不需要动工作流：
> - `config/X86_64.config` —— 增减软件包、改分区大小
> - `scripts/system-config.sh` —— 改 LAN IP / 密码 / 主机名 / 时区 / 主题
> - `scripts/feeds_update.sh` —— 增删第三方插件来源仓库

---

## 集成插件

| 插件 | 说明 | 来源 |
| --- | --- | --- |
| OpenClash | 代理客户端（**本固件唯一的代理类插件**） | ImmortalWrt 源码自带 |
| SmartDNS | DNS 分流解析 | 源码自带 |
| DDNSTO | 内网穿透（`luci-app-ddnsto` 前端 + `ddnsto` 后端） | 第三方：`linkease/nas-packages-luci`(main) + `nas-packages`(master) |
| AdGuard Home | 去广告 DNS，LuCI 面板可配置网页管理端口 | 第三方：`kenzok8/openwrt-packages`(master) |
| OAF 应用过滤 | 应用过滤 / 上网管控（`kmod-oaf` + `appfilter` + `luci-app-oaf`） | 第三方：`destan19/OpenAppFilter`(master) |
| TurboAcc | 网络加速（firewall4/nftables 版） | 第三方：`chenmozhijin/turboacc`(luci) |
| Mwan3 | 多线多拨 / 负载均衡（默认未配置，需要时自行开启） | 源码自带 |
| 带宽监控 | nlbwmon | 源码自带 |
| EasyTier | 去中心化异地组网（核心 + Web 控制台默认启用） | 第三方：`EasyTier/luci-app-easytier`(main) |
| autocore | 状态页 CPU 频率 / 温度显示 | 源码自带 |
| Argon 主题 + argon-config | 主题与主题设置 | 源码自带 |

**中文语言包**：有独立 `po/zh_Hans` 的插件已逐个勾选对应 `luci-i18n-*-zh-cn` 包（argon-config、smartdns、mwan3、nlbwmon、oaf、easytier）。
OpenClash / DDNSTO / TurboAcc / AdGuard Home 属「内置中文、无独立 i18n 包」，无需也不能勾选 —— 详见 `config/X86_64.config` 中各插件段落的注释。

**驱动**：x86 目标已把 USB 子系统（USB2/USB3 主控、OHCI/UHCI、USB 存储、USB HID）与 f2fs 全部编入内核，开箱即用。x86/64 generic 的默认包清单实际只有 9 个（e1000、tg3、bnx2、amd-xgbe、amazon-ena、forcedeth、dwmac-intel、fs-vfat、drm-i915），**不含**任何 USB 网卡驱动，也不含 Intel i211 / Realtek RTL8111 等常见板载驱动——这些都在 `config/X86_64.config` 中显式补上：USB 网卡 `usb-net / cdc-ether / cdc-ncm / rndis / asix / asix-ax88179 / rtl8150 / rtl8152`，有线网卡 `e1000e / igb（i210/i211）/ igc（i225/i226）/ r8168（RTL8111/8168）/ r8125（2.5G）`，全部取自**当前源码内核（6.6）**，不引入任何外部版本 kmod。`kmod-r8168` 与内核原生 `kmod-r8169` 争抢同一批 PCI ID，已显式排除前者，只保留一套驱动。

**Turbo ACC 与带宽监控的取舍**：软件流量分载开启后，转发流量走内核快速路径、绕过 conntrack 计数，nlbwmon 将统计不到数据，**二者互斥**。因此出厂默认开启 BBR 拥塞控制、关闭软件分载（保证带宽监控可用）；追求极限转发性能可在 LuCI「网络 → Turbo ACC」自行开启。

---

## 使用方法

1. **Fork 本仓库**到你的 GitHub 账号；
2. 进入 Fork 仓库的 **Actions** 页面，选择 **ImmortalWrt X86_64 云编译**，点 **Run workflow**（`AdGuardHome 指定版本` 留空即可，脚本会自动探测与内置 Go 兼容的最新稳定版）；推送改动 `config/` `files/` `scripts/` 或本工作流，也会自动触发一次；
3. 等待编译完成（首次约 2~3 小时，有缓存后显著缩短），到 **Releases** 页面下载固件：
   - 新式主板 / 虚拟机（UEFI）：`*-squashfs-combined-efi.img.gz`
   - Legacy BIOS 老主板：`*-squashfs-combined.img.gz`
4. `gunzip` 解压后用 balenaEtcher / Rufus（DD 模式）或 `dd` 写入磁盘；
5. 启动后访问 `http://192.168.2.1`，用 `root` / `12345678` 登录。

EasyTier Web 控制台：`http://192.168.2.1:11211`。

---

## 自行增减插件

编辑 `config/X86_64.config`（**增量式**，编译时由 `make defconfig` 自动补全）：

- **新增**：加一行 `CONFIG_PACKAGE_<包名>=y`（包名须存在于 ImmortalWrt 源码/feeds，或 `scripts/feeds_update.sh` 的第三方来源表中）；
- **移除**：改成 `# CONFIG_PACKAGE_<包名> is not set`；
- `kmod-*` 依赖由 OpenWrt 自动解析，无需手工罗列。

⚠️ **不要凭猜测写包名**。`make defconfig` 对「写了但不存在的包」是**静默丢弃**的：编译一路绿灯，固件里就是没有这个插件。本仓库用两层校验堵住这个洞（见下）。

---

## 仓库结构

```text
.
├── config/
│   └── X86_64.config                 # 编译配置（日常主要改这里）
├── files/                            # 直接打进固件的定制文件
│   ├── etc/AdGuardHome.yaml          # AdGuard Home 初始配置
│   ├── etc/config/                   # AdGuardHome / mwan3 / turboacc 默认配置
│   ├── etc/uci-defaults/
│   │   └── 99-20-service-defaults    # 首次启动服务默认状态修正
│   └── sbin/tempinfo                 # 温度信息采集
├── scripts/
│   ├── feeds_update.sh               # 第三方插件拉取 + feeds 更新
│   ├── system-config.sh              # ★ 系统参数唯一维护点：IP/密码/主机名/时区/主题
│   ├── patch-plugins.sh              # ★ 插件编译兼容补丁（当前：AdGuardHome go.mod 适配）
│   ├── post-build.sh                 # 后置处理：扩容 rootfs_data(/overlay) 至 ≥2048MiB
│   ├── verify-packages.sh            # 编译产物严格校验（防止「假成功」）
│   └── firmware-info.sh              # 收集固件信息 → 生成 release_info.md
└── .github/workflows/build.yml       # GitHub Actions 工作流（每步骤含中文注释）
```

---

## 工作流说明

- **环境**：Ubuntu 24.04 LTS（GitHub 官方 Runner，Python 3.12；依赖安装步骤会逐个探测可用性，自动跳过 Runner 不提供的包，如已移除的 `python3-distutils`），`timeout-minutes: 355`；
- **触发**：`workflow_dispatch` 手动触发为主，改动 `config/**` `files/**` `scripts/**` 或工作流自身时 `push` 自动触发；
- **权限**：`permissions: contents: write`（不加这一项创建 Release 会直接 403）；
- **并发**：同分支同时刻只允许一个任务，且 `cancel-in-progress: false`（编译动辄数小时，不中途掐断）；
- **磁盘**：构建前清理 Runner 预装的 dotnet / Android SDK / GHC / CodeQL / miniconda 等；
- **缓存**：`actions/cache` 缓存 `dl`（下载源码包）与 `.ccache`（编译缓存，上限 4G 并开启压缩），不缓存庞大的 `build_dir`；
- **编译**：严格模式，`make -j$(nproc)` **不加** `-i` / `IGNORE_ERRORS`，任何一个包失败即整体失败；
- **发布**：自动创建 Release，附 IMG 镜像、`config.buildinfo` 与 `sha256sums`，正文由 `scripts/firmware-info.sh` 生成（含后台地址、账号密码、内核版本、固件版本、已安装应用插件清单）。

### 为什么不会有「看起来成功、实际缺件」的固件

五道闸门，任一条不满足都不可能走到发布环节：

| # | 闸门 | 实现 |
| --- | --- | --- |
| 1 | feeds / 第三方拉取失败 | `scripts/feeds_update.sh` 逐项校验 `Makefile` 存在，缺失即打印「缺失项 / 来源仓库 / 指定分支 / 仓库内路径」并终止 |
| 2 | 插件编译兼容补丁打不上 | `scripts/patch-plugins.sh` 失败即终止 |
| 3 | `make defconfig` 后关键开关被静默丢弃 | 工作流第 13 步逐条复核 `TARGET_x86_64` / `GRUB_EFI_IMAGES` / `TARGET_ROOTFS_PARTSIZE` / `BUILD_LOG` / `TARGET_IMAGES_GZIP` 等 13 项，并反向确认 ISO/QCOW2/VDI/VMDK/VHDX/EXT4FS 未被打开 |
| 4 | 任何软件包编译失败 | 严格模式 + `CONFIG_BUILD_LOG=y`（每个包单独写 `logs/package/<feed>/<包名>/compile.txt` 与 `error.txt`） |
| 5 | 产物与配置对不上 | `scripts/verify-packages.sh` 把配置里每一个 `CONFIG_PACKAGE_xxx=y` 拿去和固件 `*.manifest` 逐条对账，并复核 18 个关键组件与两个镜像文件 |

失败时工作流会自动把完整日志打包成 `build-logs.tar.gz` 上传为 Artifact（含 `build.log`、`final.config`、`logs/`、`.config`、`package/thirdparty/`），并在 Summary 里直接指出**是哪个包、来自哪个仓库、本地源码路径、包版本、错误摘要**。

---

## 常见问题

**Q：想改 LAN IP / 密码，要改几个地方？**
只改 `scripts/system-config.sh` 顶部配置块一处。它会生成首次启动脚本写入固件，Release 页面上的后台地址与密码也是从同一处读出来的，不会不一致。

**Q：AdGuard Home 编译报 Go 版本错误怎么办？**
不用管。`scripts/patch-plugins.sh` 会自动把版本对齐到与 ImmortalWrt 24.10 内置 Go 1.23.12 兼容的稳定版并重算哈希，同时修掉新版 `go.mod` 的 `tool` / `ignore` 语法。需要指定版本时在 `Run workflow` 里填 `agh_version`。

**Q：为什么编译失败后没有 Release？**
这是设计如此 —— 上面五道闸门任一不过都会直接终止。去 Actions 日志的 Summary 看「失败包定位」段落，或下载 `build-logs` Artifact。

**Q：能加 UPnP / 其它插件吗？**
可以。在 `config/X86_64.config` 加一行 `CONFIG_PACKAGE_<包名>=y` 即可，前提是包名真实存在（可先在 ImmortalWrt 官方软件索引里确认）。写错包名会被第 5 道闸门拦下，不会静默产出错固件。

---

## 许可

仅供学习交流使用。固件基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)（GPL-2.0）编译，请遵守上游开源协议；第三方插件请遵循各自仓库的许可声明。
