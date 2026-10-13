# ImmortalWrt X86_64 自动云编译仓库

基于 GitHub Actions 的 ImmortalWrt 24.10（`openwrt-24.10` 分支）X86_64 定制固件云编译方案，
全自动编译 squashfs-combined 格式 IMG 镜像并自动发布 Release。

## 使用方法
1. Fork 本仓库到自己的 GitHub 账号；
2. 进入仓库 **Actions** 页面启用工作流，选择 *Build ImmortalWrt X86_64* → **Run workflow**；
3. 等待约 2~4 小时编译完成，前往 **Releases** 页面下载固件（或从 Artifacts 下载）。

## 常用自定义
| 需求 | 修改位置 |
| ---- | ---- |
| 增减编译插件 | `.config` |
| 修改 LAN IP / 登录密码 / 主机名 / 时区 / 默认主题 | `scripts/system-config.sh` |
| Release 页面展示的账号信息 | `scripts/release-info.sh` |
| 第三方插件拉取 | `scripts/diy-part2.sh` |

## 默认信息
- 管理地址：http://192.168.2.1（账号 `root`，密码 `asdfghjkL666666`）
- 集成：Argon 主题、SmartDNS、AdGuardHome、DDNSTO、OAF 应用过滤、Turbo ACC、
  Mwan3、nlbwmon、EasyTier、OpenClash（唯一代理插件），全部带中文界面
- 内核驱动：USB / USB 网卡 / Intel i211 / RTL8111 等常见有线网卡

## 排错
编译失败时，在 Actions 该次运行的 Artifacts 中下载 `openwrt_build_failed_log`（build.log），
日志包含单线程详细模式的完整错误输出，按报错定位即可。
