#!/bin/bash

# 高级 S3 到 NFS 同步脚本
# 支持多种 S3 兼容存储（MinIO、AWS S3、阿里云 OSS 等）

set -e

# 默认配置文件
CONFIG_FILE="./config/s3-to-nfs.conf"

# 默认配置
DEFAULT_S3_ENDPOINT="127.0.0.1:9000"
DEFAULT_S3_BUCKET="xsky-data"
DEFAULT_S3_ACCESS_KEY="minioadmin"
DEFAULT_S3_SECRET_KEY="minioadmin123"
DEFAULT_S3_REGION="us-east-1"
DEFAULT_USE_HTTPS="false"
DEFAULT_NFS_EXPORT_DIR="$HOME/nfs-s3-sync"
DEFAULT_SYNC_INTERVAL="30"
DEFAULT_SYNC_THREADS="10"

# 日志配置
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/s3-to-nfs-advanced-$(date +%Y%m%d).log"

# 创建必要目录
mkdir -p logs config

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 加载配置文件
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "加载配置文件: $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log "配置文件不存在，使用默认配置"
        create_default_config
    fi
    
    # 设置变量（优先使用配置文件，其次使用环境变量，最后使用默认值）
    S3_ENDPOINT="${S3_ENDPOINT:-$DEFAULT_S3_ENDPOINT}"
    S3_BUCKET="${S3_BUCKET:-$DEFAULT_S3_BUCKET}"
    S3_ACCESS_KEY="${S3_ACCESS_KEY:-$DEFAULT_S3_ACCESS_KEY}"
    S3_SECRET_KEY="${S3_SECRET_KEY:-$DEFAULT_S3_SECRET_KEY}"
    S3_REGION="${S3_REGION:-$DEFAULT_S3_REGION}"
    USE_HTTPS="${USE_HTTPS:-$DEFAULT_USE_HTTPS}"
    NFS_EXPORT_DIR="${NFS_EXPORT_DIR:-$DEFAULT_NFS_EXPORT_DIR}"
    SYNC_INTERVAL="${SYNC_INTERVAL:-$DEFAULT_SYNC_INTERVAL}"
    SYNC_THREADS="${SYNC_THREADS:-$DEFAULT_SYNC_THREADS}"
    
    log "配置加载完成:"
    log "  S3 端点: $S3_ENDPOINT"
    log "  S3 存储桶: $S3_BUCKET"
    log "  使用 HTTPS: $USE_HTTPS"
    log "  NFS 导出目录: $NFS_EXPORT_DIR"
    log "  同步间隔: ${SYNC_INTERVAL}秒"
    log "  同步线程数: $SYNC_THREADS"
}

# 创建默认配置文件
create_default_config() {
    log "创建默认配置文件: $CONFIG_FILE"
    
    cat > "$CONFIG_FILE" << EOF
# S3 到 NFS 同步配置文件

# S3 存储配置
S3_ENDPOINT="$DEFAULT_S3_ENDPOINT"
S3_BUCKET="$DEFAULT_S3_BUCKET"
S3_ACCESS_KEY="$DEFAULT_S3_ACCESS_KEY"
S3_SECRET_KEY="$DEFAULT_S3_SECRET_KEY"
S3_REGION="$DEFAULT_S3_REGION"
USE_HTTPS="$DEFAULT_USE_HTTPS"

# NFS 配置
NFS_EXPORT_DIR="$DEFAULT_NFS_EXPORT_DIR"

# 同步配置
SYNC_INTERVAL="$DEFAULT_SYNC_INTERVAL"
SYNC_THREADS="$DEFAULT_SYNC_THREADS"

# 高级选项
SYNC_DELETE_DST="false"  # 是否删除目标中多余的文件
SYNC_CHECK_NEW="false"   # 是否验证新复制文件的完整性
SYNC_DRY_RUN="false"     # 是否只是预览而不实际复制

# 过滤选项
INCLUDE_PATTERN=""       # 包含文件模式（如 "*.pdf,*.txt"）
EXCLUDE_PATTERN=""       # 排除文件模式（如 "*.tmp,*.log"）
MAX_FILE_SIZE=""         # 最大文件大小（如 "100M"）
MIN_FILE_SIZE=""         # 最小文件大小（如 "1K"）

# 日志配置
LOG_LEVEL="INFO"         # 日志级别: DEBUG, INFO, WARN, ERROR
EOF

    log "✅ 默认配置文件已创建"
}

