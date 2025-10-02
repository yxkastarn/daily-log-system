#!/bin/bash
set -e

GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"

echo "Waiting for Grafana..."
until curl -s "${GRAFANA_URL}/api/health" > /dev/null; do
    sleep 2
done

echo "Adding PostgreSQL datasource..."
curl -X POST "${GRAFANA_URL}/api/datasources" \
  -H "Content-Type: application/json" \
  -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
  -d '{
    "name": "Daily Log PostgreSQL",
    "type": "postgres",
    "url": "localhost:5432",
    "database": "daily_log",
    "user": "dailylog",
    "secureJsonData": {"password": "dailylog123"},
    "isDefault": true
  }' || echo "Datasource may already exist"

echo "✓ Grafana setup complete!"
