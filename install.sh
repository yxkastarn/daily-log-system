#!/bin/bash#!/bin/bash



# Daily Log System - Installation Script# Daily Log System - Installation Script

# Author: yxkastarn# Author: yxkastarn

# Version: 2.0# Version: 2.0



set -eset -e



# Colors for output# Colors for output

RED='\033[0;31m'RED='\033[0;31m'

GREEN='\033[0;32m'GREEN='\033[0;32m'

YELLOW='\033[1;33m'YELLOW='\033[1;33m'

BLUE='\033[0;34m'BLUE='\033[0;34m'

NC='\033[0m'NC='\033[0m'



# Default values# Default values

DEFAULT_MEMORY=2048DEFAULT_MEMORY=2048

DEFAULT_DISK_SIZE=8DEFAULT_DISK_SIZE=8

DEFAULT_STORAGE="local-lvm"DEFAULT_STORAGE="local-lvm"

DEFAULT_NETWORK="vmbr0"DEFAULT_NETWORK="vmbr0"

DEFAULT_HOSTNAME="daily-log"DEFAULT_HOSTNAME="daily-log"

TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"

REPO_URL="https://github.com/yxkastarn/daily-log-system.git"REPO_URL="https://github.com/yxkastarn/daily-log-system.git"

RAW_URL="https://raw.githubusercontent.com/yxkastarn/daily-log-system/main"RAW_URL="https://raw.githubusercontent.com/yxkastarn/daily-log-system/main"



# Database configuration# Database configuration

DB_NAME="daily_log"DB_NAME="daily_log"

DB_USER="dailylog"DB_USER="dailylog"

DB_PASSWORD="dailylog123"DB_PASSWORD="dailylog123"



# Logging functions# Logging functions

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }

log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

log_error() { echo -e "${RED}[ERROR]${NC} $1"; }log_error() { echo -e "${RED}[ERROR]${NC} $1"; }



# Print usage information# Print usage information

show_usage() {show_usage() {

    cat << EOF    cat << EOF

Användning: $0 [OPTIONS] CONTAINER_IDAnvändning: $0 [OPTIONS] CONTAINER_ID



Detta script installerar Daily Log System i en Proxmox LXC container.Detta script installerar Daily Log System i en Proxmox LXC container.



Obligatoriska argument:Obligatoriska argument:

    CONTAINER_ID        ID för containern (100-999999)    CONTAINER_ID        ID för containern (100-999999)



Tillgängliga options:Tillgängliga options:

    -m, --memory       Minnesstorlek i MB (default: ${DEFAULT_MEMORY})    -m, --memory       Minnesstorlek i MB (default: ${DEFAULT_MEMORY})

    -d, --disk        Diskstorlek i GB (default: ${DEFAULT_DISK_SIZE})    -d, --disk        Diskstorlek i GB (default: ${DEFAULT_DISK_SIZE})

    -s, --storage     Lagringsenhet (default: ${DEFAULT_STORAGE})    -s, --storage     Lagringsenhet (default: ${DEFAULT_STORAGE})

    -n, --network     Nätverksbrygga (default: ${DEFAULT_NETWORK})    -n, --network     Nätverksbrygga (default: ${DEFAULT_NETWORK})

    -h, --hostname    Värdnamn för containern (default: ${DEFAULT_HOSTNAME})    -h, --hostname    Värdnamn för containern (default: ${DEFAULT_HOSTNAME})

    --help           Visa denna hjälptext    --help           Visa denna hjälptext



Exempel:Exempel:

    $0 101    $0 101

    $0 -m 4096 -d 16 102    $0 -m 4096 -d 16 102

    $0 --memory 8192 --disk 32 --hostname custom-daily-log 103    $0 --memory 8192 --disk 32 --hostname custom-daily-log 103

EOFEOF

}}



# Validate environment and prerequisitescheck_root() {

check_prerequisites() {    if [[ $EUID -ne 0 ]]; then

    # Check if running as root        log_error "Detta script mÃ¥ste kÃ¶ras som root"

    if [[ $EUID -ne 0 ]]; then        exit 1

        log_error "Detta script måste köras som root"    fi

        exit 1}

    fi

