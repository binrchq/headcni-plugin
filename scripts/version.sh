#!/usr/bin/env bash
# version.sh - Extract and export version information from git
#
# Usage: source ./scripts/version.sh
#
# Exports:
#   VERSION    - Git tag or "dev" if no tag
#   COMMIT     - Short commit hash or "dev" if not in git repo
#   BUILD_DATE - Current UTC timestamp
#
# Called by: Other build scripts that need version info
#

# 获取版本信息
VERSION=${VERSION:-$(git describe --tags --dirty --always 2>/dev/null || echo "dev")}
COMMIT=${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo "dev")}
BUILD_DATE=${BUILD_DATE:-$(date -u '+%Y-%m-%d_%H:%M:%S')}

# 导出变量
export VERSION
export COMMIT
export BUILD_DATE

# 显示版本信息
echo "Version: ${VERSION}"
echo "Commit: ${COMMIT}"
echo "Build Date: ${BUILD_DATE}" 