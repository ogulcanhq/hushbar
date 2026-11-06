#!/bin/zsh
# Builds build/Hushbar.app. With --install, also copies it to /Applications.
#
# The app gets an ad-hoc signature, which changes every build, so macOS asks for the
# audio permission again after each rebuild. To keep it, sign with your own identity:
#   HUSHBAR_SIGN_IDENTITY="Apple Development: ..." ./scripts/build.sh
set -euo pipefail

cd "${0:A:h}/.."

swift build -c release
binary="$(swift build -c release --show-bin-path)/Hushbar"

app=build/Hushbar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Hushbar"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
for catalog in Resources/*.xcstrings; do
    xcrun xcstringstool compile "$catalog" --output-directory "$app/Contents/Resources"
done
codesign --force --sign "${HUSHBAR_SIGN_IDENTITY:--}" "$app"

echo "Built $PWD/$app"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Hushbar.app
    cp -R "$app" /Applications/Hushbar.app
    echo "Installed /Applications/Hushbar.app"
fi
