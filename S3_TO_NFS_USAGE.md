# S3 到 NFS 直接同步使用指南

## 概述

本项目提供了两个强大的脚本，可以直接使用 JuiceFS Sync 将 S3 兼容存储的文件同步到 NFS 导出目录，无需中间的 JuiceFS 挂载步骤。

## 脚本对比

| 特性 | s3-to-nfs-direct.sh | s3-to-nfs-advanced.sh |
|------|---------------------|----------------------|
| 配置方式 | 脚本内硬编码 | 外部配置文件 |
| 过滤选项 | 无 | 支持包含/排除模式 |
| 文件大小限制 | 无 | 支持最大/最小文件大小 |
| 同步模式 | 完整/增量 | 完整/增量/预览 |
| 高级选项 | 基础 | 完整的 JuiceFS 选项 |
| 适用场景 | 简单快速使用 | 生产环境/复杂需求 |

## 快速开始

### 1. 使用简单版本

```bash
# 完整设置（推荐首次使用）
./s3-to-nfs-direct.sh setup

# 仅同步一次
./s3-to-nfs-direct.sh sync

# 增量同步
./s3-to-nfs-direct.sh incremental

# 持续同步
./s3-to-nfs-direct.sh continuous
```

### 2. 使用高级版本

```bash
# 预览要同步的文件（不实际复制）
./s3-to-nfs-advanced.sh dry-run

# 完整设置
./s3-to-nfs-advanced.sh setup

# 增量同步
./s3-to-nfs-advanced.sh incremental

# 持续同步
./s3-to-nfs-advanced.sh continuous
```

## 配置说明

### 简单版本配置

编辑 `s3-to-nfs-direct.sh` 文件中的配置参数：

```bash
MINIO_ENDPOINT="127.0.0.1:9000"
MINIO_BUCKET="xsky-data"
MINIO_ACCESS_KEY="minioadmin"
MINIO_SECRET_KEY="minioadmin123"
NFS_EXPORT_DIR="$HOME/nfs-s3-direct"
SYNC_INTERVAL=30
```

### 高级版本配置

高级版本会自动创建配置文件 `./config/s3-to-nfs.conf`：

```bash
# 查看配置
./s3-to-nfs-advanced.sh config

# 编辑配置
./s3-to-nfs-advanced.sh config edit
```

配置文件示例：
```bash
# S3 存储配置
S3_ENDPOINT="127.0.0.1:9000"
S3_BUCKET="xsky-data"
S3_ACCESS_KEY="minioadmin"
S3_SECRET_KEY="minioadmin123"
USE_HTTPS="false"

# 过滤选项
INCLUDE_PATTERN="*.pdf,*.docx,*.xlsx"  # 只同步这些类型
EXCLUDE_PATTERN="*.tmp,*.log"          # 排除这些类型
MAX_FILE_SIZE="100M"                   # 最大文件大小
MIN_FILE_SIZE="1K"                     # 最小文件大小

# 高级选项
SYNC_DELETE_DST="false"                # 是否删除目标多余文件
SYNC_CHECK_NEW="true"                  # 验证新文件完整性
```

## 实际使用案例

### 案例 1：定期备份重要文档

```bash
# 1. 配置只同步文档文件
echo 'INCLUDE_PATTERN="*.pdf,*.docx,*.xlsx,*.pptx"' >> ./config/s3-to-nfs.conf

# 2. 预览要同步的文件
./s3-to-nfs-advanced.sh dry-run

# 3. 执行同步
./s3-to-nfs-advanced.sh sync

# 4. 设置定时任务（每小时同步一次）
echo "0 * * * * /path/to/s3-to-nfs-advanced.sh incremental" | crontab -
```

### 案例 2：实时同步小文件

```bash
# 1. 配置排除大文件
echo 'MAX_FILE_SIZE="10M"' >> ./config/s3-to-nfs.conf
echo 'EXCLUDE_PATTERN="*.dmg,*.iso,*.zip"' >> ./config/s3-to-nfs.conf

# 2. 启动持续同步（每30秒检查一次）
./s3-to-nfs-advanced.sh continuous
```

