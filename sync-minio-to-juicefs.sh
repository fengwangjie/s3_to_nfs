#!/bin/bash

# MinIO 到 JuiceFS 同步脚本
# 使用 JuiceFS sync 命令将 MinIO 中的文件同步到 JuiceFS 挂载点

set -e

# 配置参数
MINIO_ENDPOINT="127.0.0.1:9000"
MINIO_BUCKET="xsky-data"
MINIO_ACCESS_KEY="minioadmin"
MINIO_SECRET_KEY="minioadmin123"
JUICEFS_MOUNT_POINT="/Users/fengwangjie/nfs-exports/xsky-data"
SYNC_INTERVAL=30  # 同步间隔（秒）

# 日志文件
LOG_FILE="./logs/sync-$(date +%Y%m%d).log"

# 创建日志目录
mkdir -p logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查 JuiceFS 挂载点是否存在
check_mount_point() {
    if [ ! -d "$JUICEFS_MOUNT_POINT" ]; then
        log "错误: JuiceFS 挂载点 $JUICEFS_MOUNT_POINT 不存在"
        exit 1
    fi
    
    # 检查是否已挂载
    if ! mountpoint -q "$JUICEFS_MOUNT_POINT" 2>/dev/null; then
        log "警告: $JUICEFS_MOUNT_POINT 可能未正确挂载"
    fi
}

# 执行同步
sync_files() {
    log "开始同步 MinIO 到 JuiceFS..."
    
    # 使用 JuiceFS sync 命令
    if juicefs sync \
        --no-https \
        "s3://$MINIO_ACCESS_KEY:$MINIO_SECRET_KEY@$MINIO_ENDPOINT/$MINIO_BUCKET/" \
        "$JUICEFS_MOUNT_POINT/" \
        --verbose 2>&1 | tee -a "$LOG_FILE"; then
        log "同步完成"
    else
        log "同步失败，退出码: $?"
    fi
}

# 主函数
main() {
    log "启动 MinIO 到 JuiceFS 同步服务"
    
    check_mount_point
    
    if [ "$1" = "--once" ]; then
        # 执行一次同步
        sync_files
    else
        # 持续同步模式
        log "进入持续同步模式，间隔: ${SYNC_INTERVAL}秒"
        while true; do
            sync_files
            log "等待 ${SYNC_INTERVAL} 秒后进行下次同步..."
            sleep "$SYNC_INTERVAL"
        done
    fi
}

# 信号处理
trap 'log "收到退出信号，停止同步服务"; exit 0' SIGINT SIGTERM

# 运行主函数
main "$@"