# API Documentation

## Base URL

```
http://<container-ip>/api
```

## Endpoints

### Health Check

```
GET /api/health
```

### Entries

#### Get all entries
```
GET /api/entries?start_date=2025-10-01&end_date=2025-10-01
```

#### Create entry
```
POST /api/entries
Content-Type: application/json

{
  "entry_date": "2025-10-01",
  "start_time": "09:00",
  "description": "Mejlkoll"
}
```

#### Delete entry
```
DELETE /api/entries/:id
```

### Statistics

```
GET /api/statistics
```

Returns:
- Total entries
- Total days logged
- Top 10 activities
