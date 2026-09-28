# OpenWrt LEDE 云编译固件

## 固件信息

| 项目 | 详情 |
|------|------|
| 固件版本 | {{FIRMWARE_VERSION}} |
| 内核版本 | {{KERNEL_VERSION}} |
| 目标架构 | {{TARGET_ARCH}} |
| 镜像格式 | squashfs combined (IMG) |
| 叠加层大小 | 2GB（/overlay 可写空间） |
| 编译日期 | {{BUILD_DATE}} |
| 时区设置 | {{TIMEZONE}} |

## 登录信息

| 项目 | 详情 |
|------|------|
| 管理后台地址 | http://{{LAN_IP}} |
| 主机名称 | {{HOSTNAME}} |
| 登录用户名 | {{ROOT_USERNAME}} |
| 登录密码 | {{ROOT_PASSWORD}} |

> 首次启动后建议立即修改默认密码，确保安全。

## 默认主题

{{THEME_INFO}}

## 已安装插件清单（共 {{PLUGIN_COUNT}} 个）

{{PLUGIN_LIST}}

## 镜像文件说明

- 本固件仅输出 **IMG 格式**镜像文件，适用于 x86_64 架构物理机 / 虚拟机。
- 镜像采用 **squashfs** 只读根文件系统 + **可写 overlay** 叠加层设计。
- overlay 分区预留 **2GB** 可写空间，用于运行时安装软件包、保存缓存及配置。
- 固件内置 USB 驱动、USB 网卡驱动，以及 Intel（英特尔）/ Realtek（瑞昱）系列网卡驱动。

## 使用方法

1. 下载 `.img.gz` 镜像文件。
2. 使用 gunzip 解压：`gunzip openwrt-x86-64-generic-squashfs-combined.img.gz`
3. 使用 dd 或 balenaEtcher 将镜像写入磁盘 / U盘：
   ```
   dd if=openwrt-x86-64-generic-squashfs-combined.img of=/dev/sdX bs=1M
   ```
4. 启动设备后，通过浏览器访问管理后台：`http://{{LAN_IP}}`

## 注意事项

- 本固件不包含任何代理类插件。
- 如需增减插件，请修改仓库 `config/.config` 文件后重新触发编译。
- 如需修改 LAN IP、主机名、密码等系统参数，请修改 `scripts/system_config.sh`。