check_proxmox() {

    # Check if running on Proxmox    if ! command -v pct &> /dev/null; then

    if ! command -v pct &> /dev/null; then        log_error "Proxmox (pct) hittades inte."

        log_error "Proxmox VE (pct) hittades inte. Är detta en Proxmox server?"        exit 1

        exit 1    fi

    fi}



    # Check if curl is installedcheck_vmid() {

    if ! command -v curl &> /dev/null; then    local vmid=$1

        log_error "curl krävs men är inte installerat"    if [[ -z "$vmid" ]]; then

        exit 1        log_error "Du måste ange ett container ID som argument. Exempel: ./install.sh 100"

    fi        exit 1

}    fi

    

# Validate container ID    if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then

validate_container_id() {        log_error "Container ID måste vara ett nummer"

    local id=$1        exit 1

        fi

    if ! [[ "$id" =~ ^[0-9]+$ ]]; then    

        log_error "Container ID måste vara ett nummer"    if pvesh get /cluster/resources --type vm --output-format json | grep -q "\"vmid\":$vmid"; then

        show_usage        log_error "Container ID $vmid är redan i användning"

        exit 1        exit 1

    fi    fi

    

    if [[ "$id" -lt 100 || "$id" -gt 999999 ]]; then    return 0

        log_error "Container ID måste vara mellan 100 och 999999"}

        exit 1

    fidownload_template() {

    log_info "Kontrollerar LXC template..."

    if pvesh get /cluster/resources --type vm --output-format json | grep -q "\"vmid\":$id"; then    if pveam list local | grep -q "$TEMPLATE"; then

        log_error "Container ID $id är redan i användning"        log_info "Template finns redan"

        exit 1        return 0

    }    fi

}    log_info "Laddar ner Ubuntu 22.04 template..."

    pveam update

# Check and download template    pveam download local "$TEMPLATE"

prepare_template() {}

    log_info "Kontrollerar LXC template..."

    if ! pveam list local | grep -q "$TEMPLATE"; thenensure_files_exist() {

        log_info "Laddar ner Ubuntu 22.04 template..."    local cid=$1

        pveam update    log_info "SÃ¤kerstÃ¤ller att alla filer finns..."

        pveam download local "$TEMPLATE" || {    

            log_error "Kunde inte ladda ner template"    # Kontrollera schema.sql

            exit 1    if ! pct exec $cid -- test -f /opt/daily-log-system/database/schema.sql; then

        }        log_warn "schema.sql saknas, hÃ¤mtar frÃ¥n GitHub..."

    else        pct exec $cid -- bash -c "curl -sL ${RAW_URL}/database/schema.sql -o /opt/daily-log-system/database/schema.sql"

        log_info "Template finns redan"    fi

    fi    

}    # Kontrollera index.html

    if ! pct exec $cid -- test -f /opt/daily-log-system/frontend/public/index.html; then

# Create and start container        log_warn "index.html saknas, hÃ¤mtar frÃ¥n GitHub..."

create_container() {        pct exec $cid -- bash -c "curl -sL ${RAW_URL}/frontend/public/index.html -o /opt/daily-log-system/frontend/public/index.html"

    local id=$1    fi

    local memory=$2    

    local disk=$3    # Kontrollera nginx.conf

    local storage=$4    if ! pct exec $cid -- test -f /opt/daily-log-system/nginx.conf; then

    local network=$5        log_warn "nginx.conf saknas, hÃ¤mtar frÃ¥n GitHub..."

    local hostname=$6        pct exec $cid -- bash -c "curl -sL ${RAW_URL}/nginx.conf -o /opt/daily-log-system/nginx.conf"

    fi

    log_info "Skapar LXC container..."    

    local template_path="local:vztmpl/$TEMPLATE"    log_info "âœ“ Alla nÃ¶dvÃ¤ndiga filer finns"

    }

    pct create "$id" "$template_path" \

        --hostname "$hostname" \main() {

        --memory "$memory" \    echo -e "${BLUE}â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—"

        --net0 "name=eth0,bridge=$network,ip=dhcp" \    echo "â•‘         Daily Log System - Proxmox Installation           â•‘"

        --rootfs "$storage:$disk" \    echo "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"

        --features "nesting=1" \    

        --unprivileged 1 \    check_root

        --onboot 1 || {    check_proxmox

            log_error "Kunde inte skapa containern"    

            exit 1    CONTAINER_ID="$1"

        }    check_vmid "$CONTAINER_ID"

    log_info "Använder container ID: ${BLUE}${CONTAINER_ID}${NC}"

    log_info "Startar container..."    

    pct start "$id"    download_template

    sleep 10    

}    log_info "Skapar LXC container..."

    TEMPLATE_PATH="local:vztmpl/$TEMPLATE"

