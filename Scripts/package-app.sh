#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$project_dir/dist/Meeting Transcript Prompt.app"
binary_dir="$app_dir/Contents/MacOS"
resource_dir="$app_dir/Contents/Resources"

cd "$project_dir"
swift build -c "$configuration"

mkdir -p "$binary_dir" "$resource_dir"
cp ".build/$configuration/meeting-transcript-prompt" "$binary_dir/meeting-transcript-prompt"
cp "Resources/Info.plist" "$app_dir/Contents/Info.plist"

codesign --force --deep --sign - \
  --entitlements "Resources/MeetingTranscriptPrompt.entitlements" \
  "$app_dir"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dir/Contents/Info.plist")"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$lsregister" -f "$app_dir"
tccutil reset Accessibility "$bundle_id"

echo "$app_dir"
