# OpenWrt LEDE 云编译（X86_64）

基于 GitHub Actions 的 OpenWrt LEDE 自动化云编译仓库，编译环境为 Ubuntu 22.04，目标架构为 X86_64，生成 squashfs 格式 combined IMG 镜像。

## 仓库结构

```
.
├── .github/workflows/
│   └── build.yml              # 主工作流（仅负责流水线调度，不硬编码插件源和系统参数）
├── scripts/
│   ├── feeds_manage.sh        # 第三方插件源管理脚本（稀疏克隆，不全量拉取）
│   ├── system_config.sh       # 系统参数配置脚本（LAN IP / 主机名 / 密码 / 主题）
│   └── gen_release_info.sh    # Release 发布信息生成脚本
├── config/
│   └── .config                # 固件编译配置文件（用户在此增减插件）
├── docs/
│   └── release_template.md    # Release 信息模板
├── .gitignore
└── README.md
```

## 固件特性

| 项目 | 说明 |
|------|------|
| 架构 | x86_64 |
| 镜像格式 | squashfs combined（仅输出 IMG） |
| 叠加层 | /overlay 预留约 2GB 可写空间 |
| 默认主题 | Argon |
| 网卡驱动 | Intel（e1000/e1000e/igb/igc/ixgbe）、Realtek（r8169/r8125/r8168） |
| USB 驱动 | USB 2.0/3.0 核心 + USB 存储 + USB 网卡 |
| 代理插件 | 不包含任何代理类插件 |

### 已集成插件

- **Smart DNS** — 智能 DNS 分流
- **DDNSTO** — 内网穿透远程访问
- **AdGuardHome** — 广告过滤 / DNS 拦截
- **OFA（OpenAppFilter）** — 应用过滤
- **TurboAcc** — 网络加速 / NAT 转发加速
- **mwan3** — 多 WAN 负载均衡
- **Argon 主题 + argon-config** — 默认主题及配置器
- **带宽监控（nlbwmon）** — 网络带宽监控
- **EasyTier** — 内网穿透组网

## 使用方法

### 1. 触发编译

以下方式均可触发编译：
- **推送代码**：修改 `config/.config`、`scripts/`、`docs/release_template.md` 或 `build.yml` 后推送到 `main` 分支
- **手动触发**：在 GitHub 仓库 → Actions 页面选择 "OpenWrt LEDE 云编译" → 点击 "Run workflow"
- **定时触发**：每周日凌晨 3:00（北京时间）自动编译

### 2. 获取固件

编译成功后：
1. 在仓库 **Releases** 页面找到对应版本的 Release
2. 下载 `.img.gz` 镜像文件
3. 解压：`gunzip openwrt-x86-64-generic-squashfs-combined.img.gz`
4. 写入磁盘：`dd if=openwrt-x86-64-generic-squashfs-combined.img of=/dev/sdX bs=1M`
5. 启动设备，浏览器访问管理后台（默认 `http://192.168.1.1`）

### 3. 修改系统参数

**修改 LAN IP、主机名、登录密码、主题**：

只需编辑 [scripts/system_config.sh](scripts/system_config.sh) 中的参数区：

```bash
# LAN 口 IP 地址
LAN_IP="192.168.1.1"

# 主机名称
HOSTNAME="OpenWrt"

# 登录用户名
ROOT_USERNAME="root"

# 登录密码
ROOT_PASSWORD="password"

# 默认主题
DEFAULT_THEME="argon"
```

修改后提交即可触发重新编译，无需改动 `build.yml` 或其他脚本。

### 4. 增减编译插件

**场景一：插件已在 LEDE 原生 feeds 或已有外挂源中**

编辑 [config/.config](config/.config)，找到对应插件行：
- 启用：`CONFIG_PACKAGE_luci-app-xxx=y`
- 禁用：`CONFIG_PACKAGE_luci-app-xxx=n`（或注释掉）

**场景二：需要新增不在现有列表的第三方插件源**

1. 编辑 [scripts/feeds_manage.sh](scripts/feeds_manage.sh)，在 `THIRD_PARTY_FEEDS` 数组中添加：
   ```
   "仓库名|仓库URL|仓库内插件目录路径|目标放置目录"
   ```
2. 编辑 [config/.config](config/.config)，添加 `CONFIG_PACKAGE_luci-app-xxx=y`
3. 提交代码，触发编译

**场景三：修改 LAN IP / 主机名 / 账号密码**

编辑 [scripts/system_config.sh](scripts/system_config.sh) 参数区即可，无需改动 `build.yml`。

### 5. 修改 Release 信息模板

编辑 [docs/release_template.md](docs/release_template.md)，模板中的 `{{占位符}}` 会在编译完成后由 `gen_release_info.sh` 自动替换为实际值。

## 工作流优化

| 优化项 | 说明 |
|--------|------|
| 源码缓存 | 使用 actions/cache 缓存 LEDE 源码和 feeds，避免重复全量克隆 |
| 下载缓存 | 缓存 dl/ 目录（源码包），避免重复下载 |
| 磁盘扩容 | 编译前清理 Runner 预装组件，释放约 10GB+ 磁盘空间 |
| 错误终止 | 编译出错时工作流立即终止，不继续后续步骤 |

## 第三方插件源

| 插件 | 仓库地址 |
|------|----------|
| SmartDNS / AdGuardHome / OFA / Argon 主题等 | https://github.com/kenzok8/openwrt-packages |
| EasyTier | https://github.com/EasyTier/luci-app-easytier |
| DDNSTO（LuCI 界面） | https://github.com/linkease/nas-packages-luci |
| DDNSTO（后端程序） | https://github.com/linkease/nas-packages |

> 以上第三方插件均采用稀疏克隆方式，仅拉取所需目录，不全量克隆整个仓库。

## 注意事项

1. 本仓库不包含任何代理类插件
2. 镜像仅输出 IMG 格式，不生成 VHDX、VMDK 等格式
3. 固件 squashfs 只读根文件系统 + overlay 可写层设计，恢复出厂设置只需清除 overlay
4. 首次启动后建议立即修改默认密码
5. GitHub Actions 免费额度有限，请合理控制编译频率
