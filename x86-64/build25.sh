#!/bin/bash
# =============================================================
# build25.sh —— ImmortalWrt 25.12.x (x86-64) 构建脚本
# 说明：
#   * 25.12 起 ImmortalWrt 包管理器由 opkg 改为 apk
#   * 官方仓库包为 .apk，imagebuilder 的 packages/ 目录只认 .apk
#   * 集成插件：
#       1) openclash   —— 官方 luci 仓库 apk (luci-app-openclash)
#       2) AdZero      —— 官方 release apk (adzero-immortalwrt-25.12.2-x86_64.apk)
#       3) lucky       —— apk 方式（借鉴 wukongdaily/apk：luci-app-lucky + lucky + 中文包）
#                          (下载 3 个 apk 到 packages/，PACKAGES 加包名，make image 自动安装)
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


# ============= 1. 集成 AdZero (官方 apk -> apk add 到临时 root -> 拷专属文件到 files/) =============
# AdZero = luci-app-adzero，官方为 ImmortalWrt 25.12.2 提供预编译 apk。
# 官方 install.sh 的安装方式是 `apk add <file.apk>` 直接装本地文件（不经过包索引/包名）。
# 经排查：apk-tools 3.0.5 不支持 --no-deps；apk add 到空 root 须配置官方仓库才能解析依赖
# （Makefile 用 --repositories-file <TOPDIR>/repositories + --repository <PACKAGE_DIR>/packages.adb）。
# 因此这里：apk add adzero 到临时 root（依赖从官方仓库拉取），再用 apk info -L 列出 adzero 专属
# 文件拷入 files/，由 imagebuilder 拷入固件 rootfs（不拷贝官方依赖，避免版本覆盖）。
echo "🔄 正在下载 AdZero 官方 apk ..."
mkdir -p /home/build/immortalwrt/packages
ADZERO_URL="https://github.com/slobys/AdZero/releases/download/v0.21.5/adzero-immortalwrt-25.12.2-x86_64.apk"
APK_BIN=/home/build/immortalwrt/staging_dir/host/bin/apk
REPOS_FILE=/home/build/immortalwrt/repositories
if wget -q "$ADZERO_URL" -O /home/build/immortalwrt/packages/adzero-immortalwrt-25.12.2-x86_64.apk; then
  echo "✅ AdZero apk 已下载:"
  ls -lh /home/build/immortalwrt/packages/adzero-immortalwrt-25.12.2-x86_64.apk
  echo "--- imagebuilder 官方仓库列表 ---"
  cat "$REPOS_FILE" 2>/dev/null | head -10
  echo "--- apk add 到临时 root (依赖从官方仓库解析) ---"
  rm -rf /tmp/adzroot && mkdir -p /tmp/adzroot
  "$APK_BIN" --root /tmp/adzroot --initdb --repositories-file "$REPOS_FILE" --allow-untrusted add /home/build/immortalwrt/packages/adzero-immortalwrt-25.12.2-x86_64.apk > /tmp/adzero_add.log 2>&1
  echo "apk add exit=$?"
  tail -25 /tmp/adzero_add.log
  if [ -d /tmp/adzroot/usr ] || [ -d /tmp/adzroot/etc ]; then
    echo "✅ adzero 安装成功! 拷贝专属文件到 files/"
    "$APK_BIN" --root /tmp/adzroot info -L luci-app-adzero 2>/dev/null | while IFS= read -r rel; do
      rel="${rel#/}"
      [ -z "$rel" ] && continue
      case "/$rel" in
        /etc/*|/usr/*|/lib/*|/www/*|/overlay/*)
          src="/tmp/adzroot/$rel"
          if [ -f "$src" ]; then
            dstdir="/home/build/immortalwrt/files/$(dirname "$rel")"
            mkdir -p "$dstdir"
            cp -a "$src" "/home/build/immortalwrt/files/$rel"
          fi
          ;;
      esac
    done
    echo "--- files/ 中 adzero 相关文件 ---"
    find /home/build/immortalwrt/files -iname '*adzero*' 2>/dev/null | head -30
  else
    echo "⚠️ adzero 安装失败，将不集成"
    exit 1
  fi
else
  echo "⚠️ AdZero 下载失败，将不集成 luci-app-adzero"
fi


# ============= 2. 集成 lucky (apk 方式，借鉴 wukongdaily/ImmortalWrt-ImageBuilder) =============
# 25.12 官方/主流源(dl.openwrt.ai)只有 lucky 的 .ipk，但 wukongdaily/apk 仓库为 25.12 提供
# 完整 apk 三件套：luci-app-lucky(界面) + lucky(核心) + luci-i18n-lucky-zh-cn(中文)。
# 做法：把 apk 下载到 imagebuilder 的 packages/ 目录，并在 PACKAGES 中加入包名，
#       make image 时 imagebuilder 会自动扫描 packages/ 目录建立 apk 索引并安装。
#       这样侧边栏菜单与 apk 管理器均可见（标准 apk 安装）。
echo "🔄 正在下载 lucky apk 三件套到 packages/ ..."
mkdir -p /home/build/immortalwrt/packages
LUCKY_BASE="https://github.com/wukongdaily/apk/raw/master/run/x86/lucky"
wget -q "$LUCKY_BASE/luci-app-lucky-3.0.3-r15.apk" -O /home/build/immortalwrt/packages/luci-app-lucky-3.0.3-r15.apk
wget -q "$LUCKY_BASE/luci-i18n-lucky-zh-cn-26.021.55893~28c17bc.apk" -O /home/build/immortalwrt/packages/luci-i18n-lucky-zh-cn-26.021.55893~28c17bc.apk
wget -q "$LUCKY_BASE/lucky-2.27.2-r1.apk" -O /home/build/immortalwrt/packages/lucky-2.27.2-r1.apk
echo "✅ lucky apk 已下载到 packages/ :"
ls -lh /home/build/immortalwrt/packages/luci-app-lucky*.apk /home/build/immortalwrt/packages/lucky*.apk


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
# PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
# 25.12 使用 apk 包管理器，包管理界面为 luci-app-package-manager (替代 luci-app-opkg)
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
# ====== lucky (apk 方式，见上方 lucky 段) ======
PACKAGES="$PACKAGES luci-app-lucky lucky luci-i18n-lucky-zh-cn"
# ====== 代理 ======
PACKAGES="$PACKAGES luci-app-openclash"
# ====== 去广告 ======
# AdZero 已改为文件级集成（见上方 AdZero 段），不再加入 PACKAGES（避免走 apk 索引安装失败）；
# 补齐其运行时依赖，确保 AdZero 在固件内可用
PACKAGES="$PACKAGES adblock-fast"
PACKAGES="$PACKAGES ca-bundle conntrack coreutils-timeout rpcd-mod-file rpcd-mod-ucode tcpdump-mini"
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
