#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MEMORY=2048
DISK_SIZE=8
STORAGE="local-lvm"
NETWORK="vmbr0"
CONTAINER_NAME="daily-log"
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
REPO_URL="https://github.com/yxkastarn/daily-log-system.git"

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Kontrollera container ID
CONTAINER_ID="$1"
if [ -z "$CONTAINER_ID" ]; then
    error "Container ID krävs som argument"
fi

# Kontrollera om container ID redan existerar
if pct status $CONTAINER_ID &>/dev/null; then
    error "Container $CONTAINER_ID existerar redan"
fi

# Kontrollera om pveam är tillgängligt
if ! command -v pveam &> /dev/null; then
    error "pveam command not found. Are you running this on a Proxmox VE host?"
fi

# Kontrollera och ladda ner template om den inte finns
log "Kontrollerar om Ubuntu template finns..."
if ! pveam available | grep -q "$TEMPLATE"; then
    log "Uppdaterar template-listan..."
    pveam update || error "Kunde inte uppdatera template-listan"
fi

if ! pveam list local | grep -q "$TEMPLATE"; then
    log "Template saknas, laddar ner..."
    pveam download local "$TEMPLATE" || error "Kunde inte ladda ner template"
fi

# Dubbelkolla att templaten finns tillgänglig
if ! [ -f "/var/lib/vz/template/cache/$TEMPLATE" ]; then
    error "Template hittades inte i cache efter nedladdning"
fi

log "Skapar LXC container..."
pct create $CONTAINER_ID "/var/lib/vz/template/cache/$TEMPLATE" \
    --hostname $CONTAINER_NAME \
    --memory $MEMORY \
    --rootfs $STORAGE:$DISK_SIZE \
    --net0 name=eth0,bridge=$NETWORK,ip=dhcp \
    --unprivileged 1 \
    --features nesting=1 \
    || error "Kunde inte skapa container"

log "Startar container..."
pct start $CONTAINER_ID || error "Kunde inte starta container"

# Vänta på att containern ska starta helt
sleep 5

log "Installerar systempaket..."
pct exec $CONTAINER_ID -- bash -c '
    apt-get update
    apt-get install -y curl git nodejs npm postgresql postgresql-contrib nginx
    npm install -g pm2
'

log "Konfigurerar locale..."
pct exec $CONTAINER_ID -- bash -c '
    apt-get install -y locales
    locale-gen en_US.UTF-8
    update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
'

log "Startar PostgreSQL..."
pct exec $CONTAINER_ID -- systemctl start postgresql
pct exec $CONTAINER_ID -- systemctl enable postgresql

log "Klonar repository..."
pct exec $CONTAINER_ID -- bash -c "
    cd /opt
    git clone $REPO_URL
    chown -R root:root daily-log-system
"

log "Konfigurerar PostgreSQL..."
pct exec $CONTAINER_ID -- bash -c '
    # Vänta på att PostgreSQL ska starta helt
    sleep 5
    
    # Skapa användare och databas som postgres-användare
    su - postgres -c "psql -c \"CREATE USER dailylog WITH PASSWORD '\''dailylog123'\'';\""
    su - postgres -c "psql -c \"CREATE DATABASE daily_log;\""
    su - postgres -c "psql -c \"ALTER DATABASE daily_log OWNER TO dailylog;\""
    
    # Vänta lite till för att säkerställa att ändringarna har applicerats
    sleep 2
'

log "Sätter upp backend..."
pct exec $CONTAINER_ID -- bash -c '
    cd /opt/daily-log-system/backend
    npm install
    
    # Kör databasmigrering
    node migrations/run-migrations.js
    
    # Starta backend med PM2
    pm2 start server.js --name daily-log-api
    pm2 save
    pm2 startup
'

log "Konfigurerar nginx..."
pct exec $CONTAINER_ID -- bash -c '
    rm /etc/nginx/sites-enabled/default
    cp /opt/daily-log-system/nginx.conf /etc/nginx/sites-available/daily-log
    ln -s /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/
    nginx -t && systemctl restart nginx
'

IP=$(pct exec $CONTAINER_ID -- bash -c "ip addr show eth0 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1")

log "Installation klar!"
echo -e "${BLUE}Container IP: ${NC}$IP"
echo -e "${BLUE}Webbgränssnitt: ${NC}http://$IP"
echo -e "${BLUE}Grafana: ${NC}http://$IP:3000"