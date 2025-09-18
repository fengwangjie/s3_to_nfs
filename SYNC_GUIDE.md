# MinIO 到 JuiceFS 同步指南

## 概述

本指南提供了多种方法将 MinIO 上传的文件同步到 JuiceFS 挂载点。

## 前提条件

1. 确保 Docker 服务正在运行
2. 启动 MinIO 和 Redis 服务：

   ```bash
   docker-compose up -d
   ```

3. 确保 JuiceFS 已正确挂载（注意权限设置）：

   ```bash
   # 如果已挂载但权限不对，先卸载
   sudo juicefs umount /tmp/s3_xsky_mount

   # 重新挂载，设置正确的用户权限
   juicefs mount redis://127.0.0.1:6379/1 /tmp/s3_xsky_mount \
       --cache-dir ./data/s3-cache \
       --cache-size 1024 \
       --background \
       --log ./logs/existing-s3-juicefs.log \
       --all-squash $(id -u):$(id -g)
   ```

## 同步方法

### 方法一：手动同步（一次性）

```bash
juicefs sync \
    --no-https \
    s3://minioadmin:minioadmin123@127.0.0.1:9000/xsky-data/ \
    /tmp/s3_xsky_mount \
    --verbose
```

**注意**：确保 MinIO 服务正在运行且 JuiceFS 挂载点权限正确。

### 方法二：使用同步脚本

执行一次同步：

```bash
./sync-minio-to-juicefs.sh --once
```

持续同步（每 30 秒检查一次）：

```bash
./sync-minio-to-juicefs.sh
```

### 方法三：Python 实时监控

首先安装依赖：

```bash
pip3 install minio
```

然后运行监控脚本：

````bash
python3 realtime-sync.py
```##

## 测试同步

1. 通过 MinIO Web 控制台上传文件：
   - 访问 http://localhost:9001
   - 用户名：minioadmin
   - 密码：minioadmin123

2. 检查 JuiceFS 挂载点：
   ```bash
   ls -la /tmp/s3_xsky_mount/
````

## 监控和日志

- 同步脚本日志：`./logs/sync-YYYYMMDD.log`
- Python 监控日志：`./logs/realtime-sync-YYYYMMDD.log`
- JuiceFS 日志：`./logs/existing-s3-juicefs.log`

## 故障排除

### 常见问题

1. **JuiceFS 未挂载**

   ```bash
   # 检查挂载状态
   mount | grep juicefs

   # 重新挂载
   juicefs umount /tmp/s3_xsky_mount
   juicefs mount redis://127.0.0.1:6379/1 /tmp/s3_xsky_mount
   ```

2. **MinIO 连接失败**

   ```bash
   # 检查 MinIO 服务状态
   docker-compose ps

   # 重启服务
   docker-compose restart minio
   ```

3. **权限问题**
   ```bash
   # 确保脚本有执行权限
   chmod +x sync-minio-to-juicefs.sh
   ```

## 性能优化建议

1. **调整同步间隔**：根据数据更新频率调整 `SYNC_INTERVAL`
2. **缓存设置**：增加 JuiceFS 缓存大小以提高性能
3. **并发同步**：使用 `--threads` 参数增加同步线程数

```bash
juicefs sync --threads 10 s3://... /tmp/s3_xsky_mount/
```

## 成

功案例

刚才的测试显示同步成功：

- 发现了 16 个对象
- 成功复制了 11 个文件（18.81 MiB）
- 包括 PDF、Excel 等各种格式的文件
- 权限问题已解决

## 下一步

现在你可以：

1. **设置持续同步**：

   ```bash
   ./sync-minio-to-juicefs.sh
   ```

2. **通过 MinIO Web 控制台测试**：

   - 访问 http://localhost:9001
   - 上传新文件到 `xsky-data` bucket
   - 等待同步脚本检测并同步

3. **验证同步结果**：
   ```bash
   ls -la /tmp/s3_xsky_mount/
   ```

同步系统现在已经正常工作了！
