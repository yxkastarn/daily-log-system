#!/bin/bash

# Daily Log System - Automatisk Proxmox LXC Installation
# FÃ¶rfattare: yxkastarn

set -e

# FÃ¤rger fÃ¶r output
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
        log_error "Detta script mÃ¥ste kÃ¶ras som root"
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
    log_info "SÃ¶ker efter ledigt container ID..."
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
    log_info "SÃ¤kerstÃ¤ller att alla filer finns..."
    
    # Kontrollera schema.sql
    if ! pct exec $cid -- test -f /opt/daily-log-system/database/schema.sql; then
        log_warn "schema.sql saknas, hÃ¤mtar frÃ¥n GitHub..."
        pct exec $cid -- bash -c "curl -sL ${RAW_URL}/database/schema.sql -o /opt/daily-log-system/database/schema.sql"
    fi
    
    # Kontrollera index.html
    if ! pct exec $cid -- test -f /opt/daily-log-system/frontend/public/index.html; then
        log_warn "index.html saknas, hÃ¤mtar frÃ¥n GitHub..."
        pct exec $cid -- bash -c "curl -sL ${RAW_URL}/frontend/public/index.html -o /opt/daily-log-system/frontend/public/index.html"
    fi
    
    # Kontrollera nginx.conf
    if ! pct exec $cid -- test -f /opt/daily-log-system/nginx.conf; then
        log_warn "nginx.conf saknas, hÃ¤mtar frÃ¥n GitHub..."
        pct exec $cid -- bash -c "curl -sL ${RAW_URL}/nginx.conf -o /opt/daily-log-system/nginx.conf"
    fi
    
    log_info "âœ“ Alla nÃ¶dvÃ¤ndiga filer finns"
}

main() {
    echo -e "${BLUE}â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—"
    echo "â•‘         Daily Log System - Proxmox Installation           â•‘"
    echo "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
    
    check_root
    check_proxmox
    
    CONTAINER_ID=$(find_next_free_vmid ${1:-100})
    log_info "AnvÃ¤nder container ID: ${BLUE}${CONTAINER_ID}${NC}"
    
    download_template
    
    log_info "Skapar LXC container..."
    TEMPLATE_PATH="local:vztmpl/$TEMPLATE"
    pct create "$CONTAINER_ID" "$TEMPLATE_PATH" --hostname "$CONTAINER_NAME" --memory "$MEMORY" --net0 "name=eth0,bridge=$NETWORK,ip=dhcp" --rootfs "$STORAGE:$DISK_SIZE" --features "nesting=1" --unprivileged 1 --onboot 1
    
    log_info "Startar container..."
    pct start $CONTAINER_ID
    sleep 10
    
    log_info "Installerar paket (detta tar nÃ¥gra minuter)..."
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
    
    log_info "Klonar repository frÃ¥n GitHub..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt && git clone $REPO_URL"
    
    log_info "Skapar katalogstruktur..."
    pct exec $CONTAINER_ID -- bash -c "mkdir -p /opt/daily-log-system/database /opt/daily-log-system/frontend/public /opt/daily-log-system/grafana /opt/daily-log-system/scripts"
    
    # SÃ¤kerstÃ¤ll att alla filer finns (hÃ¤mtar frÃ¥n GitHub om de saknas)
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
    
    log_info "KÃ¶r databas-migrationer..."
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
    echo -e "${GREEN}â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—"
    echo "â•‘              Installation SlutfÃ¶rd! ðŸŽ‰                     â•‘"
    echo "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
    echo ""
    echo -e "${BLUE}Container Information:${NC}"
    echo -e "  ID: ${GREEN}${CONTAINER_ID}${NC}"
    echo -e "  IP: ${GREEN}${CONTAINER_IP}${NC}"
    echo ""
    echo -e "${BLUE}Ã…tkomst:${NC}"
    echo -e "  ${GREEN}âœ“${NC} WebbgrÃ¤nssnitt: ${YELLOW}http://${CONTAINER_IP}${NC}"
    echo -e "  ${GREEN}âœ“${NC} Grafana:        ${YELLOW}http://${CONTAINER_IP}:3000${NC}"
    echo -e "      - AnvÃ¤ndarnamn: ${YELLOW}admin${NC}"
    echo -e "      - LÃ¶senord:     ${YELLOW}admin${NC} ${RED}(Ã¤ndra vid fÃ¶rsta inloggningen!)${NC}"
    echo ""
    echo -e "${BLUE}NÃ¤sta steg:${NC}"
    echo "  1. Ã–ppna webbgrÃ¤nssnittet och registrera din fÃ¶rsta aktivitet"
    echo "  2. Logga in pÃ¥ Grafana och utforska dashboards"
    echo "  3. Ã„ndra standardlÃ¶senord fÃ¶r Grafana"
    echo ""
    echo -e "${BLUE}AnvÃ¤ndbara kommandon:${NC}"
    echo -e "  Logga in i container: ${YELLOW}pct enter ${CONTAINER_ID}${NC}"
    echo -e "  Se backend-loggar:    ${YELLOW}pct exec ${CONTAINER_ID} -- pm2 logs${NC}"
    echo -e "  Stoppa container:     ${YELLOW}pct stop ${CONTAINER_ID}${NC}"
    echo -e "  Starta container:     ${YELLOW}pct start ${CONTAINER_ID}${NC}"
    echo ""
    echo -e "${GREEN}Lycka till med Daily Log System! ðŸš€${NC}"
    echo ""
}

main "$@"
