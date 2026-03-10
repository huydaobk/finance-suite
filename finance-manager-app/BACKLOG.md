# Finance Manager App — Backlog & Workflows (Kanban)

> Language: Vietnamese (UI), technical docs in English where helpful.
> Storage: `/mnt/toshiba/projects/finance-manager-app/`

## Roles
- **Sếp Huy**: Product owner (final decisions), acceptance testing.
- **Đệ (OpenClaw / main)**: Architect + PM/Orchestrator, writes specs, integrates parts, runs checks.
- **Agent `work` (proxypal/gpt-5.3-codex)**: Implementation tasks (Flutter, DB, OCR integration), code structure.
- **Agent `ops` (google/gemini-2.5-flash)**: Release/ops scripts, CI checks, environment sanity, perf sanity.
- **Agent `admin` (proxypal/gpt-5.2)**: Security review, secrets handling, deployment hardening, Telegram bot risk controls.

---

## Kanban

### Todo
- [ ] Confirm MVP scope & acceptance criteria (SPEC.md)
- [ ] Initialize Flutter repo skeleton (folders, lint, flavors)
- [ ] Define SQLite schema + migrations (drift) (ARCHITECTURE.md)
- [ ] Core features:
  - [ ] Categories & wallets (seed defaults)
  - [ ] Transactions CRUD + list + filters
  - [ ] Budget module + overspend alerts
  - [ ] Bills recurring + 08:00 scheduler
  - [ ] Anomaly rule (>= 2,500,000 VND)
  - [ ] Local notifications
- [ ] OCR (receipt scan: total + date) integration
- [ ] Export CSV + backup
- [ ] i18n VI copywriting finalized (UI_COPY_VI.md)

### Doing
- [ ] Create project documentation pack (SPEC.md, ARCHITECTURE.md, UI_COPY_VI.md, TELEGRAM_BOT_SPEC.md)

### Done
- [ ] Project directory created on Toshiba HDD

---

## Workflow diagram (text)

1) **Spec & Architecture (Đệ)**
   - Draft docs → Sếp duyệt → freeze v1
2) **Implementation (Agent work)**
   - Build modules in feature branches
3) **Ops/Quality (Agent ops)**
   - Build/lint/test automation, performance sanity
4) **Security/Deployment review (Agent admin)**
   - Data privacy, Telegram bot permissions, secrets, firewall notes
5) **Integration (Đệ)**
   - Merge, run acceptance checklist
6) **User acceptance (Sếp)**
   - Test on iOS + Android

---

## Milestones

- **M0 (Today):** Specs ready + repo skeleton.
- **M1:** Transactions + categories + wallets.
- **M2:** Budgets + alerts + local notifications.
- **M3:** Bills + reminders.
- **M4:** OCR scan.
- **M5 (V1.5):** Telegram input + multi-user household (cloud).
