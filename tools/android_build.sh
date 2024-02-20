#!/bin/bash

set -e

ROOT=${PWD}

if [ $# -lt 2 ]; then
  echo "Requires a path to the Android NDK and an SDK version number (optionally: target arch)"
  echo "Usage: android_build.sh <ndk_path> <sdk_version> [target_arch]"
  exit 1
fi

ANDROID_SDK_VERSION="$2"

SCRIPT_DIR="$(dirname "$BASH_SOURCE")"
cd "$SCRIPT_DIR"
SCRIPT_DIR=${PWD}

cd "$ROOT"
cd "$1"
ANDROID_NDK_PATH=${PWD}
cd "$SCRIPT_DIR"
cd ../

# Use the ar from the Android NDK instead of from the system.
PREBUILT="${ANDROID_NDK_PATH}/toolchains/llvm/prebuilt"
OS="$(uname | tr '[:upper:]' '[:lower:]')"
ARCH="$(arch)"
PLATFORM="${OS}-${ARCH}"
if [ ! -d "${PREBUILT}/${PLATFORM}" ]; then
  PLATFORM="${OS}-x86_64"
fi
if [ ! -d "${PREBUILT}/${PLATFORM}" ]; then
  echo "Could not find Android NDK tool chain for current platform."
  exit 1
fi
AR="${PREBUILT}/${PLATFORM}/bin/llvm-ar"

# Create standalone static library.
BUILD_LIB_NODE_MOBILE() {
  FILE_LIST="${1}/libNodeMobile.a.ar-file-list"
  LIB_NODE_MOBILE="out_android/$TARGET_ARCH_FOLDER/libNodeMobile.a"
  rm -f "${FILE_LIST}"
  # Find all the .o files in out/Release/obj.target and package them into one single
  # static library.
  find "${1}" -name \*.o > "${FILE_LIST}"
  rm -f "${LIB_NODE_MOBILE}"
  "${AR}" crs "${LIB_NODE_MOBILE}" "@${FILE_LIST}"
}

BUILD_ARCH() {
  # Clean previous compilation
  make clean
  rm -rf android-toolchain/

  # Compile
  eval '"./android-configure" "$ANDROID_NDK_PATH" $ANDROID_SDK_VERSION $TARGET_ARCH'
  make -j $(getconf _NPROCESSORS_ONLN)

  # Move binaries
  TARGET_ARCH_FOLDER="$TARGET_ARCH"
  if [ "$TARGET_ARCH_FOLDER" == "arm" ]; then
    # Use the Android NDK ABI name.
    TARGET_ARCH_FOLDER="armeabi-v7a"
  elif [ "$TARGET_ARCH_FOLDER" == "arm64" ]; then
    # Use the Android NDK ABI name.
    TARGET_ARCH_FOLDER="arm64-v8a"
  fi
  mkdir -p "out_android/$TARGET_ARCH_FOLDER/"
  if [ "${NODE_JS_MOBILE_STATIC}" = "1" ]; then
    LIBRARY_NAME=libnode.a
  else
    LIBRARY_NAME=libnode.so
  fi
  OUTPUT_DIR1="out/Release/lib.target"
  OUTPUT_DIR2="out/Release/obj.target"
  OUTPUT1="${OUTPUT_DIR1}/${LIBRARY_NAME}"
  OUTPUT2="${OUTPUT_DIR2}/${LIBRARY_NAME}"
  if [ -f "$OUTPUT1" ]; then
    if [ "${NODE_JS_MOBILE_STATIC}" = "1" ]; then
      BUILD_LIB_NODE_MOBILE "$OUTPUT_DIR1"
    else
      cp "$OUTPUT1" "out_android/$TARGET_ARCH_FOLDER/${LIBRARY_NAME}"
    fi
  elif [ -f "$OUTPUT2" ]; then
    if [ "${NODE_JS_MOBILE_STATIC}" = "1" ]; then
      BUILD_LIB_NODE_MOBILE "$OUTPUT_DIR2"
    else
      cp "$OUTPUT2" "out_android/$TARGET_ARCH_FOLDER/${LIBRARY_NAME}"
    fi
  else
    echo "Could not find ${LIBRARY_NAME} file after compilation"
    exit 1
  fi
}

if [ $# -eq 2 ]; then
  TARGET_ARCH="arm"
  BUILD_ARCH
  # TARGET_ARCH="x86"
  # BUILD_ARCH
  TARGET_ARCH="arm64"
  BUILD_ARCH
  TARGET_ARCH="x86_64"
  BUILD_ARCH
else
  TARGET_ARCH=$3
  BUILD_ARCH
fi

source $SCRIPT_DIR/copy_libnode_headers.sh android

cd "$ROOT"
