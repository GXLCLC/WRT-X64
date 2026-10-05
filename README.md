# ImmortalWrt x86_64 云编译仓库

基于 GitHub Actions 的 ImmortalWrt 固件全自动云编译（P3TERX 风格）。

## 使用
1. Fork / 基于本仓库创建新仓库（公有仓库可免费使用 Actions）
2. Actions → Build ImmortalWrt x86_64 → Run workflow
3. 约 2~4 小时后在 Releases 页面下载 .img.gz 固件

## 自定义
- **增减插件**：编辑 `config/x86-64.config`
- **修改 LAN IP / 密码 / 主机名**：编辑 `scripts/modify_system_config.sh`
- **调整第三方包来源**：编辑 `scripts/prepare-packages.sh` 映射表
