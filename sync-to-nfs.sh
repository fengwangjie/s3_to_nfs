#!/bin/bash

# 将 JuiceFS 内容同步到 NFS 导出目录的脚本

set -e

# 配置参数
JUICEFS_MOUNT_POINT="$HOME/nfs-exports/xsky-data"
NFS_EXPORT_DIR="$HOME/nfs-test-export"
SYNC_INTERVAL=30  # 同步间隔（秒）

# 日志文件
LOG_FILE="./logs/nfs-sync-$(date +%Y%m%d).log"

# 创建日志目录
mkdir -p logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查 JuiceFS 挂载点
check_juicefs_mount() {
    if [ ! -d "$JUICEFS_MOUNT_POINT" ]; then
        log "错误: JuiceFS 挂载点 $JUICEFS_MOUNT_POINT 不存在"
        return 1
    fi
    
    # 检查是否有内容（排除隐藏文件）
    if [ -z "$(ls -A "$JUICEFS_MOUNT_POINT" 2>/dev/null | grep -v '^\.')" ]; then
        log "警告: JuiceFS 挂载点 $JUICEFS_MOUNT_POINT 为空或未正确挂载"
        return 1
    fi
    
    return 0
}

# 同步数据到 NFS 导出目录
sync_to_nfs() {
    log "开始同步 JuiceFS 数据到 NFS 导出目录..."
    
    # 创建 NFS 导出目录
    mkdir -p "$NFS_EXPORT_DIR"
    
    # 使用 rsync 同步数据（排除隐藏文件）
    if rsync -av --delete \
        --exclude='.*' \
        "$JUICEFS_MOUNT_POINT/" \
        "$NFS_EXPORT_DIR/" 2>&1 | tee -a "$LOG_FILE"; then
        
        log "同步完成"
        
        # 显示同步后的内容
        log "NFS 导出目录内容:"
        ls -la "$NFS_EXPORT_DIR" | head -10 | tee -a "$LOG_FILE"
        
        return 0
    else
        log "同步失败"
        return 1
    fi
}

# 配置 NFS 导出
setup_nfs_export() {
    log "配置 NFS 导出: $NFS_EXPORT_DIR"
    
    # 配置 exports 文件
    echo "$NFS_EXPORT_DIR -ro -mapall=nobody localhost" | sudo tee /etc/exports
    
    # 重启 NFS 服务
    sudo nfsd restart
    
    # 等待服务启动
    sleep 2
    
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

# 测试 NFS 挂载
test_nfs_mount() {
    local test_mount_point="/tmp/test-xsky-nfs"
    
    log "测试 NFS 挂载..."
    
    # 创建测试挂载点
    mkdir -p "$test_mount_point"
    
    # 尝试挂载
    if sudo mount -t nfs -o ro,noresvport localhost:"$NFS_EXPORT_DIR" "$test_mount_point"; then
        log "✅ NFS 挂载成功"
        
        log "挂载点内容:"
        ls -la "$test_mount_point" | head -10 | tee -a "$LOG_FILE"
        
        # 测试读取文件
        if [ -f "$test_mount_point/config/users.conf" ]; then
            log "测试文件内容:"
            cat "$test_mount_point/config/users.conf" | tee -a "$LOG_FILE"
        fi
        
        # 卸载测试挂载点
        sudo umount "$test_mount_point"
        rmdir "$test_mount_point"
        
        log "✅ NFS 测试完成"
        log "可以使用以下命令挂载 XSky 数据:"
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
        if check_juicefs_mount; then
            sync_to_nfs
        else
            log "JuiceFS 挂载点检查失败，跳过本次同步"
        fi
        
        log "等待 ${SYNC_INTERVAL} 秒后进行下次同步..."
        sleep "$SYNC_INTERVAL"
    done
}

# 主函数
main() {
    case "${1:-setup}" in
        "setup")
            log "开始设置 JuiceFS 到 NFS 同步..."
            
            if check_juicefs_mount; then
                sync_to_nfs
                setup_nfs_export
                test_nfs_mount
            else
                log "❌ JuiceFS 挂载点检查失败"
                exit 1
            fi
            ;;
        "sync")
            if check_juicefs_mount; then
                sync_to_nfs
            else
                log "❌ JuiceFS 挂载点检查失败"
                exit 1
            fi
            ;;
        "continuous")
            continuous_sync
            ;;
        "test")
            test_nfs_mount
            ;;
        *)
            echo "用法: $0 [setup|sync|continuous|test]"
            echo "  setup      - 完整设置（同步数据 + 配置NFS + 测试）"
            echo "  sync       - 仅同步数据到 NFS 导出目录"
            echo "  continuous - 持续同步模式"
            echo "  test       - 测试 NFS 挂载"
            exit 1
            ;;
    esac
}

# 信号处理
trap 'log "收到中断信号，停止同步"; exit 0' SIGINT SIGTERM

# 运行主函数
main "$@"