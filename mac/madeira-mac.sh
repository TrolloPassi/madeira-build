#!/bin/bash
# Baut Madeira (github.com/willfaust/Madeira) auf einem Mac, stufenweise.
#
#   madeira-mac.sh <stufe>
#
# Umgebung: M = Madeira-Checkout (Standard: ./m), SRT = dieses Repo,
#   PATCH_DIR = Patches je Submodul (Standard: $SRT/madeira/patches),
#   TOOL_DIR = Hilfsskripte (Standard: $SRT/madeira/tools),
#   FEX_SKIP = FEX-Patchnummern, die ausgelassen werden (Standard: 0001),
#   BASE_IPA_REPO / BASE_IPA_TAG = Release, aus dem VC++-Runtime, i386-windows und die
#     aarch64-Dienste kommen (leerer Tag = neuestes Release).
# Die Stufen folgen docs/BUILDING.md von Madeira und rufen dessen Skripte in
# build/ auf; was dort fehlt (Basis-Archiv des wineservers, Nachbearbeitung
# der ntdll, das Zusammenlegen von DXMT mit LLVM) steht hier.
#
# Stufen: tools deps fex llvm wine-host wine-pe unix dxmt dock fex-pe vcruntime app
set -euo pipefail

STAGE=${1:?Stufe fehlt}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRT="${SRT:-$(cd "$HERE/../../.." && pwd)}"
M="${M:-$PWD/m}"
PATCH_DIR="${PATCH_DIR:-$SRT/madeira/patches}"
TOOL_DIR="${TOOL_DIR:-$SRT/madeira/tools}"
FEX_SKIP="${FEX_SKIP:-0001}"
JOBS=$(sysctl -n hw.ncpu)
LLVM_MINGW_VER=20260421
LLVM_MINGW="$M/toolchains/llvm-mingw-$LLVM_MINGW_VER-ucrt-macos-universal"
# llvm-config --libs bitwriter passes (dxmt/src/airconv/meson.build)
LLVM_LIBS="LLVMPasses LLVMTarget LLVMObjCARCOpts LLVMCoroutines LLVMipo LLVMInstrumentation
LLVMVectorize LLVMLinker LLVMIRReader LLVMAsmParser LLVMFrontendOpenMP LLVMScalarOpts
LLVMInstCombine LLVMAggressiveInstCombine LLVMTransformUtils LLVMBitWriter LLVMAnalysis
LLVMProfileData LLVMSymbolize LLVMDebugInfoPDB LLVMDebugInfoMSF LLVMDebugInfoDWARF LLVMObject
LLVMTextAPI LLVMMCParser LLVMMC LLVMDebugInfoCodeView LLVMBitReader LLVMCore LLVMRemarks
LLVMBitstreamReader LLVMBinaryFormat LLVMSupport LLVMDemangle"

