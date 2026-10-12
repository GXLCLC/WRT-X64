# ImmortalWrt 24.10 X86_64 云编译仓库

基于 GitHub Actions 的全自动云编译方案，无需本地环境，无交互式操作。

## 使用方法
1. Fork 本仓库 → 2. Actions 页面手动触发「ImmortalWrt X86_64 云编译」
→ 3. 约 2~4 小时后在 Releases 页下载 squashfs combined IMG 镜像。

## 自定义入口（互不影响，独立维护）
| 需求 | 修改文件 |
| --- | --- |
| 增减插件 / kmod | `config/x86_64.config` |
| LAN IP / 密码 / 主机名 / 主题 | `scripts/system-config.sh` |
| 第三方源与拉取规则 | `scripts/pull-packages.sh` |

## 默认信息
- LAN IP：192.168.2.1　账号：root　密码：asdfghjkL666666

