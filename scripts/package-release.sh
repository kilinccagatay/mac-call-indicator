#!/bin/sh
# Source-only reproducible packaging; no user preferences or credentials copied.
set -eu
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' packaging/Info.plist)
RELEASE_DIR="dist/releases/v$VERSION"
APP="$RELEASE_DIR/MacCallIndicator.app"
mkdir -p "$RELEASE_DIR" "$APP/Contents/MacOS"

swift build -c release --arch arm64 --scratch-path .local/release-arm64
ARM_DIR=$(swift build -c release --arch arm64 --scratch-path .local/release-arm64 --show-bin-path)
swift build -c release --arch x86_64 --scratch-path .local/release-x86_64
INTEL_DIR=$(swift build -c release --arch x86_64 --scratch-path .local/release-x86_64 --show-bin-path)
xcrun lipo -create "$ARM_DIR/MacCallIndicator" "$INTEL_DIR/MacCallIndicator" \
    -output "$APP/Contents/MacOS/MacCallIndicator"
xcrun strip -S "$APP/Contents/MacOS/MacCallIndicator"
cp packaging/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier local.MacCallIndicator "$APP"
codesign --verify --deep --strict "$APP"

# Fail rather than publish local build paths / household settings.
python3 - "$APP" <<'PY'
from pathlib import Path
import subprocess, sys
binary = Path(sys.argv[1]) / "Contents/MacOS/MacCallIndicator"
architectures = subprocess.check_output(["xcrun", "lipo", "-archs", str(binary)], text=True).split()
if set(architectures) != {"arm64", "x86_64"}:
    raise SystemExit("Both release architectures are required.")
strings = subprocess.check_output(["strings", str(binary)])
if any(value in strings for value in [b"/Users/", b"/home/"]):
    raise SystemExit("Private build path found: package was not published.")
build = subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
minimums = [line.split()[-1] for line in build.splitlines() if line.strip().startswith("minos ")]
if minimums != ["13.0", "13.0"]:
    raise SystemExit("Unexpected deployment target: inspect package before publication.")
print("Universal app signature, architectures and macOS 13 deployment target verified.")
PY

ditto --norsrc -c -k --keepParent "$APP" "$RELEASE_DIR/MacCallIndicator-v$VERSION-macos-universal.zip"
python3 - "$RELEASE_DIR" "$VERSION" <<'PY'
from pathlib import Path
import hashlib, sys, zipfile
out, version = Path(sys.argv[1]), sys.argv[2]
with zipfile.ZipFile(out / f"MacCallIndicator-HomeAssistant-v{version}.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(Path("custom_components/mac_call_indicator").rglob("*")):
        if file.is_file() and "__pycache__" not in file.parts and file.suffix != ".pyc":
            archive.write(file, str(file))
    archive.writestr("INSTALL.txt", "Copy custom_components/mac_call_indicator to your Home Assistant config folder, restart, then add Mac Call Indicator under Devices & services. See the repository Home Assistant guide.\n")
with zipfile.ZipFile(out / f"MacCallIndicator-Screenshots-v{version}.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    for name in ["settings-connection.png", "settings-status-only.png", "settings-color-light.png",
                 "meeting-until-hour.png", "meeting-until-minute.png", "hoarydash-call-badge.png",
                 "accessibility-help.png", "office-agenda-demo.jpg"]:
        file = Path("docs/images") / name
        archive.write(file, name)
lines = [f"{hashlib.sha256(file.read_bytes()).hexdigest()}  {file.name}\n"
         for file in sorted(out.glob("*.zip"))]
(out / "SHA256SUMS.txt").write_text("".join(lines))
print("Application, integration, screenshots and SHA256SUMS packaged.")
PY
