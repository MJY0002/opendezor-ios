#!/usr/bin/env bash
# ==============================================================================
# OpenDezor — Automated iOS IPA Build & Sideload Packaging Pipeline
# Targets: iOS 17.0+ | Compatible with AltStore, Sideloadly, TrollStore, Scarlet
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
APP_NAME="OpenDezor"
BUNDLE_ID="org.opendezor.app"
IPA_PATH="${BUILD_DIR}/${APP_NAME}.ipa"
CONFIGURATION="${1:-Release}"
APP_BUNDLE_DIR="${PAYLOAD_DIR}/${APP_NAME}.app"

echo "================================================================================"
echo "  🚀 OpenDezor — Automated iOS Build & IPA Packaging Pipeline"
echo "================================================================================"
echo "  Project Root:   ${PROJECT_DIR}"
echo "  Build Dir:      ${BUILD_DIR}"
echo "  Target App:     ${APP_NAME} (${BUNDLE_ID})"
echo "  Configuration:  ${CONFIGURATION}"
echo "  Host System:    $(uname -sm)"
echo "  Xcode Version:  $(xcodebuild -version 2>/dev/null | tr '\n' ' ' || echo 'CLI Tools')"
echo "  Swift Version:  $(swift --version | head -n 1)"
echo "================================================================================"

# 1. Clean previous build artifacts
echo "🧹 [1/6] Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${PAYLOAD_DIR}"
mkdir -p "${APP_BUNDLE_DIR}"

# 2. Compile iOS Binary
echo "🔨 [2/6] Compiling OpenDezor binary..."
cd "${PROJECT_DIR}"

# The iPhoneOS SDK is the only one that can produce this artifact. There used to be a
# macOS-SDK fallback and, under it, a raw `swiftc` fallback over every .swift file — both
# "succeeded" while emitting a macOS binary that step [5/6] then rejected. Fail here, where
# the actual problem is, instead of three steps later.
if ! SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null) || [ ! -d "${SDK_PATH}" ]; then
    echo "❌ ERROR: iPhoneOS SDK not found. Select full Xcode:" >&2
    echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi
echo "  Using iOS SDK: ${SDK_PATH}"

if [ ! -d "${PROJECT_DIR}/OpenDezor.xcodeproj" ]; then
    echo "❌ ERROR: OpenDezor.xcodeproj is missing. Generate it first:" >&2
    echo "   python3 scripts/generate_xcodeproj.py" >&2
    exit 1
fi

echo "  Building via xcodebuild with project configuration..."
xcodebuild build \
    -project "${PROJECT_DIR}/OpenDezor.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration "${CONFIGURATION}" \
    -sdk iphoneos \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    OTHER_SWIFT_FLAGS="\$(inherited) -file-prefix-map ${PROJECT_DIR}=. -file-prefix-map ${BUILD_DIR}=build" \
    DEPLOYMENT_POSTPROCESSING=YES \
    STRIP_INSTALLED_PRODUCT=YES \
    STRIP_STYLE=all

BUILT_APP=$(find "${BUILD_DIR}/DerivedData" -name "${APP_NAME}.app" -type d | head -n 1)
if [ -z "${BUILT_APP}" ] || [ ! -d "${BUILT_APP}" ]; then
    echo "❌ ERROR: xcodebuild produced no ${APP_NAME}.app under ${BUILD_DIR}/DerivedData." >&2
    echo "   If the scheme is missing, open the project in Xcode once so it is autocreated." >&2
    exit 1
fi
cp -R "${BUILT_APP}/"* "${APP_BUNDLE_DIR}/"

# Clean up any loose intermediate .o or .build files from app bundle directory
find "${APP_BUNDLE_DIR}" -name "*.o" -type f -delete 2>/dev/null || true
find "${APP_BUNDLE_DIR}" -name "*.build" -type d -exec rm -rf {} + 2>/dev/null || true

# Ensure executable permissions
chmod +x "${APP_BUNDLE_DIR}/${APP_NAME}"

# 3. Bundle metadata
echo "📦 [3/6] Checking Info.plist and bundle metadata..."
# Keep the Info.plist xcodebuild processed: it carries CFBundleSupportedPlatforms, the DT*
# platform keys and the CFBundleIcons that actool merged in. Copying the raw source plist
# over it (as this step used to) stripped all of that and shipped an iconless bundle
# without a platform declaration.
if ! /usr/libexec/PlistBuddy -c "Print :CFBundleSupportedPlatforms:0" "${APP_BUNDLE_DIR}/Info.plist" 2>/dev/null | grep -qx "iPhoneOS"; then
    echo "❌ ERROR: ${APP_BUNDLE_DIR}/Info.plist does not declare iPhoneOS in CFBundleSupportedPlatforms." >&2
    exit 1
