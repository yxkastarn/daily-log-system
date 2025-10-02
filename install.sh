#!/bin/bash

# Daily Log System - Automatisk Proxmox LXC Installation
# Författare: yxkastarn

set -e

# Färger för output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variabler
CONTAINER_ID=${1:-100}
CONTAINER_NAME="daily-log"
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
MEMORY=2048
DISK_SIZE=8
STORAGE="local-lvm"
NETWORK="vmbr0"
REPO_URL="https://github.com/yxkastarn/daily-log-system.git"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Detta script måste köras som root"
        exit 1
    fi
}

check_proxmox() {
    if ! command -v pct &> /dev/null; then
        log_error "Proxmox (pct) hittades inte. Kör detta script på en Proxmox-värd."
        exit 1
    fi
}

main() {
    log_info "=== Daily Log System Installation ==="
    echo ""
    
    check_root
    check_proxmox
    
    # Kontrollera om container redan finns
    if pct status $CONTAINER_ID &> /dev/null; then
        log_warn "Container $CONTAINER_ID finns redan"
        read -p "Vill du ta bort den och fortsätta? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Tar bort befintlig container..."
            pct stop $CONTAINER_ID || true
            pct destroy $CONTAINER_ID
        else
            log_error "Avbryter installation"
            exit 1
        fi
    fi
    
    # Skapa LXC container
    log_info "Skapar LXC container..."
    pct create $CONTAINER_ID local:vztmpl/$TEMPLATE \
        --hostname $CONTAINER_NAME \
        --memory $MEMORY \
        --net0 name=eth0,bridge=$NETWORK,ip=dhcp \
        --storage $STORAGE \
        --rootfs $STORAGE:$DISK_SIZE \
        --features nesting=1 \
        --unprivileged 1 \
        --onboot 1
    
    log_info "Startar container..."
    pct start $CONTAINER_ID
    sleep 5
    
    log_info "Installerar grundläggande paket..."
    pct exec $CONTAINER_ID -- bash -c "apt update && apt upgrade -y"
    pct exec $CONTAINER_ID -- bash -c "apt install -y curl wget git nano sudo"
    
    # Installera PostgreSQL
    log_info "Installerar PostgreSQL..."
    pct exec $CONTAINER_ID -- bash -c "apt install -y postgresql postgresql-contrib"
    
    # Installera Node.js
    log_info "Installerar Node.js..."
    pct exec $CONTAINER_ID -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"
    pct exec $CONTAINER_ID -- bash -c "apt install -y nodejs"
    pct exec $CONTAINER_ID -- bash -c "npm install -g pm2"
    
    # Installera Nginx
    log_info "Installerar Nginx..."
    pct exec $CONTAINER_ID -- bash -c "apt install -y nginx"
    
    # Installera Grafana
    log_info "Installerar Grafana..."
    pct exec $CONTAINER_ID -- bash -c "apt install -y software-properties-common"
    pct exec $CONTAINER_ID -- bash -c "wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -"
    pct exec $CONTAINER_ID -- bash -c "echo 'deb https://packages.grafana.com/oss/deb stable main' | tee /etc/apt/sources.list.d/grafana.list"
    pct exec $CONTAINER_ID -- bash -c "apt update && apt install -y grafana"
    
    # Klona repository
    log_info "Klonar repository..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt && git clone $REPO_URL"
    
    # Konfigurera databas
    log_info "Konfigurerar databas..."
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"CREATE DATABASE daily_log;\""
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"CREATE USER dailylog WITH PASSWORD 'dailylog123';\""
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE daily_log TO dailylog;\""
    
    # Kör databas-migrationer
    log_info "Kör databas-migrationer..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && npm install"
    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && npm run migrate"
    
    # Konfigurera backend
    log_info "Konfigurerar backend..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && cp .env.example .env"
    
    # Starta backend med PM2
    log_info "Startar backend-tjänst..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && pm2 start server.js --name daily-log-api"
    pct exec $CONTAINER_ID -- bash -c "pm2 startup systemd -u root --hp /root"
    pct exec $CONTAINER_ID -- bash -c "pm2 save"
    
    # Konfigurera Nginx
    log_info "Konfigurerar Nginx..."
    pct exec $CONTAINER_ID -- bash -c "cp /opt/daily-log-system/nginx.conf /etc/nginx/sites-available/daily-log"
    pct exec $CONTAINER_ID -- bash -c "ln -sf /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/"
    pct exec $CONTAINER_ID -- bash -c "rm -f /etc/nginx/sites-enabled/default"
    pct exec $CONTAINER_ID -- bash -c "nginx -t && systemctl reload nginx"
    
    # Konfigurera och starta Grafana
    log_info "Konfigurerar Grafana..."
    pct exec $CONTAINER_ID -- bash -c "systemctl enable grafana-server"
    pct exec $CONTAINER_ID -- bash -c "systemctl start grafana-server"
    
    # Importera Grafana dashboards
    log_info "Importerar Grafana dashboards..."
    sleep 10
    pct exec $CONTAINER_ID -- bash -c "bash /opt/daily-log-system/scripts/setup-grafana.sh"
    
    # Hämta IP-adress
    CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I | awk '{print $1}')
    
    # Installation klar
    echo ""
    log_info "=== Installation klar! ==="
    echo ""
    echo -e "${GREEN}✓${NC} Webbgränssnitt: http://$CONTAINER_IP"
    echo -e "${GREEN}✓${NC} Grafana: http://$CONTAINER_IP:3000"
    echo -e "  - Användarnamn: admin"
    echo -e "  - Lösenord: admin (ändra vid första inloggningen)"
    echo ""
}

main "$@"
