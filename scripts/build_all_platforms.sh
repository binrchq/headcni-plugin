#!/usr/bin/env bash
# build_all_platforms.sh - Build HeadCNI plugin for all supported platforms
#
# Usage: OUTPUT_DIR=dist ./scripts/build_all_platforms.sh
#
# Environment Variables:
#   OUTPUT_DIR   - Output directory (default: dist)
#
# Output: All platform binaries in ${OUTPUT_DIR}/
#   - Linux: 7 architectures (via build_all_linux.sh)
#   - Windows: amd64, arm64
#   - macOS: amd64, arm64
#
# Called by: make build-all-script, GitHub Actions release workflow
#
set -ex

cd $(dirname $0)/..

# 设置输出目录
OUTPUT_DIR=${OUTPUT_DIR:-dist}
mkdir -p ${OUTPUT_DIR}

echo "Building all platforms for headcni plugin"
echo "Output directory: ${OUTPUT_DIR}"

# 构建所有Linux架构
echo "Building Linux architectures..."
./scripts/build_all_linux.sh

# 构建Windows版本
echo "Building Windows versions..."
GOOS=windows GOARCH=amd64 OUTPUT_DIR=${OUTPUT_DIR} ./scripts/build_headcni.sh
GOOS=windows GOARCH=arm64 OUTPUT_DIR=${OUTPUT_DIR} ./scripts/build_headcni.sh

# 构建macOS版本
echo "Building macOS versions..."
GOOS=darwin GOARCH=amd64 OUTPUT_DIR=${OUTPUT_DIR} ./scripts/build_headcni.sh
GOOS=darwin GOARCH=arm64 OUTPUT_DIR=${OUTPUT_DIR} ./scripts/build_headcni.sh

echo "All platforms built successfully!"
echo "Binaries created in ${OUTPUT_DIR}/:"
ls -la ${OUTPUT_DIR}/headcni-* 