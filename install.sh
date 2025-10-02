#!/bin/bash

# Daily Log System - Automatisk Proxmox LXC Installation
# Författare: yxkastarn

set -e

# Färger för output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variabler
CONTAINER_NAME="daily-log"
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
MEMORY=2048
DISK_SIZE=8
STORAGE="local-lvm"
NETWORK="vmbr0"
REPO_URL="https://github.com/yxkastarn/daily-log-system.git"
RAW_URL="https://raw.githubusercontent.com/yxkastarn/daily-log-system/main"

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
        log_error "Proxmox (pct) hittades inte."
        exit 1
    fi
}

find_next_free_vmid() {
    log_info "Söker efter ledigt container ID..."
    local used_vmids=$(pvesh get /cluster/resources --type vm --output-format json | grep -oP '"vmid":\K\d+' | sort -n)
    local start_id=${1:-100}
    local vmid=$start_id
    while echo "$used_vmids" | grep -q "^${vmid}$"; do
        vmid=$((vmid + 1))
    done
    echo "$vmid"
}

download_template() {
    log_info "Kontrollerar LXC template..."
    if pveam list local | grep -q "$TEMPLATE"; then
        log_info "Template finns redan"
        return 0
    fi
    log_info "Laddar ner Ubuntu 22.04 template..."
    pveam update
    pveam download local "$TEMPLATE"
}

ensure_files_exist() {
    local cid=$1
    log_info "Säkerställer att alla filer finns..."
    
    # Kontrollera schema.sql
    if ! pct exec $cid -- test -f /opt/daily-log-system/database/schema.sql; then
        log_warn "schema.sql saknas, hämtar från GitHub..."
        pct exec $cid -- bash -c "curl -sL ${RAW_URL}/database/schema.sql -o /opt/daily-log-system/database/schema.sql"
    fi
    
    # Kontrollera index.html
    if ! pct exec $cid -- test -f /opt/daily-log-system/frontend/public/index.html; then
        log_warn "index.html saknas, hämtar från GitHub..."
        pct exec $cid -- bash -c "curl -sL ${RAW_URL}/frontend/public/index.html -o /opt/daily-log-system/frontend/public/index.html"
    fi
    
    # Kontrollera nginx.conf
    if ! pct exec $cid -- test -f /opt/daily-log-system/nginx.conf; then
        log_warn "nginx.conf saknas, hämtar från GitHub..."
        pct exec $cid -- bash -c "curl -sL ${RAW_URL}/nginx.conf -o /opt/daily-log-system/nginx.conf"
    fi
    
    log_info "✓ Alla nödvändiga filer finns"
}

