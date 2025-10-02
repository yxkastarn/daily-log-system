cd ~/daily-log-system
cat > install.sh << 'EOFINSTALL'
#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONTAINER_NAME="daily-log"
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
MEMORY=2048
DISK_SIZE=8
REPO_URL="https://github.com/yxkastarn/daily-log-system.git"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Detta script måste köras som root"
        exit 1
    fi
}

check_container_exists() {
    if pct status $1 &>/dev/null; then
        return 0
    else
        return 1
    fi
}

prompt_container_id() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗"
    echo "║         Daily Log System - Proxmox Installation           ║"
    echo "╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Befintliga containers:${NC}"
    pct list
    echo ""
    
    while true; do
        read -p "$(echo -e ${BLUE}Ange container ID för Daily Log System: ${NC})" CONTAINER_ID
        
        if [[ ! "$CONTAINER_ID" =~ ^[0-9]+$ ]]; then
            log_error "Container ID måste vara ett nummer"
            continue
        fi
        
        if check_container_exists "$CONTAINER_ID"; then
            log_warn "Container ID $CONTAINER_ID finns redan!"
            read -p "Vill du ta bort den och fortsätta? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Stoppar och tar bort container $CONTAINER_ID..."
                pct stop $CONTAINER_ID 2>/dev/null || true
                pct destroy $CONTAINER_ID
                break
            fi
        else
            break
        fi
    done
    
    echo "$CONTAINER_ID"
}

download_template() {
    log_info "Kontrollerar LXC template..."
    if pveam list local 2>/dev/null | grep -q "$TEMPLATE"; then
        log_info "Template finns redan"
        return 0
    fi
    log_info "Laddar ner Ubuntu 22.04 template..."
    pveam update
    pveam download local "$TEMPLATE"
    log_info "✓ Template nedladdad"
}

main() {
    check_root
    
    # Prompt för container ID
    CONTAINER_ID=$(prompt_container_id)
    
    log_info "Använder container ID: ${BLUE}${CONTAINER_ID}${NC}"
    
    download_template
    
    log_info "Skapar LXC container..."
    pct create ${CONTAINER_ID} local:vztmpl/${TEMPLATE} \
        --hostname ${CONTAINER_NAME} \
        --memory ${MEMORY} \
        --cores 2 \
        --rootfs local-lvm:${DISK_SIZE} \
        --net0 name=eth0,bridge=vmbr0,ip=dhcp \
        --features nesting=1 \
        --unprivileged 1 \
        --onboot 1
    
    log_info "✓ Container skapad"
    
    log_info "Startar container..."
    pct start ${CONTAINER_ID}
    sleep 10
    
    log_info "Installerar paket (detta tar några minuter)..."
    pct exec ${CONTAINER_ID} -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get upgrade -y && apt-get install -y curl wget git nano sudo postgresql postgresql-contrib nginx software-properties-common apt-transport-https gnupg"
    
    log_info "Installerar Node.js 18..."
    pct exec ${CONTAINER_ID} -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"
    pct exec ${CONTAINER_ID} -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs"
    pct exec ${CONTAINER_ID} -- bash -c "npm install -g pm2"
    
    log_info "Installerar Grafana..."
    pct exec ${CONTAINER_ID} -- bash -c "mkdir -p /etc/apt/keyrings/"
    pct exec ${CONTAINER_ID} -- bash -c "wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg"
    pct exec ${CONTAINER_ID} -- bash -c "echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list"
    pct exec ${CONTAINER_ID} -- bash -c "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y grafana"
    
    log_info "Klonar repository..."
    pct exec ${CONTAINER_ID} -- bash -c "cd /opt && git clone ${REPO_URL}"
    
    log_info "Konfigurerar PostgreSQL..."
    pct exec ${CONTAINER_ID} -- bash -c "sudo -u postgres psql -c \"CREATE DATABASE daily_log;\""
    pct exec ${CONTAINER_ID} -- bash -c "sudo -u postgres psql -c \"CREATE USER dailylog WITH PASSWORD 'dailylog123';\""
    pct exec ${CONTAINER_ID} -- bash -c "sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE daily_log TO dailylog;\""
    pct exec ${CONTAINER_ID} -- bash -c "sudo -u postgres psql -d daily_log -c \"GRANT ALL ON SCHEMA public TO dailylog;\""
    
    log_info "Säkerställer schema.sql..."
    pct exec ${CONTAINER_ID} -- bash -c "mkdir -p /opt/daily-log-system/database"
    pct exec ${CONTAINER_ID} -- bash -c "curl -sL https://raw.githubusercontent.com/yxkastarn/daily-log-system/main/database/schema.sql -o /opt/daily-log-system/database/schema.sql"
    
    log_info "Installerar backend..."
    pct exec ${CONTAINER_ID} -- bash -c "cd /opt/daily-log-system/backend && npm install"
    pct exec ${CONTAINER_ID} -- bash -c "cd /opt/daily-log-system/backend && cp .env.example .env"
    pct exec ${CONTAINER_ID} -- bash -c "cd /opt/daily-log-system/backend && npm run migrate"
    
    log_info "Startar backend..."
    pct exec ${CONTAINER_ID} -- bash -c "cd /opt/daily-log-system/backend && pm2 start server.js --name daily-log-api"
    pct exec ${CONTAINER_ID} -- bash -c "pm2 startup systemd -u root --hp /root"
    pct exec ${CONTAINER_ID} -- bash -c "pm2 save"
    
    log_info "Konfigurerar Nginx..."
    pct exec ${CONTAINER_ID} -- bash -c "cp /opt/daily-log-system/nginx.conf /etc/nginx/sites-available/daily-log"
    pct exec ${CONTAINER_ID} -- bash -c "ln -sf /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/"
    pct exec ${CONTAINER_ID} -- bash -c "rm -f /etc/nginx/sites-enabled/default"
    pct exec ${CONTAINER_ID} -- bash -c "nginx -t && systemctl reload nginx"
    
    log_info "Startar Grafana..."
    pct exec ${CONTAINER_ID} -- bash -c "systemctl enable grafana-server"
    pct exec ${CONTAINER_ID} -- bash -c "systemctl start grafana-server"
    
    sleep 10
    CONTAINER_IP=$(pct exec ${CONTAINER_ID} -- hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗"
    echo "║              Installation Slutförd! 🎉                     ║"
    echo "╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Container ID: ${GREEN}${CONTAINER_ID}${NC}"
    echo -e "Container IP: ${GREEN}${CONTAINER_IP}${NC}"
    echo ""
    echo -e "  ${GREEN}✓${NC} Webbgränssnitt: ${YELLOW}http://${CONTAINER_IP}${NC}"
    echo -e "  ${GREEN}✓${NC} Grafana: ${YELLOW}http://${CONTAINER_IP}:3000${NC}"
    echo -e "      User: ${YELLOW}admin${NC} / Pass: ${YELLOW}admin${NC} ${RED}(ändra vid första inloggning!)${NC}"
    echo ""
    echo -e "Användbara kommandon:"
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

chmod +x install.sh
git add install.sh
git commit -m "Interactive prompt for container ID with existing container check"
git push