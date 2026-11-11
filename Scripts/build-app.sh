#!/bin/bash
set -euo pipefail

configuration="${1:-release}"
if [[ $# -gt 1 || ( "$configuration" != "release" && "$configuration" != "debug" ) ]]; then
    echo "Usage: $0 [release|debug]" >&2
    exit 2
fi

project_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_directory"
run_quietly() {
    local output
    if ! output="$("$@" 2>&1)"; then
        printf '%s\n' "$output" >&2
        return 1
    fi
}

run_quietly swift build --configuration "$configuration" --product AgentBar
if ! binary_directory="$(swift build --configuration "$configuration" --show-bin-path 2>&1)"; then
    printf '%s\n' "$binary_directory" >&2
    exit 1
fi
bundle="$project_directory/build/AgentBar.app"
mkdir -p "$bundle/Contents/MacOS"
cp "$binary_directory/AgentBar" "$bundle/Contents/MacOS/AgentBar"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.agentbar.AgentBar</string>
    <key>CFBundleName</key><string>AgentBar</string>
    <key>CFBundleExecutable</key><string>AgentBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
PLIST
run_quietly codesign --force --sign - "$bundle"
printf '%s\n' "$bundle"
