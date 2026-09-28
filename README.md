# OpenWrt 云编译仓库

基于 Ubuntu 22.04 环境的 OpenWrt（LEDE）云编译仓库，使用 GitHub Actions 自动编译 **X86_64 架构** 固件，编译成功后自动发布到 GitHub Releases。

## 功能特性

- 全程自动化执行，无交互式 SSH 登录操作
- 工作流与脚本解耦：`build.yml` 仅负责流水线调度，所有配置逻辑剥离到独立脚本
- 仅编译 X86_64 架构 squashfs combined 镜像，overlay 预留 2G 可写空间
- 自动拉取 LEDE 最新源码，集成常用第三方插件（无任何代理类插件）
- 自动扩容 Runner 磁盘、缓存源码与 feeds，规避磁盘不足、加速重复编译
- 编译失败立即终止工作流；编译成功自动创建 Release 并填充固件信息
- 内置 USB / Intel / Realtek 网卡驱动

## 仓库目录结构

```
.
├── .github/
│   └── workflows/
│       └── build.yml              # 主工作流（流水线调度，不硬编码插件源/系统参数）
├── scripts/
│   ├── feeds_manage.sh            # 第三方插件源管理（稀疏克隆 + feeds update/install）
│   ├── system_config.sh           # 系统基础参数（LAN IP/主机名/账号密码/时区）
│   └── gen_release_info.sh        # Release 信息生成（读取配置/内核/插件清单）
├── config/
│   └── .config                    # 固件编译配置（用户在此勾选增减插件）
├── docs/
│   └── release_template.md        # Release 页面信息模板
├── README.md                      # 本说明文件
└── .gitignore                     # git 忽略文件
```

## 已集成插件

| 插件 | 说明 | 来源 |
| --- | --- | --- |
| Smart DNS | 智能 DNS 解析分流，支持测速择优 | kenzok8/openwrt-packages |
| DDNSTO | 内网穿透 / DDNS 远程访问 | linkease/nas-packages-luci + nas-packages |
| AdGuardHome | 去广告 + DNS 过滤 | LEDE 官方 / kenzok8 |
| OFA (应用过滤) | 应用层特征过滤 | kenzok8/openwrt-packages |
| TurboAcc 加速 | 流量加速 / NAT 加速 / BBR | LEDE 官方 |
| mwan3 | 多 WAN 负载均衡 / 策略路由 | LEDE 官方 |
| Argon 主题 | 设为系统默认主题 | kenzok8/openwrt-packages |
| argon-config | Argon 主题在线配置 | kenzok8/openwrt-packages |
| 带宽监控 (nlbwmon) | 网络带宽监控 | LEDE 官方 |
| EasyTier 内网穿透 | 去中心化组网 | EasyTier/luci-app-easytier |

> 仓库不添加任何代理类插件。

## 驱动支持

- USB 总线与 USB 主机控制器（USB2/UHCI/OHCI/USB3）
- USB 网卡（ASIX / AX88179 / RTL8150 / RTL8152 / CDC-NCM 等）
- Intel 网卡（e1000 / e1000e / igb / igbvf / ixgbe / i40e / igc）
- Realtek 网卡（r8169 / 8139cp / 8139too）

## 使用方法

### 1. 触发编译

两种方式触发：

- **手动触发**：在仓库 `Actions` 页面选择「OpenWrt 云编译」工作流，点击 `Run workflow`，可在输入框填写自定义 Release 标签（留空自动生成）
- **自动触发**：向 `main` 分支推送代码，且改动涉及 `config/.config`、`scripts/` 或 `build.yml` 时自动触发

### 2. 修改插件（增减插件）

修改 `config/.config`：

- 添加插件：将对应行改为 `CONFIG_PACKAGE_xxx=y`
- 移除插件：将对应行改为 `# CONFIG_PACKAGE_xxx is not set`
- 提交后自动触发重新编译

### 3. 修改系统参数（LAN IP / 主机名 / 账号密码）

仅修改 `scripts/system_config.sh` 顶部参数区：

```bash
LAN_IP="192.168.1.1"          # LAN 口 IP
HOST_NAME="OpenWrt"           # 主机名
LOGIN_USER="root"             # 登录用户名
LOGIN_PASSWORD="password"     # 登录密码
```

