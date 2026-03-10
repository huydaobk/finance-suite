# finance-api

FastAPI + JWT service to sync transactions into the Flutter finance app.

## Env
See `.env.example`.

## Run (dev)
```bash
uvicorn finance_api.app:app --host 127.0.0.1 --port 8088
```

## Migration
Create the inbox table used by sync/ingest:
```bash
psql "$DATABASE_URL" -f sql/001_create_transactions_inbox.sql
```

## Ingest endpoint
Internal producer endpoint:
- `POST /ingest/transactions`
- Header: `X-Ingest-Secret: <INGEST_SHARED_SECRET>`

Example:
```bash
curl -X POST http://127.0.0.1:8088/ingest/transactions \
  -H 'Content-Type: application/json' \
  -H 'X-Ingest-Secret: replace-with-strong-secret' \
  -d '{
    "type": "expense",
    "amount_vnd": 45000,
    "category": "food",
    "wallet": "cash",
    "note": "Bánh mì",
    "tx_date": "2026-03-06",
    "raw_text": "chi 45k ăn trưa"
  }'
```