# 构建 JuiceFS sync 命令
build_sync_command() {
    local sync_mode="$1"  # full, incremental, dry-run
    
    # 基础命令
    local cmd="juicefs sync"
    
    # HTTPS 设置
    if [ "$USE_HTTPS" != "true" ]; then
        cmd="$cmd --no-https"
    fi
    
    # 线程数
    cmd="$cmd --threads $SYNC_THREADS"
    
    # 同步模式选项
    case "$sync_mode" in
        "incremental")
            cmd="$cmd --update"
            ;;
        "dry-run")
            cmd="$cmd --dry"
            ;;
    esac
    
    # 高级选项
    if [ "$SYNC_DELETE_DST" = "true" ]; then
        cmd="$cmd --delete-dst"
    fi
    
    if [ "$SYNC_CHECK_NEW" = "true" ]; then
        cmd="$cmd --check-new"
    fi
    
    # 过滤选项
    if [ -n "$INCLUDE_PATTERN" ]; then
        IFS=',' read -ra PATTERNS <<< "$INCLUDE_PATTERN"
        for pattern in "${PATTERNS[@]}"; do
            cmd="$cmd --include '$pattern'"
        done
    fi
    
    if [ -n "$EXCLUDE_PATTERN" ]; then
        IFS=',' read -ra PATTERNS <<< "$EXCLUDE_PATTERN"
        for pattern in "${PATTERNS[@]}"; do
            cmd="$cmd --exclude '$pattern'"
        done
    fi
    
    if [ -n "$MAX_FILE_SIZE" ]; then
        cmd="$cmd --max-size $MAX_FILE_SIZE"
    fi
    
    if [ -n "$MIN_FILE_SIZE" ]; then
        cmd="$cmd --min-size $MIN_FILE_SIZE"
    fi
    
    # 详细输出
    cmd="$cmd --verbose"
    
    # 源和目标
    cmd="$cmd \"s3://$S3_ACCESS_KEY:$S3_SECRET_KEY@$S3_ENDPOINT/$S3_BUCKET/\" \"$NFS_EXPORT_DIR/\""
    
    echo "$cmd"
}

# 执行同步
execute_sync() {
    local sync_mode="$1"
    local description="$2"
    
    log "开始$description..."
    
    # 确保目标目录存在
    mkdir -p "$NFS_EXPORT_DIR"
    
    # 构建并执行命令
    local sync_cmd=$(build_sync_command "$sync_mode")
    log "执行命令: $sync_cmd"
    
    if eval "$sync_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log "✅ $description完成"
        return 0
    else
        log "❌ $description失败"
        return 1
    fi
}

# 配置 NFS 导出
configure_nfs_export() {
    log "配置 NFS 导出..."
    
    # 检查目录是否存在且有内容
    if [ ! -d "$NFS_EXPORT_DIR" ] || [ -z "$(ls -A "$NFS_EXPORT_DIR" 2>/dev/null)" ]; then
        log "❌ NFS 导出目录为空或不存在，请先执行同步"
        return 1
    fi
    
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
        return 1
    fi
}

# 监控同步状态
monitor_sync() {
    local duration="${1:-60}"  # 监控时长（秒）
    
    log "开始监控同步状态，持续 ${duration} 秒..."
    
    local start_time=$(date +%s)
    local end_time=$((start_time + duration))
    
    while [ $(date +%s) -lt $end_time ]; do
        if [ -d "$NFS_EXPORT_DIR" ]; then
            local file_count=$(find "$NFS_EXPORT_DIR" -type f | wc -l)
            local total_size=$(du -sh "$NFS_EXPORT_DIR" 2>/dev/null | cut -f1)
            
            log "当前状态: $file_count 个文件, 总大小: $total_size"
        fi
        
        sleep 10
    done
    
    log "监控完成"
}