无需改动 `build.yml` 或其他脚本。

### 4. 新增第三方插件源

若插件不在 LEDE 原生 feeds 且不在已有外挂源内：

1. 在 `scripts/feeds_manage.sh` 顶部配置区新增：
   ```bash
   FEED_XXX_REPO="https://github.com/xxx/yyy"
   FEED_XXX_PACKAGES="luci-app-xxx"   # 仅克隆所需插件目录
   FEED_XXX_BRANCH="main"
   ```
2. 在主流程中调用 `sparse_clone` 与 `register_feed`
3. 在 `config/.config` 中开启对应 `CONFIG_PACKAGE_luci-app-xxx=y`

无需改动 `build.yml`。

### 5. 修改 Release 模板

编辑 `docs/release_template.md`，使用 `{{占位符}}` 引用变量（占位符会被 `gen_release_info.sh` 自动替换）：

| 占位符 | 含义 |
| --- | --- |
| `{{LAN_IP}}` | LAN 口 IP |
| `{{HOST_NAME}}` | 主机名 |
| `{{LOGIN_USER}}` | 登录用户名 |
| `{{LOGIN_PASSWORD}}` | 登录密码 |
| `{{KERNEL_VERSION}}` | 内核版本 |
| `{{FIRMWARE_VERSION}}` | 固件版本 |
| `{{BUILD_DATE}}` | 编译日期 |
| `{{LEDE_COMMIT}}` | LEDE 源码 commit 信息 |
| `{{PACKAGES}}` | 已安装插件清单（每行一个） |

## 镜像说明

- 产物：`*.img.gz`（gzip 压缩的 squashfs combined 镜像）
- 仅生成 IMG 镜像，不生成 VHDX / VMDK / QCOW 等其他格式
- overlay 预留 2G 可写空间，用于运行时安装软件包、存放缓存与保存配置
- 刷写前需先解压：`gunzip xxx.img.gz`
- 写盘命令（Linux）：`sudo dd if=xxx.img of=/dev/sdX bs=4M status=progress`

## 工作流执行流程

1. 检出仓库代码
2. 扩容 Runner 磁盘（删除 .NET/Android/Haskell 等大型工具链）
3. 初始化编译环境（安装依赖）
4. 缓存源码与 feeds（`actions/cache`，按 `.config` 与 `feeds_manage.sh` 内容键控）
5. 拉取 LEDE 最新源码
6. 应用 `config/.config` 编译配置
7. 执行 `scripts/feeds_manage.sh`（管理第三方插件源）
8. 执行 `scripts/system_config.sh`（修改系统参数）
9. `make defconfig` + `make download`（生成配置并预下载依赖）
10. `make` 编译固件（失败即终止）
11. 执行 `scripts/gen_release_info.sh` 生成 Release 正文
12. 收集 IMG 镜像（排除 VHDX/VMDK）
13. 自动创建 GitHub Release 并上传镜像
14. 失败时上传编译日志便于排查

## 扩展修改规则一览

| 需求 | 修改位置 | 是否需改动 build.yml |
| --- | --- | --- |
| 增减 LEDE 原生/已有外挂源插件 | `config/.config` | 否 |
| 新增第三方插件源 | `scripts/feeds_manage.sh` + `config/.config` | 否 |
| 修改 LAN IP/主机名/账号密码 | `scripts/system_config.sh` | 否 |
| 修改 Release 模板 | `docs/release_template.md` | 否 |

## 常见问题

- **首次编译时间较长**：首次克隆源码与下载依赖耗时较久，后续编译命中缓存会显著加速
- **磁盘空间不足**：工作流已内置 Runner 磁盘扩容步骤，通常不会出现该问题
- **插件编译失败**：检查 `.config` 是否开启了不存在的插件，或对应第三方源地址是否变更
- **Release 未发布**：确认仓库 `Settings -> Actions -> General -> Workflow permissions` 已勾选「Read and write permissions」

## 免责声明

本固件仅供学习与交流使用，请勿用于商业用途。编译所用源码与插件均来自各自开源仓库，版权归原作者所有。使用本固件产生的任何后果由使用者自行承担。
