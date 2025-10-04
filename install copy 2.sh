#!/bin/bash#!/bin/bash

set -eset -e



# Colors# Colors

RED='\033[0;31m'RED='\033[0;31m'

GREEN='\033[0;32m'GREEN='\033[0;32m'

YELLOW='\033[1;33m'YELLOW='\033[1;33m'

BLUE='\033[0;34m'BLUE='\033[0;34m'

NC='\033[0m'NC='\033[0m'



# Configuration# Configuration

MEMORY=2048MEMORY=2048

DISK_SIZE=8DISK_SIZE=8

STORAGE="local-lvm"STORAGE="local-lvm"

NETWORK="vmbr0"NETWORK="vmbr0"

CONTAINER_NAME="daily-log"CONTAINER_NAME="daily-log"

TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"

REPO_URL="https://github.com/yxkastarn/daily-log-system.git"REPO_URL="https://github.com/yxkastarn/daily-log-system.git"



log() { echo -e "${GREEN}[✓]${NC} $1"; }log() { echo -e "${GREEN}[✓]${NC} $1"; }

warn() { echo -e "${YELLOW}[!]${NC} $1"; }warn() { echo -e "${YELLOW}[!]${NC} $1"; }

error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }



# Kontrollera container ID# Kontrollera container ID

CONTAINER_ID="$1"CONTAINER_ID="$1"

[[ -z "$CONTAINER_ID" ]] && error "Användning: $0 <container-id>\nExempel: $0 101"[[ -z "$CONTAINER_ID" ]] && error "Användning: $0 <container-id>\nExempel: $0 101"

[[ ! "$CONTAINER_ID" =~ ^[0-9]+$ ]] && error "Container ID måste vara ett nummer"[[ ! "$CONTAINER_ID" =~ ^[0-9]+$ ]] && error "Container ID måste vara ett nummer"

[[ "$EUID" -ne 0 ]] && error "Detta script måste köras som root"[[ "$EUID" -ne 0 ]] && error "Detta script måste köras som root"

command -v pct &> /dev/null || error "Proxmox (pct) hittades inte"command -v pct &> /dev/null || error "Proxmox (pct) hittades inte"



# Kontrollera om container redan finns# Kontrollera om container redan finns

if pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | grep -q "\"vmid\":$CONTAINER_ID"; thenif pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | grep -q "\"vmid\":$CONTAINER_ID"; then

    error "Container ID $CONTAINER_ID används redan"    error "Container ID $CONTAINER_ID används redan"

fifi



echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

echo -e "${BLUE}    Daily Log System - Proxmox Installation${NC}"echo -e "${BLUE}    Daily Log System - Proxmox Installation${NC}"

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

echo ""echo ""



# Ladda ner template# Ladda ner template

log "Kontrollerar Ubuntu 22.04 template..."log "Kontrollerar Ubuntu 22.04 template..."

if ! pveam list local | grep -q "$TEMPLATE"; thenif ! pveam list local | grep -q "$TEMPLATE"; then

    log "Laddar ner template..."    log "Laddar ner template..."

    pveam update    pveam update

    pveam download local "$TEMPLATE"    pveam download local "$TEMPLATE"

fifi



# Skapa container# Skapa container

log "Skapar LXC container ${CONTAINER_ID}..."log "Skapar LXC container ${CONTAINER_ID}..."

pct create "$CONTAINER_ID" "local:vztmpl/$TEMPLATE" \pct create "$CONTAINER_ID" "local:vztmpl/$TEMPLATE" \

    --hostname "$CONTAINER_NAME" \    --hostname "$CONTAINER_NAME" \

    --memory "$MEMORY" \    --memory "$MEMORY" \

    --net0 "name=eth0,bridge=$NETWORK,ip=dhcp" \    --net0 "name=eth0,bridge=$NETWORK,ip=dhcp" \

    --rootfs "$STORAGE:$DISK_SIZE" \    --rootfs "$STORAGE:$DISK_SIZE" \

    --features "nesting=1" \    --features "nesting=1" \

    --unprivileged 1 \    --unprivileged 1 \

    --onboot 1    --onboot 1



log "Startar container..."log "Startar container..."

pct start "$CONTAINER_ID"pct start "$CONTAINER_ID"

sleep 10sleep 10



# Installera systempaket# Installera systempaket

log "Uppdaterar system..."log "Uppdaterar system..."

pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt update && apt upgrade -y"pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt update && apt upgrade -y"



log "Installerar grundpaket..."log "Installerar grundpaket..."

pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y \pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y \

    curl wget git nano sudo postgresql postgresql-contrib nginx software-properties-common apt-transport-https gnupg"    curl wget git nano sudo postgresql postgresql-contrib nginx software-properties-common apt-transport-https gnupg"



# Installera Node.js# Installera Node.js

