#!/bin/bash
# build-multiarch-fixed.sh - Docker multi-architecture build with buildx
#
# Usage: ./scripts/build-multiarch-fixed.sh [all|build|push|manifest|verify|cleanup]
#
# Commands:
#   all       - Complete build workflow: build, export, create manifest, verify, cleanup
#   build     - Build platform images only
#   push      - Push platform images to registry
#   manifest  - Create and push multi-platform manifest
#   verify    - Verify built images and manifest
#   cleanup   - Remove temporary build files
#
# Environment Variables:
#   REGISTRY      - Docker registry (default: docker.io)
#   NAMESPACE     - Docker namespace (default: binrc)
#   IMAGE_NAME    - Image name (default: headcni-plugin)
#   IMAGE_TAG     - Image tag (default: latest)
#   SKIP_PUSH     - Skip manifest push (default: false)
#
# Requirements:
#   - Docker with buildx support
#   - QEMU for cross-platform builds
#   - jq for manifest inspection
#
# Output:
#   - Multi-architecture Docker images
#   - .docker/.built_platforms.txt - List of built platform images
#   - .docker/.manifest_tag.txt - Manifest tag
#
# Called by: make docker-multiarch
#

set -e

# Configuration
REGISTRY="${REGISTRY:-docker.io}"
NAMESPACE="${NAMESPACE:-binrc}"
IMAGE_NAME="${IMAGE_NAME:-headcni-plugin}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Supported platforms (ordered by build speed)
PLATFORMS=(
    "linux/amd64"
    "linux/arm64"
    "linux/386"
    "linux/arm/v7"
    "linux/arm/v8"
    "linux/ppc64le"
    "linux/s390x"
    "linux/riscv64"
)

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info()  { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1" >&2; }

# Check required dependencies
check_dependencies() {
    log_step "检查依赖..."

    local missing=()
    command -v docker >/dev/null 2>&1 || missing+=("docker")
    command -v docker buildx >/dev/null 2>&1 || missing+=("docker buildx")

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "缺少依赖: ${missing[*]}"
        exit 1
    fi

    log_info "依赖检查通过"
}

# Setup multi-architecture builder
setup_local_builder() {
    log_step "设置多架构构建器..."

    # Install QEMU for cross-platform builds
    if ! docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1; then
        log_error "安装 QEMU (binfmt) 失败"
        exit 1
    fi
    log_info "QEMU 已安装，支持跨架构构建"

    # Create or use existing builder
    if docker buildx ls | grep -q "multi-builder"; then
        log_info "使用已有的 multi-builder"
        docker buildx use multi-builder
    else
        log_info "创建新的 multi-builder"
        docker buildx create --name multi-builder --driver docker-container --use
    fi

    docker buildx inspect --bootstrap
}

# Build single platform image
build_platform() {
    local platform=$1
    local os_arch=$(echo "$platform" | sed 's/\//-/g')
    local image_tag="${NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}-${os_arch}"

    log_info "构建平台: $platform -> $image_tag"

    local start_time=$(date +%s)
    local log_file="/tmp/headcni_build_${os_arch}.log"

    # Build image
    if docker buildx build \
        --platform "$platform" \
        --tag "$image_tag" \
        --file .docker/Dockerfile \
        --progress=plain \
        --build-arg TARGETOS=$(echo "$platform" | cut -d'/' -f1) \
        --build-arg TARGETARCH=$(echo "$platform" | cut -d'/' -f2) \
        --cache-from type=local,src=/tmp/.buildx-cache \
        --cache-to type=local,dest=/tmp/.buildx-cache,mode=max \
        . > "$log_file" 2>&1; then

        local duration=$(($(date +%s) - start_time))
        log_info "✓ 平台镜像构建完成: $image_tag (耗时: ${duration}s)"
        echo "$image_tag"
        return 0
    else
        log_error "✗ 平台镜像构建失败: $platform (日志: $log_file)"
        return 1
    fi
}

# Calculate optimal parallel job count based on system resources
get_max_jobs() {
    local cpu_cores=$(nproc 2>/dev/null || echo 4)
    local available_memory=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)

    local max_jobs=4
    if [ "$cpu_cores" -ge 32 ] && [ "$available_memory" -ge 32768 ]; then
        max_jobs=12
    elif [ "$cpu_cores" -ge 16 ] && [ "$available_memory" -ge 16384 ]; then
        max_jobs=8
    elif [ "$cpu_cores" -ge 8 ] && [ "$available_memory" -ge 8192 ]; then
        max_jobs=6
    elif [ "$cpu_cores" -ge 4 ] && [ "$available_memory" -ge 4096 ]; then
        max_jobs=4
    else
        max_jobs=2
    fi

    log_info "系统资源: CPU核心=$cpu_cores, 内存=${available_memory}MB, 并行数=$max_jobs"
    echo $max_jobs
}

