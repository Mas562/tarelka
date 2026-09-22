# Respect an explicit toolchain. Otherwise use Xcode only when it is ready to build.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if [[ -d /Applications/Xcode.app/Contents/Developer ]] && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift --version >/dev/null 2>&1; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        export DEVELOPER_DIR="$(xcode-select -p)"
    fi
fi
# The CLT 27 SDK requires SwiftUI macros that aren't bundled in CLT. The installed
# 26.5 SDK retains the State property wrapper and fully supports Liquid Glass.
if [[ "$DEVELOPER_DIR" == /Library/Developer/CommandLineTools && -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
