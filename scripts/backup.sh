#!/bin/bash

# Daily Log System - Backup Script
# Backs up PostgreSQL database and uploads to specified location

set -e

# Configuration
BACKUP_DIR="/opt/daily-log-system/backups"
DB_NAME="daily_log"
DB_USER="dailylog"
RETENTION_DAYS=30
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/daily_log_${DATE}.sql"
COMPRESSED_FILE="${BACKUP_FILE}.gz"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

echo "=== Daily Log Backup Started at $(date) ==="

# Dump database
echo "Creating database backup..."
PGPASSWORD="dailylog123" pg_dump -U "${DB_USER}" -h localhost "${DB_NAME}" > "${BACKUP_FILE}"

if [ $? -eq 0 ]; then
    echo "✓ Database backup created: ${BACKUP_FILE}"
else
    echo "✗ Database backup failed!"
    exit 1
fi

# Compress backup
echo "Compressing backup..."
gzip "${BACKUP_FILE}"

if [ $? -eq 0 ]; then
    echo "✓ Backup compressed: ${COMPRESSED_FILE}"
    FINAL_SIZE=$(du -h "${COMPRESSED_FILE}" | cut -f1)
    echo "  Size: ${FINAL_SIZE}"
else
    echo "✗ Compression failed!"
    exit 1
fi

# Remove old backups
echo "Cleaning old backups (older than ${RETENTION_DAYS} days)..."
find "${BACKUP_DIR}" -name "daily_log_*.sql.gz" -type f -mtime +${RETENTION_DAYS} -delete
REMAINING=$(find "${BACKUP_DIR}" -name "daily_log_*.sql.gz" -type f | wc -l)
echo "✓ Old backups removed. ${REMAINING} backups remaining."

# Optional: Upload to remote location (uncomment and configure as needed)
# echo "Uploading to remote storage..."
# scp "${COMPRESSED_FILE}" user@remote-server:/path/to/backups/
# or
# aws s3 cp "${COMPRESSED_FILE}" s3://your-bucket/backups/

# Backup verification
echo "Verifying backup integrity..."
gunzip -t "${COMPRESSED_FILE}"

if [ $? -eq 0 ]; then
    echo "✓ Backup integrity verified"
else
    echo "✗ Backup verification failed!"
    exit 1
fi

echo "=== Backup Completed Successfully at $(date) ==="
echo ""
echo "Summary:"
echo "  Backup file: ${COMPRESSED_FILE}"
echo "  File size: ${FINAL_SIZE}"
echo "  Total backups: ${REMAINING}"
echo ""

exit 0