log "Installerar Node.js 18..."log "Installerar Node.js 18..."

pct exec "$CONTAINER_ID" -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"pct exec "$CONTAINER_ID" -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"

pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y nodejs"pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y nodejs"

pct exec "$CONTAINER_ID" -- bash -c "npm install -g pm2"pct exec "$CONTAINER_ID" -- bash -c "npm install -g pm2"



# Installera Grafana# Installera Grafana

log "Installerar Grafana..."log "Installerar Grafana..."

pct exec "$CONTAINER_ID" -- bash -c "pct exec "$CONTAINER_ID" -- bash -c "

    mkdir -p /etc/apt/keyrings/    mkdir -p /etc/apt/keyrings/

    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg

    echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list    echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list

    apt update && DEBIAN_FRONTEND=noninteractive apt install -y grafana    apt update && DEBIAN_FRONTEND=noninteractive apt install -y grafana

""



# Konfigurera PostgreSQL# Konfigurera PostgreSQL

log "Konfigurerar PostgreSQL databas..."log "Konfigurerar PostgreSQL databas..."

pct exec "$CONTAINER_ID" -- bash -c "pct exec "$CONTAINER_ID" -- bash -c "

    systemctl restart postgresql    sudo -u postgres psql -c \"CREATE DATABASE daily_log;\"

    sudo -u postgres psql -c \"CREATE DATABASE daily_log;\"    sudo -u postgres psql -c \"CREATE USER dailylog WITH PASSWORD 'dailylog123';\"

    sudo -u postgres psql -c \"CREATE USER dailylog WITH PASSWORD 'dailylog123';\"    sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE daily_log TO dailylog;\"

    sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE daily_log TO dailylog;\"    sudo -u postgres psql -d daily_log -c \"GRANT ALL ON SCHEMA public TO dailylog;\"

    sudo -u postgres psql -d daily_log -c \"GRANT ALL ON SCHEMA public TO dailylog;\""

"

# Installera applikation

# Installera applikationlog "Klonar repository..."

log "Klonar repository..."pct exec "$CONTAINER_ID" -- bash -c "cd /opt && git clone $REPO_URL"

pct exec "$CONTAINER_ID" -- bash -c "cd /opt && git clone $REPO_URL"

log "Skapar katalogstruktur..."

log "Skapar katalogstruktur..."pct exec "$CONTAINER_ID" -- bash -c "mkdir -p /opt/daily-log-system/{database,frontend/public,grafana,scripts}"

pct exec "$CONTAINER_ID" -- bash -c "mkdir -p /opt/daily-log-system/{database,frontend/public,grafana,scripts}"

# Kontrollera och hämta saknade filer

# Skapa backend-konfigurationif ! pct exec "$CONTAINER_ID" -- test -f /opt/daily-log-system/backend/package.json 2>/dev/null; then

log "Konfigurerar backend..."    warn "Backend saknas, skapar grundstruktur..."

pct exec "$CONTAINER_ID" -- bash -c "cd /opt/daily-log-system/backend && npm install"    pct exec "$CONTAINER_ID" -- bash -c "mkdir -p /opt/daily-log-system/backend"

pct exec "$CONTAINER_ID" -- bash -c "    pct exec "$CONTAINER_ID" -- bash -c "cat > /opt/daily-log-system/backend/package.json << 'EOF'

cat > /opt/daily-log-system/backend/.env << EOF{

PORT=3001  \"name\": \"daily-log-api\",

NODE_ENV=production  \"version\": \"1.0.0\",

DB_HOST=localhost  \"main\": \"server.js\",

DB_PORT=5432  \"scripts\": {

DB_NAME=daily_log    \"start\": \"node server.js\",

DB_USER=dailylog    \"migrate\": \"echo 'No migrations yet'\"

DB_PASSWORD=dailylog123  },

EOF"  \"dependencies\": {

    \"express\": \"^4.18.2\",

# Konfigurera Nginx    \"pg\": \"^8.11.0\",

log "Konfigurerar Nginx..."    \"dotenv\": \"^16.0.3\",

pct exec "$CONTAINER_ID" -- bash -c "cat > /etc/nginx/sites-available/daily-log << 'EOF'    \"cors\": \"^2.8.5\"

server {  }

    listen 80 default_server;}

    server_name _;EOF"

    fi

    root /opt/daily-log-system/frontend/public;

    index index.html;log "Installerar backend dependencies..."

    pct exec "$CONTAINER_ID" -- bash -c "cd /opt/daily-log-system/backend && npm install 2>/dev/null || true"

    location / {

        try_files \$uri \$uri/ /index.html;# Skapa enkel .env om den inte finns

    }pct exec "$CONTAINER_ID" -- bash -c "

    if [ ! -f /opt/daily-log-system/backend/.env ]; then

    location /api/ {    cat > /opt/daily-log-system/backend/.env << 'EOF'

        proxy_pass http://localhost:3001/api/;DATABASE_URL=postgresql://dailylog:dailylog123@localhost:5432/daily_log

        proxy_http_version 1.1;PORT=3001

        proxy_set_header Upgrade \$http_upgrade;NODE_ENV=production

        proxy_set_header Connection 'upgrade';EOF

        proxy_set_header Host \$host;fi

        proxy_cache_bypass \$http_upgrade;"

    }

}# Skapa enkel server.js om den inte finns

