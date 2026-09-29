# ImmortalWrt X86_64 固件发布

> 基于 ImmortalWrt master 分支云编译，仅 X86_64 架构，squashfs combined 镜像格式，overlay 预留 2G 可写空间

## 固件信息

| 项目 | 内容 |
| --- | --- |
| 编译日期 | {{BUILD_DATE}} |
| 固件版本 | {{FIRMWARE_VERSION}} |
| ImmortalWrt 源码 | {{LEDE_COMMIT}} |
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