fi
if [ ! -f "${APP_BUNDLE_DIR}/Assets.car" ]; then
    echo "❌ ERROR: Assets.car missing — the asset catalog was not compiled into the app." >&2
    exit 1
fi
echo "  ✓ Info.plist declares iPhoneOS; Assets.car present."

# A published IPA must not carry the build machine's paths (they name the volume and
# project folder). -file-prefix-map rewrites them at compile time; this proves it.
if LC_ALL=C grep -a -q "${PROJECT_DIR}" "${APP_BUNDLE_DIR}/${APP_NAME}"; then
    echo "❌ ERROR: the binary still contains the local path ${PROJECT_DIR}." >&2
    exit 1
fi
echo "  ✓ No local build paths in the binary."

# Copy PkgInfo
echo -n "APPL????" > "${APP_BUNDLE_DIR}/PkgInfo"

# 4. Code Signing (Ad-hoc)
echo "🔏 [4/6] Applying ad-hoc codesign signature..."
if command -v codesign &> /dev/null; then
    ENTITLEMENTS_FLAG=""
    if [ -f "${PROJECT_DIR}/OpenDezor/Resources/OpenDezor.entitlements" ]; then
        ENTITLEMENTS_FLAG="--entitlements ${PROJECT_DIR}/OpenDezor/Resources/OpenDezor.entitlements"
    elif [ -f "${PROJECT_DIR}/Resources/OpenDezor.entitlements" ]; then
        ENTITLEMENTS_FLAG="--entitlements ${PROJECT_DIR}/Resources/OpenDezor.entitlements"
    fi
    codesign -f -s - ${ENTITLEMENTS_FLAG} "${APP_BUNDLE_DIR}"
    echo "  Ad-hoc signature successfully applied."
else
    echo "  Warning: codesign tool not found, skipping signature."
fi

# 5. Verification Checks
echo "🔍 [5/6] Verifying bundle structure and signatures..."

# a) Assert executable exists and is non-empty
if [ ! -f "${APP_BUNDLE_DIR}/${APP_NAME}" ] || [ ! -s "${APP_BUNDLE_DIR}/${APP_NAME}" ]; then
    echo "❌ Assertion Failed: ${APP_BUNDLE_DIR}/${APP_NAME} does not exist or is empty!" >&2
    exit 1
fi
echo "  ✓ Executable exists and is non-empty ($(ls -lh "${APP_BUNDLE_DIR}/${APP_NAME}" | awk '{print $5}'))"

# b) Assert file contains "Mach-O"
FILE_INFO=$(file "${APP_BUNDLE_DIR}/${APP_NAME}")
if [[ "${FILE_INFO}" != *"Mach-O"* ]]; then
    echo "❌ Assertion Failed: ${APP_BUNDLE_DIR}/${APP_NAME} is not a valid Mach-O executable! (${FILE_INFO})" >&2
    exit 1
fi
echo "  ✓ Mach-O executable verified: ${FILE_INFO}"

# c) Assert codesign reports Format=app bundle with Mach-O
if command -v codesign &> /dev/null; then
    CODESIGN_OUTPUT=$(codesign -dvvv "${APP_BUNDLE_DIR}" 2>&1)
    if [[ "${CODESIGN_OUTPUT}" != *"Format=app bundle with Mach-O"* ]]; then
        echo "❌ Assertion Failed: codesign -dvvv did not report Format=app bundle with Mach-O!" >&2
        echo "  Actual codesign output:" >&2
        echo "${CODESIGN_OUTPUT}" >&2
        exit 1
    fi
    echo "  ✓ Codesign bundle format verified: $(echo "${CODESIGN_OUTPUT}" | grep "Format=")"
fi

# 6. Package into .ipa Zip Archive and Final Verification
echo "📦 [6/6] Packaging Payload directory into ${IPA_PATH}..."
cd "${BUILD_DIR}"
zip -q -r -y "${IPA_PATH}" "Payload"

if [ -f "${IPA_PATH}" ] && [ -s "${IPA_PATH}" ]; then
    IPA_SIZE=$(ls -lh "${IPA_PATH}" | awk '{print $5}')
    SHA256_SUM=$(shasum -a 256 "${IPA_PATH}" | awk '{print $1}')
    
    echo "================================================================================"
    echo "  ✅ SUCCESS: OpenDezor.ipa build generated successfully!"
    echo "================================================================================"
    echo "  Artifact:       ${IPA_PATH}"
    echo "  File Size:      ${IPA_SIZE}"
    echo "  SHA256:         ${SHA256_SUM}"
    echo "  Sideload Ready: AltStore, Sideloadly, TrollStore, Scarlet"
    echo "================================================================================"
    
    # List package contents verification
    echo "  IPA Content Inspection:"
    unzip -l "${IPA_PATH}" | head -n 25
    echo "================================================================================"
    exit 0
else
    echo "❌ ERROR: Failed to generate valid IPA package at ${IPA_PATH}" >&2
    exit 1
fi
