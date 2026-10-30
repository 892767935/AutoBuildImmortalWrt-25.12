#!/bin/bash
# =============================================================
# build25.sh —— ImmortalWrt 25.12.x (x86-64) 构建脚本
# 说明：
#   * 25.12 起 ImmortalWrt 包管理器由 opkg 改为 apk
#   * 官方仓库包为 .apk，imagebuilder 的 packages/ 目录只认 .apk
#   * 集成插件：
#       1) openclash   —— 官方 luci 仓库 apk (luci-app-openclash)
#       2) AdZero      —— 官方 release apk (adzero-immortalwrt-25.12.2-x86_64.apk)
#       3) lucky       —— 官方/第三方源只有 ipk，25.12 无 apk，采用"文件级集成"
#                          (下载 ipk -> 解包 -> 把文件放入 files/ 由 imagebuilder 拷入 rootfs)
#       4) argon 主题  —— 官方 luci 仓库 apk (luci-theme-argon + luci-app-argon-config)
# =============================================================

# 确保在 imagebuilder 根目录下执行
# (25.12 镜像的 WORKDIR 与 24.10 不同，可能不在 /home/build/immortalwrt，
#  必须显式 cd，否则 make image 找不到 Makefile、相对路径 files/ 也会落错目录)
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

# ============= 1. 集成 AdZero (官方 apk -> packages 目录) =============
# AdZero = luci-app-adzero，官方为 ImmortalWrt 25.12.2 提供预编译 apk
echo "🔄 正在下载 AdZero 官方 apk ..."
mkdir -p /home/build/immortalwrt/packages
ADZERO_URL="https://github.com/slobys/AdZero/releases/download/v0.21.5/adzero-immortalwrt-25.12.2-x86_64.apk"
if wget -q "$ADZERO_URL" -O /home/build/immortalwrt/packages/adzero-immortalwrt-25.12.2-x86_64.apk; then
  echo "✅ AdZero apk 已下载:"
  ls -lh /home/build/immortalwrt/packages/*.apk
else
  echo "⚠️ AdZero 下载失败，将不集成 luci-app-adzero"
fi

# ===== 诊断: apk mkndx 是否能正确解析 packages/*.apk =====
(
  cd /home/build/immortalwrt/packages
  echo "=== 诊断 apk mkndx ==="
  ls -la /home/build/immortalwrt/staging_dir/host/bin/apk* 2>&1 | head
  APK_BIN=/home/build/immortalwrt/staging_dir/host/bin/apk
  echo "--- 单独解析 adzero ---"
  "$APK_BIN" mkndx --allow-untrusted --output /tmp/az.adb adzero-immortalwrt-25.12.2-x86_64.apk 2>&1 | head -20
  echo "adzero mkndx exit=$?"
  if [ -f /tmp/az.adb ]; then echo "az.adb 大小: $(wc -c < /tmp/az.adb)"; fi
  echo "--- 生成 packages/packages.adb (mkndx 全部) ---"
  "$APK_BIN" mkndx --allow-untrusted --output packages.adb *.apk 2>&1 | head
  echo "--- apk list 带 root 查真实包名 ---"
  mkdir -p /home/build/immortalwrt/tmp/root
  "$APK_BIN" --root /home/build/immortalwrt/tmp/root --initdb --repositories-file /dev/null --repository /home/build/immortalwrt/packages/packages.adb --allow-untrusted update 2>&1 | head -5
  "$APK_BIN" --root /home/build/immortalwrt/tmp/root --repositories-file /dev/null --repository /home/build/immortalwrt/packages/packages.adb list 2>&1 | head -40
  echo "--- apk info 单个 adzero apk 直接读 pkgname ---"
  "$APK_BIN" --root /home/build/immortalwrt/tmp/root --repositories-file /dev/null --repository /home/build/immortalwrt/packages/packages.adb --allow-untrusted info adzero-immortalwrt-25.12.2-x86_64 2>&1 | head -20
  "$APK_BIN" --root /home/build/immortalwrt/tmp/root --repositories-file /dev/null --repository /home/build/immortalwrt/packages/packages.adb --allow-untrusted info '*' 2>&1 | head -40
  echo "--- 解析所有 apk ---"
  "$APK_BIN" mkndx --allow-untrusted --output /tmp/test.adb *.apk 2>&1 | head -40
  echo "all mkndx exit=$?"
  if [ -f /tmp/test.adb ]; then echo "test.adb 大小: $(wc -c < /tmp/test.adb)"; fi
  echo "=== 诊断结束 ==="
)

# ============= 2. 集成 lucky (文件级集成，解包到 files) =============
# lucky 官方/主流源只有 .ipk (25.12 无 apk)，但 lucky 二进制为静态编译(仅依赖libc)，
# 且只有 4 个文件，非常适合"文件级集成"：解包后放入 files/ 由 imagebuilder 拷入 rootfs。
echo "🔄 正在下载 lucky ipk 并解包到 files ..."
LUCKY_URL="https://dl.openwrt.ai/packages-25.12/x86_64/kiddin9/lucky_2.27.2-r4_x86_64.ipk"
mkdir -p /tmp/lucky
if wget -q "$LUCKY_URL" -O /tmp/lucky/lucky.ipk; then
  # 用 subshell 包裹 cd，避免改变主脚本的工作目录（否则后续 make image 会找不到 Makefile）
  (
    cd /tmp/lucky
    # lucky.ipk 实际是 gzip 压缩的 tar 容器，内含 data.tar.gz / control.tar.gz
    tar xzf lucky.ipk
    if [ -f data.tar.gz ]; then
      # 把 data 里的文件 (./etc/init.d/lucky ./etc/config/lucky ./usr/bin/lucky ./usr/libexec/lucky-runner) 解到 files/
      tar xzf data.tar.gz -C /home/build/immortalwrt/files/
      chmod +x /home/build/immortalwrt/files/usr/bin/lucky 2>/dev/null
      chmod +x /home/build/immortalwrt/files/etc/init.d/lucky 2>/dev/null
      chmod +x /home/build/immortalwrt/files/usr/libexec/lucky-runner 2>/dev/null
      echo "✅ lucky 文件已集成到 files/ :"
      ls -lh /home/build/immortalwrt/files/usr/bin/lucky
    else
      echo "⚠️ lucky ipk 解包失败(未找到 data.tar.gz)"
    fi
  )
else
  echo "⚠️ lucky 下载失败，将不集成 lucky"
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# ============= imm仓库内的插件 =============
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
# ====== argon 主题 ======
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
# 25.12 使用 apk 包管理器，包管理界面为 luci-app-package-manager (替代 luci-app-opkg)
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
# ====== 代理 ======
PACKAGES="$PACKAGES luci-app-openclash"
# ====== 去广告 ======
PACKAGES="$PACKAGES luci-app-adzero"
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
