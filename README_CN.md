# HeadCNI Plugin

[![Go 版本](https://img.shields.io/badge/Go-1.24+-blue.svg)](https://golang.org)
[![CNI 版本](https://img.shields.io/badge/CNI-1.0.0-green.svg)](https://github.com/containernetworking/cni)
[![许可证](https://img.shields.io/badge/许可证-Apache%202.0-blue.svg)](LICENSE)
[![平台支持](https://img.shields.io/badge/平台-Linux%20%7C%20Windows%20%7C%20macOS-lightgrey.svg)](https://binrc.com/headcni-plugin)

**HeadCNI Plugin** 是一个高级的 CNI (Container Network Interface) meta-plugin，专为 Kubernetes 和容器环境设计。它提供了智能的网络配置管理、跨平台支持和插件链执行功能。

## 🚀 核心特性

- **🔗 智能委托**: 自动委托给底层网络插件（bridge、ipvlan等）
- **🌍 跨平台支持**: 支持 Linux、Windows、macOS (amd64/arm64)
- **⚙️ 动态配置**: 从 YAML 文件动态加载网络配置
- **🔧 插件链执行**: 支持多个 CNI 插件的顺序执行
- **📊 状态管理**: 完整的插件执行状态跟踪和回滚
- **🚀 高性能**: 优化的网络配置处理和执行
- **🔒 安全**: 支持网络策略和访问控制

## 📋 系统要求

- **Go**: 1.24+ 
- **操作系统**: Linux, Windows, macOS
- **架构**: amd64, arm64
- **CNI**: 1.0.0+

## 🛠️ 快速开始

### 1. 安装

#### 从源码构建

```bash
# 克隆仓库
git clone https://binrc.com/headcni-plugin.git
cd headcni-plugin

# 构建
make build

# 安装到系统
sudo make install
```

#### 使用 Docker

```bash
# 构建 Docker 镜像
make docker

# 运行容器
docker run --rm -v /opt/cni/bin:/app/bin headcni-plugin:latest
```

### 2. 配置

#### 基本配置 (10-headcni.conflist)

```json
{
  "cniVersion": "1.0.0",
  "name": "cbr0",
  "plugins": [
    {
      "type": "headcni",
      "delegate": {
        "type": "bridge",
        "bridge": "cbr0",
        "isDefaultGateway": true,
        "isGateway": true,
        "hairpinMode": true
      },
      "dataDir": "/var/lib/cni/headcni",
      "subnetFile": "/run/headcni/env.yaml"
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      }
    }
  ]
}
```

#### 环境配置文件 (env.yaml)

```yaml
# IPv4 网络配置
network: "10.244.0.0/16"
subnet: "10.244.1.0/24"

# IPv6 网络配置 (可选)
ipv6_network: "fd00::/64"
ipv6_subnet: "fd00::/80"

# MTU 配置
mtu: 1500

# IP 伪装配置
ipmasq: true

# 路由配置 (可选)
routes:
  - dst: "10.244.0.0/16"
    gw: "10.244.1.1"
  - dst: "0.0.0.0/0"
    gw: "10.244.1.1"

# DNS 配置 (可选)
dns:
  nameservers:
    - "10.244.0.10"
    - "8.8.8.8"
  search:
    - "cluster.local"
  options:
    - "ndots:5"
```

### 3. 使用

#### 在 Kubernetes 中使用

1. **部署 HeadCNI DaemonSet**:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: headcni-daemon
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: headcni-daemon
  template:
    metadata:
      labels:
        name: headcni-daemon
    spec:
      containers:
      - name: headcni
        image: binrc/headcni:latest
        command: ["/usr/local/bin/headcni"]
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        volumeMounts:
        - name: cni-bin
          mountPath: /opt/cni/bin
        - name: cni-conf
          mountPath: /etc/cni/net.d
        - name: headcni-data
          mountPath: /var/lib/headcni
      volumes:
      - name: cni-bin
        hostPath:
          path: /opt/cni/bin
      - name: cni-conf
        hostPath:
          path: /etc/cni/net.d
      - name: headcni-data
        hostPath:
          path: /var/lib/headcni
```

2. **配置 CNI**:

```bash
# 复制配置文件
sudo cp 10-headcni.conflist /etc/cni/net.d/

# 重启 kubelet
sudo systemctl restart kubelet
```

#### 手动测试

```bash
# 创建测试网络命名空间
sudo ip netns add test

# 执行 ADD 命令
echo '{"cniVersion": "1.0.0", "name": "test", "type": "headcni"}' | \
sudo CNI_COMMAND=ADD CNI_CONTAINERID=test123 CNI_NETNS=/var/run/netns/test \
CNI_IFNAME=eth0 CNI_PATH=/opt/cni/bin /opt/cni/bin/headcni

# 执行 DEL 命令
sudo CNI_COMMAND=DEL CNI_CONTAINERID=test123 CNI_NETNS=/var/run/netns/test \
CNI_IFNAME=eth0 CNI_PATH=/opt/cni/bin /opt/cni/bin/headcni

# 清理
sudo ip netns del test
```

## 🏗️ 架构设计

### 核心组件

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CNI Runtime  │───▶│  HeadCNI Core   │───▶│ Delegate Plugin │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │  Configuration  │
                       │     Manager     │
                       └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   State Store   │
                       └─────────────────┘
```

### 执行流程

1. **配置加载**: 从 CNI 配置和环境文件加载网络配置
2. **委托执行**: 将网络操作委托给底层插件（bridge、ipvlan等）
3. **状态管理**: 跟踪插件执行状态，支持回滚
4. **结果返回**: 返回网络配置结果

## 🔧 高级配置

### 自定义委托插件

```json
{
  "type": "headcni",
  "delegate": {
    "type": "ipvlan",
    "master": "eth0",
    "mode": "l2",
    "ipam": {
      "type": "host-local",
      "subnet": "10.244.1.0/24"
    }
  }
}
```

### 运行时配置

```json
{
  "runtimeConfig": {
    "portMappings": [
      {
        "hostPort": 8080,
        "containerPort": 80,
        "protocol": "tcp"
      }
    ],
    "bandwidth": {
      "ingressRate": 1000000,
      "egressRate": 1000000
    }
  }
}
```

## 📊 监控和调试

### 日志配置

```bash
# 设置日志级别
export CNI_LOG_LEVEL=debug

# 查看插件日志
sudo journalctl -u kubelet -f | grep headcni
```

### 健康检查

```bash
# 检查插件状态
sudo /opt/cni/bin/headcni version

# 验证配置
sudo /opt/cni/bin/headcni check
```

## 🚀 性能优化

### 构建优化

```bash
# 静态链接构建
make build-static

# 跨平台构建
make build-all

# 优化构建
make build-optimized
```

### 运行时优化

- 使用 `CGO_ENABLED=0` 进行静态链接
- 启用 Go 编译器优化 (`-ldflags "-s -w"`)
- 使用 Alpine Linux 作为基础镜像

## 🐛 故障排除

### 常见问题

1. **插件未找到**
   ```bash
   # 检查插件路径
   ls -la /opt/cni/bin/headcni
   
   # 检查权限
   sudo chmod +x /opt/cni/bin/headcni
   ```

2. **配置错误**
   ```bash
   # 验证配置文件
   cat /etc/cni/net.d/10-headcni.conflist | jq .
   
   # 检查环境文件
   cat /var/lib/headcni/env.yaml
   ```

3. **网络连接失败**
   ```bash
   # 检查网络接口
   ip link show
   
   # 检查路由表
   ip route show
   ```

### 调试模式

```bash
# 启用详细日志
export CNI_LOG_LEVEL=debug
export CNI_LOG_FILE=/tmp/headcni.log

# 手动测试
sudo CNI_COMMAND=ADD CNI_CONTAINERID=test CNI_NETNS=/var/run/netns/test \
CNI_IFNAME=eth0 CNI_PATH=/opt/cni/bin /opt/cni/bin/headcni
```

## 🤝 贡献指南

我们欢迎社区贡献！请查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详情。

### 开发环境设置

```bash
# 克隆仓库
git clone https://binrc.com/headcni-plugin.git
cd headcni-plugin

# 安装依赖
go mod download

# 运行测试
make test

# 构建
make build
```

### 代码规范

- 遵循 Go 官方代码规范
- 使用 `gofmt` 格式化代码
- 运行 `golint` 检查代码质量
- 确保测试覆盖率 > 80%

## 📄 许可证

本项目采用 [Apache License 2.0](LICENSE) 许可证。

## 🙏 致谢

- [CNI](https://github.com/containernetworking/cni) - Container Network Interface
- [CNI Plugins](https://github.com/containernetworking/plugins) - 标准 CNI 插件
- [Kubernetes](https://kubernetes.io/) - 容器编排平台

## 📞 支持

- **GitHub Issues**: [报告问题](https://binrc.com/headcni-plugin/issues)
- **文档**: [查看文档](https://binrc.com/headcni-plugin/wiki)
- **讨论**: [GitHub Discussions](https://binrc.com/headcni-plugin/discussions)

---

**HeadCNI Plugin** - 让容器网络配置更简单、更强大！ 🚀 