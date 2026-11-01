#!/bin/bash
# =============================================================
# build24.sh —— ImmortalWrt 24.10.6 (x86-64) 构建脚本
# 说明：
#   * 24.10 系列包管理器为 opkg（.ipk），与 25.12(apk) 不同
#   * 集成插件（与 25.12 保持一致）：
#       1) openclash   —— ImmortalWrt 24.10.6 官方 luci 源 ipk (luci-app-openclash)
#       2) lucky       —— wukongdaily/store 提供的 24.10 ipk（luci-app-lucky + lucky）
#       3) argon 主题  —— 官方 luci 源 ipk (luci-theme-argon)
#       4) 定时重启    —— 官方 luci 源 ipk (luci-app-autoreboot)
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


# ============= 1. 集成 lucky (wukongdaily/store 提供的 24.10 ipk) =============
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
