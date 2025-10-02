# Daily Log System - Proxmox LXC

Ett komplett system för dagliga loggböcker med webbgränssnitt, databas och Grafana-integration.

## Översikt

Detta system är en modern webbapplikation för att spåra dagliga aktiviteter som:
- Registrerar dagliga aktiviteter med datum, tid och beskrivning
- Beräknar arbetstid automatiskt
- Visar historik och statistik i Grafana
- Körs i en Proxmox LXC-container

Systemet är byggt från grunden för att ersätta manuella Excel-baserade loggböcker med en professionell webblösning.

## Snabbinstallation

Kör följande kommando i Proxmox CLI:

```bash
bash <(curl -s https://raw.githubusercontent.com/yxkastarn/daily-log-system/main/install.sh) 108
```

Scriptet kommer att:
1. Skapa en ny LXC-container (Ubuntu 22.04) med ID 108
2. Installera alla beroenden (PostgreSQL, Node.js, Grafana, Nginx)
3. Konfigurera databasen och importera befintlig data
4. Starta alla tjänster

## Åtkomst efter installation

- **Webbgränssnitt**: `http://<container-ip>`
- **Grafana**: `http://<container-ip>:3000`
  - Användarnamn: `admin`
  - Lösenord: `admin` (ändra vid första inloggningen)

## Systemarkitektur

### Komponenter

```
┌─────────────────────────────────────────┐
│         Proxmox LXC Container           │
├─────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐            │
│  │  Nginx   │  │ Grafana  │            │
│  │  :80     │  │  :3000   │            │
│  └────┬─────┘  └────┬─────┘            │
│       │             │                   │
│  ┌────▼─────────────▼─────┐            │
│  │   React Frontend       │            │
│  └────────┬───────────────┘            │
│           │                             │
│  ┌────────▼────────────┐               │
│  │  Node.js Backend    │               │
│  │  Express REST API   │               │
│  └────────┬────────────┘               │
│           │                             │
│  ┌────────▼────────────┐               │
│  │   PostgreSQL DB     │               │
│  └─────────────────────┘               │
└─────────────────────────────────────────┘
```

### Databasschema

```sql
-- Användare
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Dagliga loggposter
CREATE TABLE log_entries (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    entry_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME,
    description TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Projekt (för framtida utökning)
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT
);

-- Dagsammanfattningar
CREATE TABLE daily_summaries (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    entry_date DATE NOT NULL,
    total_hours DECIMAL(4,2),
    lunch_hours DECIMAL(3,2) DEFAULT 0.5,
    work_hours DECIMAL(4,2),
    UNIQUE(user_id, entry_date)
);
```

## API-endpoints

### Loggposter

- `GET /api/entries` - Hämta alla poster (med filter)
- `GET /api/entries/:id` - Hämta specifik post
- `POST /api/entries` - Skapa ny post
- `PUT /api/entries/:id` - Uppdatera post
- `DELETE /api/entries/:id` - Ta bort post

### Sammanfattningar

- `GET /api/summaries/daily` - Daglig sammanfattning
- `GET /api/summaries/weekly` - Veckosammanfattning
- `GET /api/summaries/monthly` - Månadssammanfattning

### Import

- `POST /api/import/bulk` - Bulk-importera poster (JSON-format)

## Grafana Dashboards

Systemet kommer med tre förkonfigurerade dashboards:

### 1. Daglig översikt
- Arbetade timmar per dag
- Aktiviteter i tidssekvens
- Jämförelse med genomsnitt

### 2. Veckorapport
- Total arbetstid per vecka
- Fördelning av aktiviteter
- Trender över tid

### 3. Månadsrapport
- Totala timmar per månad
- Mest frekventa aktiviteter
- Produktivitetsanalys

## Manuell installation

Om du föredrar manuell installation:

### 1. Skapa LXC-container

```bash
pct create 100 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname daily-log \
  --memory 2048 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --storage local-lvm \
  --rootfs local-lvm:8
```

### 2. Starta och logga in

```bash
pct start 100
pct enter 100
```

### 3. Installera beroenden

```bash
apt update && apt upgrade -y
apt install -y postgresql nginx nodejs npm git
npm install -g pm2
```

### 4. Klona repository

```bash
cd /opt
git clone https://github.com/yxkastarn/daily-log-system.git
cd daily-log-system
```

### 5. Installera applikationen

```bash
# Backend
cd backend
npm install
cp .env.example .env
# Redigera .env med databasinställningar
npm run migrate
pm2 start npm --name "daily-log-api" -- start

# Frontend
cd ../frontend
npm install
npm run build

# Konfigurera Nginx
cp ../nginx.conf /etc/nginx/sites-available/daily-log
ln -s /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
```

## Utveckling

### Köra lokalt

```bash
# Backend
cd backend
npm run dev

# Frontend (ny terminal)
cd frontend
npm run dev
```

### Tester

```bash
# Backend-tester
cd backend
npm test

# Frontend-tester
cd frontend
npm test
```

## Backup

### Manuell backup av databas

```bash
pg_dump daily_log > backup_$(date +%Y%m%d).sql
```

### Automatisk backup (konfigureras vid installation)

```bash
# Läggs till i crontab
0 2 * * * /opt/daily-log-system/scripts/backup.sh
```

## Uppdatering

```bash
cd /opt/daily-log-system
git pull
cd backend && npm install && pm2 restart daily-log-api
cd ../frontend && npm install && npm run build
```

## Felsökning

### Kontrollera tjänsternas status

```bash
# Backend API
pm2 status

# Nginx
systemctl status nginx

# PostgreSQL
systemctl status postgresql

# Grafana
systemctl status grafana-server
```

### Loggar

```bash
# Backend-loggar
pm2 logs daily-log-api

# Nginx-loggar
tail -f /var/log/nginx/error.log

# PostgreSQL-loggar
tail -f /var/log/postgresql/postgresql-14-main.log
```

## Säkerhet

- Ändra standardlösenord för Grafana vid första inloggningen
- Konfigurera brandvägg: `ufw enable && ufw allow 80 && ufw allow 3000`
- Överväg SSL/TLS-certifikat för produktion (Let's Encrypt)
- Använd starka databaslösenord

## Support

För problem eller frågor, skapa ett issue på GitHub:
https://github.com/yxkastarn/daily-log-system/issues

## Licens

MIT License - Se LICENSE-filen för detaljer