# OpenWrt X86_64 固件发布

> 基于 LEDE 源码云编译，仅 X86_64 架构，squashfs combined 镜像格式，overlay 预留 2G 可写空间

## 固件信息

| 项目 | 内容 |
| --- | --- |
| 编译日期 | {{BUILD_DATE}} |
| 固件版本 | {{FIRMWARE_VERSION}} |
| LEDE 源码 | {{LEDE_COMMIT}} |
| 内核版本 | {{KERNEL_VERSION}} |
| 目标架构 | X86_64 |
| 镜像格式 | squashfs combined（gzip 压缩） |
| overlay 分区 | 2G 可写空间 |
| 时区 | Asia/Shanghai |

## 后台登录信息

| 项目 | 内容 |
| --- | --- |
| LAN IP | {{LAN_IP}} |
| 主机名 | {{HOST_NAME}} |
| 用户名 | {{LOGIN_USER}} |
| 密码 | {{LOGIN_PASSWORD}} |

## 已安装插件清单

> 每行展示一个插件，方便使用者快速查阅

{{PACKAGES}}

## 镜像说明

- 产物为 `*.img.gz` 压缩镜像，使用前需先解压得到 `*.img`
- 仅生成 IMG 镜像，不生成 VHDX / VMDK / QCOW 等其他格式
- 镜像类型：squashfs combined（内核 + rootfs 合一，支持恢复出厂设置）
- 内置驱动：USB 总线、USB 网卡、Intel 网卡（e1000/e1000e/igb/ixgbe/i40e/igc）、Realtek 网卡（r8169/8139）

## 使用方法

1. 下载下方附件中的 `.img.gz` 文件
2. 解压得到 `.img` 镜像文件：`gunzip xxx.img.gz`
3. 使用写盘工具（如 dd / Rufus / balenaEtcher / physdiskwrite）写入磁盘或 U 盘
   - Linux：`sudo dd if=xxx.img of=/dev/sdX bs=4M status=progress`
   - Windows：使用 Rufus 选择「dd 模式」写入
4. 启动设备后，浏览器访问 `{{LAN_IP}}` 进入 LuCI 后台
5. 使用上方账号密码登录

## 刷写后注意事项

- overlay 预留 2G 空间可用于后续 `opkg install` 安装软件包、保存配置与缓存
- 如需修改 LAN IP、主机名、账号密码，请修改源仓库的 `scripts/system_config.sh` 后重新编译
- 如需增减插件，请修改源仓库的 `config/.config` 后重新编译

## 免责声明

本固件仅供学习与交流使用，请勿用于商业用途。编译所用源码与插件均来自各自开源仓库，版权归原作者所有。使用本固件产生的任何后果由使用者自行承担。
