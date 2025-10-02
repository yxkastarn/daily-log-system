# Projektstruktur

```
daily-log-system/
├── README.md
├── QUICKSTART.md
├── LICENSE
├── install.sh
├── backend/
│   ├── package.json
│   ├── .env.example
│   ├── server.js
│   └── migrations/
│       └── run-migrations.js
├── frontend/
│   └── public/
│       └── index.html
├── database/
│   └── schema.sql
├── grafana/
│   └── dashboard-daily-log.json
├── nginx.conf
└── scripts/
    ├── setup-grafana.sh
    └── backup.sh
```

## Komponenter

- **Backend**: Express.js REST API
- **Frontend**: HTML/JavaScript med Tailwind CSS
- **Database**: PostgreSQL
- **Visualization**: Grafana
- **Web Server**: Nginx
