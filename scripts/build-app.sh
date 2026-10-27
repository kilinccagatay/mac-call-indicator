#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP=dist/MacCallIndicator.app
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MacCallIndicator "$APP/Contents/MacOS/MacCallIndicator"
cp packaging/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier local.MacCallIndicator "$APP"
echo "Built $APP"
