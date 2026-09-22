#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
TARELKA_FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
if [[ -d "$TARELKA_FRAMEWORKS/Testing.framework" ]]; then
    swift test --build-system native --scratch-path .build --cache-path .build/cache --disable-sandbox \
        --disable-xctest --enable-swift-testing \
        -Xswiftc -F -Xswiftc "$TARELKA_FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$TARELKA_FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "${TARELKA_FRAMEWORKS:h}/usr/lib"
else
    swift test --build-system native --scratch-path .build --cache-path .build/cache --disable-sandbox
fi
