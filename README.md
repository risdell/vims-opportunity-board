# VIMS Research & Internship Opportunity Board

A mobile-friendly Shiny app for displaying approved VIMS research and internship opportunities to William & Mary students. The app uses Supabase for persistent storage and Posit Connect Cloud for hosting.

## Architecture

- **Students:** browse approved, non-expired opportunities without signing in.
- **VIMS faculty:** submit opportunities through the app.
- **Board administrator:** reviews pending rows in the Supabase Table Editor and changes `status` to `approved`.
- **Connect Cloud:** hosts the Shiny interface but does not store the records.

## 1. Create the Supabase database

1. Create a Supabase project.
2. Open **SQL Editor**.
3. Paste and run `sql/setup.sql`.
4. Open **Table Editor → opportunities** to confirm that the table exists.
5. Optional: use **Insert → Import data from CSV** to import `data/import_template.csv`.

The SQL enables Row Level Security. Anonymous app visitors can:

- read only rows with `status = 'approved'` whose expiration date has not passed;
- insert only rows with `status = 'pending'` and a `@vims.edu` contact address;
- never update or delete rows.

Do not add a Supabase secret key or legacy `service_role` key to this app.

## 2. Copy the Supabase settings

From the Supabase project **Connect** dialog or **Settings → API Keys**, copy:

- the project URL;
- a **publishable** key beginning with `sb_publishable_`.

For local development, copy `.Renviron.example` to `.Renviron` and replace the placeholders. `.Renviron` is excluded from Git.

Restart R after creating or editing `.Renviron`.

## 3. Run locally

Open `VIMSOpportunityBoard.Rproj`, then run:

```r
source("prepare_deployment.R")
shiny::runApp()
```

Before Supabase is configured, the app runs in demo mode using `data/sample_opportunities.csv`.

## 4. Approve submissions

1. Open **Supabase → Table Editor → opportunities**.
2. Filter `status` to `pending`.
3. Review and edit the record.
4. Set an `expiration_date`.
5. Change `status` to `approved` and save.

The app refreshes automatically every five minutes. Visitors can also select **Refresh opportunities**.

To remove an opportunity, set `status` to `closed` or set its expiration date in the past.

## 5. Prepare the Connect Cloud deployment

Connect Cloud requires `manifest.json` for R content. Run:

```r
source("prepare_deployment.R")
```

Commit the generated `manifest.json`.

## 6. Push to GitHub

On the Connect Cloud free tier, use a public GitHub repository.

```bash
git init
git add .
git commit -m "Initial VIMS opportunity board"
git branch -M main
git remote add origin https://github.com/YOUR-ACCOUNT/vims-opportunity-board.git
git push -u origin main
```

## 7. Deploy to Posit Connect Cloud

1. Sign in to Connect Cloud.
2. Select **Publish**.
3. Install/authorize the Connect Cloud GitHub app when prompted.
4. Select **Shiny** and choose the repository and `main` branch.
5. Choose `app.R` as the primary file.
6. Under advanced settings, add these secret variables:
   - `SUPABASE_URL`
   - `SUPABASE_PUBLISHABLE_KEY`
7. Publish.

Automatic republishing on GitHub push is enabled by default. You can customize the app's Connect Cloud URL in its content settings.

## 8. Routine maintenance

- Review pending submissions in Supabase.
- Approve, edit, close, or reject rows in the Table Editor.
- Push visual or functional changes to GitHub; Connect Cloud will redeploy.
- Periodically export the `opportunities` table as a backup.

## Security notes

The publishable key is intentionally low-privilege and all access is constrained by Row Level Security. The app never needs a Supabase secret key. Because the submission endpoint is public, the approval queue is also the spam-control boundary. If spam becomes a problem, add a CAPTCHA/Turnstile-protected Edge Function or retain a separate faculty-only form.
