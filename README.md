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
bash <(curl -s https://raw.githubusercontent.com/yxkastarn/daily-log-system/main/install.sh)
```

## Åtkomst efter installation

- **Webbgränssnitt**: `http://<container-ip>`
- **Grafana**: `http://<container-ip>:3000`
  - Användarnamn: `admin`
  - Lösenord: `admin` (ändra vid första inloggningen)

## Dokumentation

- [Snabbstartsguide](QUICKSTART.md)
- [Projektstruktur](PROJECT_STRUCTURE.md)
- [API-dokumentation](docs/API.md)

## Funktioner

- ✅ Webbaserat gränssnitt för registrering
- ✅ REST API för integrationer
- ✅ PostgreSQL-databas med optimerade views
- ✅ Grafana dashboards för analys
- ✅ Automatiska dagliga backups
- ✅ Responsiv design för mobil och desktop

## Licens

MIT License - Se LICENSE-filen för detaljer
