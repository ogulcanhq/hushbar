#!/bin/zsh
# Builds build/Hushbar.app.
#   --install      also copy it to /Applications
#   --diagnostics  include the --probe, --list, --rows and --snapshot commands. These let
#                  any local program use the app's audio permission, so never install one.
#
# The app gets an ad-hoc signature, which changes every build, so macOS asks for the
# audio permission again after each rebuild. To keep it, sign with your own identity:
#   HUSHBAR_SIGN_IDENTITY="Apple Development: ..." ./scripts/build.sh
set -euo pipefail

cd "${0:A:h}/.."

install=false
swift_flags=()
for argument in "$@"; do
    case "$argument" in
        --install) install=true ;;
        --diagnostics) swift_flags=(-Xswiftc -DHUSHBAR_DIAGNOSTICS) ;;
        *) echo "unknown option: $argument" >&2; exit 1 ;;
    esac
done
if [[ "$install" == true && ${#swift_flags[@]} -gt 0 ]]; then
    echo "--install and --diagnostics can't be combined" >&2
    exit 1
fi

swift build -c release "${swift_flags[@]}"
binary="$(swift build -c release "${swift_flags[@]}" --show-bin-path)/Hushbar"

app=build/Hushbar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Hushbar"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
for catalog in Resources/*.xcstrings; do
    xcrun xcstringstool compile "$catalog" --output-directory "$app/Contents/Resources"
done
# The hardened runtime stops other programs injecting code to borrow the audio permission.
codesign --force --options runtime --sign "${HUSHBAR_SIGN_IDENTITY:--}" "$app"

echo "Built $PWD/$app"

if [[ "$install" == true ]]; then
    rm -rf /Applications/Hushbar.app
    cp -R "$app" /Applications/Hushbar.app
    echo "Installed /Applications/Hushbar.app"
fi
