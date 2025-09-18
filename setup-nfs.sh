#!/bin/bash

# macOS NFS 设置脚本
# 用于将 JuiceFS 挂载点通过 NFS 暴露

set -e

# 配置参数
JUICEFS_MOUNT_POINT="$HOME/nfs-exports/xsky-data"
NFS_EXPORT_DIR="$HOME/nfs-test-export"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 清理函数
cleanup() {
    log "清理 NFS 配置..."
    sudo nfsd disable 2>/dev/null || true
    sudo rm -f /etc/exports 2>/dev/null || true
    sudo rm -rf "$NFS_EXPORT_DIR" 2>/dev/null || true
}

# 设置 NFS 导出
setup_nfs() {
    log "设置 NFS 导出目录: $NFS_EXPORT_DIR"
    
    # 创建导出目录
    sudo mkdir -p "$NFS_EXPORT_DIR"
    sudo chmod 755 "$NFS_EXPORT_DIR"
    
    # 创建符号链接到 JuiceFS 挂载点
    if [ -d "$JUICEFS_MOUNT_POINT" ]; then
        sudo ln -sf "$(pwd)/$JUICEFS_MOUNT_POINT"/* "$NFS_EXPORT_DIR/" 2>/dev/null || true
        
        # # 或者使用 rsync 同步（如果符号链接不工作）
        # if [ "$(ls -A $NFS_EXPORT_DIR 2>/dev/null)" = "" ]; then
        #     log "使用 rsync 同步文件..."
        #     sudo rsync -av "$JUICEFS_MOUNT_POINT/" "$NFS_EXPORT_DIR/" 2>/dev/null || true
        # fi
    else
        log "警告: JuiceFS 挂载点 $JUICEFS_MOUNT_POINT 不存在"
    fi
    
    # 配置 NFS 导出
    log "配置 NFS 导出..."
    echo "$NFS_EXPORT_DIR -ro -mapall=nobody localhost" | sudo tee /etc/exports
    
    # 启动 NFS 服务
    log "启动 NFS 服务..."
    sudo nfsd enable
    sudo nfsd restart
    
    # 等待服务启动
    sleep 2
    
    # 检查导出状态
    log "检查 NFS 导出状态..."
    if showmount -e localhost | grep -q "$NFS_EXPORT_DIR"; then
        log "✅ NFS 导出成功配置"
        showmount -e localhost
    else
        log "❌ NFS 导出配置失败"
        log "检查系统日志:"
        sudo log show --predicate 'process == "nfsd"' --last 2m | tail -10
        return 1
    fi
}

# 测试 NFS 挂载
test_nfs_mount() {
    local test_mount_point="/tmp/test-nfs-mount"
    
    log "测试 NFS 挂载..."
    
    # 创建测试挂载点
    mkdir -p "$test_mount_point"
    
    # 尝试挂载
    if sudo mount -t nfs -o ro,noresvport localhost:"$NFS_EXPORT_DIR" "$test_mount_point"; then
        log "✅ NFS 挂载成功"
        log "挂载点内容:"
        ls -la "$test_mount_point" | head -10
        
        # 卸载测试挂载点
        sudo umount "$test_mount_point"
        rmdir "$test_mount_point"
        
        log "✅ NFS 服务配置完成"
        log "可以使用以下命令挂载:"
        log "sudo mount -t nfs -o ro,noresvport localhost:$NFS_EXPORT_DIR /your/mount/point"
        
        return 0
    else
        log "❌ NFS 挂载失败"
        rmdir "$test_mount_point" 2>/dev/null || true
        return 1
    fi
}

# 主函数
main() {
    case "${1:-setup}" in
        "setup")
            log "开始设置 NFS 服务..."
            setup_nfs
            test_nfs_mount
            ;;
        "cleanup")
            cleanup
            log "NFS 配置已清理"
            ;;
        "test")
            test_nfs_mount
            ;;
        *)
            echo "用法: $0 [setup|cleanup|test]"
            echo "  setup   - 设置 NFS 导出（默认）"
            echo "  cleanup - 清理 NFS 配置"
            echo "  test    - 测试 NFS 挂载"
            exit 1
            ;;
    esac
}

# 信号处理
trap 'log "收到中断信号"; exit 1' SIGINT SIGTERM

# 运行主函数
main "$@"