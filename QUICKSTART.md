# Daily Log System - Snabbstartsguide

## 🚀 Installation på Proxmox (Rekommenderat)

### Steg 1: Kör installationsscriptet

Logga in på din Proxmox-värd via SSH och kör:

```bash
bash <(curl -s https://raw.githubusercontent.com/yxkastarn/daily-log-system/main/install.sh)
```

### Steg 2: Vänta på installation
Scriptet kommer automatiskt att:
- ✓ Skapa LXC-container (Ubuntu 22.04)
- ✓ Installera PostgreSQL, Node.js, Nginx, Grafana
- ✓ Konfigurera databas och skapa tabeller
- ✓ Bygga och starta applikationen
- ✓ Importera Grafana dashboards

**Tid:** ~10-15 minuter

### Steg 3: Åtkomst

Efter installation, systemet är tillgängligt på:

```
Webbgränssnitt: http://<container-ip>
Grafana:        http://<container-ip>:3000
```

**Grafana login:**
- Användarnamn: `admin`
- Lösenord: `admin` (ändra vid första inloggningen!)

---

## 📊 Första användning

### 1. Öppna webbgränssnittet

Navigera till `http://<container-ip>` i din webbläsare.

### 2. Registrera din första aktivitet

Fyll i formuläret:
- **Datum**: Välj datum (standard = idag)
- **Tid**: T.ex. `09:00`
- **Beskrivning**: T.ex. `Mejlkoll`

Klicka på "Lägg till aktivitet"

### 3. Visa statistik i Grafana

1. Öppna `http://<container-ip>:3000`
2. Logga in med admin/admin
3. Byt lösenord när du uppmanas
4. Gå till **Dashboards** → **Daily Log - Översikt**

Du ser nu:
- 📈 Arbetade timmar per dag
- 📊 Vecko- och månadssammanfattningar
- 🏆 Vanligaste aktiviteter
- ⏰ Aktivitetsfördelning per timme

---

## 💡 Daglig användning

### Morgonrutin

```
1. Öppna webbgränssnittet
2. Fyll i dagens första aktivitet
3. Fortsätt logga aktiviteter under dagen
```

### Tips för effektiv loggning

**Använd korta beskrivningar:**
- ✓ "Mejlkoll"
- ✓ "Projektmöte"
- ✓ "Kodgranskning"
- ✗ "Granskade kod för det nya projektet tillsammans med teamet"

**Logga kontinuerligt:**
- Lägg till aktiviteter när de händer
- Använd konsekvent namngivning
- Gruppera liknande aktiviteter

---

## 🔧 Vanliga uppgifter

### Visa dagens sammanfattning

Öppna webbgränssnittet - högerpanelen visar:
- Arbetstid (exkl. lunch)
- Antal aktiviteter
- Lunchtid

### Kontrollera specifikt datum

1. Ändra datum i formuläret
2. Dagens aktiviteter uppdateras automatiskt

### Exportera data

**Via databas:**
```bash
pct exec 100 -- pg_dump -U dailylog daily_log > export.sql
```

**Via Grafana:**
1. Öppna valfri panel
2. Klicka på "..." → "Inspect" → "Data"
3. Klicka "Download CSV"

### Ta bort en aktivitet

Klicka på **×** till höger om aktiviteten → Bekräfta

---

## 📱 Åtkomst från andra enheter

### Från samma nätverk

Använd container-IP:
```
http://192.168.1.XXX
```

### Från internet (valfritt)

**Säkra åtkomst med reverse proxy:**

1. Installera Nginx på Proxmox-värden
2. Konfigurera port forwarding
3. Använd Let's Encrypt för HTTPS

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://<container-ip>;
    }
}
```

---

## 🔄 Backup

### Automatisk daglig backup

Backups skapas automatiskt kl 02:00 varje natt till:
```
/opt/daily-log-system/backups/
```

Retentionsperiod: 30 dagar

### Manuell backup

```bash
pct exec 100 -- bash /opt/daily-log-system/scripts/backup.sh
```

### Återställ från backup

```bash
pct exec 100 -- bash /opt/daily-log-system/scripts/restore.sh /path/to/backup.sql.gz
```

---

## ⚙️ Inställningar och anpassningar

### Ändra lunchtid

Redigera i databas:
```sql
UPDATE daily_summaries SET lunch_hours = 1.0;
```

### Lägg till fler användare

```sql
INSERT INTO users (name, email) VALUES ('Ny Användare', 'email@example.com');
```

### Anpassa Grafana dashboards

1. Öppna Grafana
2. Gå till Dashboard → Edit
3. Lägg till/redigera paneler
4. Spara dashboard

---

## 🆘 Felsökning

### Webbgränssnittet laddar inte

```bash
# Kontrollera Nginx
pct exec 100 -- systemctl status nginx

