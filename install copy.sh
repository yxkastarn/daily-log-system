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
[[ -z "$CONTAINER_ID" ]] && error "Användning: $0 <container-id>\nExempel: $0 101"
[[ ! "$CONTAINER_ID" =~ ^[0-9]+$ ]] && error "Container ID måste vara ett nummer"
[[ "$EUID" -ne 0 ]] && error "Detta script måste köras som root"
command -v pct &> /dev/null || error "Proxmox (pct) hittades inte"

# Kontrollera om container redan finns
if pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | grep -q "\"vmid\":$CONTAINER_ID"; then
    error "Container ID $CONTAINER_ID används redan"
fi

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    Daily Log System - Proxmox Installation${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

# Ladda ner template
log "Kontrollerar Ubuntu 22.04 template..."
if ! pveam list local | grep -q "$TEMPLATE"; then
    log "Laddar ner template..."
    pveam update
    pveam download local "$TEMPLATE"
fi

# Skapa container
log "Skapar LXC container ${CONTAINER_ID}..."
pct create "$CONTAINER_ID" "local:vztmpl/$TEMPLATE" \
    --hostname "$CONTAINER_NAME" \
    --memory "$MEMORY" \
    --net0 "name=eth0,bridge=$NETWORK,ip=dhcp" \
    --rootfs "$STORAGE:$DISK_SIZE" \
    --features "nesting=1" \
    --unprivileged 1 \
    --onboot 1

log "Startar container..."
pct start "$CONTAINER_ID"
sleep 10

# Installera systempaket
log "Uppdaterar system..."
pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt update && apt upgrade -y"

log "Installerar grundpaket..."
pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y \
    curl wget git nano sudo postgresql postgresql-contrib nginx software-properties-common apt-transport-https gnupg"

# Installera Node.js
log "Installerar Node.js 18..."
pct exec "$CONTAINER_ID" -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"
pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y nodejs"
pct exec "$CONTAINER_ID" -- bash -c "npm install -g pm2"

# Installera Grafana
log "Installerar Grafana..."
pct exec "$CONTAINER_ID" -- bash -c "
    mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list
    apt update && DEBIAN_FRONTEND=noninteractive apt install -y grafana
"

# Konfigurera PostgreSQL
log "Konfigurerar PostgreSQL databas..."
pct exec "$CONTAINER_ID" -- bash -c "
    sudo -u postgres psql -c \"CREATE DATABASE daily_log;\"
    sudo -u postgres psql -c \"CREATE USER dailylog WITH PASSWORD 'dailylog123';\"
    sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE daily_log TO dailylog;\"
    sudo -u postgres psql -d daily_log -c \"GRANT ALL ON SCHEMA public TO dailylog;\"
"

# Installera applikation
log "Klonar repository..."
pct exec "$CONTAINER_ID" -- bash -c "cd /opt && git clone $REPO_URL"

log "Skapar katalogstruktur..."
pct exec "$CONTAINER_ID" -- bash -c "mkdir -p /opt/daily-log-system/{database,frontend/public,grafana,scripts}"

# Kontrollera och hämta saknade filer
if ! pct exec "$CONTAINER_ID" -- test -f /opt/daily-log-system/backend/package.json 2>/dev/null; then
    warn "Backend saknas, skapar grundstruktur..."
    pct exec "$CONTAINER_ID" -- bash -c "mkdir -p /opt/daily-log-system/backend"
    pct exec "$CONTAINER_ID" -- bash -c "cat > /opt/daily-log-system/backend/package.json << 'EOF'
{
  \"name\": \"daily-log-api\",
  \"version\": \"1.0.0\",
  \"main\": \"server.js\",
  \"scripts\": {
    \"start\": \"node server.js\",
    \"migrate\": \"echo 'No migrations yet'\"
  },
  \"dependencies\": {
    \"express\": \"^4.18.2\",
    \"pg\": \"^8.11.0\",
    \"dotenv\": \"^16.0.3\",
    \"cors\": \"^2.8.5\"
  }
}
EOF"
fi

log "Installerar backend dependencies..."
pct exec "$CONTAINER_ID" -- bash -c "cd /opt/daily-log-system/backend && npm install 2>/dev/null || true"

