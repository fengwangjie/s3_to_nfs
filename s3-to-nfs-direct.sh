#!/bin/bash

# 直接使用 JuiceFS Sync 将 S3 文件同步到 NFS 的脚本
# 跳过中间的 JuiceFS 挂载步骤，直接同步到 NFS 导出目录

set -e

# 配置参数
MINIO_ENDPOINT="127.0.0.1:9000"
MINIO_BUCKET="xsky-data"
MINIO_ACCESS_KEY="minioadmin"
MINIO_SECRET_KEY="minioadmin123"
NFS_EXPORT_DIR="$HOME/nfs-s3-direct"
SYNC_INTERVAL=30  # 同步间隔（秒）

# 日志文件
LOG_FILE="./logs/s3-to-nfs-direct-$(date +%Y%m%d).log"

# 创建日志目录
mkdir -p logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查依赖
check_dependencies() {
    log "检查依赖..."
    
    if ! command -v juicefs &> /dev/null; then
        log "❌ JuiceFS 未安装"
        return 1
    fi
    
    if ! command -v showmount &> /dev/null; then
        log "❌ NFS 工具未安装"
        return 1
    fi
    
    log "✅ 依赖检查通过"
    return 0
}

# 创建 NFS 导出目录
setup_nfs_export_dir() {
    log "设置 NFS 导出目录: $NFS_EXPORT_DIR"
    
    # 创建目录
    mkdir -p "$NFS_EXPORT_DIR"
    chmod 755 "$NFS_EXPORT_DIR"
    
    log "✅ NFS 导出目录创建完成"
}

# 直接同步 S3 到 NFS 目录
sync_s3_to_nfs() {
    log "开始直接同步 S3 到 NFS 目录..."
    
    # 使用 JuiceFS sync 直接同步
    if juicefs sync \
        --no-https \
        --verbose \
        "s3://$MINIO_ACCESS_KEY:$MINIO_SECRET_KEY@$MINIO_ENDPOINT/$MINIO_BUCKET/" \
        "$NFS_EXPORT_DIR/" 2>&1 | tee -a "$LOG_FILE"; then
        
        log "✅ S3 到 NFS 同步完成"
        
        # 显示同步结果
        log "NFS 导出目录内容:"
        ls -la "$NFS_EXPORT_DIR" | head -10 | tee -a "$LOG_FILE"
        
        return 0
    else
        log "❌ S3 到 NFS 同步失败"
        return 1
    fi
}

# 配置 NFS 导出
configure_nfs_export() {
    log "配置 NFS 导出..."
    
    # 配置 exports 文件
    echo "$NFS_EXPORT_DIR -ro -mapall=nobody localhost" | sudo tee /etc/exports
    
    # 重启 NFS 服务
    sudo nfsd restart
    
    # 等待服务启动
    sleep 3
    
    # 检查导出状态
    if showmount -e localhost 2>/dev/null | grep -q "$NFS_EXPORT_DIR"; then
        log "✅ NFS 导出配置成功"
        showmount -e localhost | tee -a "$LOG_FILE"
        return 0
    else
        log "❌ NFS 导出配置失败"
        sudo log show --predicate 'process == "nfsd"' --last 2m | tail -5 | tee -a "$LOG_FILE"
        return 1
    fi
}

# 测试 NFS 挂载
test_nfs_mount() {
    local test_mount_point="/tmp/test-s3-nfs-direct"
    
    log "测试 NFS 挂载..."
    
    # 创建测试挂载点
    mkdir -p "$test_mount_point"
    
    # 尝试挂载
    if sudo mount -t nfs -o ro,noresvport localhost:"$NFS_EXPORT_DIR" "$test_mount_point"; then
        log "✅ NFS 挂载成功"
        
        log "挂载点内容:"
        ls -la "$test_mount_point" | head -10 | tee -a "$LOG_FILE"
        
        # 测试文件访问
        if find "$test_mount_point" -name "*.txt" -o -name "*.pdf" -o -name "*.xlsx" | head -1 | read first_file; then
            log "✅ 可以访问文件: $(basename "$first_file")"
            log "文件大小: $(ls -lh "$first_file" | awk '{print $5}')"
        fi
        
        # 卸载测试挂载点
        sudo umount "$test_mount_point"
        rmdir "$test_mount_point"
        
        log "✅ NFS 测试完成"
        log "可以使用以下命令挂载 S3 数据:"
        log "sudo mount -t nfs -o ro,noresvport localhost:$NFS_EXPORT_DIR /your/mount/point"
        
        return 0
    else
        log "❌ NFS 挂载失败"
        rmdir "$test_mount_point" 2>/dev/null || true
        return 1
    fi
}