# Install required packages    pct create "$CONTAINER_ID" "$TEMPLATE_PATH" --hostname "$CONTAINER_NAME" --memory "$MEMORY" --net0 "name=eth0,bridge=$NETWORK,ip=dhcp" --rootfs "$STORAGE:$DISK_SIZE" --features "nesting=1" --unprivileged 1 --onboot 1

install_packages() {    

    local id=$1    log_info "Startar container..."

        pct start "$CONTAINER_ID"

    log_info "Installerar systempaket..."    sleep 10

    pct exec "$id" -- bash -c "DEBIAN_FRONTEND=noninteractive apt update && apt upgrade -y"    

    pct exec "$id" -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y \    log_info "Installerar paket (detta tar nÃ¥gra minuter)..."

        curl wget git nano sudo \    pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt update && apt upgrade -y"

        postgresql postgresql-contrib \    pct exec "$CONTAINER_ID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y curl wget git nano sudo postgresql postgresql-contrib nginx software-properties-common apt-transport-https gnupg"

        nginx software-properties-common \    

        apt-transport-https gnupg"    log_info "Installerar Node.js 18..."

    pct exec $CONTAINER_ID -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"

    log_info "Installerar Node.js 18..."    pct exec $CONTAINER_ID -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y nodejs"

    pct exec "$id" -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"    pct exec $CONTAINER_ID -- bash -c "npm install -g pm2"

    pct exec "$id" -- bash -c "DEBIAN_FRONTEND=noninteractive apt install -y nodejs"    

    pct exec "$id" -- bash -c "npm install -g pm2"    log_info "Installerar Grafana..."

    pct exec $CONTAINER_ID -- bash -c "mkdir -p /etc/apt/keyrings/"

    log_info "Installerar Grafana..."    pct exec $CONTAINER_ID -- bash -c "wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg"

    pct exec "$id" -- bash -c "mkdir -p /etc/apt/keyrings/"    pct exec $CONTAINER_ID -- bash -c "echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list"

    pct exec "$id" -- bash -c "wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg"    pct exec $CONTAINER_ID -- bash -c "apt update && DEBIAN_FRONTEND=noninteractive apt install -y grafana"

    pct exec "$id" -- bash -c "echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list"    

    pct exec "$id" -- bash -c "apt update && DEBIAN_FRONTEND=noninteractive apt install -y grafana"    log_info "Klonar repository frÃ¥n GitHub..."

}    pct exec $CONTAINER_ID -- bash -c "cd /opt && git clone $REPO_URL"

    

# Configure PostgreSQL    log_info "Skapar katalogstruktur..."

setup_database() {    pct exec $CONTAINER_ID -- bash -c "mkdir -p /opt/daily-log-system/database /opt/daily-log-system/frontend/public /opt/daily-log-system/grafana /opt/daily-log-system/scripts"

    local id=$1    

        # SÃ¤kerstÃ¤ll att alla filer finns (hÃ¤mtar frÃ¥n GitHub om de saknas)

    log_info "Konfigurerar PostgreSQL..."    ensure_files_exist $CONTAINER_ID

    pct exec "$id" -- bash -c "sudo -u postgres psql -c \"CREATE DATABASE $DB_NAME;\""    

    pct exec "$id" -- bash -c "sudo -u postgres psql -c \"CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';\""    log_info "Konfigurerar PostgreSQL..."

    pct exec "$id" -- bash -c "sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;\""    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"CREATE DATABASE daily_log;\""

    pct exec "$id" -- bash -c "sudo -u postgres psql -d $DB_NAME -c \"GRANT ALL ON SCHEMA public TO $DB_USER;\""    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"CREATE USER dailylog WITH PASSWORD 'dailylog123';\""

}    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE daily_log TO dailylog;\""

    pct exec $CONTAINER_ID -- bash -c "sudo -u postgres psql -d daily_log -c \"GRANT ALL ON SCHEMA public TO dailylog;\""