main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗"
    echo "║         Daily Log System - Proxmox Installation           ║"
    echo "╚════════════════════════════════════════════════════════════╝${NC}"
    
    check_root
    check_proxmox
    
    CONTAINER_ID=$(find_next_free_vmid ${1:-100})
    log_info "Använder container ID: ${BLUE}${CONTAINER_ID}${NC}"
    
    download_template
    
    log_info "Skapar LXC container..."
    pct create $CONTAINER_ID local:vztmpl/$TEMPLATE \
        --hostname $CONTAINER_NAME \
        --memory $MEMORY \
        --net0 name=eth0,bridge=$NETWORK,ip=dhcp \
        --rootfs $STORAGE:$DISK_SIZE \
        --features nesting=1 \
        --unprivileged 1 \
        --onboot 1
    
    log_info "Startar container..."
    pct start $CONTAINER_ID
    sleep 10
    
    log_info "Installerar paket (detta tar några minuter)..."
    pct exec $CONTAINER_ID -- bash -c "DEBIAN_FRONTEND=noninteractive apt update && apt upgrade -y"
    pct exec $CONTAINER_ID -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y curl wget git nano sudo postgresql postgresql-contrib nginx software-properties-common apt-transport-https gnupg"
    
    log_info "Installerar Node.js 18..."
    pct exec $CONTAINER_ID -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"
    pct exec $CONTAINER_ID -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y nodejs"
    pct exec $CONTAINER_ID -- bash -c "npm install -g pm2"
    
    log_info "Installerar Grafana..."
    pct exec $CONTAINER_ID -- bash -c "mkdir -p /etc/apt/keyrings/"
    pct exec $CONTAINER_ID -- bash -c "wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg"
    pct exec $CONTAINER_ID -- bash -c "echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list"
    pct exec $CONTAINER_ID -- bash -c "apt update && DEBIAN_FRONTEND=noninteractive apt install -y grafana"
    
    log_info "Klonar repository från GitHub..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt && git clone $REPO_URL"
    
    log_info "Skapar katalogstruktur..."
    pct exec $CONTAINER_ID -- bash -c "mkdir -p /opt/daily-log-system/database /opt/daily-log-system/frontend/public /opt/daily-log-system/grafana /opt/daily-log-system/scripts"
    
    # Säkerställ att alla filer finns (hämtar från GitHub om de saknas)
    ensure_files_exist $CONTAINER_ID
    
    log_info "Konfigurerar PostgreSQL..."
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"CREATE DATABASE daily_log;\""
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"CREATE USER dailylog WITH PASSWORD 'dailylog123';\""
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE daily_log TO dailylog;\""
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -d daily_log -c \"GRANT ALL ON SCHEMA public TO dailylog;\""
    
    log_info "Installerar backend dependencies..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && npm install"
    
    log_info "Konfigurerar backend..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && cp .env.example .env"
    
    log_info "Kör databas-migrationer..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && npm run migrate"
    
    log_info "Startar backend API..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && pm2 start server.js --name daily-log-api"
    pct exec $CONTAINER_ID -- bash -c "pm2 startup systemd -u root --hp /root"
    pct exec $CONTAINER_ID -- bash -c "pm2 save"
    
    log_info "Konfigurerar Nginx..."
    pct exec $CONTAINER_ID -- bash -c "cp /opt/daily-log-system/nginx.conf /etc/nginx/sites-available/daily-log"
    pct exec $CONTAINER_ID -- bash -c "ln -sf /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/"
    pct exec $CONTAINER_ID -- bash -c "rm -f /etc/nginx/sites-enabled/default"
    pct exec $CONTAINER_ID -- bash -c "nginx -t && systemctl reload nginx"
    
    log_info "Startar Grafana..."
    pct exec $CONTAINER_ID -- bash -c "systemctl enable grafana-server"
    pct exec $CONTAINER_ID -- bash -c "systemctl start grafana-server"
    
    sleep 10
    CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗"
    echo "║              Installation Slutförd! 🎉                     ║"
    echo "╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Container Information:${NC}"
    echo -e "  ID: ${GREEN}${CONTAINER_ID}${NC}"
    echo -e "  IP: ${GREEN}${CONTAINER_IP}${NC}"
    echo ""
    echo -e "${BLUE}Åtkomst:${NC}"
    echo -e "  ${GREEN}✓${NC} Webbgränssnitt: ${YELLOW}http://${CONTAINER_IP}${NC}"
    echo -e "  ${GREEN}✓${NC} Grafana:        ${YELLOW}http://${CONTAINER_IP}:3000${NC}"
    echo -e "      - Användarnamn: ${YELLOW}admin${NC}"
    echo -e "      - Lösenord:     ${YELLOW}admin${NC} ${RED}(ändra vid första inloggningen!)${NC}"
    echo ""
    echo -e "${BLUE}Nästa steg:${NC}"
    echo "  1. Öppna webbgränssnittet och registrera din första aktivitet"
    echo "  2. Logga in på Grafana och utforska dashboards"
    echo "  3. Ändra standardlösenord för Grafana"
    echo ""
    echo -e "${BLUE}Användbara kommandon:${NC}"
    echo -e "  Logga in i container: ${YELLOW}pct enter ${CONTAINER_ID}${NC}"
    echo -e "  Se backend-loggar:    ${YELLOW}pct exec ${CONTAINER_ID} -- pm2 logs${NC}"
    echo -e "  Stoppa container:     ${YELLOW}pct stop ${CONTAINER_ID}${NC}"
    echo -e "  Starta container:     ${YELLOW}pct start ${CONTAINER_ID}${NC}"
    echo ""
    echo -e "${GREEN}Lycka till med Daily Log System! 🚀${NC}"
    echo ""
}

main "$@"
EOFINSTALL