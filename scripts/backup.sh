#!/bin/bash
set -e

BACKUP_DIR="/opt/daily-log-system/backups"
DB_NAME="daily_log"
DB_USER="dailylog"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/daily_log_${DATE}.sql"

mkdir -p "${BACKUP_DIR}"

echo "Creating database backup..."
PGPASSWORD="dailylog123" pg_dump -U "${DB_USER}" -h localhost "${DB_NAME}" > "${BACKUP_FILE}"

echo "Compressing backup..."
gzip "${BACKUP_FILE}"

echo "Cleaning old backups (>30 days)..."
find "${BACKUP_DIR}" -name "daily_log_*.sql.gz" -type f -mtime +30 -delete

echo "✓ Backup completed: ${BACKUP_FILE}.gz"