# Setup application    

setup_application() {    log_info "Installerar backend dependencies..."

    local id=$1    pct exec "$CONTAINER_ID" -- bash -c "cd /opt/daily-log-system/backend && npm install"

        

    log_info "Klonar repository från GitHub..."    log_info "Konfigurerar backend..."

    pct exec "$id" -- bash -c "cd /opt && git clone $REPO_URL"    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && cp .env.example .env"

        

    log_info "Skapar katalogstruktur..."    log_info "KÃ¶r databas-migrationer..."

    pct exec "$id" -- bash -c "mkdir -p /opt/daily-log-system/{database,frontend/public,grafana,scripts}"    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && npm run migrate"

    

    log_info "Hämtar konfigurationsfiler..."    log_info "Startar backend API..."

    pct exec "$id" -- bash -c "curl -sL ${RAW_URL}/database/schema.sql -o /opt/daily-log-system/database/schema.sql"    pct exec $CONTAINER_ID -- bash -c "cd /opt/daily-log-system/backend && pm2 start server.js --name daily-log-api"

    pct exec "$id" -- bash -c "curl -sL ${RAW_URL}/frontend/public/index.html -o /opt/daily-log-system/frontend/public/index.html"    pct exec $CONTAINER_ID -- bash -c "pm2 startup systemd -u root --hp /root"

    pct exec "$id" -- bash -c "curl -sL ${RAW_URL}/nginx.conf -o /opt/daily-log-system/nginx.conf"    pct exec $CONTAINER_ID -- bash -c "pm2 save"

    

    log_info "Installerar backend dependencies..."    log_info "Konfigurerar Nginx..."

    pct exec "$id" -- bash -c "cd /opt/daily-log-system/backend && npm install"    pct exec $CONTAINER_ID -- bash -c "cp /opt/daily-log-system/nginx.conf /etc/nginx/sites-available/daily-log"

    pct exec "$id" -- bash -c "cd /opt/daily-log-system/backend && cp .env.example .env"    pct exec $CONTAINER_ID -- bash -c "ln -sf /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/"

    pct exec $CONTAINER_ID -- bash -c "rm -f /etc/nginx/sites-enabled/default"

    log_info "Kör databas-migrationer..."    pct exec $CONTAINER_ID -- bash -c "nginx -t && systemctl reload nginx"

    pct exec "$id" -- bash -c "cd /opt/daily-log-system/backend && npm run migrate"    

}    log_info "Startar Grafana..."

    pct exec $CONTAINER_ID -- bash -c "systemctl enable grafana-server"

# Configure services    pct exec $CONTAINER_ID -- bash -c "systemctl start grafana-server"

configure_services() {    

    local id=$1    sleep 10

        CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I | awk '{print $1}')

    log_info "Startar backend API..."    

    pct exec "$id" -- bash -c "cd /opt/daily-log-system/backend && pm2 start server.js --name daily-log-api"    echo ""

    pct exec "$id" -- bash -c "pm2 startup systemd -u root --hp /root"    echo -e "${GREEN}â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—"

    pct exec "$id" -- bash -c "pm2 save"    echo "â•‘              Installation SlutfÃ¶rd! ðŸŽ‰                     â•‘"

    echo "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"

    log_info "Konfigurerar Nginx..."    echo ""

    pct exec "$id" -- bash -c "cp /opt/daily-log-system/nginx.conf /etc/nginx/sites-available/daily-log"    echo -e "${BLUE}Container Information:${NC}"

    pct exec "$id" -- bash -c "ln -sf /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/"    echo -e "  ID: ${GREEN}${CONTAINER_ID}${NC}"

    pct exec "$id" -- bash -c "rm -f /etc/nginx/sites-enabled/default"    echo -e "  IP: ${GREEN}${CONTAINER_IP}${NC}"

    pct exec "$id" -- bash -c "nginx -t && systemctl reload nginx"    echo ""

    echo -e "${BLUE}Ã…tkomst:${NC}"

    log_info "Startar Grafana..."    echo -e "  ${GREEN}âœ“${NC} WebbgrÃ¤nssnitt: ${YELLOW}http://${CONTAINER_IP}${NC}"

    pct exec "$id" -- bash -c "systemctl enable grafana-server"    echo -e "  ${GREEN}âœ“${NC} Grafana:        ${YELLOW}http://${CONTAINER_IP}:3000${NC}"

    pct exec "$id" -- bash -c "systemctl start grafana-server"    echo -e "      - AnvÃ¤ndarnamn: ${YELLOW}admin${NC}"

}    echo -e "      - LÃ¶senord:     ${YELLOW}admin${NC} ${RED}(Ã¤ndra vid fÃ¶rsta inloggningen!)${NC}"

    echo ""