### 案例 3：一次性迁移数据

```bash
# 1. 使用简单版本进行完整同步
./s3-to-nfs-direct.sh setup

# 2. 验证同步结果
./s3-to-nfs-direct.sh stats

# 3. 挂载 NFS 共享验证
sudo mkdir -p /mnt/s3-backup
sudo mount -t nfs -o ro,noresvport localhost:/Users/$(whoami)/nfs-s3-direct /mnt/s3-backup
ls -la /mnt/s3-backup/
```

## 监控和维护

### 查看同步状态

```bash
# 查看统计信息
./s3-to-nfs-direct.sh stats

# 监控同步过程（60秒）
./s3-to-nfs-advanced.sh monitor 60

# 验证同步结果
./s3-to-nfs-advanced.sh verify
```

### 查看日志

```bash
# 查看最新日志
tail -f ./logs/s3-to-nfs-direct-$(date +%Y%m%d).log

# 查看高级版本日志
tail -f ./logs/s3-to-nfs-advanced-$(date +%Y%m%d).log
```

### NFS 客户端挂载

```bash
# 创建挂载点
sudo mkdir -p /mnt/s3-data

# 挂载 NFS 共享（只读）
sudo mount -t nfs -o ro,noresvport localhost:/Users/$(whoami)/nfs-s3-direct /mnt/s3-data

# 查看挂载的数据
ls -la /mnt/s3-data/

# 卸载
sudo umount /mnt/s3-data
```

## 性能优化

### 1. 调整同步线程数

```bash
# 在配置文件中设置
SYNC_THREADS="20"  # 增加到20个线程
```

### 2. 使用增量同步

```bash
# 首次完整同步后，使用增量同步
./s3-to-nfs-advanced.sh incremental
```

### 3. 过滤不需要的文件

```bash
# 排除临时文件和日志
EXCLUDE_PATTERN="*.tmp,*.log,*.cache,*~"
```

## 故障排除

### 常见问题

1. **权限错误**
   ```bash
   # 检查 NFS 导出目录权限
   ls -la ~/nfs-s3-direct/
   
   # 重新配置 NFS 导出
   ./s3-to-nfs-direct.sh nfs-setup
   ```

2. **S3 连接失败**
   ```bash
   # 检查 S3 配置
   curl -I http://127.0.0.1:9000/minio/health/live
   
   # 验证访问密钥
   ./s3-to-nfs-advanced.sh config
   ```

3. **同步速度慢**
   ```bash
   # 增加线程数
   SYNC_THREADS="20"
   
   # 使用增量同步
   ./s3-to-nfs-advanced.sh incremental
   ```

### 日志分析

```bash
# 查看错误日志
grep -i error ./logs/s3-to-nfs-*.log

# 查看同步统计
grep -i "Found:" ./logs/s3-to-nfs-*.log | tail -5
```

## 最佳实践

1. **首次使用建议**：
   - 先使用 `dry-run` 预览要同步的文件
   - 使用 `setup` 命令进行完整配置
   - 验证 NFS 挂载是否正常工作

2. **生产环境建议**：
   - 使用高级版本的配置文件管理
   - 设置合适的过滤规则
   - 使用增量同步减少网络传输
   - 定期检查日志文件

3. **性能优化建议**：
   - 根据网络带宽调整线程数
   - 使用文件大小限制避免同步超大文件
   - 在网络空闲时间进行大量数据同步

## 总结

通过这两个脚本，你可以轻松实现：

- ✅ **直接同步**：S3 → NFS，无需中间步骤
- ✅ **灵活配置**：支持各种过滤和同步选项
- ✅ **实时监控**：完整的日志和统计信息
- ✅ **高性能**：多线程并发同步
- ✅ **易于使用**：简单的命令行界面

现在你已经有了一个完整的 S3 到 NFS 的同步解决方案！