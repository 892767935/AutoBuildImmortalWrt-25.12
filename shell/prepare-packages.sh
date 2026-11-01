#!/bin/sh
# =============================================================
# prepare-packages.sh —— 25.12 (apk) 版本
# 说明：
#   * ImmortalWrt 25.12 包管理器为 apk，imagebuilder 的 packages/ 目录只认 .apk
#   * 本脚本负责把 extra-packages/ 目录下搜集到的 .apk 统一整理到 packages/
#   * (Lucky 等 apk 已由 build25.sh 直接下载到 packages/，本脚本为兜底/扩展)
# =============================================================

BASE_DIR="extra-packages"
TARGET_DIR="packages"

mkdir -p "$BASE_DIR" "$TARGET_DIR"

# 1. 收集 extra-packages/ 下的 .apk 文件 (含一级子目录)
find "$BASE_DIR" -type f -name "*.apk" ! -path "$TARGET_DIR/*" \
  -exec echo "👉 Found:" {} \; \
  -exec cp -v {} "$TARGET_DIR"/ \; 2>/dev/null

echo "✅ 所有 .apk 文件已整理至 $TARGET_DIR/"

# 列出 packages/ 下最终可用的 .apk
if ls "$TARGET_DIR"/*.apk >/dev/null 2>&1; then
  ls -lh "$TARGET_DIR"/*.apk
else
  echo "ℹ️ packages/ 目录暂无 .apk (Lucky 等 apk 由 build25.sh 下载)"
fi
