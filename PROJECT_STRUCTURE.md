# Daily Log System - Komplett Projektstruktur

## Katalogstruktur

```
daily-log-system/
├── README.md
├── install.sh
├── LICENSE
│
├── backend/
│   ├── package.json
│   ├── .env.example
│   ├── .env
│   ├── server.js
│   ├── migrations/
│   │   └── run-migrations.js
│   └── tests/
│       └── api.test.js
│
├── frontend/
│   ├── package.json
│   ├── public/
│   │   └── index.html
│   ├── src/
│   │   ├── index.js
│   │   ├── App.jsx
│   │   ├── components/
│   │   │   ├── EntryForm.jsx
│   │   │   ├── EntryList.jsx
│   │   │   └── Summary.jsx
│   │   └── utils/
│   │       └── api.js
│   └── build/
│
├── database/
│   ├── schema.sql
│   └── seed-data.sql
│
├── grafana/
│   ├── datasource.yaml
│   ├── dashboard-daily-log.json
│   └── dashboard-weekly.json
│
├── nginx.conf
│
├── scripts/
│   ├── setup-grafana.sh
│   ├── backup.sh
│   └── restore.sh
│
└── docs/
    ├── API.md
    ├── DEPLOYMENT.md
    └── TROUBLESHOOTING.md
```

## Filbeskrivningar

### Root-nivå
- **README.md**: Huvuddokumentation med installation och användning
- **install.sh**: Automatiskt installationsscript för Proxmox
- **LICENSE**: MIT-licens

### Backend (/backend)
- **server.js**: Express API-server med alla endpoints
- **package.json**: Node.js dependencies
- **.env.example**: Mall för miljövariabler
- **migrations/run-migrations.js**: Databas-migrationsscript

### Frontend (/frontend)
- **public/index.html**: Huvudsaklig HTML-fil med inbyggd JavaScript
- **package.json**: Frontend dependencies (om du vill bygga med React)
- **src/**: React-komponenter (valfritt)

### Database (/database)
- **schema.sql**: Komplett databasschema med tabeller, views och funktioner
- **seed-data.sql**: Testdata (valfritt)

### Grafana (/grafana)
- **dashboard-daily-log.json**: Huvuddashboard för daglig översikt
- **datasource.yaml**: PostgreSQL-datakälla konfiguration

### Scripts (/scripts)
- **setup-grafana.sh**: Konfigurerar Grafana automatiskt
- **backup.sh**: Daglig backup-script
- **restore.sh**: Återställer från backup

### Nginx
- **nginx.conf**: Reverse proxy-konfiguration

## Snabbstart

### 1. Klona repository
```bash
git clone https://github.com/yxkastarn/daily-log-system.git
cd daily-log-system
```

### 2. Automatisk installation på Proxmox
```bash
bash install.sh
```

### 3. Manuell installation

#### Backend
```bash
cd backend
npm install
cp .env.example .env
# Redigera .env med dina inställningar
npm run migrate
pm2 start server.js --name daily-log-api
```

#### Frontend
```bash
cd frontend
npm install
npm run build
```

#### Database
```bash
sudo -u postgres psql -c "CREATE DATABASE daily_log;"
sudo -u postgres psql -c "CREATE USER dailylog WITH PASSWORD 'dailylog123';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE daily_log TO dailylog;"
psql -U dailylog -d daily_log -f database/schema.sql
```

#### Nginx
```bash
sudo cp nginx.conf /etc/nginx/sites-available/daily-log
sudo ln -s /etc/nginx/sites-available/daily-log /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

#### Grafana
```bash
bash scripts/setup-grafana.sh
```

## API Endpoints

### Entries
- `GET /api/entries` - Hämta loggposter
- `POST /api/entries` - Skapa ny post
- `PUT /api/entries/:id` - Uppdatera post
- `DELETE /api/entries/:id` - Ta bort post

### Summaries
- `GET /api/summaries/daily?date=YYYY-MM-DD` - Daglig sammanfattning
- `GET /api/summaries/weekly?start_date=YYYY-MM-DD` - Veckosammanfattning
- `GET /api/summaries/monthly?year=YYYY&month=MM` - Månadssammanfattning

### Import
- `POST /api/import/excel` - Importera Excel-fil

### Statistics
- `GET /api/statistics` - Allmän statistik

## Databasschema

### Tabeller
1. **users** - Användare
2. **log_entries** - Loggposter
3. **daily_summaries** - Dagliga sammanfattningar
4. **projects** - Projekt (framtida användning)

### Views (för Grafana)
1. **vw_daily_hours** - Dagliga arbetstimmar
2. **vw_activity_frequency** - Aktivitetsfrekvens
3. **vw_weekly_summary** - Veckosammanfattning
4. **vw_monthly_summary** - Månadssammanfattning
5. **vw_recent_activity** - Senaste aktiviteter
6. **vw_hourly_distribution** - Timfördelning

## Miljövariabler

```bash
# Backend (.env)
PORT=3001
NODE_ENV=production
DB_HOST=localhost
DB_PORT=5432
DB_NAME=daily_log
DB_USER=dailylog
DB_PASSWORD=dailylog123
```

## Backup och Återställning

### Manuell backup
```bash
bash scripts/backup.sh
```

### Automatisk backup (crontab)
```bash
0 2 * * * /opt/daily-log-system/scripts/backup.sh
```

### Återställ från backup
```bash
bash scripts/restore.sh /path/to/backup.sql.gz
```

## Tester

### Backend-tester
```bash
cd backend
npm test
```

### API-tester med curl
```bash
# Skapa post
curl -X POST http://localhost:3001/api/entries \
  -H "Content-Type: application/json" \
  -d '{"entry_date":"2025-10-01","start_time":"09:00","description":"Mejlkoll"}'

# Hämta poster
curl http://localhost:3001/api/entries?start_date=2025-10-01&end_date=2025-10-01
```

## Säkerhet

1. **Ändra standardlösenord**
   - Grafana: admin/admin
   - Database: dailylog123

2. **Aktivera HTTPS** (produktion)
   ```bash
   sudo apt install certbot python3-certbot-nginx
   sudo certbot --nginx -d your-domain.com
   ```

3. **Brandvägg**
   ```bash
   sudo ufw enable
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw allow 3000/tcp
   ```

## Felsökning

### Kontrollera tjänster
```bash
# Backend
pm2 status
pm2 logs daily-log-api

# Nginx
sudo systemctl status nginx
sudo tail -f /var/log/nginx/error.log

# PostgreSQL
sudo systemctl status postgresql
sudo tail -f /var/log/postgresql/postgresql-14-main.log

# Grafana
sudo systemctl status grafana-server
```

### Vanliga problem

**Problem**: Cannot connect to database
**Lösning**: Kontrollera PostgreSQL är igång och credentials i .env

**Problem**: 502 Bad Gateway
**Lösning**: Kontrollera att backend körs på port 3001

**Problem**: Grafana visar ingen data
**Lösning**: Verifiera PostgreSQL datasource i Grafana

## Support och Bidrag

- GitHub Issues: https://github.com/yxkastarn/daily-log-system/issues
- Wiki: https://github.com/yxkastarn/daily-log-system/wiki

## Licens

MIT License - Se LICENSE-filen