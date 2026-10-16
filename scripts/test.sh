#!/bin/zsh
# Roda os testes. Com apenas as Command Line Tools (sem Xcode), o SwiftPM não
# encontra o framework Testing sozinho, então passamos o caminho explicitamente.
# O overlay _Testing_Foundation das CLT vem sem módulo, por isso é desativado.
set -e
cd "${0:A:h}/.."

frameworks=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if ! xcodebuild -version >/dev/null 2>&1 && [[ -d $frameworks/Testing.framework ]]; then
    exec swift test \
        -Xswiftc -F -Xswiftc $frameworks \
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker -F -Xlinker $frameworks -Xlinker -rpath -Xlinker $frameworks \
        "$@"
fi
exec swift test "$@"
