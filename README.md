# AutoBuildImmortalWrt-25.12

基于 **ImmortalWrt 25.12 系列** + ImageBuilder + GitHub Actions 的 x86-64 固件自动编译项目。

> 本项目为原 [AutoBuildImmortalWrt](https://github.com/wukongdaily/AutoBuildImmortalWrt) 的 **25.12 (apk) 版本**独立仓库。
> 原项目仅支持到 24.10.6（opkg 包管理）；25.12 起 ImmortalWrt 已全面切换到 **apk** 包管理器，本项目据此完整适配。

## 🚀 默认集成插件

| 插件 | 集成方式 | 说明 |
|------|----------|------|
| **OpenClash** | 官方 luci apk | `luci-app-openclash`，自动附带 clash_meta 内核 + GeoIP/GeoSite 数据库 |
| **Lucky** | apk 三件套 | `luci-app-lucky` + `lucky` + `luci-i18n-lucky-zh-cn`（来源 wukongdaily/apk 的 25.12 apk 源），标准 apk 安装，侧边栏菜单与软件包管理器均可见 |
| **AdZero** | 官方 release apk（文件级集成） | `luci-app-adzero`（v0.21.5），官方为 ImmortalWrt 25.12.2 预编译。因该 apk 无法被 imagebuilder 的 apk 索引安装，采用「apk add 解包 → 拷贝 AdZero 专属文件到 `files/`」打入固件，并补齐其全部运行时依赖（adblock-fast、conntrack、tcpdump-mini、ucode 全家等） |
| **Argon 主题** | 官方 luci apk | `luci-theme-argon` + `luci-app-argon-config` + 中文语言包，刷机后默认生效 |

同时默认预装：`curl`、`luci-i18n-firewall-zh-cn`、`luci-i18n-package-manager-zh-cn`（25.12 的软件包管理界面，替代 luci-app-opkg）。

支持可选：Docker（`luci-i18n-dockerman-zh-cn`）、PPPoE 拨号、自定义管理 IP、自定义固件大小。

## ⚙️ 关于 25.12 的 apk 机制（必读）

- ImmortalWrt **25.12 起包管理器从 opkg 改为 apk**，官方仓库包为 `.apk` 格式。
- ImageBuilder 的 `packages/` 目录只认 `.apk` 文件，`.ipk` 无法被 25.12 安装。
- 本项目已按此适配：
  - `x86-64/build25.sh`：Lucky 以 apk 三件套（`luci-app-lucky` + `lucky` + `luci-i18n-lucky-zh-cn`）下载到 `packages/` 并由 PACKAGES 安装；AdZero 以 `apk add <adzero.apk>`（带官方仓库解析依赖）解包到临时 root，再用 `apk info -L` 列出其专属文件拷入 `files/`，依赖由 PACKAGES 显式安装。
  - `shell/prepare-packages.sh`：改为收集 `.apk`。
  - `x86-64/imm.config`：`CONFIG_USE_APK=y`，opkg 相关选项全部替换为 apk / luci-app-package-manager。
  - `files/etc/uci-defaults/99-custom.sh`：`opkg list-installed` → `apk info`，并启用 Lucky 服务、设置 Argon 为默认主题、做网口/防火墙/DNS 等开机初始化。

> ℹ️ 编译日志中 OpenClash 偶现的 `/lib/functions.sh: No such file or directory` 等提示，是 OpenClash 脚本在**构建期**（imagebuilder 准备 rootfs）被提前执行、当时 `/lib/functions.sh` 尚未就位所致，属编译期正常 warning；**不影响固件产出，也不影响 OpenClash 在路由器上运行**（运行时该文件已存在）。

## 🔨 基本用法（GitHub Actions）

1. **Fork 或新建仓库**（见下方"新建 GitHub 项目"）。
2. 进入仓库 **Actions** 标签页 → 选择 **build-x86-64-immortalwrt-25.12.x** 工作流 → **Run workflow**。
3. 按需填写参数：
   - **选择luci版本**：`25.12.0` / `25.12.1` / `25.12.2`（默认最新稳定版 25.12.2）
   - **路由器管理地址**：多网口机型生效，如 `192.168.1.10`
   - **固件大小**：默认 1024（MB）
   - **是否编译 Docker 插件**：`yes` / `no`
   - **是否配置PPPoE**：`yes` 时填写宽带账号/密码
4. 构建完成后固件自动上传到 **Releases**，文件名类似：
   `immortalwrt-25.12.2-x86-64-generic-squashfs-combined-efi.img.gz`

## 🌐 固件默认配置（对应 99-custom.sh）

首次开机 `99-custom.sh` 会自动完成以下初始化（详情见 `files/etc/uci-defaults/99-custom.sh`）：

- **网口映射**：最后一个物理网口为 **WAN**，其余全部为 **LAN**；单网口设备则 **LAN 走 DHCP** 自动获取 IP（类似 NAS，开机即可访问后台）。
- **管理地址**：
  - 多网口设备：静态 IP，为你在 Actions UI 里填的值（默认 `192.168.100.1`，可在界面改）。
  - 单网口设备：DHCP 自动获取，浏览器访问路由器分到的 IP 即可。
- **防火墙**：默认放行 WAN 入站，方便首次访问 WebUI；调试完毕后建议在「网络 → 防火墙」把 WAN 入站改为「拒绝」。
- **安卓原生 TV 联网**：自动写入 `time.android.com → 203.107.6.88` 的 DNS 映射，解决安卓 TV 无法联网的问题。
- **PPPoE 拨号**：可选，`yes` 时按你填的宽带账号/密码拨号。
- **Docker**：可选；集成后自动配置 `172.16.0.0/12` 子网防火墙放行规则。
- **终端/SSH**：所有网口均可访问网页终端（ttyd）与 SSH。
- **主题**：默认启用 **Argon** 主题。
- **Lucky**：默认启用（`lucky.@lucky[0].enabled=1` + init 服务）。
- **版本标识**：`DISTRIB_DESCRIPTION = "Packaged by mantang"`。

## 📦 插件来源

- OpenClash：ImmortalWrt 25.12.2 官方 luci 仓库
- Lucky：wukongdaily/apk（25.12 apk 三件套：`luci-app-lucky` 3.0.3 + `lucky` 2.27.2 + 中文包）
- AdZero：[slobys/AdZero](https://github.com/slobys/AdZero) 官方 Release（v0.21.5，ImmortalWrt 25.12.2）
- Argon：ImmortalWrt 25.12.2 官方 luci 仓库

## 📁 项目结构

```
├── .github/workflows/build-x86-64-25.12.x.yml   # GitHub Actions 工作流
├── files/etc/uci-defaults/99-custom.sh           # 首次开机配置(网络/防火墙/Argon/Lucky/apk适配)
├── shell/
│   ├── custom-packages.sh                        # 可选第三方插件拼接
│   └── prepare-packages.sh                       # 收集 .apk
└── x86-64/
    ├── build25.sh                                # 25.12 构建脚本(Lucky apk / AdZero 集成 + make image)
    └── imm.config                                # 25.12 (apk) 内核配置
```

## 🙏 鸣谢

- [ImmortalWrt](https://github.com/immortalwrt)
- [wukongdaily/AutoBuildImmortalWrt](https://github.com/wukongdaily/AutoBuildImmortalWrt)
- [gdy666/luci-app-lucky](https://github.com/gdy666/lucky) / [Lucky](https://ilucky.net)
- [slobys/AdZero](https://github.com/slobys/AdZero)
- [vernesong/OpenClash](https://github.com/vernesong/OpenClash)
- [kiddin9/kwrt-packages](https://github.com/kiddin9/kwrt-packages)