# Kontrollera backend
pct exec 100 -- pm2 status
```

### Grafana visar ingen data

```bash
# Kontrollera PostgreSQL
pct exec 100 -- systemctl status postgresql

# Testa databasanslutning
pct exec 100 -- psql -U dailylog -d daily_log -c "SELECT COUNT(*) FROM log_entries;"
```

### Import av Excel fungerar inte

Om du behöver bulk-importera data, använd JSON-format via API:
```bash
curl -X POST http://<ip>/api/import/bulk \
  -H "Content-Type: application/json" \
  -d '{
    "entries": [
      {
        "entry_date": "2025-10-01",
        "start_time": "09:00",
        "description": "Mejlkoll"
      }
    ]
  }'
```

---

## 📚 Nästa steg

### Utforska Grafana

- Skapa egna dashboards
- Lägg till alerts för låg arbetstid
- Analysera produktivitetstrender

### API Integration

Bygg egna integrationer:
```javascript
// Lägg till post via API
fetch('http://<ip>/api/entries', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    entry_date: '2025-10-01',
    start_time: '09:00',
    description: 'Automatisk logg'
  })
});
```

### Anpassa till ditt arbetssätt

- Lägg till projekt-kategorisering
- Skapa custom views i Grafana
- Integrera med kalendern

---

## 📞 Få hjälp

**Problem?**
- Kontrollera logs: `pct exec 100 -- pm2 logs`
- Läs [TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md)
- Skapa issue på GitHub

**Vill bidra?**
- Fork repository
- Gör dina ändringar
- Skicka Pull Request

---

## 🎯 Sammanfattning av kommandon

### Container-hantering
```bash
# Starta container
pct start 100

# Stoppa container
pct stop 100

# Logga in i container
pct enter 100

# Se container-status
pct status 100
```

### Tjänstehantering (inne i container)
```bash
# Backend
pm2 status
pm2 restart daily-log-api
pm2 logs daily-log-api

# Nginx
systemctl status nginx
systemctl restart nginx

# PostgreSQL
systemctl status postgresql
systemctl restart postgresql

# Grafana
systemctl status grafana-server
systemctl restart grafana-server
```

### Databas-kommandon
```bash
# Logga in i databas
psql -U dailylog -d daily_log

# Visa tabeller
\dt

# Visa antal poster
SELECT COUNT(*) FROM log_entries;

# Visa senaste poster
SELECT * FROM log_entries ORDER BY entry_date DESC, start_time DESC LIMIT 10;

# Backup
pg_dump -U dailylog daily_log > backup.sql

# Restore
psql -U dailylog -d daily_log < backup.sql
```

---

## 📈 Användningsexempel

### Scenario 1: Veckorapport till chef

1. Öppna Grafana
2. Gå till "Veckossammanfattning"-panel
3. Välj aktuell vecka
4. Exportera som PDF eller ta skärmdump
5. Skicka rapport

### Scenario 2: Analysera produktivitet

1. Öppna "Aktivitetsfördelning per Timme"
2. Identifiera mest produktiva timmar
3. Planera viktiga uppgifter under dessa timmar

### Scenario 3: Månadsrapportering

1. Gå till Grafana → "Månadsssammanfattning"
2. Se total arbetstid och arbetsdagar
3. Jämför med föregående månader
4. Identifiera trender

### Scenario 4: Automatisera med script

Skapa dagligt påminnelse-script:
```bash
#!/bin/bash
# remind-log.sh

