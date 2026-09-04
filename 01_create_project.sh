#!/bin/bash
set -e

PROJECT_NAME="PhotoName"
BUNDLE_ID="com.longint.photoname"  # ← 改成你的 Bundle ID

echo "🔨 Creating Xcode Multiplatform Project..."

# 使用 xcodegen 直接生成项目（无需手动在 Xcode 中创建）
# 先确保 project.yml 存在
if [ ! -f "project.yml" ]; then
    echo "❌ project.yml not found. Please place it in the same directory."
    exit 1
fi

xcodegen generate

echo "✅ Xcode project generated successfully."
echo "📂 Open ${PROJECT_NAME}.xcodeproj in Xcode to verify."
