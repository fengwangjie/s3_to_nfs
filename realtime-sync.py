#!/usr/bin/env python3
"""
实时监控 MinIO 并同步到 JuiceFS 的 Python 脚本
使用 MinIO Python SDK 监控对象变化
"""

import os
import time
import logging
import subprocess
from datetime import datetime, timezone
from minio import Minio
from minio.error import S3Error

# 配置
MINIO_ENDPOINT = "127.0.0.1:9000"
MINIO_ACCESS_KEY = "minioadmin"
MINIO_SECRET_KEY = "minioadmin123"
MINIO_BUCKET = "xsky-data"
JUICEFS_MOUNT_POINT = "/tmp/s3_xsky_mount"
CHECK_INTERVAL = 10  # 检查间隔（秒）

# 设置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'./logs/realtime-sync-{datetime.now().strftime("%Y%m%d")}.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class MinIOJuiceFSSync:
    def __init__(self):
        self.client = Minio(
            MINIO_ENDPOINT,
            access_key=MINIO_ACCESS_KEY,
            secret_key=MINIO_SECRET_KEY,
            secure=False
        )
        self.last_sync_time = datetime.now(timezone.utc)
        
    def check_bucket_exists(self):
        """检查 bucket 是否存在"""
        try:
            return self.client.bucket_exists(MINIO_BUCKET)
        except S3Error as e:
            logger.error(f"检查 bucket 失败: {e}")
            return False
    
    def get_objects_modified_since(self, since_time):
        """获取指定时间后修改的对象"""
        try:
            objects = self.client.list_objects(MINIO_BUCKET, recursive=True)
            modified_objects = []
            
            for obj in objects:
                if obj.last_modified > since_time:
                    modified_objects.append(obj)
                    
            return modified_objects
        except S3Error as e:
            logger.error(f"获取对象列表失败: {e}")
            return []
    
    def sync_to_juicefs(self):
        """执行同步到 JuiceFS"""
        try:
            cmd = [
                "juicefs", "sync",
                "--no-https",
                f"s3://{MINIO_ACCESS_KEY}:{MINIO_SECRET_KEY}@{MINIO_ENDPOINT}/{MINIO_BUCKET}/",
                f"{JUICEFS_MOUNT_POINT}/",
                "--verbose"
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info("同步成功完成")
                return True
            else:
                logger.error(f"同步失败: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"执行同步命令失败: {e}")
            return False
    
    def run_monitoring(self):
        """运行监控循环"""
        logger.info("启动 MinIO 到 JuiceFS 实时同步监控")
        
        if not self.check_bucket_exists():
            logger.error(f"Bucket '{MINIO_BUCKET}' 不存在")
            return
        
        logger.info(f"开始监控 bucket: {MINIO_BUCKET}")
        
        while True:
            try:
                # 检查是否有新的或修改的对象
                modified_objects = self.get_objects_modified_since(self.last_sync_time)
                
                if modified_objects:
                    logger.info(f"发现 {len(modified_objects)} 个修改的对象:")
                    for obj in modified_objects:
                        logger.info(f"  - {obj.object_name} (修改时间: {obj.last_modified})")
                    
                    # 执行同步
                    if self.sync_to_juicefs():
                        self.last_sync_time = datetime.now(timezone.utc)
                        logger.info("同步完成，更新最后同步时间")
                else:
                    logger.debug("没有发现新的修改")
                
                time.sleep(CHECK_INTERVAL)
                
            except KeyboardInterrupt:
                logger.info("收到中断信号，停止监控")
                break
            except Exception as e:
                logger.error(f"监控过程中发生错误: {e}")
                time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    # 创建日志目录
    os.makedirs("logs", exist_ok=True)
    
    sync_monitor = MinIOJuiceFSSync()
    sync_monitor.run_monitoring()