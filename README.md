# LEDE X86_64 自动编译工程

使用 **Ubuntu 24.04 + GitHub Actions** 全自动化编译 `coolsnowwolf/lede`（大雕 LEDE）**X86_64 Generic / squashfs** 固件，手动触发、无人值守、自动发布 Release。

## 一、固件规格

| 项目 | 值 |
|---|---|
| 源码 | coolsnowwolf/lede @ master |
| 架构 | x86/64 Generic，squashfs-combined 镜像 |
| 内核 | **6.12**（强制切换，编译前后双重校验） |
| 后台 IP | 192.168.2.1 |
| 默认密码 | 空（首次登录无需密码） |
| 默认主题 | Argon |
| 时区 | Asia/Shanghai (CST-8) |
| Overlay/根分区 | 2048 MiB（2G） |
| 产物 | 仅 `img.gz`，文件名前缀为编译时间戳 |

## 二、仓库结构

```
.
├── .github/workflows/build-lede-x86-64.yml   # 工作流（仅 workflow_dispatch，全中文注释）
├── config/X86_64.config                      # 插件与驱动总清单（增删插件改这里）
└── scripts/
    ├── lib/common.sh                         # 公共库：日志/校验/稀疏克隆/包集成
    ├── 01-init-env.sh                        # 写 feeds.conf → update → install → 扫描成果
    ├── 02-kernel-6.12.sh                     # 强制 6.12 内核 + 打印/校验内核版本
    ├── 03-fetch-plugins.sh                   # 第三方插件：批量预拉 + 差分补漏
    ├── 04-defaults.sh                        # IP/空密码/主机名/时区/主题 + 清除预设配置
    ├── 05-configure.sh                       # 生成 .config → 冲突处理 → 严格依赖校验
    ├── 06-build.sh                           # 严格模式编译 + 失败错误摘要
    └── 07-verify.sh                          # 产物校验 + Release 说明 + 整理上传目录
```

## 三、使用方法

1. Fork 本仓库；进入 **Actions → LEDE X86_64 固件自动编译 → Run workflow**。
2. 可选入参：主机名（默认 `OpenWrt`）、是否发布 Release、是否启用 DL 缓存。
3. 编译完成后：
   - Artifacts：`LEDE-X86_64-固件`
   - Releases：自动创建 `LEDE-x86_64-<时间戳>`，含内核版本、固件版本、插件清单、SHA256。
4. 失败时只上传 `ERROR-编译失败日志`（`build-error.log`），含缺失依赖、路径错误、模块冲突等定位信息。

## 四、插件与依赖策略

**预装 16 项**（面板 + 核心程序 + 依赖 + 内核模块一体打包）：
smartdns、ddnsto、adguardhome、oaf 应用过滤（含 kmod-oaf）、turboacc（仅分载/全锥 NAT/BBR）、mwan3、argon-config、argon 主题、bandix、easytier、wol、upnp、ttyd、autoreboot、wechatpush、nlbwmon。

**多级源优先级**（`03-fetch-plugins.sh`）：
1. Feeds（coolsnowwolf packages/luci/routing）批量拉取并扫描，已提供的包不再走第三方；
2. `kenzok8/small-package`（main，优先级最高）→ `kenzok8/openwrt-packages`（master）；
3. 独立维护仓库兜底：OpenAppFilter、timsaya/bandix（前后端）、chenmozhijin/turboacc。

拉取方式：`--depth=1` 裁剪提交历史 + `--filter=blob:none` 部分克隆 + `sparse-checkout` 按需检出指定目录，不做整仓下载；拉取前强制校验仓库连通性、分支存在、目录完整（必须有 `Makefile`），异常直接终止并给出修复建议。

**依赖冲突**：`package/custom` 中若与 Feeds 官方包重名，自动移除第三方副本，保留官方版本；不引入与官方内核冲突的外部 kmod（唯一例外：`nft-fullcone` 为全锥形 NAT 必需，随 turboacc 官方脚本引入）。

## 五、关键实现说明

- **内核 6.12**：改写 `target/linux/x86` 下 Makefile 的 `KERNEL_PATCHVER / KERNEL_TESTING_PATCHVER`，并校验 `include/kernel-6.12` 存在；解析出完整版本号（如 `6.12.xx`）写入 `.kernel-version`，编译后再用 `bin/targets/x86/64/packages/kmod-*.ipk` 复核，非 6.12 直接判失败。
- **Turbo ACC 不含 SFE**：执行官方 `add_turboacc.sh --no-sfe`（下载 luci-app-turboacc + nft-fullcone，替换 firewall4/libnftnl/nftables 并只打 952 补丁）；删除任何 `shortcut-fe` 目录，并把 `sfe_flow` 默认置 0。
- **预设清零**：mwan3、smartdns、adguardhome、easytier、ddnsto、wechatpush、bandix、oaf 等插件自带的 `files/etc/config/*` 默认配置全部删除，开机即为未配置状态。
- **严格编译**：配置阶段逐项校验必需包是否进入 `.config`；编译阶段任意包报错即终止，不用 `-k`，不做「跳过失败包继续」；失败后单线程复现一次以精确定位。
- **产物校验**：镜像存在性 → gzip/squashfs 格式 → 分区容量 ≥ 2G → 内核版本 6.12，任一不达标即终止；未生成 `generic-squashfs-combined.img.gz` 一律判定编译失败。

## 六、增删插件

编辑 `config/X86_64.config`：新增一行 `CONFIG_PACKAGE_<包名>=y` 即可；删除对应行即不打包。
若插件不在 Feeds 中，需在 `scripts/03-fetch-plugins.sh` 的 `PKGS` 数组里补充候选源（格式：`包名|small:路径|pkgs:路径`）。
中文语言包以 `CONFIG_PACKAGE_luci-i18n-<插件名>-zh-cn=y` 形式配套，内置中文的插件无需添加。

## 七、注意事项

- 首次编译约 1.5–3 小时，已开启 DL 缓存，二次编译显著加快；工作流超时上限设为 360 分钟。
- `include/kernel-6.12` 若被上游移除，脚本会直接终止并提示更换源码提交——这是内核切换的硬性前提。
- OpenAppFilter 的 `kmod-oaf` 与内核版本强相关，如遇编译报错，优先确认上游是否已适配 6.12。
- Turbo ACC 会替换防火墙相关组件（firewall4/libnftnl/nftables），属于其功能依赖，非外部内核模块。
- 无密码固件仅供内网自用，首次登录后请立即设置密码。
