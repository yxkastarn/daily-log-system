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
    # Uppdatera paketlistan
    apt-get update

    # Installera grundläggande paket
    apt-get install -y curl git postgresql postgresql-contrib nginx

    # Lägg till Grafana repository och installera Grafana
    apt-get install -y apt-transport-https software-properties-common
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
    apt-get update
    apt-get install -y grafana

    # Installera Node.js 18
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    # Verifiera Node.js version
    node --version
    npm --version

    # Installera PM2 globalt och verifiera installationen
    npm install -g pm2
    ln -s "$(which pm2)" /usr/bin/pm2
    pm2 --version
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
    
    # Rensa npm cache och node_modules för att säkerställa ren installation
    rm -rf node_modules package-lock.json
    npm cache clean --force
    
    # Installera dependencies
    npm install
    
    # Kör databasmigrering
    node migrations/run-migrations.js
    
    # Säkerställ att PM2 är tillgängligt i PATH
    export PATH="$PATH:/usr/local/bin:/usr/bin"
    
    # Säkerställ att PM2 är korrekt installerat
    if ! command -v pm2 &> /dev/null; then
        echo "Reinstalling PM2..."
        npm install -g pm2
        ln -sf "$(which pm2)" /usr/bin/pm2
    fi

    # Starta backend med PM2
    pm2 delete daily-log-api 2>/dev/null || true  # Remove if exists
    pm2 start server.js --name daily-log-api || {
        echo "Failed to start with pm2. Checking pm2 installation..."
        which pm2
        pm2 --version
        exit 1
    }
    
    # Säkerställ att PM2 är konfigurerat för automatisk start
    pm2 startup systemd -u root --hp /root
    
    # Spara PM2 konfiguration efter att processen har startats
    pm2 save --force
    
    # Aktivera och starta pm2-root service
    systemctl daemon-reload
    systemctl enable pm2-root
    systemctl start pm2-root
'

# Konfigurera Grafana



log "Konfigurerar Grafana..."
pct exec $CONTAINER_ID -- bash -c '
    # Säkerställ att Grafana är installerad
    if ! command -v grafana-server &> /dev/null; then
        echo "Error: Grafana is not installed"
        exit 1
    fi

    # Skapa Grafana kataloger om de inte finns
    mkdir -p /var/lib/grafana
    mkdir -p /etc/grafana/provisioning

    # Säkerställ att Grafana-katalogerna har rätt behörigheter
    if getent group grafana >/dev/null; then
        chown -R grafana:grafana /var/lib/grafana
        chown -R grafana:grafana /etc/grafana
    else
        echo "Warning: grafana user/group not found, skipping ownership change"
    fi

    # Hämta container IP
    CONTAINER_IP=$(ip addr show eth0 | grep "inet " | awk "{print \$2}" | cut -d/ -f1)

    # Uppdatera Grafana konfiguration
    cat > /etc/grafana/grafana.ini << EOF
[server]
protocol = http
http_addr = 0.0.0.0
http_port = 3000
domain = ${CONTAINER_IP}
serve_from_sub_path = true
root_url = %(protocol)s://%(domain)s/grafana/

[security]
allow_embedding = true
cookie_secure = false
cookie_samesite = disabled

[auth.anonymous]
enabled = true

[paths]
provisioning = /etc/grafana/provisioning
EOF

    # Sätt miljövariabel för att inaktivera pager
    export SYSTEMD_PAGER=cat
    
    # Enable and start Grafana
    systemctl enable grafana-server --no-pager
    systemctl start grafana-server --no-pager
    
    # Vänta på att Grafana ska starta
    sleep 5
    
    # Kontrollera status
    if systemctl is-active --quiet grafana-server; then
        echo "Grafana startade framgångsrikt"
    else
        echo "Warning: Grafana service is not active"
        systemctl status grafana-server --no-pager --lines=10
    fi
'

log "Konfigurerar nginx..."
pct exec $CONTAINER_ID -- bash -c '
    # Ta bort default konfiguration
    rm -f /etc/nginx/sites-enabled/default

    # Kopiera och rensa upp nginx konfigurationen
    cp /opt/daily-log-system/nginx.conf /etc/nginx/sites-available/daily-log
    
    # Ta bort eventuella gamla symlinks
    rm -f /etc/nginx/sites-enabled/daily-log
    
    # Skapa ny symlink
    ln -sf /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/
    
    # Verifiera och starta om nginx
    if nginx -t; then
        systemctl restart nginx
    else
        echo "Nginx configuration test failed"
        exit 1
    fi
'

IP=$(pct exec $CONTAINER_ID -- bash -c "ip addr show eth0 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1")

log "Installation klar!"
echo -e "${BLUE}Container IP: ${NC}$IP"
echo -e "${BLUE}Webbgränssnitt: ${NC}http://$IP"
echo -e "${BLUE}Grafana: ${NC}http://$IP:3000"