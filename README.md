# XSky 对象存储到 NFS 转换网关

基于 JuiceFS 实现 XSky 对象存储到 NFS 的转换服务，使用 MinIO 模拟 XSky 进行测试。

## 项目概述

本项目提供了一个完整的解决方案，将对象存储（S3 兼容）转换为 NFS 文件系统，并实现自动同步功能。

## 系统架构

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌─────────────┐
│ NFS 客户端  │───▶│  NFS    │───▶│  JuiceFS    │───▶│   MinIO     │
│             │    │   服务       │    │  文件系统   │    │ (模拟XSky)  │
└─────────────┘    └──────────────┘    └─────────────┘    └─────────────┘
                                              │                    │
                                              ▼                    │
                                       ┌─────────────┐             │
                                       │   Redis     │◀────────────┘
                                       │  (元数据)   │
                                       └─────────────┘
```

## 核心组件

| 组件         | 作用                          | 配置                            |
| ------------ | ----------------------------- | ------------------------------- |
| **MinIO**    | S3 兼容对象存储，模拟 XSky    | 端口: 9000 (API), 9001 (Web UI) |
| **Redis**    | JuiceFS 元数据存储            | 端口: 6379                      |
| **JuiceFS**  | 对象存储到 POSIX 文件系统转换 | 挂载点: `/tmp/s3_xsky_mount`     |
| **同步脚本** | 自动同步 MinIO 数据到 JuiceFS | 支持一次性和持续同步            |

## 快速开始

### 1. 启动基础服务

```bash
# 启动 MinIO 和 Redis
docker-compose up -d

# 检查服务状态
docker-compose ps
```

### 2. 初始化 JuiceFS

```bash
# 格式化 JuiceFS 文件系统
juicefs format \
    --storage s3 \
    --bucket http://127.0.0.1:9000/xsky-data \
    --access-key minioadmin \
    --secret-key minioadmin123 \
    redis://127.0.0.1:6379/1 \
    nfs-xsky
```

### 3. 挂载 JuiceFS

```bash
# 创建挂载点和缓存目录
mkdir -p data/xsky-mount data/s3-cache logs

# 挂载 JuiceFS（注意权限设置）
juicefs mount redis://127.0.0.1:6379/1 /tmp/s3_xsky_mount \
    --cache-dir ./data/s3-cache \
    --cache-size 1024 \
    --background \
    --log ./logs/juicefs.log \
    --all-squash $(id -u):$(id -g)
```

### 4. 配置同步

```bash
# 给同步脚本执行权限
chmod +x sync-minio-to-juicefs.sh

# 执行一次性同步
./sync-minio-to-juicefs.sh --once

# 或启动持续同步（每30秒检查一次）
./sync-minio-to-juicefs.sh
```

### 5.挂载 NFS 共享
```bash
sudo mount -t nfs -o vers=4.0,ro,noresvport,intr,timeo=3,retrans=2 NFS_Server_IP:/mnt/juicefs /Volumes/nfs-share
```
## 使用说明

### MinIO Web 管理界面

- **访问地址**: http://localhost:9001
- **用户名**: minioadmin
- **密码**: minioadmin123

### 文件同步

项目提供了多种同步方式：

1. **手动同步**

   ```bash
   juicefs sync --no-https \
       s3://minioadmin:minioadmin123@127.0.0.1:9000/xsky-data/ \
       /tmp/s3_xsky_mount/ --verbose
   ```

2. **自动同步脚本**

   ```bash
   # 一次性同步
   ./sync-minio-to-juicefs.sh --once

   # 持续监控同步
   ./sync-minio-to-juicefs.sh
   ```

3. **Python 实时监控**（需要安装 minio 包）
   ```bash
   pip3 install minio
   python3 realtime-sync.py
   ```

### 验证同步

```bash
# 查看挂载点内容
ls -la /tmp/s3_xsky_mount/

# 查看同步日志
tail -f ./logs/sync-$(date +%Y%m%d).log
```

## 目录结构

```
.
├── README.md                    # 项目说明
├── SYNC_GUIDE.md               # 详细同步指南
├── docker-compose.yml          # Docker 服务配置
├── sync-minio-to-juicefs.sh    # Bash 同步脚本
├── realtime-sync.py            # Python 实时监控脚本
├── com.xsky.minio-juicefs-sync.plist  # macOS 系统服务配置
├── data/
│   ├── xsky-mount/             # JuiceFS 挂载点
│   └── s3-cache/               # JuiceFS 缓存目录
└── logs/                       # 日志文件目录
```

## 故障排除

### 常见问题

1. **权限拒绝错误**

   ```bash
   # 重新挂载并设置正确权限
   sudo juicefs umount /tmp/s3_xsky_mount
   juicefs mount redis://127.0.0.1:6379/1 /tmp/s3_xsky_mount \
       --all-squash $(id -u):$(id -g) [其他参数...]
   ```

2. **MinIO 连接失败**

   ```bash
   # 检查服务状态
   docker-compose ps
   # 重启服务
   docker-compose restart minio
   ```

3. **JuiceFS 挂载失败**
   ```bash
   # 检查 Redis 连接
   redis-cli -h 127.0.0.1 -p 6379 ping
   # 查看 JuiceFS 日志
   tail -f ./logs/juicefs.log
   ```

### 日志文件

- JuiceFS 日志: `./logs/juicefs.log`
- 同步脚本日志: `./logs/sync-YYYYMMDD.log`
- Python 监控日志: `./logs/realtime-sync-YYYYMMDD.log`

## 性能优化

- **缓存大小**: 根据可用内存调整 `--cache-size` 参数
- **同步间隔**: 修改脚本中的 `SYNC_INTERVAL` 变量
- **并发线程**: 使用 `--threads` 参数增加同步并发数

## 更多信息

详细的同步配置和使用说明请参考 [SYNC_GUIDE.md](./SYNC_GUIDE.md)。
