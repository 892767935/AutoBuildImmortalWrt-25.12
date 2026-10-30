#!/bin/bash
# ============= 可选第三方插件 (apk) =============
# 本文件被 x86-64/build25.sh source，用于拼接 ImmortalWrt 仓库外的第三方 apk 包名。
# 打开注释即可加入；对应的 .apk 需提前下载到 imagebuilder 的 packages/ 目录，
# 或由官方/自建 apk 源提供，make image 才会真正安装。
# （Lucky 已通过 build25.sh 的 lucky 段以 apk 三件套集成，无需在此重复。）
CUSTOM_PACKAGES=""
# 示例：
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-aurora luci-app-aurora-config luci-i18n-aurora-config-zh-cn"