# Skapa enkel .env om den inte finns
pct exec "$CONTAINER_ID" -- bash -c "
if [ ! -f /opt/daily-log-system/backend/.env ]; then
    cat > /opt/daily-log-system/backend/.env << 'EOF'
DATABASE_URL=postgresql://dailylog:dailylog123@localhost:5432/daily_log
PORT=3001
NODE_ENV=production
EOF
fi
"

# Skapa enkel server.js om den inte finns
if ! pct exec "$CONTAINER_ID" -- test -f /opt/daily-log-system/backend/server.js 2>/dev/null; then
    pct exec "$CONTAINER_ID" -- bash -c "cat > /opt/daily-log-system/backend/server.js << 'EOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const app = express();

app.use(cors());
app.use(express.json());

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', message: 'Daily Log API running' });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(\`API running on port \${PORT}\`));
EOF"
fi

# Starta backend
log "Startar backend API..."
pct exec "$CONTAINER_ID" -- bash -c "cd /opt/daily-log-system/backend && pm2 start server.js --name daily-log-api"
pct exec "$CONTAINER_ID" -- bash -c "pm2 startup systemd -u root --hp /root && pm2 save"

# Skapa enkel frontend om den inte finns
if ! pct exec "$CONTAINER_ID" -- test -f /opt/daily-log-system/frontend/public/index.html 2>/dev/null; then
    pct exec "$CONTAINER_ID" -- bash -c "cat > /opt/daily-log-system/frontend/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang=\"sv\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Daily Log System</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #333; }
        .status { padding: 10px; background: #d4edda; border-radius: 5px; margin: 20px 0; }
        a { color: #007bff; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>Daily Log System</h1>
    <div class=\"status\">✓ System is running</div>
    <p>Welcome to Daily Log System. The application is successfully installed!</p>
    <p><a href=\"http://\" + window.location.hostname + \":3000\">Open Grafana Dashboard</a></p>
</body>
</html>
EOF"
fi

# Konfigurera Nginx
log "Konfigurerar Nginx..."
pct exec "$CONTAINER_ID" -- bash -c "cat > /etc/nginx/sites-available/daily-log << 'EOF'
server {
    listen 80 default_server;
    server_name _;
    
    root /opt/daily-log-system/frontend/public;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location /api/ {
        proxy_pass http://localhost:3001/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF"

pct exec "$CONTAINER_ID" -- bash -c "
    ln -sf /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx
"

# Starta Grafana
log "Startar Grafana..."
pct exec "$CONTAINER_ID" -- bash -c "systemctl enable grafana-server && systemctl start grafana-server"

sleep 5
CONTAINER_IP=$(pct exec "$CONTAINER_ID" -- hostname -I | awk '{print $1}')

# Slutrapport
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}         Installation Slutförd! 🎉${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Container Info:${NC}"
echo -e "  ID:  ${GREEN}${CONTAINER_ID}${NC}"
echo -e "  IP:  ${GREEN}${CONTAINER_IP}${NC}"
echo ""
echo -e "${BLUE}Åtkomst:${NC}"
echo -e "  ${GREEN}✓${NC} Webbgränssnitt: ${YELLOW}http://${CONTAINER_IP}${NC}"
echo -e "  ${GREEN}✓${NC} Grafana:        ${YELLOW}http://${CONTAINER_IP}:3000${NC}"
echo -e "      → Användarnamn: ${YELLOW}admin${NC}"
echo -e "      → Lösenord:     ${YELLOW}admin${NC} ${RED}(ändra direkt!)${NC}"
echo ""
echo -e "${BLUE}Användbara kommandon:${NC}"
echo -e "  ${YELLOW}pct enter ${CONTAINER_ID}${NC}      - Logga in i container"
echo -e "  ${YELLOW}pct exec ${CONTAINER_ID} -- pm2 logs${NC}  - Se backend-loggar"
echo -e "  ${YELLOW}pct stop ${CONTAINER_ID}${NC}       - Stoppa container"
echo -e "  ${YELLOW}pct start ${CONTAINER_ID}${NC}      - Starta container"
echo ""
echo -e "${GREEN}Lycka till! 🚀${NC}"
echo ""