# ImmortalWrt 24.10 X86_64 云编译仓库（修正版）

## 本版修正
1. **修复 DDNSTO / OAF 缺失**：拉取脚本改为严格模式（浅克隆 + find 自动探测
   + Makefile 校验，失败即终止）；工作流新增 defconfig 后「关键包强校验」，
   任何关键包未生效都会让 Actions 直接失败并高亮报错，绝不再产出残缺固件。
2. **默认无密码**：root 空密码，首次登录 LuCI 后再设置。
3. LuCI 24 中 opkg 更名 package-manager，config 已双写兼容。

## 使用方法
Fork 本仓库 → Actions 页面手动触发 → 编译完成后在 Releases 下载镜像

## 默认信息
- LAN IP：192.168.2.1　账号：root　**密码：无（首次登录后请立即设置）**

## 自定义入口（互不影响，独立维护）
| 需求 | 修改文件 |
| --- | --- |
| 增减插件 / kmod | config/x86_64.config（同时更新 yml 中 REQUIRED_PKGS）|
| LAN IP / 密码 / 主机名 / 主题 | scripts/system-config.sh |
| 第三方源与拉取规则 | scripts/pull-packages.sh |

## 如何确认 DDNSTO / OAF 真的编进去了
1. Actions 日志「9. 关键包强校验」步骤：逐包显示 ✔
2. Actions 日志「16. 整理固件产物」步骤：ipk 清单中可见 ddnsto / kmod-oaf