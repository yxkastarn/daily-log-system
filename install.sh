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

find_next_free_vmid() {
    log_info "Söker efter ledigt container ID..."
    
    local used_vmids=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | grep -oP '"vmid":\K\d+' | sort -n)
    
    local start_id=${1:-100}
    local vmid=$start_id
    
    while echo "$used_vmids" | grep -q "^${vmid}$"; do
        vmid=$((vmid + 1))
    done
    
    echo "$vmid"
}

download_template() {
    log_info "Kontrollerar LXC template..."
    
    if pveam list local 2>/dev/null | grep -q "$TEMPLATE"; then
        log_info "Template finns redan: $TEMPLATE"
        return 0
    fi
    
    log_info "Laddar ner Ubuntu 22.04 LXC template..."
    log_warn "Detta kan ta några minuter..."
    
    pveam update
    
    if ! pveam download local "$TEMPLATE" 2>/dev/null; then
        log_error "Kunde inte ladda ner template: $TEMPLATE"
        log_info "Försöker hitta alternativ template..."
        
        local available=$(pveam available 2>/dev/null | grep ubuntu | grep -E '22\.04|20\.04' | head -1 | awk '{print $2}')
        
        if [ -n "$available" ]; then
            log_info "Använder alternativ template: $available"
            TEMPLATE="$available"
            pveam download local "$TEMPLATE"
        else
            log_error "Ingen lämplig Ubuntu template hittades"
            exit 1
        fi
    fi
    
    log_info "✓ Template nedladdad: $TEMPLATE"
}

main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         Daily Log System - Proxmox Installation           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
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
        --storage $STORAGE \
        --rootfs $STORAGE:$DISK_SIZE \
        --features nesting=1 \
        --unprivileged 1 \
        --onboot 1
    
    log_info "✓ Container skapad med ID: $CONTAINER_ID"
    
    log_info "Startar container..."
    pct start $CONTAINER_ID
    sleep 10
    
    log_info "Installerar grundläggande paket..."
    pct exec $CONTAINER_ID -- bash -c "apt update && apt upgrade -y"
    pct exec $CONTAINER_ID -- bash -c "apt install -y curl wget git nano sudo"
    
    log_info "Installerar PostgreSQL..."
    pct exec $CONTAINER_ID -- bash -c "apt install -y postgresql postgresql-contrib"
    
    log_info "Installerar Node.js 18..."
    pct exec $CONTAINER_ID -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"
    pct exec $CONTAINER_ID -- bash -c "apt install -y nodejs"
    pct exec $CONTAINER_ID -- bash -c "npm install -g pm2"
    
    log_info "Installerar Nginx..."
    pct exec $CONTAINER_ID -- bash -c "apt install -y nginx"
    
    log_info "Installerar Grafana..."
    pct exec $CONTAINER_ID -- bash -c "apt install -y software-properties-common apt-transport-https"
    pct exec $CONTAINER_ID -- bash -c "mkdir -p /etc/apt/keyrings/"
    pct exec $CONTAINER_ID -- bash -c "wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg"
    pct exec $CONTAINER_ID -- bash -c "echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' | tee /etc/apt/sources.list.d/grafana.list"
    pct exec $CONTAINER_ID -- bash -c "apt update && apt install -y grafana"
    
    log_info "Klonar repository från GitHub..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt && git clone $REPO_URL"
    
    log_info "Konfigurerar PostgreSQL databas..."
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"CREATE DATABASE daily_log;\""
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"CREATE USER dailylog WITH PASSWORD 'dailylog123';\""
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE daily_log TO dailylog;\""
    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"ALTER DATABASE daily_log OWNER TO dailylog;\""
    
    log_info "Installerar backend dependencies..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && npm install"
    
    log_info "Konfigurerar backend..."
    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && cp .env.example .env"
    
    log_info "Skapar database schema manuellt (fallback)..."
    pct exec $CONTAINER_ID -- bash -c "mkdir -p /opt/daily-log-system/database"
    pct exec $CONTAINER_ID -- bash -c "curl -s https://raw.githubusercontent.com/yxkastarn/daily-log-system/main/database/schema.sql -o /opt/daily-log-system/database/schema.sql"
    
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
    
    log_info "Konfigurerar Grafana..."
    pct exec $CONTAINER_ID -- bash -c "systemctl enable grafana-server"
    pct exec $CONTAINER_ID -- bash -c "systemctl start grafana-server"
    
    log_info "Väntar på att Grafana startar..."
    sleep 15
    
    log_info "Importerar Grafana dashboards..."
    pct exec $CONTAINER_ID -- bash -c "bash /opt/daily-log-system/scripts/setup-grafana.sh" || log_warn "Grafana setup misslyckades, konfigurera manuellt"
    
    log_info "Konfigurerar automatisk backup..."
    pct exec $CONTAINER_ID -- bash -c "chmod +x /opt/daily-log-system/scripts/backup.sh"
    pct exec $CONTAINER_ID -- bash -c "(crontab -l 2>/dev/null; echo '0 2 * * * /opt/daily-log-system/scripts/backup.sh') | crontab -"
    
    sleep 5
    CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              Installation Slutförd! 🎉                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
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
    echo -e "${GREEN}Lycka till med Daily Log System! 🚀${NC}"
    echo ""
}

main "$@"
EOFINSTALL