# Build all platforms in parallel
build_platforms_parallel() {
    local max_jobs=$(get_max_jobs)
    local temp_dir=$(mktemp -d)
    local result_file="$temp_dir/build_results.txt"

    log_step "开始构建 ${#PLATFORMS[@]} 个平台镜像..."

    local platform_index=0
    while [ $platform_index -lt ${#PLATFORMS[@]} ]; do
        # Wait if max parallel jobs reached
        while [ $(jobs -r | wc -l) -ge $max_jobs ]; do
            sleep 1
        done

        local platform="${PLATFORMS[$platform_index]}"
        log_info "启动后台构建: $platform"

        (
            if image_tag=$(build_platform "$platform"); then
                echo "$image_tag" >> "$result_file"
                log_info "✓ 后台构建完成: $platform"
            else
                log_error "✗ 后台构建失败: $platform"
                exit 1
            fi
        ) &

        platform_index=$((platform_index + 1))
        sleep 0.5
    done

    # Wait for all jobs with progress reporting
    log_info "等待所有构建作业完成..."
    local total=${#PLATFORMS[@]}

    while true; do
        local running=$(jobs -r | wc -l)
        local completed=$((total - running))
        [ $completed -lt 0 ] && completed=0

        log_info "构建进度: $completed/$total 完成, $running 运行中..."
        [ $running -eq 0 ] && break

        sleep 5
    done

    wait

    if [ $? -ne 0 ]; then
        log_error "部分构建作业失败"
        rm -rf "$temp_dir"
        return 1
    fi

    log_info "✓ 所有构建作业完成"

    # Save results
    local built_images=()
    if [ -f "$result_file" ]; then
        while IFS= read -r image; do
            [ -n "$image" ] && built_images+=("$image")
        done < "$result_file"
    fi

    rm -rf "$temp_dir"

    if [ ${#built_images[@]} -eq 0 ]; then
        log_error "没有成功构建的镜像"
        return 1
    fi

    # Save to file
    printf "%s\n" "${built_images[@]}" > .docker/.built_platforms.txt
    log_info "保存的镜像标签 (${#built_images[@]} 个):"
    printf "%s\n" "${built_images[@]}" | sed 's/^/  - /'

    return 0
}

# Export images from buildx cache to local
export_images_from_cache() {
    log_step "从 buildx 缓存导出镜像到本地..."

    [ ! -f .docker/.built_platforms.txt ] && { log_error "找不到构建结果文件"; return 1; }

    while IFS= read -r image; do
        if [ -n "$image" ]; then
            log_info "导出镜像到本地: $image"

            if docker buildx imagetools inspect "$image" > /dev/null 2>&1; then
                local temp_dockerfile="/tmp/export_${RANDOM}.Dockerfile"
                echo "FROM $image" > "$temp_dockerfile"
                docker buildx build --load -f "$temp_dockerfile" -t "$image" . > /dev/null 2>&1
                rm -f "$temp_dockerfile"
                log_info "✓ 镜像导出完成: $image"
            else
                log_error "✗ 镜像不存在于 buildx 缓存: $image"
            fi
        fi
    done < .docker/.built_platforms.txt

    log_info "所有镜像导出完成"
}

# Push platform images to registry
push_platform_images() {
    log_step "推送平台镜像到远程仓库..."

    [ ! -f .docker/.built_platforms.txt ] && { log_error "找不到构建结果文件"; return 1; }

    while IFS= read -r image; do
        [ -n "$image" ] && { log_info "推送镜像: $image"; docker push "$image"; }
    done < .docker/.built_platforms.txt

    log_info "所有平台镜像推送完成"
}

# Create multi-platform manifest
create_manifest() {
    local skip_push="${SKIP_PUSH:-false}"
    log_step "创建多平台 manifest..."

    local manifest_tag="${NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"

    [ ! -f .docker/.built_platforms.txt ] && { log_error "找不到构建结果文件"; return 1; }

    # Collect platform images
    local platform_images=()
    while IFS= read -r image; do
        [ -n "$image" ] && platform_images+=("$image")
    done < .docker/.built_platforms.txt

    if [ ${#platform_images[@]} -eq 0 ]; then
        log_error "没有找到平台镜像，无法创建 manifest"
        return 1
    fi

    log_info "准备创建 manifest: $manifest_tag (包含 ${#platform_images[@]} 个平台镜像)"

    # Verify local images exist
    for img in "${platform_images[@]}"; do
        if ! docker image inspect "$img" > /dev/null 2>&1; then
            log_error "本地镜像不存在: $img"
            return 1
        fi
    done

    # Push platform images first
    push_platform_images

    # Create manifest
    docker manifest rm "$manifest_tag" 2>/dev/null || true
    log_info "创建 manifest: $manifest_tag"
    docker manifest create "$manifest_tag" "${platform_images[@]}"

    # Push manifest if not skipped
    if [ "$skip_push" = "true" ]; then
        log_info "跳过 manifest 推送 (SKIP_PUSH=true)"
    else
        log_info "推送 manifest 到远程仓库..."
        docker manifest push "$manifest_tag"
    fi

    log_info "✓ 多平台 manifest 创建完成: $manifest_tag"
    echo "$manifest_tag" > .docker/.manifest_tag.txt

    return 0
}

# Verify built images and manifest
verify_images() {
    log_step "验证构建的镜像..."

    local manifest_tag="${NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"

    # Check local platform images
    log_info "检查本地平台镜像..."
    while IFS= read -r image; do
        if [ -n "$image" ]; then
            if docker image inspect "$image" > /dev/null 2>&1; then
                log_info "✓ 本地镜像存在: $image"
            else
                log_error "✗ 本地镜像不存在: $image"
            fi
        fi
    done < .docker/.built_platforms.txt

    # Check manifest
    log_info "检查 manifest..."
    if docker manifest inspect "$manifest_tag" > /dev/null 2>&1; then
        log_info "✓ Manifest 验证通过: $manifest_tag"

        # Show supported platforms
        if command -v jq >/dev/null 2>&1; then
            docker manifest inspect "$manifest_tag" | \
                jq -r '.manifests[] | "\(.platform.os)/\(.platform.architecture)"' 2>/dev/null | \
                while read platform; do log_info "  支持平台: $platform"; done
        fi
    else
        log_warn "✗ Manifest 验证失败或不存在: $manifest_tag"
    fi

    return 0
}

# Cleanup temporary files
cleanup() {
    log_step "清理临时文件..."

    rm -f .docker/.built_platforms.txt
    rm -f .docker/.manifest_tag.txt
    rm -f /tmp/headcni_build_*.log 2>/dev/null || true

    log_info "✓ 清理完成"
}

# Main function
main() {
    local action="${1:-all}"

    case "$action" in
        all)
            log_step "开始完整的多架构构建流程..."
            check_dependencies
            setup_local_builder
            build_platforms_parallel
            export_images_from_cache
            create_manifest
            verify_images
            cleanup
            log_info "✓ 多架构构建流程完成"
            ;;
        build)
            log_step "开始构建平台镜像..."
            check_dependencies
            setup_local_builder
            build_platforms_parallel
            export_images_from_cache
            log_info "✓ 平台镜像构建完成"
            ;;
        push)
            log_step "推送平台镜像..."
            push_platform_images
            log_info "✓ 平台镜像推送完成"
            ;;
        manifest)
            log_step "创建多平台 manifest..."
            create_manifest
            log_info "✓ Manifest 创建完成"
            ;;
        verify)
            log_step "验证镜像..."
            verify_images
            log_info "✓ 镜像验证完成"
            ;;
        cleanup)
            cleanup
            ;;
        *)
            log_error "未知操作: $action"
            echo "用法: $0 [all|build|push|manifest|verify|cleanup]"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
