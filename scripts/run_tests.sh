#!/bin/bash
# 自动化功能测试脚本
# 编译、运行模拟器、执行 UI 测试

set -e

PROJECT_NAME="BookReader"
SCHEME="BookReader"
UI_TEST_SCHEME="BookReaderUITests"
DESTINATION="platform=iOS Simulator,name=iPhone 16"

echo "=== BookReader 自动化测试 ==="

# 检查是否需要生成项目
if [ ! -f "$PROJECT_NAME.xcodeproj" ]; then
    echo "生成 Xcode 项目..."
    xcodegen generate
fi

# 检查模拟器是否运行，如果没有则启动
SIMULATOR_RUNNING=$(xcrun simctl list devices | grep "Booted" | head -1)
if [ -z "$SIMULATOR_RUNNING" ]; then
    echo "启动模拟器..."
    open -a Simulator
    sleep 5
    # 等待模拟器启动
    xcrun simctl boot "iPhone 16" 2>/dev/null || true
    sleep 3
fi

# 编译并运行 UI 测试
echo "编译并运行 UI 测试..."
xcodebuild test \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$UI_TEST_SCHEME" \
    -destination "$DESTINATION" \
    -quiet

TEST_RESULT=$?

if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ 测试通过"
    exit 0
else
    echo "❌ 测试失败"
    exit 1
fi
