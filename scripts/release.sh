#!/bin/bash

set -euo pipefail

workspace_dir=$(cd "$(dirname "$0")/.." && pwd)
publish_release=false
release_version=""
notes_file=""

usage() {
  echo "Usage: scripts/release.sh <version> <release-notes-file> [--publish]"
  echo "Example: scripts/release.sh 0.3.0 release-notes/0.3.0.txt --publish"
}

for argument in "$@"; do
  case "$argument" in
    --publish) publish_release=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$release_version" ]]; then
        release_version="$argument"
      elif [[ -z "$notes_file" ]]; then
        notes_file="$argument"
      else
        echo "Unexpected argument: $argument" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$release_version" || -z "$notes_file" ]]; then
  usage
  exit 1
fi

cd "$workspace_dir"
notes_file=$(cd "$(dirname "$notes_file")" && pwd)/$(basename "$notes_file")

if [[ ! -f "$notes_file" ]]; then
  echo "Release notes file does not exist: $notes_file" >&2
  exit 1
fi

if ! [[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Version must look like 0.3.0 or 0.3.0-beta.1" >&2
  exit 1
fi

if [[ "$publish_release" == true ]]; then
  command -v gh >/dev/null || {
    echo "GitHub CLI is required for --publish. Install it with: brew install gh" >&2
    exit 1
  }
  gh auth status >/dev/null
  unexpected_changes=$(git status --short | grep -Ev '^( M|M |MM) (CinematicWall\.xcodeproj/project\.pbxproj|appcast\.xml)$' || true)
  [[ -z "$unexpected_changes" ]] || {
    echo "Commit the app changes before publishing. Only prepared version/appcast changes may remain:" >&2
    printf '%s\n' "$unexpected_changes" >&2
    exit 1
  }
fi

sparkle_version="2.9.5"
tools_dir="$workspace_dir/.tools/sparkle-$sparkle_version"
release_work_dir="$workspace_dir/.release-work/$release_version"
derived_data_dir="$release_work_dir/DerivedData"
products_dir="$derived_data_dir/Build/Products/Release"
artifacts_dir="$release_work_dir/artifacts"
staging_dir="$release_work_dir/dmg"
mount_dir="$release_work_dir/dmg-mount"
rw_dmg_path="$release_work_dir/Foldwalls-$release_version-rw.dmg"
background_path="$workspace_dir/Design/foldwalls-dmg-background-v1.png"
zip_name="Foldwalls-$release_version-macOS.zip"
dmg_name="Foldwalls-$release_version-macOS.dmg"
zip_path="$artifacts_dir/$zip_name"
dmg_path="$artifacts_dir/$dmg_name"

mkdir -p "$tools_dir" "$artifacts_dir"

if [[ ! -f "$background_path" ]]; then
  echo "DMG background does not exist: $background_path" >&2
  exit 1
fi

if [[ ! -x "$tools_dir/bin/sign_update" ]]; then
  archive_path="$tools_dir/Sparkle.tar.xz"
  curl -fsSL \
    "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" \
    -o "$archive_path"
  tar -xJf "$archive_path" -C "$tools_dir"
fi

current_build=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\);/\1/p' CinematicWall.xcodeproj/project.pbxproj | head -1)
current_version=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' CinematicWall.xcodeproj/project.pbxproj | head -1)
if [[ "$current_version" == "$release_version" ]]; then
  next_build=$current_build
else
  next_build=$((current_build + 1))
fi

perl -0pi -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $release_version;/g; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $next_build;/g" CinematicWall.xcodeproj/project.pbxproj

xcodebuild \
  -project CinematicWall.xcodeproj \
  -scheme CinematicWall \
  -configuration Release \
  -derivedDataPath "$derived_data_dir" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

app_path="$products_dir/Foldwalls.app"
if [[ ! -d "$app_path" ]]; then
  echo "Foldwalls.app was not produced." >&2
  exit 1
fi

# codesign --verify alone does not prove that a Hardened Runtime app can load
# every embedded framework. In particular, an ad-hoc host may pass structural
# verification and still be killed by dyld when loading Sparkle. Exercise the
# packaged executable against an empty library and require it to remain alive.
cold_launch_root="$release_work_dir/cold-launch-library"
cold_launch_log="$release_work_dir/cold-launch.log"
rm -rf "$cold_launch_root"
mkdir -p "$cold_launch_root"

FOLDWALLS_LIBRARY_ROOT="$cold_launch_root" \
  "$app_path/Contents/MacOS/Foldwalls" >"$cold_launch_log" 2>&1 &
cold_launch_pid=$!
cold_launch_failed=false
for _ in 1 2 3 4 5 6; do
  sleep 1
  if ! kill -0 "$cold_launch_pid" 2>/dev/null; then
    cold_launch_failed=true
    break
  fi
done

if [[ "$cold_launch_failed" == true ]]; then
  set +e
  wait "$cold_launch_pid"
  cold_launch_status=$?
  set -e
  echo "Foldwalls failed the clean cold-launch check (status $cold_launch_status)." >&2
  sed -n '1,160p' "$cold_launch_log" >&2
  exit 1
fi

kill -TERM "$cold_launch_pid" 2>/dev/null || true
wait "$cold_launch_pid" 2>/dev/null || true
echo "Clean cold-launch check passed."

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

rm -rf "$staging_dir"
mkdir -p "$staging_dir/.background"
ditto "$app_path" "$staging_dir/Foldwalls.app"
ln -s /Applications "$staging_dir/Applications"
ditto "$background_path" "$staging_dir/.background/background.png"

volume_name="Foldwalls Installer $release_version"
rm -f "$rw_dmg_path" "$dmg_path"
rm -rf "$mount_dir"
mkdir -p "$mount_dir"
hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "$rw_dmg_path" >/dev/null

dmg_is_mounted=false
cleanup_mounted_dmg() {
  if [[ "$dmg_is_mounted" == true ]]; then
    hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true
  fi
}
trap cleanup_mounted_dmg EXIT

hdiutil attach \
  "$rw_dmg_path" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$mount_dir" >/dev/null
dmg_is_mounted=true

osascript <<APPLESCRIPT
set dmgFolder to POSIX file "$mount_dir" as alias
set backgroundPicture to POSIX file "$mount_dir/.background/background.png" as alias
tell application "Finder"
  open dmgFolder
  set dmgWindow to container window of dmgFolder
  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set pathbar visible of dmgWindow to false
  set bounds of dmgWindow to {160, 100, 920, 630}

  set iconOptions to icon view options of dmgWindow
  set arrangement of iconOptions to not arranged
  set icon size of iconOptions to 112
  set text size of iconOptions to 13
  set label position of iconOptions to bottom
  set background picture of iconOptions to backgroundPicture

  set position of item "Foldwalls.app" of dmgFolder to {205, 245}
  set position of item "Applications" of dmgFolder to {555, 245}

  update dmgFolder without registering applications
  delay 3
  close dmgWindow
  delay 2
end tell
APPLESCRIPT

sync
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -f "$mount_dir/.DS_Store" ]] && break
  sleep 1