# 验证同步结果
verify_sync() {
    log "验证同步结果..."
    
    if [ ! -d "$NFS_EXPORT_DIR" ]; then
        log "❌ NFS 导出目录不存在"
        return 1
    fi
    
    local file_count=$(find "$NFS_EXPORT_DIR" -type f | wc -l)
    local dir_count=$(find "$NFS_EXPORT_DIR" -type d | wc -l)
    local total_size=$(du -sh "$NFS_EXPORT_DIR" 2>/dev/null | cut -f1)
    
    log "同步结果统计:"
    log "  文件数量: $file_count"
    log "  目录数量: $dir_count"
    log "  总大小: $total_size"
    
    if [ $file_count -gt 0 ]; then
        log "✅ 同步验证通过"
        
        log "最大的 5 个文件:"
        find "$NFS_EXPORT_DIR" -type f -exec ls -lh {} + 2>/dev/null | sort -k5 -hr | head -5 | tee -a "$LOG_FILE"
        
        return 0
    else
        log "❌ 同步验证失败：没有文件被同步"
        return 1
    fi
}

# 主函数
main() {
    # 加载配置
    load_config
    
    case "${1:-help}" in
        "setup")
            log "开始完整设置..."
            execute_sync "full" "完整同步" || exit 1
            configure_nfs_export || exit 1
            verify_sync || exit 1
            log "🎉 S3 到 NFS 同步设置完成！"
            ;;
        "sync")
            execute_sync "full" "完整同步" || exit 1
            verify_sync
            ;;
        "incremental")
            execute_sync "incremental" "增量同步" || exit 1
            verify_sync
            ;;
        "dry-run")
            execute_sync "dry-run" "预览同步（不实际复制）"
            ;;
        "continuous")
            log "启动持续同步模式..."
            while true; do
                execute_sync "incremental" "增量同步"
                log "等待 ${SYNC_INTERVAL} 秒后进行下次同步..."
                sleep "$SYNC_INTERVAL"
            done
            ;;
        "monitor")
            monitor_sync "${2:-60}"
            ;;
        "verify")
            verify_sync
            ;;
        "nfs-setup")
            configure_nfs_export
            ;;
        "config")
            if [ "$2" = "edit" ]; then
                ${EDITOR:-nano} "$CONFIG_FILE"
            else
                log "当前配置:"
                cat "$CONFIG_FILE"
            fi
            ;;
        "help"|*)
            echo "高级 S3 到 NFS 同步工具"
            echo ""
            echo "用法: $0 <命令> [参数]"
            echo ""
            echo "命令:"
            echo "  setup       - 完整设置（同步 + 配置NFS + 验证）"
            echo "  sync        - 执行完整同步"
            echo "  incremental - 执行增量同步"
            echo "  dry-run     - 预览同步（不实际复制文件）"
            echo "  continuous  - 持续同步模式"
            echo "  monitor [秒] - 监控同步状态"
            echo "  verify      - 验证同步结果"
            echo "  nfs-setup   - 仅配置 NFS 导出"
            echo "  config      - 显示当前配置"
            echo "  config edit - 编辑配置文件"
            echo ""
            echo "配置文件: $CONFIG_FILE"
            echo "日志文件: $LOG_FILE"
            echo ""
            echo "示例:"
            echo "  $0 setup           # 首次完整设置"
            echo "  $0 dry-run         # 预览要同步的文件"
            echo "  $0 incremental     # 增量同步"
            echo "  $0 continuous      # 持续监控同步"
            echo "  $0 monitor 120     # 监控 2 分钟"
            ;;
    esac
}

# 信号处理
trap 'log "收到中断信号，停止同步"; exit 0' SIGINT SIGTERM

# 运行主函数
main "$@"