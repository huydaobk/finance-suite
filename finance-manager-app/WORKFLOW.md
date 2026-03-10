# Finance Manager App — Workflow & Responsibility Matrix

## Who does what

### Đệ (main)
- Owns architecture decisions and the final spec pack.
- Maintains the Kanban and milestones.
- Integrates and validates deliverables.

### Agent `work` (implementation)
- Flutter app implementation:
  - UI scaffolding & navigation
  - SQLite (drift) layer + repositories
  - Features: transactions, budgets, bills, alerts
  - OCR integration (total+date) and attachment handling

### Agent `ops` (quality/ops)
- Build/lint/test automation
- Release packaging
- Performance sanity checks (startup time, DB query profiling)

### Agent `admin` (security)
- Privacy review (data stored locally, future cloud sync)
- Telegram bot threat model + permission boundaries
- Secrets and token handling in V1.5

### Sếp Huy (product)
- Approves spec v1
- Validates Vietnamese copy/tone
- Runs acceptance tests on real devices

## Project storage
- `/mnt/toshiba/projects/finance-manager-app/`

## Next immediate actions
1) Đệ writes spec pack.
2) Spawn `work` to create Flutter repo skeleton and DB schema.
