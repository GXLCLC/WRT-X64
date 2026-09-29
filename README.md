# ImmortalWrt X86_64 云编译仓库

基于 GitHub Actions 自动化编译 ImmortalWrt X86_64 固件。

## 特性

- **源码**：ImmortalWrt master 分支（https://github.com/immortalwrt/immortalwrt）
- **架构**：仅 X86_64
- **镜像格式**：squashfs combined IMG（不生成 VHDX/VMDK）
- **overlay 分区**：编译后自动扩容至 2G 可写空间
- **默认主题**：Argon
- **自动化**：全程无交互式 SSH 登录

## 内置插件

| 插件 | 说明 |
| --- | --- |
| SmartDNS | 智能 DNS |
| DDNSTO | 内网穿透 |
| AdGuardHome | 广告拦截 DNS |
| OAF（luci-app-oaf） | 应用过滤 |
| TurboAcc | 网络加速 |
| mwan3 | 多 WAN 负载均衡 |
| Argon 主题 | 系统默认主题 |
| argon-config | Argon 主题配置 |
| 带宽监控（nlbwmon） | 网络带宽监控 |
| EasyTier | 内网穿透 |
| OpenClash | 代理插件（唯一代理插件） |

## 目录结构

```
.github/workflows/build.yml   # 主工作流（流水线调度）
scripts/
  feeds_manage.sh             # 第三方插件源管理（稀疏克隆）
  system_config.sh            # 系统基础参数（IP/主机名/账号密码/主题）
  resize_overlay.sh           # 后置扩容 overlay 至 2G
  gen_release_info.sh         # Release 正文生成
config/.config                # 编译配置（增减插件改这里）
docs/release_template.md      # Release 模板
README.md
.gitignore
```

## 操作方法

### 修改系统参数（LAN IP / 主机名 / 账号密码）

仅修改 `scripts/system_config.sh` 顶部参数区，无需改动其他文件：

```bash
LAN_IP="192.168.1.1"          # LAN 口 IP
HOST_NAME="ImmortalWrt"       # 主机名
LOGIN_USER="root"             # 登录用户名
LOGIN_PASSWORD="password"     # 登录密码
```

### 增减插件

修改 `config/.config`，将目标插件的 `CONFIG_PACKAGE_xxx=y` 取消注释或添加：

- ImmortalWrt 自带插件：直接在 `.config` 中开启
- 第三方插件：先在 `scripts/feeds_manage.sh` 顶部 `FEED_*` 配置区添加仓库地址，再在 `.config` 中开启

### 新增第三方插件源

仅修改 `scripts/feeds_manage.sh` 顶部配置区，添加仓库地址、插件目录、分支即可，无需改动 `build.yml`。

## 编译触发

- 推送代码到 `main` 分支（修改 `config/.config`、`scripts/**`、`build.yml` 时自动触发）
- 或在 GitHub Actions 页面手动运行「ImmortalWrt 云编译」工作流

编译成功后固件自动发布到 Releases 页面。
