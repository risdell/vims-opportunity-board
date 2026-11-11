> **Current update: November 10, 2026.** See [`DEPLOY-2026-11-10.md`](DEPLOY-2026-11-10.md) for the current staging upgrade, new deadline rules, private admin dashboard, and optional email notifications. Earlier instructions below describe the initial October deployment.

# VIMS & Batten School Opportunity Board — VIMS Shiny Server build

This build replaces the Connect Cloud/Supabase backend with a local SQLite database for deployment on the VIMS Shiny Server.

## Runtime architecture

- App code: `/home/risdell/vims-opportunity-board-vims/` (or another deployment directory)
- Shiny symlink: `/srv/shiny-server/OpportunityBoardTest`
- SQLite database: `/var/lib/vims-opportunity-board/opportunities.sqlite`
- Runtime user: `shiny`

## Required R packages

`shiny`, `bslib`, `DBI`, `RSQLite`, `dplyr`, `stringr`, `purrr`, `lubridate`, `htmltools`

Check them with:

```bash
sudo -u shiny Rscript scripts/check_packages.R
```

## Initialize persistent storage

```bash
sudo mkdir -p /var/lib/vims-opportunity-board
sudo chown shiny:shiny /var/lib/vims-opportunity-board
sudo chmod 750 /var/lib/vims-opportunity-board
sudo -u shiny Rscript scripts/initialize_database.R
```

For a quick demo, load the bundled example:

```bash
sudo -u shiny Rscript scripts/import_csv.R data/sample_opportunities.csv
```

For migration, export the Supabase `opportunities` table to CSV and substitute that CSV path in the command above.

## Review pending submissions from the command line

```bash
sudo -u shiny Rscript scripts/list_pending.R
sudo -u shiny Rscript scripts/set_status.R '<ID>' approved
```

## Publish under a temporary internal URL

```bash
sudo ln -s /home/risdell/vims-opportunity-board-vims /srv/shiny-server/OpportunityBoardTest
```

Then browse to:

`https://shiny.vims.edu/OpportunityBoardTest/`

No change to `shiny-server.conf` is needed with the current `site_dir /srv/shiny-server` configuration.
