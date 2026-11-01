#!/bin/bash
# =============================================================
# build24.sh —— ImmortalWrt 24.10.6 (x86-64) 构建脚本
# 说明：
#   * 24.10 系列包管理器为 opkg（.ipk），与 25.12(apk) 不同
#   * 集成插件（与 25.12 保持一致）：
#       1) openclash   —— ImmortalWrt 24.10.6 官方 luci 源 ipk (luci-app-openclash)
#       2) AdZero      —— 官方 release ipk (luci-app-adzero_0.23.4-r1_all.ipk) 文件级集成
#       3) lucky       —— wukongdaily/store 提供的 24.10 ipk（luci-app-lucky + lucky）
#       4) argon 主题  —— 官方 luci 源 ipk (luci-theme-argon)
# =============================================================

# 确保在 imagebuilder 根目录下执行
cd /home/build/immortalwrt || { echo "❌ 无法进入 /home/build/immortalwrt"; exit 1; }
echo "当前工作目录: $(pwd)"
[ -f Makefile ] && echo "✅ 已定位 imagebuilder Makefile" || { echo "❌ /home/build/immortalwrt 下未找到 Makefile"; exit 1; }

source shell/custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"


echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings


# ============= 1. 集成 AdZero (官方 release ipk -> 文件级打入 files/) =============
# 24.10 用 opkg，官方为 ImmortalWrt 提供统一 IPK（luci-app-adzero_0.23.4-r1_all.ipk，noarch）。
# 做法：下载 IPK，解出内层 data.tar.gz 直接解压到 files/（文件落到 /usr、/etc、/www 对应路径），
#       再在 PACKAGES 中补齐其运行时依赖（adblock-fast、ucode 系列、tcpdump 等），
#       make image 时由 imagebuilder 从官方源安装这些依赖，保证 AdZero 在固件内可用。
echo "🔄 正在下载 AdZero 官方 ipk ..."
mkdir -p /home/build/immortalwrt/files
ADZERO_URL="https://github.com/slobys/AdZero/releases/download/v0.23.4/luci-app-adzero_0.23.4-r1_all.ipk"
mkdir -p /tmp/adzero
if wget -q "$ADZERO_URL" -O /tmp/adzero/adzero.ipk; then
  echo "✅ AdZero ipk 已下载:"
  ls -lh /tmp/adzero/adzero.ipk
  cd /tmp/adzero
  tar -xzf adzero.ipk
  if [ -f data.tar.gz ]; then
    tar -xzf data.tar.gz -C /home/build/immortalwrt/files/
    echo "✅ AdZero 文件已解压到 files/"
    find /home/build/immortalwrt/files -iname '*adzero*' 2>/dev/null | head -20
  else
    echo "⚠️ AdZero data.tar.gz 未找到，将不集成"
  fi
  cd /home/build/immortalwrt
else
  echo "⚠️ AdZero 下载失败，将不集成 luci-app-adzero"
fi


# ============= 2. 集成 lucky (wukongdaily/store 提供的 24.10 ipk) =============
# 24.10 官方源无 lucky，这里从 wukongdaily/store 仓库取 x86-64 的 ipk（luci-app-lucky + lucky）。
# 做法：把 ipk 下载到 imagebuilder 的 packages/ 目录，并在 PACKAGES 中加入包名，
#       make image 时 imagebuilder 会自动扫描 packages/ 建立索引并安装。
echo "🔄 正在下载 lucky ipk 到 packages/ ..."
mkdir -p /home/build/immortalwrt/packages
LUCKY_BASE="https://raw.githubusercontent.com/wukongdaily/store/master/run/x86/luci-app-lucky"
wget -q "$LUCKY_BASE/luci-app-lucky_1.2.0-r11_all.ipk" -O /home/build/immortalwrt/packages/luci-app-lucky_1.2.0-r11_all.ipk
wget -q "$LUCKY_BASE/lucky_2.17.8-r8_x86_64.ipk" -O /home/build/immortalwrt/packages/lucky_2.17.8-r8_x86_64.ipk
echo "✅ lucky ipk 已下载到 packages/ :"
ls -lh /home/build/immortalwrt/packages/luci-app-lucky*.ipk /home/build/immortalwrt/packages/lucky*.ipk


# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."


# ============= imm仓库内的插件 =============
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
# ====== argon 主题 ======
PACKAGES="$PACKAGES luci-theme-argon"
# ====== 定时重启 ======
PACKAGES="$PACKAGES luci-app-autoreboot"
PACKAGES="$PACKAGES luci-i18n-autoreboot-zh-cn"
# 24.10 使用 opkg 包管理器，包管理界面为 luci-app-package-manager
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
# ====== lucky (ipk 方式，见上方 lucky 段) ======
PACKAGES="$PACKAGES luci-app-lucky lucky"
# ====== 代理 ======
PACKAGES="$PACKAGES luci-app-openclash"
# ====== 去广告 ======
# AdZero 已改为文件级集成（见上方 AdZero 段），不再加入 PACKAGES（避免走 opkg 索引安装失败）；
# 补齐其运行时依赖（与 IPK control 的 Depends 一致），确保 AdZero 在固件内可用
PACKAGES="$PACKAGES adblock-fast"
PACKAGES="$PACKAGES ca-bundle conntrack coreutils-timeout rpcd-mod-file rpcd-mod-ucode tcpdump"
PACKAGES="$PACKAGES ucode ucode-mod-fs ucode-mod-socket ucode-mod-ubus ucode-mod-uci ucode-mod-uloop"
# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"


# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi


# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi


# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"


# 确保在 imagebuilder 根目录执行 make image (lucky 等子流程曾切换过工作目录)
cd /home/build/immortalwrt


make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE


if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi


echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
