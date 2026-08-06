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
zip_name="Foldwalls-$release_version-macOS.zip"
dmg_name="Foldwalls-$release_version-macOS.dmg"
zip_path="$artifacts_dir/$zip_name"
dmg_path="$artifacts_dir/$dmg_name"

mkdir -p "$tools_dir" "$artifacts_dir"

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

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

rm -rf "$staging_dir"
mkdir -p "$staging_dir"
ditto "$app_path" "$staging_dir/Foldwalls.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create \
  -volname "Foldwalls $release_version" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path" >/dev/null

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
