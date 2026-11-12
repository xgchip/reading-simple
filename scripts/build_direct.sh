#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
# Production-isolated direct distribution. No upload to GitHub and no local App replacement.
set -eu
cd "${0:A:h:h}"
direct_version="${DIRECT_VERSION:-1.0.0}"
direct_build="${DIRECT_BUILD_NUMBER:-1}"
direct_copyright="${DIRECT_COPYRIGHT:-2026 Yanli Tan}"
direct_output="${1:-$PWD/release/direct}"
direct_output="${direct_output:A}"
direct_identity="${DIRECT_SIGNING_IDENTITY:--}"
direct_notary="${DIRECT_NOTARY_PROFILE:-}"
if [[ -e "$direct_output" ]]; then
    echo 'Output already exists; choose a new directory. Existing releases are never overwritten.' >&2
    exit 2
fi
if [[ "$direct_identity" != - && "$direct_identity" != 'Developer ID Application:'* ]]; then
    echo 'Direct distribution requires an explicit Developer ID Application identity, or - for ad-hoc.' >&2
    exit 2
fi
if [[ -n "$direct_notary" && "$direct_identity" == - ]]; then
    echo 'Notarization requires Developer ID signing; no credentials are requested for ad-hoc builds.' >&2
    exit 2
fi
if [[ "$direct_identity" != - ]]; then
    security find-identity -v -p codesigning | DIRECT_EXPECTED_IDENTITY="$direct_identity" python3 -c 'import os,sys; sys.exit(0 if "\""+os.environ["DIRECT_EXPECTED_IDENTITY"]+"\"" in sys.stdin.read() else 1)'
fi
mkdir -p build/direct Reader.xcodeproj "$direct_output"
# Resources under ReaderApp are checked in: no private design directory or local Xcode account required.
python3 scripts/generate_project.py
xcodebuild -project Reader.xcodeproj -scheme MarginReader-AppStore -configuration AppStore \
    -destination 'generic/platform=macOS' -derivedDataPath build/direct/DerivedData \
    -clonedSourcePackagesDirPath build/direct/SourcePackages \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SWIFT_ACTIVE_COMPILATION_CONDITIONS=APPSTORE \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    "MARKETING_VERSION=$direct_version" "CURRENT_PROJECT_VERSION=$direct_build" \
    "APP_COPYRIGHT=$direct_copyright" build > "$direct_output/build.log" 2>&1
direct_app="$direct_output/阅读从简.app"
ditto build/direct/DerivedData/Build/Products/AppStore/MarginReader.app "$direct_app"
direct_sign_args=(--force --sign "$direct_identity" --options runtime)
if [[ "$direct_identity" != - ]]; then direct_sign_args+=(--timestamp);fi
# Sign nested resource bundles first; do not use --deep to select production entitlements.
while IFS= read -r -d '' direct_bundle; do
    codesign "${direct_sign_args[@]}" "$direct_bundle"
done < <(find "$direct_app/Contents" -depth -type d -name '*.bundle' -print0)
codesign "${direct_sign_args[@]}" --entitlements ReaderApp/MarginReader.entitlements "$direct_app"
codesign --verify --deep --strict "$direct_app"
if [[ -n "$direct_notary" ]]; then
    ditto -c -k --keepParent "$direct_app" "$direct_output/notarization-app.zip"
    xcrun notarytool submit "$direct_output/notarization-app.zip" --keychain-profile "$direct_notary" --wait --output-format json > "$direct_output/notarization-app.json"
    python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("status")=="Accepted" else 1)' "$direct_output/notarization-app.json"
    xcrun stapler staple "$direct_app"
    xcrun stapler validate "$direct_app"
    rm "$direct_output/notarization-app.zip"
fi
direct_stage=$(mktemp -d "$PWD/build/direct/dmg-stage.XXXXXX")
trap 'rm -rf "$direct_stage"' EXIT
ditto "$direct_app" "$direct_stage/阅读从简.app"
ln -s /Applications "$direct_stage/Applications"
cp ReaderApp/Resources/COPYING.txt "$direct_stage/COPYING.txt"
mkdir "$direct_stage/第三方许可"
cp ReaderApp/Resources/ZIPFoundation-LICENSE.txt ReaderApp/Resources/PaperTexture-LICENSE.txt "$direct_stage/第三方许可/"
if [[ "$direct_identity" == - ]]; then
    print -r -- "阅读从简 $direct_version — 公开测试版。此包为 ad-hoc 签名，未经 Apple 公证。macOS 可能阻止首次打开；请自行判断来源，不要关闭系统安全功能。将 App 拖入 Applications 安装。书籍与想法保存在本机。" > "$direct_stage/安装说明.txt"
else
    print -r -- '将“阅读从简”拖入 Applications 安装。书籍与想法保存在本机。' > "$direct_stage/安装说明.txt"
fi
direct_dmg="$direct_output/ReadingSimple-$direct_version-arm64.dmg"
hdiutil create -volname '阅读从简' -srcfolder "$direct_stage" -format UDZO -ov "$direct_dmg" > "$direct_output/dmg-create.log"
if [[ "$direct_identity" != - ]]; then
    codesign --force --sign "$direct_identity" --timestamp "$direct_dmg"
fi
if [[ -n "$direct_notary" ]]; then
    xcrun notarytool submit "$direct_dmg" --keychain-profile "$direct_notary" --wait --output-format json > "$direct_output/notarization-dmg.json"
    python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("status")=="Accepted" else 1)' "$direct_output/notarization-dmg.json"
    xcrun stapler staple "$direct_dmg"
    xcrun stapler validate "$direct_dmg"
fi
python3 scripts/verify_direct.py "$direct_output"
echo "Direct artifacts: $direct_output"
if [[ -z "$direct_notary" ]]; then echo 'Not notarized; do not describe this build as Apple-trusted distribution.';fi