done
if [[ ! -f "$mount_dir/.DS_Store" ]]; then
  echo "Finder did not persist the DMG layout." >&2
  exit 1
fi

hdiutil detach "$mount_dir" >/dev/null
dmg_is_mounted=false
trap - EXIT

hdiutil convert \
  "$rw_dmg_path" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$dmg_path" >/dev/null
rm -f "$rw_dmg_path"

signature_output=$("$tools_dir/bin/sign_update" "$zip_path")
ed_signature=$(printf '%s\n' "$signature_output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
archive_length=$(stat -f %z "$zip_path")
published_at=$(LC_ALL=C date -R)
notes_content=$(sed 's/]]>/]]]]><![CDATA[>/g' "$notes_file")

if [[ -z "$ed_signature" ]]; then
  echo "Sparkle did not return an EdDSA signature." >&2
  exit 1
fi

appcast_tmp="$release_work_dir/appcast.xml"
{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
  echo '  <channel>'
  echo '    <title>Foldwalls Updates</title>'
  echo '    <link>https://github.com/ramboxian/Foldwalls</link>'
  echo '    <description>Foldwalls stable release feed</description>'
  echo '    <language>zh-cn</language>'
  echo '    <item>'
  echo "      <title>Foldwalls $release_version</title>"
  echo "      <pubDate>$published_at</pubDate>"
  echo "      <sparkle:version>$next_build</sparkle:version>"
  echo "      <sparkle:shortVersionString>$release_version</sparkle:shortVersionString>"
  echo '      <description sparkle:descriptionFormat="plain-text"><![CDATA['
  printf '%s\n' "$notes_content"
  echo '      ]]></description>'
  echo "      <enclosure url=\"https://github.com/ramboxian/Foldwalls/releases/download/v$release_version/$zip_name\" length=\"$archive_length\" type=\"application/octet-stream\" sparkle:edSignature=\"$ed_signature\" />"
  echo '    </item>'
  echo '  </channel>'
  echo '</rss>'
} > "$appcast_tmp"

cp "$appcast_tmp" "$workspace_dir/appcast.xml"

echo "Prepared Foldwalls $release_version (build $next_build)"
echo "ZIP: $zip_path"
echo "DMG: $dmg_path"
echo "Appcast: $workspace_dir/appcast.xml"

if [[ "$publish_release" == true ]]; then
  gh release create "v$release_version" \
    "$zip_path" \
    "$dmg_path" \
    --repo ramboxian/Foldwalls \
    --title "Foldwalls $release_version" \
    --notes-file "$notes_file"

  git add CinematicWall.xcodeproj/project.pbxproj appcast.xml
  git commit -m "Release Foldwalls $release_version"
  git push origin main
  echo "Published Foldwalls $release_version and pushed the signed appcast."
else
  echo "Prepared only. Re-run with --publish after reviewing the app and release notes."
fi