# 持续同步模式
continuous_sync() {
    log "启动持续同步模式，间隔: ${SYNC_INTERVAL}秒"
    
    while true; do
        sync_s3_to_nfs
        log "等待 ${SYNC_INTERVAL} 秒后进行下次同步..."
        sleep "$SYNC_INTERVAL"
    done
}

# 增量同步（只同步新文件和修改的文件）
incremental_sync() {
    log "执行增量同步..."
    
    # 使用 --update 参数只同步新文件和修改的文件
    if juicefs sync \
        --no-https \
        --update \
        --verbose \
        "s3://$MINIO_ACCESS_KEY:$MINIO_SECRET_KEY@$MINIO_ENDPOINT/$MINIO_BUCKET/" \
        "$NFS_EXPORT_DIR/" 2>&1 | tee -a "$LOG_FILE"; then
        
        log "✅ 增量同步完成"
        return 0
    else
        log "❌ 增量同步失败"
        return 1
    fi
}

# 显示同步统计
show_sync_stats() {
    log "同步统计信息:"
    
    if [ -d "$NFS_EXPORT_DIR" ]; then
        local file_count=$(find "$NFS_EXPORT_DIR" -type f | wc -l)
        local dir_count=$(find "$NFS_EXPORT_DIR" -type d | wc -l)
        local total_size=$(du -sh "$NFS_EXPORT_DIR" 2>/dev/null | cut -f1)
        
        log "文件数量: $file_count"
        log "目录数量: $dir_count"
        log "总大小: $total_size"
        
        log "最近修改的文件:"
        find "$NFS_EXPORT_DIR" -type f -exec ls -lt {} + 2>/dev/null | head -5 | tee -a "$LOG_FILE"
    else
        log "NFS 导出目录不存在"
    fi
}

# 清理函数
cleanup() {
    log "清理资源..."
    
    # 停止 NFS 导出
    sudo nfsd disable 2>/dev/null || true
    sudo rm -f /etc/exports 2>/dev/null || true
    
    log "清理完成"
}

# 主函数
main() {
    case "${1:-setup}" in
        "setup")
            log "开始设置 S3 到 NFS 直接同步..."
            
            check_dependencies || exit 1
            setup_nfs_export_dir
            sync_s3_to_nfs || exit 1
            configure_nfs_export || exit 1
            test_nfs_mount || exit 1
            show_sync_stats
            
            log "🎉 S3 到 NFS 直接同步设置完成！"
            ;;
        "sync")
            log "执行一次性同步..."
            check_dependencies || exit 1
            setup_nfs_export_dir
            sync_s3_to_nfs || exit 1
            show_sync_stats
            ;;
        "incremental")
            log "执行增量同步..."
            check_dependencies || exit 1
            incremental_sync || exit 1
            show_sync_stats
            ;;
        "continuous")
            log "启动持续同步..."
            check_dependencies || exit 1
            setup_nfs_export_dir
            continuous_sync
            ;;
        "test")
            log "测试 NFS 挂载..."
            test_nfs_mount
            ;;
        "stats")
            show_sync_stats
            ;;
        "cleanup")
            cleanup
            ;;
        *)
            echo "用法: $0 [setup|sync|incremental|continuous|test|stats|cleanup]"
            echo ""
            echo "命令说明:"
            echo "  setup       - 完整设置（同步 + 配置NFS + 测试）"
            echo "  sync        - 执行一次性完整同步"
            echo "  incremental - 执行增量同步（只同步新文件和修改的文件）"
            echo "  continuous  - 启动持续同步模式"
            echo "  test        - 测试 NFS 挂载"
            echo "  stats       - 显示同步统计信息"
            echo "  cleanup     - 清理 NFS 配置"
            echo ""
            echo "示例:"
            echo "  $0 setup      # 首次设置"
            echo "  $0 sync       # 手动同步一次"
            echo "  $0 continuous # 持续监控同步"
            exit 1
            ;;
    esac
}

# 信号处理
trap 'log "收到中断信号，停止同步"; cleanup; exit 0' SIGINT SIGTERM

# 运行主函数
main "$@"