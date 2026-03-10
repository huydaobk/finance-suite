CREATE TABLE IF NOT EXISTS transactions_inbox (
  id BIGSERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'new',
  type TEXT NOT NULL,
  amount_vnd BIGINT NOT NULL,
  category TEXT,
  wallet TEXT,
  note TEXT,
  tx_date DATE NOT NULL,
  raw_text TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_transactions_inbox_status_created_at
  ON transactions_inbox(status, created_at);