# Show completion message    echo -e "${BLUE}NÃ¤sta steg:${NC}"

show_completion() {    echo "  1. Ã–ppna webbgrÃ¤nssnittet och registrera din fÃ¶rsta aktivitet"

    local id=$1    echo "  2. Logga in pÃ¥ Grafana och utforska dashboards"

    local ip=$(pct exec "$id" -- hostname -I | awk '{print $1}')    echo "  3. Ã„ndra standardlÃ¶senord fÃ¶r Grafana"

        echo ""

    cat << EOF    echo -e "${BLUE}AnvÃ¤ndbara kommandon:${NC}"

    echo -e "  Logga in i container: ${YELLOW}pct enter ${CONTAINER_ID}${NC}"

${GREEN}╔════════════════════════════════════════════════════════════╗    echo -e "  Se backend-loggar:    ${YELLOW}pct exec ${CONTAINER_ID} -- pm2 logs${NC}"

║              Installation Slutförd! 🎉                     ║    echo -e "  Stoppa container:     ${YELLOW}pct stop ${CONTAINER_ID}${NC}"

╚════════════════════════════════════════════════════════════╝${NC}    echo -e "  Starta container:     ${YELLOW}pct start ${CONTAINER_ID}${NC}"

    echo ""

${BLUE}Container Information:${NC}    echo -e "${GREEN}Lycka till med Daily Log System! ðŸš€${NC}"

  ID: ${GREEN}${id}${NC}    echo ""

  IP: ${GREEN}${ip}${NC}}



${BLUE}Åtkomst:${NC}main "$@"

  ${GREEN}✓${NC} Webbgränssnitt: ${YELLOW}http://${ip}${NC}
  ${GREEN}✓${NC} Grafana:        ${YELLOW}http://${ip}:3000${NC}
      - Användarnamn: ${YELLOW}admin${NC}
      - Lösenord:     ${YELLOW}admin${NC} ${RED}(ändra vid första inloggningen!)${NC}

${BLUE}Nästa steg:${NC}
  1. Öppna webbgränssnittet och registrera din första aktivitet
  2. Logga in på Grafana och utforska dashboards
  3. Ändra standardlösenord för Grafana

${BLUE}Användbara kommandon:${NC}
  Logga in i container: ${YELLOW}pct enter ${id}${NC}
  Se backend-loggar:    ${YELLOW}pct exec ${id} -- pm2 logs${NC}
  Stoppa container:     ${YELLOW}pct stop ${id}${NC}
  Starta container:     ${YELLOW}pct start ${id}${NC}

${GREEN}Lycka till med Daily Log System! 🚀${NC}
EOF
}

# Main installation process
main() {
    local memory=$DEFAULT_MEMORY
    local disk=$DEFAULT_DISK_SIZE
    local storage=$DEFAULT_STORAGE
    local network=$DEFAULT_NETWORK
    local hostname=$DEFAULT_HOSTNAME
    local container_id=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--memory)
                memory="$2"
                shift 2
                ;;
            -d|--disk)
                disk="$2"
                shift 2
                ;;
            -s|--storage)
                storage="$2"
                shift 2
                ;;
            -n|--network)
                network="$2"
                shift 2
                ;;
            -h|--hostname)
                hostname="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Okänd option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$container_id" ]]; then
                    container_id="$1"
                else
                    log_error "För många argument"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$container_id" ]]; then
        log_error "Container ID måste anges"
        show_usage
        exit 1
    fi

    # Run installation steps
    check_prerequisites
    validate_container_id "$container_id"
    prepare_template
    create_container "$container_id" "$memory" "$disk" "$storage" "$network" "$hostname"
    install_packages "$container_id"
    setup_database "$container_id"
    setup_application "$container_id"
    configure_services "$container_id"
    show_completion "$container_id"
}

main "$@"