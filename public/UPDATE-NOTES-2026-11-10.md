# November 10, 2026 changes

1. Navigation: high-contrast white inactive tabs, white active tab with navy text, river-blue hover/focus; keeps W&M/VIMS/Batten logos.
2. Browse page: independent-maintainer disclaimer and automatic hiding after application deadline, end date, or board expiration date. All four dates must exist to display, including start date.
3. Submit page: Robert Isdell named as reviewer; all four dates required and validated on both UI and SQLite write.
4. About page: opportunities are offered by members of the VIMS & Batten School community; not presented as an institutional service.
5. Public "Request a change" tab records edits/removals without implementing them automatically. Claimed email is unverified.
6. SQLite: non-destructive migration adding `change_requests` table and `notification_sent_at` on opportunities. Existing records are treated as previously notified to avoid a notification flood.
7. Admin: separate Shiny management app (edit/approve/close and mark change requests handled), never mounted publicly until authenticated. Local SSH tunnel+private password for now.
8. Notifications: optional cron-driven `curl` SMTP sender for new pending opportunities and change requests. No messages sent until VIMS SMTP is configured; queued messages are retried on SMTP failure.

**Testing status:** SQLite schema and expiration query were validated using a SQLite harness; R/Shiny could not be executed in this workspace because R is not installed. Test once on the VIMS server with the commands in the deployment guide.
