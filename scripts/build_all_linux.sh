#!/usr/bin/env bash
# build_all_linux.sh - Build HeadCNI plugin for all supported Linux architectures
#
# Usage: OUTPUT_DIR=dist ./scripts/build_all_linux.sh
#
# Environment Variables:
#   OUTPUT_DIR   - Output directory (default: dist)
#
# Output: Multiple binaries in ${OUTPUT_DIR}/ for all Linux architectures
# Architectures: 386, amd64, arm, arm64, s390x, ppc64le, riscv64
#
set -ex

cd $(dirname $0)/..

# 设置输出目录
OUTPUT_DIR=${OUTPUT_DIR:-dist}
mkdir -p ${OUTPUT_DIR}

# 支持的Linux架构
ARCHITECTURES=("386" "amd64" "arm" "arm64" "s390x" "ppc64le" "riscv64")

echo "Building all Linux architectures for headcni plugin"
echo "Output directory: ${OUTPUT_DIR}"

# 构建所有架构
for arch in "${ARCHITECTURES[@]}"; do
    echo "Building for linux/${arch}..."
    GOOS=linux GOARCH=${arch} OUTPUT_DIR=${OUTPUT_DIR} ./scripts/build_headcni.sh
done

echo "All Linux architectures built successfully!"
echo "Binaries created in ${OUTPUT_DIR}/:"
ls -la ${OUTPUT_DIR}/headcni-linux-* 