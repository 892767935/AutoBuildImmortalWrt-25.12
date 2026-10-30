# AutoBuildImmortalWrt-25.12

基于 **ImmortalWrt 25.12 系列** + ImageBuilder + GitHub Actions 的 x86-64 固件自动编译项目。

> 本项目为原 [AutoBuildImmortalWrt](https://github.com/wukongdaily/AutoBuildImmortalWrt) 的 **25.12 (apk) 版本**独立仓库。
> 原项目仅支持到 24.10.6（opkg 包管理）；25.12 起 ImmortalWrt 已全面切换到 **apk** 包管理器，本项目据此完整适配。

## 🚀 本仓库默认集成插件

| 插件 | 集成方式 | 说明 |
|------|----------|------|
| **OpenClash** | 官方 luci apk | `luci-app-openclash`，自动附带 clash_meta 内核 + GeoIP/GeoSite 数据库 |
| **Lucky** | 文件级集成 | 25.12 官方/第三方源暂无 apk（仅 ipk），本仓库将 Lucky 二进制与启动脚本以文件形式打入固件，刷机即用 |
| **AdZero** | 官方 release apk | `luci-app-adzero`，官方为 ImmortalWrt 25.12.2 提供预编译 apk |
| **Argon 主题** | 官方 luci apk | `luci-theme-argon` + `luci-app-argon-config`，并设为默认主题 |

同时默认预装：`curl`、`luci-i18n-firewall-zh-cn`、`luci-i18n-package-manager-zh-cn`（25.12 的软件包管理界面，替代 luci-app-opkg）。

支持可选：Docker（`luci-i18n-dockerman-zh-cn`）、PPPoE 拨号、自定义管理 IP、自定义固件大小。

## ⚙️ 关于 25.12 的 apk 机制（必读）

- ImmortalWrt **25.12 起包管理器从 opkg 改为 apk**，官方仓库包为 `.apk` 格式。
- ImageBuilder 的 `packages/` 目录只认 `.apk` 文件，`.ipk` 无法被 25.12 安装。
- 本项目已按此适配：
  - `x86-64/build25.sh`：下载 AdZero 官方 apk 到 `packages/`；下载 Lucky ipk 解包到 `files/`（文件级集成）。
  - `shell/prepare-packages.sh`：改为收集 `.apk`。
  - `x86-64/imm.config`：`CONFIG_USE_APK=y`，opkg 相关选项全部替换为 apk / luci-app-package-manager。
  - `files/etc/uci-defaults/99-custom.sh`：`opkg list-installed` → `apk info`，并启用 Lucky 服务、设置 Argon 为默认主题。

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

## 🌐 固件默认属性

- **单网口设备**：默认 DHCP 模式，自动获取 IP（类似 NAS 做法）。
- **多网口设备**：末位网口为 WAN（DHCP），其余为 LAN，管理地址为你在 UI 设置的值（默认 `192.168.100.1`）。
- 默认开启 WAN 口入站防火墙，方便首次访问；调试完毕后建议在「网络 → 防火墙」关闭 WAN 入站。

## 🆕 如何在 GitHub 新建项目（保姆级）

> 如果你不想 fork，而是想**从零新建一个仓库**放这套 25.12 方案：

1. 登录 GitHub → 右上角 **+** → **New repository**。
2. Repository name 填如 `AutoBuildImmortalWrt-25.12`；选择 **Public**（或 Private）；**不要**勾选 "Add a README file"（否则会冲突）。
3. 点击 **Create repository**。
4. 在本机把本仓库目录初始化为 git 并推送：

   ```bash
   cd AutoBuildImmortalWrt-25.12
   git init
   git add .
   git commit -m "feat: ImmortalWrt 25.12 build with OpenClash/Lucky/AdZero/Argon"
   git branch -M main
   git remote add origin https://github.com/你的用户名/AutoBuildImmortalWrt-25.12.git
   git push -u origin main
   ```

5. 回到 GitHub 仓库 → **Actions** → 按上文基本用法运行工作流。

> 💡 若提示 Actions 未启用，在仓库 **Settings → Actions → General** 打开权限即可。

## 📦 插件来源

- OpenClash：ImmortalWrt 25.12.2 官方 luci 仓库
- Lucky：kiddin9 `dl.openwrt.ai/packages-25.12`（文件级集成，版本 2.27.2）
- AdZero：[slobys/AdZero](https://github.com/slobys/AdZero) 官方 Release（v0.21.5，ImmortalWrt 25.12.2）
- Argon：ImmortalWrt 25.12.2 官方 luci 仓库

## 📁 项目结构

```
├── .github/workflows/build-x86-64-25.12.x.yml   # GitHub Actions 工作流
├── files/etc/uci-defaults/99-custom.sh           # 首次开机配置(apk适配 + Lucky + Argon)
├── shell/
│   ├── custom-packages.sh                        # 可选第三方插件拼接
│   └── prepare-packages.sh                       # 收集 .apk
└── x86-64/
    ├── build25.sh                                # 25.12 构建脚本
    └── imm.config                                # 25.12 (apk) 内核配置
```

## 🙏 鸣谢

- [ImmortalWrt](https://github.com/immortalwrt)
- [wukongdaily/AutoBuildImmortalWrt](https://github.com/wukongdaily/AutoBuildImmortalWrt)
- [gdy666/luci-app-lucky](https://github.com/gdy666/lucky) / [Lucky](https://ilucky.net)
- [slobys/AdZero](https://github.com/slobys/AdZero)
- [vernesong/OpenClash](https://github.com/vernesong/OpenClash)
- [kiddin9/kwrt-packages](https://github.com/kiddin9/kwrt-packages)
