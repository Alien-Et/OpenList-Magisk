#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPANION_DIR="$ROOT_DIR/companion-apk"
SRC_DIR="$COMPANION_DIR/src"
TEST_DIR="$COMPANION_DIR/test"
OUTPUT_DIR="$ROOT_DIR/OpenList-Magisk/system/app/OpenListHelper"
OUTPUT_APK="$OUTPUT_DIR/OpenListHelper.apk"

echo "=== OpenList Companion APK Build System ==="

# 1. Resolve Java tools
command -v javac >/dev/null 2>&1 || { echo "Error: javac not found in PATH" >&2; exit 1; }
command -v java >/dev/null 2>&1 || { echo "Error: java not found in PATH" >&2; exit 1; }
command -v jar >/dev/null 2>&1 || { echo "Error: jar not found in PATH" >&2; exit 1; }
command -v keytool >/dev/null 2>&1 || { echo "Error: keytool not found in PATH" >&2; exit 1; }

# 2. Resolve Android SDK
if [ -z "${ANDROID_HOME:-}" ] && [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    ANDROID_HOME="$ANDROID_SDK_ROOT"
fi
if [ -z "${ANDROID_HOME:-}" ]; then
    if [ -d "/d/Program Files/Android/Sdk" ]; then
        ANDROID_HOME="/d/Program Files/Android/Sdk"
    elif [ -d "D:/Program Files/Android/Sdk" ]; then
        ANDROID_HOME="D:/Program Files/Android/Sdk"
    elif [ -d "$HOME/Android/Sdk" ]; then
        ANDROID_HOME="$HOME/Android/Sdk"
    elif [ -d "$HOME/Library/Android/sdk" ]; then
        ANDROID_HOME="$HOME/Library/Android/sdk"
    elif [ -d "/usr/lib/android-sdk" ]; then
        ANDROID_HOME="/usr/lib/android-sdk"
    fi
fi

if [ -z "${ANDROID_HOME:-}" ] || [ ! -d "$ANDROID_HOME" ]; then
    echo "Error: ANDROID_HOME not found. Please set ANDROID_HOME environment variable." >&2
    exit 1
fi
echo "Using Android SDK: $ANDROID_HOME"

# 3. Locate android.jar
ANDROID_JAR=""
if [ -f "$ANDROID_HOME/platforms/android-34/android.jar" ]; then
    ANDROID_JAR="$ANDROID_HOME/platforms/android-34/android.jar"
else
    for p in "$ANDROID_HOME"/platforms/android-*/android.jar; do
        if [ -f "$p" ]; then
            ANDROID_JAR="$p"
        fi
    done
fi

if [ -z "$ANDROID_JAR" ] || [ ! -f "$ANDROID_JAR" ]; then
    echo "Error: android.jar not found in $ANDROID_HOME/platforms" >&2
    exit 1
fi
echo "Using Android platform JAR: $ANDROID_JAR"

# 4. Locate Build Tools
BUILD_TOOLS_DIR=""
if [ -d "$ANDROID_HOME/build-tools/34.0.0" ]; then
    BUILD_TOOLS_DIR="$ANDROID_HOME/build-tools/34.0.0"
else
    for d in "$ANDROID_HOME"/build-tools/*; do
        if [ -d "$d" ]; then
            BUILD_TOOLS_DIR="$d"
        fi
    done
fi

if [ -z "$BUILD_TOOLS_DIR" ] || [ ! -d "$BUILD_TOOLS_DIR" ]; then
    echo "Error: build-tools directory not found in $ANDROID_HOME/build-tools" >&2
    exit 1
fi
echo "Using Android build-tools: $BUILD_TOOLS_DIR"

find_tool() {
    local name="$1"
    if [ -x "$BUILD_TOOLS_DIR/$name" ]; then
        echo "$BUILD_TOOLS_DIR/$name"
    elif [ -f "$BUILD_TOOLS_DIR/${name}.exe" ]; then
        echo "$BUILD_TOOLS_DIR/${name}.exe"
    elif [ -f "$BUILD_TOOLS_DIR/${name}.bat" ]; then
        echo "$BUILD_TOOLS_DIR/${name}.bat"
    elif command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
    else
        echo ""
    fi
}

AAPT2=$(find_tool aapt2)
ZIPALIGN=$(find_tool zipalign)
D8_JAR="$BUILD_TOOLS_DIR/lib/d8.jar"
APKSIGNER_JAR="$BUILD_TOOLS_DIR/lib/apksigner.jar"
D8_BIN=$(find_tool d8)
APKSIGNER_BIN=$(find_tool apksigner)

run_d8() {
    if [ -f "$D8_JAR" ]; then
        java -cp "$D8_JAR" com.android.tools.r8.D8 "$@"
    elif [ -n "$D8_BIN" ]; then
        "$D8_BIN" "$@"
    else
        echo "Error: Neither d8.jar nor d8 executable found" >&2
        exit 1
    fi
}

run_apksigner() {
    if [ -f "$APKSIGNER_JAR" ]; then
        java -jar "$APKSIGNER_JAR" "$@"
    elif [ -n "$APKSIGNER_BIN" ]; then
        "$APKSIGNER_BIN" "$@"
    else
        echo "Error: Neither apksigner.jar nor apksigner executable found" >&2
        exit 1
    fi
}

if [ -z "$AAPT2" ] || [ -z "$ZIPALIGN" ]; then
    echo "Error: Required Android SDK build tools not found (aapt2, zipalign)" >&2
    exit 1
fi

# 5. Initialize build workspace
BUILD_DIR="$COMPANION_DIR/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/test-classes" "$BUILD_DIR/classes" "$BUILD_DIR/dex" "$OUTPUT_DIR"

# 6. Step 1: Run JVM unit tests
echo "==> Step 1: Running OfflineHelperCore unit tests..."
javac -encoding UTF-8 -d "$BUILD_DIR/test-classes" \
    "$SRC_DIR/io/openlist/helper/OfflineHelperCore.java" \
    "$TEST_DIR/io/openlist/helper/OfflineHelperCoreTest.java"

java -cp "$BUILD_DIR/test-classes" io.openlist.helper.OfflineHelperCoreTest

# 7. Step 2: Compile Android Java sources with --release 8
echo "==> Step 2: Compiling Android Java sources..."
javac -encoding UTF-8 --release 8 -Xlint:-options -cp "$ANDROID_JAR" -d "$BUILD_DIR/classes" \
    "$SRC_DIR/io/openlist/helper/OfflineHelperCore.java" \
    "$SRC_DIR/io/openlist/helper/ProcessTextActivity.java"

# 8. Step 3: Convert classes to DEX with d8
echo "==> Step 3: Compiling classes to DEX with d8..."
run_d8 --output "$BUILD_DIR/dex" --lib "$ANDROID_JAR" --min-api 23 "$BUILD_DIR/classes/io/openlist/helper/"*.class

# 9. Step 4: Package resources and manifest with aapt2 link
echo "==> Step 4: Packaging APK with aapt2 link..."
"$AAPT2" link -I "$ANDROID_JAR" \
    --manifest "$COMPANION_DIR/AndroidManifest.xml" \
    -o "$BUILD_DIR/unaligned.apk"

echo "==> Adding classes.dex into unaligned.apk..."
(cd "$BUILD_DIR/dex" && jar uf "$BUILD_DIR/unaligned.apk" classes.dex)

# 10. Step 5: Align and Sign APK
echo "==> Step 5: Aligning APK with zipalign..."
"$ZIPALIGN" -f -p 4 "$BUILD_DIR/unaligned.apk" "$BUILD_DIR/aligned.apk"

KEYSTORE="$COMPANION_DIR/debug.keystore"
if [ ! -f "$KEYSTORE" ]; then
    echo "==> Generating deterministic debug keystore..."
    keytool -genkeypair -v -keystore "$KEYSTORE" \
        -storepass android -alias androiddebugkey -keypass android \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US"
fi

echo "==> Signing APK with apksigner..."
run_apksigner sign --ks "$KEYSTORE" \
    --ks-pass pass:android \
    --ks-key-alias androiddebugkey \
    --key-pass pass:android \
    --out "$OUTPUT_APK" \
    "$BUILD_DIR/aligned.apk"

echo "==> Step 6: Verifying signed APK..."
run_apksigner verify "$OUTPUT_APK"

echo "=== Build succeeded! APK: $OUTPUT_APK ($(wc -c < "$OUTPUT_APK") bytes) ==="
