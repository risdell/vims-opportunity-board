# Updating the VIMS-hosted Opportunity Board

These steps update the existing app in `/home/risdell/vims-opportunity-board-vims` while keeping the SQLite database at `/var/lib/vims-opportunity-board/opportunities.sqlite` intact.

## 1. Back up the current app and database

```bash
cd /home/risdell
cp -a vims-opportunity-board-vims vims-opportunity-board-vims.backup-2026-10-12

cd /home/risdell/vims-opportunity-board-vims
sudo -u shiny Rscript scripts/backup_database.R
```

The database script uses SQLite's online backup API through RSQLite, so it is safer than copying the live `.sqlite` file directly while WAL mode is enabled.

## 2. Copy the updated app files to the server

Extract the supplied ZIP to a temporary location, then copy its contents over the existing app directory. For example:

```bash
rsync -av /path/to/new/vims-opportunity-board-vims/ \
  /home/risdell/vims-opportunity-board-vims/
```

Do not delete or replace `/var/lib/vims-opportunity-board/opportunities.sqlite`.

The `/srv/shiny-server/OpportunityBoardTest` symlink does not need to change if it already points to `/home/risdell/vims-opportunity-board-vims`.

## 3. Run the database migration

```bash
cd /home/risdell/vims-opportunity-board-vims
sudo -u shiny Rscript scripts/initialize_database.R
```

This is safe to run against the existing database. It adds `owner_id` and `owner_email` only if they do not already exist.

Verify the schema:

```bash
sudo -u shiny Rscript scripts/show_schema.R
```

You should see `owner_id` and `owner_email` near the end of the column list.

## 4. Verify permissions

```bash
sudo -u shiny test -r /home/risdell/vims-opportunity-board-vims/app.R \
  && echo "shiny can read app"

sudo -u shiny test -w /var/lib/vims-opportunity-board \
  && echo "shiny can write database directory"
```

## 5. Reload the app

Shiny Server may keep an existing R worker alive for an active session. The most deterministic reload is:

```bash
sudo systemctl restart shiny-server
```

This briefly restarts **all** apps on this Shiny Server, including AlosApp, so use this only when a short interruption is acceptable. Otherwise, copy the files, close existing Opportunity Board sessions, and test with a new browser session after the old worker has exited.

## 6. Test

Open the existing VIMS-network URL, for example:

```text
https://shiny.vims.edu/OpportunityBoardTest/
```

Confirm:

- the navbar is navy with the new VIMS palette;
- the hero is navy/teal with gold accent;
- opportunity badges/cards use the new palette;
- the footer appears **below** the complete opportunity list and no longer overlaps cards;
- search and filters still work;
- a new submission is stored as `pending`;
- existing approved opportunities still appear.

A version query was added to `styles.css` to reduce browser-cache problems. If styling still looks old, do a hard refresh.

## 7. Roll back if needed

```bash
mv /home/risdell/vims-opportunity-board-vims \
   /home/risdell/vims-opportunity-board-vims.failed-2026-10-12
mv /home/risdell/vims-opportunity-board-vims.backup-2026-10-12 \
   /home/risdell/vims-opportunity-board-vims
```

The ownership-column database migration is additive and does not need to be rolled back; older app code simply ignores those nullable columns.
