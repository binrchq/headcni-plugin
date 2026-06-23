# HeadCNI Plugin Build Scripts

This directory contains build and packaging scripts for the HeadCNI plugin.

## Scripts Overview

### Core Build Scripts

#### `build_headcni.sh`
**Purpose**: Core build script for compiling a single platform binary.

**Usage**:
```bash
GOOS=linux GOARCH=amd64 OUTPUT_DIR=dist ./scripts/build_headcni.sh
```

**Environment Variables**:
- `GOOS`: Target OS (linux, windows, darwin)
- `GOARCH`: Target architecture (amd64, arm64, arm, 386, etc.)
- `OUTPUT_DIR`: Output directory (default: current directory)
- `VERSION`: Version string (default: from git)
- `COMMIT`: Commit hash (default: from git)
- `BUILD_DATE`: Build timestamp (default: current time)

**Features**:
- CGO enabled for amd64 (better performance)
- Static linking with `-extldflags "-static"`
- Version info embedded in binary

---

#### `build_all_linux.sh`
**Purpose**: Build all supported Linux architectures.

**Usage**:
```bash
OUTPUT_DIR=dist ./scripts/build_all_linux.sh
```

**Supported Architectures**:
- 386, amd64, arm, arm64, s390x, ppc64le, riscv64

**Called by**: `build_all_platforms.sh`, Makefile targets

---

#### `build_all_platforms.sh`
**Purpose**: Build binaries for all platforms (Linux, Windows, macOS).

**Usage**:
```bash
OUTPUT_DIR=dist ./scripts/build_all_platforms.sh
```

**Output**: All binaries in `dist/` directory with naming format `headcni-{os}-{arch}`

**Called by**: 
- Makefile: `make build-all-script`
- GitHub Actions: `.github/workflows/release.yml`

---

### Packaging Scripts

#### `package.sh`
**Purpose**: Create release packages (tar.gz for Unix, zip for Windows) from built binaries.

**Usage**:
```bash
VERSION=1.0.0 ./scripts/package.sh
```

**Input**: Expects binaries in `dist/` directory  
**Output**: Release packages in `release/` directory with:
- tar.gz/zip archives
- README.md in each package
- checksums.sha256 file

**Called by**:
- Makefile: `make release-script`
- GitHub Actions: `.github/workflows/release.yml`

---

### Utility Scripts

#### `version.sh`
**Purpose**: Extract and export version information from git.

**Usage**:
```bash
source ./scripts/version.sh
echo $VERSION
```

**Exports**:
- `VERSION`: git tag or "dev"
- `COMMIT`: short commit hash
- `BUILD_DATE`: current UTC timestamp

---

### Docker Build Scripts

#### `build-multiarch-fixed.sh` (14KB - Docker specific)
**Purpose**: Complex Docker multi-architecture build with buildx.

**Usage**:
```bash
./scripts/build-multiarch-fixed.sh [all|build|push|manifest|verify|cleanup]
```

**Features**:
- Parallel builds with dynamic resource detection
- QEMU cross-compilation support
- Docker manifest creation for multi-arch images
- Supports 8+ architectures

**Called by**: 
- Makefile: `make docker-multiarch`

**Note**: This is only used for Docker multi-architecture image builds, not for standard binary releases.

---

## Build Workflows

### Standard Binary Build (CI/CD)
```bash
# 1. Build all platforms
make build-all-script
# Uses: build_all_platforms.sh → build_all_linux.sh + individual OS builds → build_headcni.sh

# 2. Package for release
make release-script  
# Uses: package.sh
```

### Docker Multi-Architecture Build
```bash
# Build and push multi-arch Docker images
make docker-multiarch
# Uses: build-multiarch-fixed.sh
```

### Quick Local Build
```bash
# Build for current platform only
make build
# Direct go build command in Makefile
```

---

## Dependencies

All scripts require:
- Go 1.26+ (as specified in go.mod)
- Git (for version detection)
- Standard Unix tools (bash, tar, zip)

Docker scripts additionally require:
- Docker with buildx
- QEMU (for cross-platform builds)

---

## Script Permissions

All scripts should be executable:
```bash
chmod +x scripts/*.sh
```

This is automatically done by Makefile targets when needed.