LAST_ENTRY=$(curl -s http://localhost/api/entries?limit=1 | jq -r '.[0].entry_date')
TODAY=$(date +%Y-%m-%d)

if [ "$LAST_ENTRY" != "$TODAY" ]; then
    notify-send "Daily Log" "Glöm inte logga dina aktiviteter idag!"
fi
```

---

## 🏆 Best Practices

### Loggningsvanor

**Gör:**
- ✓ Logga i realtid eller direkt efter aktivitet
- ✓ Använd konsekvent namngivning
- ✓ Inkludera start- och sluttid
- ✓ Var specifik men kortfattad
- ✓ Logga även korta aktiviteter

**Undvik:**
- ✗ Samla ihop hela dagen i slutet
- ✗ Använda olika namn för samma aktivitet
- ✗ Överdrivet långa beskrivningar
- ✗ Hoppa över "små" aktiviteter

### Kategorisering

Skapa egna konventioner:
- Prefix: `[PROJEKT]` för projektarbete
- Prefix: `[MÖTE]` för möten
- Prefix: `[ADMIN]` för administrativt

Exempel:
- `[PROJEKT] AL - Kodgranskning`
- `[MÖTE] Veckomöte team`
- `[ADMIN] Mejlkoll`

### Regelbunden granskning

**Daglig granskning (5 min):**
- Kontrollera att alla aktiviteter är loggade
- Verifiera tider
- Komplettera beskrivningar

**Veckovis granskning (15 min):**
- Öppna Grafana veckorapport
- Analysera arbetsfördelning
- Identifiera förbättringsområden

**Månadsvis granskning (30 min):**
- Granska månadsstatistik
- Jämför med mål
- Planera nästa månad

---

## 🔐 Säkerhetstips

### 1. Ändra standardlösenord
```bash
# Grafana: Via webbgränssnitt vid första inloggning

# PostgreSQL
pct exec 100 -- sudo -u postgres psql -c "ALTER USER dailylog PASSWORD 'ditt-starka-lösenord';"
```

### 2. Begränsa nätverksåtkomst

I Proxmox, konfigurera brandvägg för containern:
- Tillåt endast specifika IP-adresser
- Blockera port 3001 (backend direkt åtkomst)
- Öppna endast port 80/443

### 3. Aktivera HTTPS

För produktionsmiljö:
```bash
pct exec 100 -- apt install certbot python3-certbot-nginx
pct exec 100 -- certbot --nginx
```

### 4. Regelbundna uppdateringar
```bash
# Uppdatera container
pct exec 100 -- apt update && apt upgrade -y

# Uppdatera Node.js packages
pct exec 100 -- cd /opt/daily-log-system/backend && npm update
```

---

## 📊 Dashboard-tips

### Skapa egen panel i Grafana

1. Öppna dashboard
2. Klicka "Add" → "Visualization"
3. Välj PostgreSQL datasource
4. Skriv SQL-query:
```sql
SELECT 
    entry_date as time,
    COUNT(*) as aktiviteter
FROM log_entries
WHERE entry_date >= NOW() - INTERVAL '30 days'
GROUP BY entry_date
ORDER BY entry_date
```
5. Välj visualiseringstyp
6. Spara

### Skapa alert

1. Redigera panel
2. Gå till "Alert" tab
3. Sätt villkor (t.ex. "Färre än 5 timmar per dag")
4. Konfigurera notification channel
5. Spara

---

## 🚀 Avancerad användning

### API-automation med Python

```python
import requests
from datetime import datetime

API_URL = "http://your-container-ip/api"

def log_activity(description, time=None):
    if time is None:
        time = datetime.now().strftime("%H:%M")
    
    data = {
        "entry_date": datetime.now().strftime("%Y-%m-%d"),
        "start_time": time,
        "description": description
    }
    
    response = requests.post(f"{API_URL}/entries", json=data)
    return response.json()

# Användning
log_activity("Automatisk logg från Python")
```

### Integrera med kalendern

Skapa script som importerar från Google Calendar:
```bash
# Kräver Google Calendar API setup
python scripts/import-calendar.py --date 2025-10-01
```

### Exportera till Excel

```python
import pandas as pd
import requests

# Hämta data från API
response = requests.get("http://your-ip/api/entries?limit=1000")
data = response.json()['entries']

# Skapa DataFrame och exportera
df = pd.DataFrame(data)
df.to_excel("daily_log_export.xlsx", index=False)
```

---

## 🎓 Lär dig mer

### Läs dokumentationen
- [README.md](./README.md) - Fullständig dokumentation
- [API.md](./docs/API.md) - API-referens
- [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) - Projektstruktur

### Resurser
- PostgreSQL: https://www.postgresql.org/docs/
- Grafana: https://grafana.com/docs/
- Express.js: https://expressjs.com/
- Nginx: https://nginx.org/en/docs/

---

## ✅ Checklista för framgång

**Efter installation:**
- [ ] Webbgränssnittet fungerar
- [ ] Grafana är tillgänglig
- [ ] Standardlösenord ändrade
- [ ] Första aktivitet loggad
- [ ] Excel-data importerad (om tillämpligt)

**Daglig användning:**
- [ ] Logga aktiviteter löpande
- [ ] Kontrollera dagens sammanfattning
- [ ] Granska i slutet av dagen

**Veckovis:**
- [ ] Granska veckorapport i Grafana
- [ ] Analysera produktivitet
- [ ] Planera nästa vecka

**Månadsvis:**
- [ ] Granska månadsstatistik
- [ ] Exportera data för arkivering
- [ ] Uppdatera system om nödvändigt

---

## 🎉 Lycka till!

Du har nu allt du behöver för att komma igång med Daily Log System!

**Glöm inte:**
- Konsekvent loggning ger bäst insikter
- Grafana är din vän för analys
- Backups sker automatiskt
- Ställ frågor via GitHub Issues

**Ha en produktiv dag! 🚀**