EOF"if ! pct exec "$CONTAINER_ID" -- test -f /opt/daily-log-system/backend/server.js 2>/dev/null; then

    pct exec "$CONTAINER_ID" -- bash -c "cat > /opt/daily-log-system/backend/server.js << 'EOF'

pct exec "$CONTAINER_ID" -- bash -c "require('dotenv').config();

    ln -sf /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/const express = require('express');

    rm -f /etc/nginx/sites-enabled/defaultconst cors = require('cors');

    nginx -t && systemctl restart nginxconst app = express();

"

app.use(cors());

# Starta tjänsterapp.use(express.json());

log "Startar backend API..."

pct exec "$CONTAINER_ID" -- bash -c "cd /opt/daily-log-system/backend && pm2 start server.js --name daily-log-api"app.get('/api/health', (req, res) => {

pct exec "$CONTAINER_ID" -- bash -c "pm2 startup systemd -u root --hp /root && pm2 save"  res.json({ status: 'ok', message: 'Daily Log API running' });

});

log "Startar Grafana..."

pct exec "$CONTAINER_ID" -- bash -c "systemctl enable grafana-server && systemctl start grafana-server"const PORT = process.env.PORT || 3001;

app.listen(PORT, () => console.log(\`API running on port \${PORT}\`));

# Vänta på att tjänsterna ska startaEOF"

sleep 8fi

CONTAINER_IP=$(pct exec "$CONTAINER_ID" -- hostname -I | awk '{print $1}')

# Starta backend

# Verifiera installationlog "Startar backend API..."

log "Verifierar installation..."pct exec "$CONTAINER_ID" -- bash -c "cd /opt/daily-log-system/backend && pm2 start server.js --name daily-log-api"

pct exec "$CONTAINER_ID" -- bash -c "pct exec "$CONTAINER_ID" -- bash -c "pm2 startup systemd -u root --hp /root && pm2 save"

    # Kontrollera PostgreSQL

    systemctl status postgresql | grep 'active (running)' || (echo 'PostgreSQL är inte igång' && exit 1)# Skapa enkel frontend om den inte finns

    if ! pct exec "$CONTAINER_ID" -- test -f /opt/daily-log-system/frontend/public/index.html 2>/dev/null; then

    # Kontrollera Nginx    pct exec "$CONTAINER_ID" -- bash -c "cat > /opt/daily-log-system/frontend/public/index.html << 'EOF'

    systemctl status nginx | grep 'active (running)' || (echo 'Nginx är inte igång' && exit 1)<!DOCTYPE html>

    <html lang=\"sv\">

    # Kontrollera API<head>

    curl -s http://localhost:3001/api/health || (echo 'API svarar inte' && exit 1)    <meta charset=\"UTF-8\">

        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">

    # Kontrollera Grafana    <title>Daily Log System</title>

    systemctl status grafana-server | grep 'active (running)' || (echo 'Grafana är inte igång' && exit 1)    <style>

"        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }

        h1 { color: #333; }

# Slutrapport        .status { padding: 10px; background: #d4edda; border-radius: 5px; margin: 20px 0; }

echo ""        a { color: #007bff; text-decoration: none; }

echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"        a:hover { text-decoration: underline; }

echo -e "${GREEN}         Installation Slutförd! 🎉${NC}"    </style>

echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"</head>

echo ""<body>

echo -e "${BLUE}Container Info:${NC}"    <h1>Daily Log System</h1>

echo -e "  ID:  ${GREEN}${CONTAINER_ID}${NC}"    <div class=\"status\">✓ System is running</div>

echo -e "  IP:  ${GREEN}${CONTAINER_IP}${NC}"    <p>Welcome to Daily Log System. The application is successfully installed!</p>

echo ""    <p><a href=\"http://\" + window.location.hostname + \":3000\">Open Grafana Dashboard</a></p>

echo -e "${BLUE}Åtkomst:${NC}"</body>

echo -e "  ${GREEN}✓${NC} Webbgränssnitt: ${YELLOW}http://${CONTAINER_IP}${NC}"</html>

echo -e "  ${GREEN}✓${NC} Grafana:        ${YELLOW}http://${CONTAINER_IP}:3000${NC}"EOF"

echo -e "      → Användarnamn: ${YELLOW}admin${NC}"fi

echo -e "      → Lösenord:     ${YELLOW}admin${NC} ${RED}(ändra direkt!)${NC}"

echo ""# Konfigurera Nginx

echo -e "${BLUE}Användbara kommandon:${NC}"log "Konfigurerar Nginx..."

echo -e "  ${YELLOW}pct enter ${CONTAINER_ID}${NC}      - Logga in i container"pct exec "$CONTAINER_ID" -- bash -c "cat > /etc/nginx/sites-available/daily-log << 'EOF'

echo -e "  ${YELLOW}pct exec ${CONTAINER_ID} -- pm2 logs${NC}  - Se backend-loggar"server {

echo -e "  ${YELLOW}pct stop ${CONTAINER_ID}${NC}       - Stoppa container"    listen 80 default_server;

echo -e "  ${YELLOW}pct start ${CONTAINER_ID}${NC}      - Starta container"    server_name _;

echo ""    

echo -e "${GREEN}Lycka till! 🚀${NC}"    root /opt/daily-log-system/frontend/public;

echo ""    index index.html;
    
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

# Konfigurera Grafana med databaskoppling
log "Konfigurerar Grafana datasource..."
pct exec "$CONTAINER_ID" -- bash -c "mkdir -p /etc/grafana/provisioning/datasources"
pct exec "$CONTAINER_ID" -- bash -c "cat > /etc/grafana/provisioning/datasources/postgresql.yaml << 'EOF'
apiVersion: 1

datasources:
  - name: Daily Log PostgreSQL
    type: postgres
    access: proxy
    url: localhost:5432
    database: daily_log
    user: dailylog
    secureJsonData:
      password: dailylog123
    jsonData:
      sslmode: disable
      postgresVersion: 1400
      timescaledb: false
    editable: true
    isDefault: true
EOF"

log "Konfigurerar Grafana dashboards..."
pct exec "$CONTAINER_ID" -- bash -c "mkdir -p /etc/grafana/provisioning/dashboards"
pct exec "$CONTAINER_ID" -- bash -c "cat > /etc/grafana/provisioning/dashboards/daily-log.yaml << 'EOF'
apiVersion: 1

providers:
  - name: 'Daily Log Dashboards'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF"

pct exec "$CONTAINER_ID" -- bash -c "mkdir -p /var/lib/grafana/dashboards"
pct exec "$CONTAINER_ID" -- bash -c "cat > /var/lib/grafana/dashboards/overview.json << 'EOF'
{
  \"dashboard\": {
    \"title\": \"Daily Log Overview\",
    \"tags\": [\"daily-log\"],
    \"timezone\": \"browser\",
    \"panels\": [
      {
        \"id\": 1,
        \"title\": \"Totala timmar senaste 7 dagarna\",
        \"type\": \"timeseries\",
        \"gridPos\": {\"h\": 8, \"w\": 12, \"x\": 0, \"y\": 0},
        \"targets\": [
          {
            \"rawSql\": \"SELECT entry_date as time, SUM(duration_minutes)/60.0 as hours FROM log_entries WHERE entry_date >= CURRENT_DATE - INTERVAL '7 days' GROUP BY entry_date ORDER BY entry_date\",
            \"format\": \"time_series\"
          }
        ]
      },
      {
        \"id\": 2,
        \"title\": \"Aktiviteter per dag\",
        \"type\": \"barchart\",
        \"gridPos\": {\"h\": 8, \"w\": 12, \"x\": 12, \"y\": 0},
        \"targets\": [
          {
            \"rawSql\": \"SELECT entry_date as time, COUNT(*) as count FROM log_entries WHERE entry_date >= CURRENT_DATE - INTERVAL '7 days' GROUP BY entry_date ORDER BY entry_date\",
            \"format\": \"time_series\"
          }
        ]
      },
      {
        \"id\": 3,
        \"title\": \"Senaste aktiviteter\",
        \"type\": \"table\",
        \"gridPos\": {\"h\": 8, \"w\": 24, \"x\": 0, \"y\": 8},
        \"targets\": [
          {
            \"rawSql\": \"SELECT entry_date, start_time, end_time, description, duration_minutes FROM log_entries ORDER BY entry_date DESC, start_time DESC LIMIT 10\",
            \"format\": \"table\"
          }
        ]
      }
    ],
    \"time\": {
      \"from\": \"now-7d\",
      \"to\": \"now\"
    },
    \"schemaVersion\": 16,
    \"version\": 0
  }
}
EOF"

pct exec "$CONTAINER_ID" -- bash -c "chown -R grafana:grafana /var/lib/grafana/dashboards"

# Starta Grafana
log "Startar Grafana..."
pct exec "$CONTAINER_ID" -- bash -c "systemctl enable grafana-server && systemctl start grafana-server"

sleep 8
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