log() { printf '\n==== %s ====\n' "$*"; }
apply_patches() { # dir repo
    local p
    shopt -s nullglob
    for p in "$PATCH_DIR/$1"/*.patch; do
        if [ "$1" = fex ]; then
            case " $FEX_SKIP " in *" $(basename "$p" | cut -d- -f1) "*) echo "Ausgelassen: $p"; continue;; esac
        fi
        echo "Patch: $p"
        git -C "$2" apply --verbose "$p"
    done
    shopt -u nullglob
}
export PATH="$LLVM_MINGW/bin:$PATH"
cd "$M"

case "$STAGE" in

tools)
    log "Patches für das Madeira-Repo selbst (z.B. build/ntdll-unix/virtual_ios.c)"
    apply_patches madeira .
    log "Werkzeuge"
    brew list bison >/dev/null 2>&1 || brew install -q bison
    echo "$(brew --prefix bison)/bin" >> "${GITHUB_PATH:-/dev/null}"
    if [ ! -x "$LLVM_MINGW/bin/arm64ec-w64-mingw32-clang" ]; then
        mkdir -p toolchains
        curl -sSL -o /tmp/llvm-mingw.tar.xz \
            "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_VER/llvm-mingw-$LLVM_MINGW_VER-ucrt-macos-universal.tar.xz"
        tar -C toolchains -xf /tmp/llvm-mingw.tar.xz
    fi
    xcodebuild -version
    xcrun --sdk iphoneos --show-sdk-version
    # Xcode 26 liefert den Metal-Compiler (für DXMTs Shader) nicht mehr mit
    xcrun -sdk macosx -f metal >/dev/null 2>&1 || xcodebuild -downloadComponent MetalToolchain
    "$LLVM_MINGW/bin/arm64ec-w64-mingw32-clang" --version | head -1
    ;;

deps)
    log "GMP / Nettle / GnuTLS"
    bash build/gnutls-ios/build.sh
    log "FFmpeg"
    bash build/ffmpeg/build.sh
    log "FreeType"
    [ -d research/freetype ] || git clone -q --depth 1 --branch VER-2-13-3 https://github.com/freetype/freetype.git research/freetype
    bash build/freetype-ios/build.sh
    tar -cf deps.tar toolchains/gnutls-ios toolchains/ffmpeg-ios \
        app/Madeira/libavformat.a app/Madeira/libavcodec.a app/Madeira/libswresample.a app/Madeira/libavutil.a \
        research/freetype/include build/freetype-ios/build/libfreetype.a
    ls -la deps.tar
    ;;

fex)
    log "FEXCore für iOS (Optionen wie build/fex-ios/build.sh)"
    apply_patches fex FEX
    # Scripts/aarch64_fit_native.py braucht das Python-Modul packaging
    python3 -c 'import packaging' 2>/dev/null || python3 -m pip install -q --break-system-packages packaging || python3 -m pip install -q --user packaging
    # CMAKE_SYSTEM_PROCESSOR bleibt bei CMAKE_SYSTEM_NAME=iOS leer; FEX braucht es
    cmake -S FEX -B FEX/build-ios -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF -DBUILD_THUNKS=OFF -DBUILD_FEXCONFIG=OFF -DBUILD_FEX_LINUX_TESTS=OFF \
        -DENABLE_FEX_ALLOCATOR=OFF -DENABLE_ASSERTIONS=OFF -DENABLE_CLANG_THUNKS=ON -DENABLE_CCACHE=OFF \
        -DFEX_IOS_HOST_BUILD=ON -DCMAKE_C_FLAGS=-DFEX_IOS_HOST -DCMAKE_CXX_FLAGS=-DFEX_IOS_HOST \
        -DCMAKE_ASM_FLAGS=-DFEX_IOS_HOST \
        -DTUNE_ARCH=generic -DTUNE_CPU=none -DCMAKE_POLICY_VERSION_MINIMUM=3.5   # TUNE_CPU=native liest /proc/cpuinfo
    cmake --build FEX/build-ios -j"$JOBS" --target FEXCore FEXCore_Base JemallocLibs
    find FEX/build-ios -name '*.a' | sort
    find FEX/build-ios -name '*.o' -delete
    tar -cf fex-ios.tar FEX/build-ios
    ls -la fex-ios.tar
    ;;

llvm)
    log "LLVM ${LLVM_SHA:?LLVM_SHA fehlt} für iOS (Optionen aus docs/BUILDING.md)"
    if [ ! -f toolchains/llvm-project/llvm/CMakeLists.txt ]; then
        git init -q toolchains/llvm-project
        git -C toolchains/llvm-project remote add origin https://github.com/llvm/llvm-project.git
        git -C toolchains/llvm-project fetch -q --depth 1 origin "$LLVM_SHA"
        git -C toolchains/llvm-project checkout -q FETCH_HEAD
    fi
    COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD= -DLLVM_ENABLE_PROJECTS=
            -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF
            -DLLVM_INCLUDE_DOCS=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF
            -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_BINDINGS=OFF
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5)
    log "LLVM: llvm-tblgen für den Mac"
    cmake -S toolchains/llvm-project/llvm -B toolchains/llvm-host-build "${COMMON[@]}"
    cmake --build toolchains/llvm-host-build -j"$JOBS" --target llvm-tblgen
    log "LLVM: Bibliotheken für iOS"
    cmake -S toolchains/llvm-project/llvm -B toolchains/llvm-ios-build "${COMMON[@]}" \
        -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=iphoneos \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
        -DLLVM_HOST_TRIPLE=arm64-apple-ios17.0 -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-ios17.0 \
        -DLLVM_TARGET_ARCH=host -DLLVM_BUILD_TOOLS=OFF \
        -DLLVM_TABLEGEN="$M/toolchains/llvm-host-build/bin/llvm-tblgen" \
        -DCMAKE_MACOSX_BUNDLE=OFF   # sonst will install() für llvm-tblgen ein App-Bundle
    # shellcheck disable=SC2086
    cmake --build toolchains/llvm-ios-build -j"$JOBS" --target $LLVM_LIBS
    tar -cf llvm-ios.tar toolchains/llvm-project/llvm/include toolchains/llvm-ios-build/include \
        $(for l in $LLVM_LIBS; do echo "toolchains/llvm-ios-build/lib/lib$l.a"; done)
    ls -la llvm-ios.tar
    ;;

wine-host)
    log "Wine: Konfiguration für den Mac (nur include/config.h wird gebraucht)"
    apply_patches wine wine
    mkdir -p wine/build-macos && cd wine/build-macos
    # Wine verlangt für arm64 einen PE-Compiler; llvm-mingw (Stufe tools) liegt im PATH
    ../configure --without-x --without-freetype --disable-tests > configure.log 2>&1 \
        || { tail -40 configure.log; exit 1; }
    test -f include/config.h
    # build/ntdll-unix/build.sh liest die aus IDL erzeugten Header aus DIESEM Baum
    make -j"$JOBS" $(grep -oE '^include/[A-Za-z0-9_]+\.h:' Makefile | tr -d ':' | sort -u) > headers.log 2>&1 \
        || { tail -20 headers.log; exit 1; }
    ls include/dwrite_3.h include/wtypes.h
    ;;

wine-pe)
    log "Wine: ntdll.dll + kernelbase.dll (ARM64EC) mit llvm-mingw"
    mkdir -p wine/build-arm64ec && cd wine/build-arm64ec
    ../configure --enable-archs=arm64ec --without-x --without-freetype --disable-tests --enable-winegstreamer \
        > configure.log 2>&1 || { tail -40 configure.log; exit 1; }
    # cryptsp.dll fehlt in Madeiras DLL-Farm; Dungeons' winmm.dll braucht SystemFunction032.
    # include/dwrite.h und wtypes.h (aus IDL) braucht build/ntdll-unix/build.sh.
    make -j"$JOBS" dlls/ntdll/arm64ec-windows/ntdll.dll dlls/kernelbase/arm64ec-windows/kernelbase.dll \
        dlls/cryptsp/arm64ec-windows/cryptsp.dll \
        $(grep -oE '^include/[A-Za-z0-9_]+\.h:' Makefile | tr -d ':' | sort -u) \
        > make.log 2>&1 || { tail -40 make.log; exit 1; }
    cd "$M"
    for f in ntdll kernelbase cryptsp; do
        cp "wine/build-arm64ec/dlls/$f/arm64ec-windows/$f.dll" "app/Madeira/arm64ec-windows/$f.dll"
        llvm-strip "app/Madeira/arm64ec-windows/$f.dll"
    done
    # .mhook (madeira/patches/wine/0003) ausführbar markieren, dann wie
    # build/wine-pe/build-ntdll.sh auf SizeOfImage + 0x50000 auffüllen
    python3 "$TOOL_DIR/pe-section-flags.py" app/Madeira/arm64ec-windows/ntdll.dll .mhook 0xe0000060 || true
    python3 - app/Madeira/arm64ec-windows/ntdll.dll <<'PY'
import struct, sys
p = sys.argv[1]; d = open(p, 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]
target = struct.unpack_from('<I', d, pe + 24 + 56)[0] + 0x50000
assert len(d) <= target, (len(d), target)
open(p, 'ab').write(bytes(target - len(d)))
print(f"ntdll.dll: {len(d)} + {target - len(d)} Bytes = {target}")
PY
    ls -la app/Madeira/arm64ec-windows/ntdll.dll app/Madeira/arm64ec-windows/kernelbase.dll
    ;;

unix)
    log "libntdll_unix.a"
    bash build/ntdll-unix/build.sh || {
        for e in build/ntdll-unix/obj/*.err; do
            [ -s "$e" ] && [ ! -f "${e%.err}.o" ] && { echo "== $e"; head -40 "$e"; }
        done; exit 1; }
    log "libwineserver.a: Basis-Archiv aus wine/server (build/wineserver/build.sh ersetzt darin seine Dateien)"
    SDK=$(xcrun --sdk iphoneos --show-sdk-path)
    WS=build/wineserver; OBJ="$WS/obj"; mkdir -p "$OBJ/base"
    CC_FLAGS=(-arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 -O2
        -I"$M/wine/include" -I"$M/wine/include/wine" -I"$M/wine/build-macos/include"
        -I"$M/$WS" -I"$M/wine/server" -I"$M/build/ntdll-unix/shims"
        -I"$M/build/madsync" -DHAVE_LINUX_NTSYNC_H=1
        -include "$M/$WS/config_ios.h" -include stdarg.h -include "$M/$WS/unicode_fix.h"
        -include "$M/$WS/wineserver_ios_kill.h"
        -DBINDIR=\"/usr/local/bin\" -DDATADIR=\"/usr/local/share\"
        -D__WINESRC__ -DWINE_IOS=1 -Dmain=wineserver_main -Wno-implicit-function-declaration)
    for src in wine/server/*.c; do
        n=$(basename "$src" .c)
        printf '  %-16s' "$n"
        if xcrun -sdk iphoneos clang "${CC_FLAGS[@]}" -c "$src" -o "$OBJ/base/$n.o" 2>"$OBJ/base/$n.err"; then echo OK
        else echo FAILED; cat "$OBJ/base/$n.err"; exit 1; fi
    done
    rm -f "$OBJ/libwineserver.a"
    xcrun -sdk iphoneos ar rcs "$OBJ/libwineserver.a" "$OBJ"/base/*.o
    bash build/wineserver/build.sh all
    log "libwin32u_unix.a"
    bash build/win32u-unix/build.sh || {
        for e in build/win32u-unix/obj/*.err; do
            [ -s "$e" ] && [ ! -f "${e%.err}.o" ] && { echo "== $e"; head -40 "$e"; }
        done; exit 1; }
    ls -la app/Madeira/libntdll_unix.a app/Madeira/libwineserver.a app/Madeira/libwin32u_unix.a
    ;;

dxmt)
    apply_patches dxmt dxmt
    # winemetal_unix.c bindet ../../../../remote-metal/… ein; seit der Umstrukturierung
    # von Madeira liegt das unter research/remote-metal.
    [ -e remote-metal ] || ln -s research/remote-metal remote-metal
    # …und build/madeira_cfg.h eine Ebene zu hoch (../../../../../ statt ../../../../).
    mkdir -p "$M/../build"
    ln -sf "$M/build/madeira_cfg.h" "$M/../build/madeira_cfg.h"
    log "airconv-Shader als Bitcode-Header (wie dxmt/src/airconv/meson.build: metal -> xxd)"
    # build/dxmt-ios/build.sh erzeugt nur dxmt_command.h; airconv_context.cpp
    # braucht zusätzlich air_msad.h, air_samplepos.h, air_tessellation.h.
    mkdir -p build/dxmt-ios/shader-headers
    for m in dxmt/src/airconv/shaders/*.metal; do
        n=$(basename "$m" .metal)
        xcrun -sdk macosx metal -std=metal3.1 --target=air64-apple-macos14.0 \
            -o "build/dxmt-ios/shader-headers/$n.air" -c "$m"
        (cd build/dxmt-ios/shader-headers && xxd -n "$n" -i "$n.air" "$n.h")
        echo "  $n.h"
    done
    log "DXMT unix side + airconv + madeira-d3d12"
    bash build/dxmt-ios/build.sh || {
        n=0
        for e in build/dxmt-ios/obj/*.err; do
            [ -s "$e" ] && [ ! -f "${e%.err}.o" ] || continue
            if [ $n -lt 8 ]; then echo "== $e"; grep -m 12 -E "error:|fatal" "$e" || head -20 "$e"
            else printf '%s: ' "$e"; grep -m 1 -E "error:|fatal" "$e" || echo "(kein error:)"; fi
            n=$((n + 1))
        done; exit 1; }
    log "libdxmt_combined.a = libdxmt_unix.a + LLVM"
    # shellcheck disable=SC2046
    xcrun -sdk iphoneos libtool -static -o app/Madeira/libdxmt_combined.a build/dxmt-ios/libdxmt_unix.a \
        $(for l in $LLVM_LIBS; do echo "toolchains/llvm-ios-build/lib/lib$l.a"; done)
    ls -la app/Madeira/libdxmt_combined.a
    ;;

dock)
    log "Madeira Dock (dockhost.exe) mit Patches"
    apply_patches madeira-dock madeira-dock
    # Host-Selbsttest (nicht nötig fürs Bauen): mit macOS-SDK, Fehler nur melden
    (cd madeira-dock && env -u SDKROOT -u IPHONEOS_DEPLOYMENT_TARGET SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" \
        HOST_CC=clang bash tools/check.sh) || echo "WARNUNG: Madeira-Dock-Selbsttest fehlgeschlagen (Build geht weiter)"
    bash build/madeira-dock/build.sh
    ls -la app/Madeira/arm64ec-windows/dockhost.exe
    ;;

fex-pe)
    log "FEX ARM64EC (xtajit64.dll) mit Patches, Optionen wie build/fex-arm64ec/build.sh"
    if git -C FEX diff --quiet; then apply_patches fex FEX; else echo "FEX bereits gepatcht"; fi
    python3 -c 'import packaging' 2>/dev/null || python3 -m pip install -q --break-system-packages packaging || python3 -m pip install -q --user packaging
    command -v ninja >/dev/null || brew install -q ninja
    cmake -S FEX -B FEX/build-arm64ec -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$M/FEX/Data/CMake/toolchain_mingw.cmake" -DMINGW_TRIPLE=arm64ec-w64-mingw32 \
        -DFEX_IOS_HOST_BUILD=ON -DCMAKE_C_FLAGS=-DFEX_IOS_HOST -DCMAKE_CXX_FLAGS=-DFEX_IOS_HOST \
        -DCMAKE_ASM_FLAGS=-DFEX_IOS_HOST -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DENABLE_LTO=OFF \
        -DENABLE_FEX_ALLOCATOR=ON -DENABLE_JEMALLOC_GLIBC_ALLOC=ON -DENABLE_OFFLINE_RUNTIME=ON \
        -DBUILD_FEXCONFIG=ON -DENABLE_CLANG_THUNKS=ON -DENABLE_CCACHE=OFF \
        -DBUILD_TESTING=OFF -DBUILD_THUNKS=OFF -DENABLE_ASSERTIONS=OFF \
        -DTUNE_ARCH=generic -DTUNE_CPU=none   # TUNE_CPU=native liest /proc/cpuinfo (gibt es auf macOS nicht)
    cmake --build FEX/build-arm64ec --target arm64ecfex -j"$JOBS"
    cp FEX/build-arm64ec/Bin/libarm64ecfex.dll app/Madeira/arm64ec-windows/xtajit64.dll
    ls -la app/Madeira/arm64ec-windows/xtajit64.dll
    ;;

vcruntime)
    log "VC++ Runtime, i386-windows, aarch64-Dienste aus ${BASE_IPA_REPO:?} ${BASE_IPA_TAG:-(neuestes)}"
    rm -rf /tmp/pf && mkdir -p /tmp/pf
    if [ -z "${BASE_IPA_TAG:-}" ]; then
        # neuestes Release mit IPA, Vorabversionen eingeschlossen, ohne die App-Test-Builds selbst
        BASE_IPA_TAG=$(gh api "repos/$BASE_IPA_REPO/releases?per_page=30" \
            -q '[.[] | select((.tag_name | test("app")) | not) | select(any(.assets[]; .name | endswith(".ipa")))][0].tag_name')
        echo "Basis-Release: $BASE_IPA_TAG"
    fi
    gh release download "${BASE_IPA_TAG:?kein Basis-Release gefunden}" -R "$BASE_IPA_REPO" --pattern '*.ipa' --dir /tmp/pf
    IPA="$(ls /tmp/pf/*.ipa | head -1)"
    mkdir -p app/Madeira/x86_64-vcruntime
    unzip -q -o -j "$IPA" 'Payload/*.app/x86_64-vcruntime/*' -d app/Madeira/x86_64-vcruntime
    ls app/Madeira/x86_64-vcruntime | wc -l
    # Was die Stufen hier nicht bauen (unverändert aus dem Release): 32-bit-Wine (i386-windows)
    # und die aarch64-Dienstprogramme. Nichts überschreiben, was gebaut wurde.
    rm -rf /tmp/pfx && mkdir -p /tmp/pfx
    unzip -q -o "$IPA" 'Payload/*.app/i386-windows/*' 'Payload/*.app/aarch64-windows/*' -d /tmp/pfx \
        || { r=$?; [ $r -eq 1 ] || { echo "unzip i386/aarch64: Fehler $r"; exit 1; }; }
    for d in i386-windows aarch64-windows; do
        mkdir -p "app/Madeira/$d"
        n0=$(ls "app/Madeira/$d" | wc -l)
        # macOS-cp -n endet mit 1, sobald es etwas überspringt -> rsync
        rsync -a --ignore-existing /tmp/pfx/Payload/*.app/"$d"/ "app/Madeira/$d/"
        echo "$d: $n0 -> $(ls "app/Madeira/$d" | wc -l) Dateien"
    done
    ;;

app)
    log "Xcode-Build (Debug, unsigniert)"
    # FEXCore referenziert Hooks der FEX-PE-Module (Mono-Bridge, Sub-Floor, FEX-Band);
    # die App linkt FEXCore ohne sie -> schwache Stubs im Ruhezustand ins Archiv.
    xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -O2 \
        -c "$HERE/fex-ios-host-stubs.c" -o FEX/build-ios/fex-ios-host-stubs.o
    xcrun -sdk iphoneos ar rs FEX/build-ios/FEXCore/Source/libFEXCore.a FEX/build-ios/fex-ios-host-stubs.o
    bash build/stage-licenses.sh
    xcodebuild -project app/Madeira.xcodeproj -target Madeira -configuration Debug -sdk iphoneos -arch arm64 \
        ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
        DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= SYMROOT="$M/app/build" build \
        > xcodebuild.log 2>&1 || {
            grep -v "ld: warning" xcodebuild.log | grep -E -A12 "error:|fatal error|Undefined symbols|duplicate symbol" | head -120
            grep -v "warning" xcodebuild.log | tail -25; exit 1; }
    APP=app/build/Debug-iphoneos/Madeira.app
    test -d "$APP"
    rm -rf Payload && mkdir Payload && cp -R "$APP" Payload/
    zip -qr "Madeira-${MADEIRA_TAG:-dev}-app.ipa" Payload
    ls -la ./*.ipa
    ;;

*)
    echo "unbekannte Stufe: $STAGE" >&2; exit 2 ;;
esac
