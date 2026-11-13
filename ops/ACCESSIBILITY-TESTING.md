# Opportunity Board — Development accessibility and test-data guide
Updated 2026-11-13. Changes belong to GitHub branch **vims-dev**; do not promote without testing.

## 1. Sync and check development

On the VIMS server (as risdell):
```bash
bash ~/oppboard-deploy.sh sync-dev
cd /home/risdell/vims-opportunity-board-dev
Rscript -e 'parse("public/app.R"); parse("ops/dev_data.R"); cat("R syntax OK\n")'
```
Open https://shiny.vims.edu/OpportunityBoardDev/ in a fresh browser window. The script reloads this Shiny app without restarting the whole Shiny Server.

## 2. Add safe demonstration records (recommended)

The helper is **deliberately locked** to the development database and refuses to run with the production database path. It creates three clearly labelled DEMO-only, approved records, idempotently. It does not read or clone production submissions.

```bash
cd /home/risdell/vims-opportunity-board-dev
sudo -u shiny env \
  OPPORTUNITY_DB=/var/lib/vims-opportunity-board-dev/opportunities.sqlite \
  Rscript ops/dev_data.R seed
```

Click **Refresh opportunities** in the development board. Three demo listings should appear, with both short and unusually long titles, badges, details, and variable action links.

To list pending development submissions (including the fake submission you made through the public form):
```bash
sudo -u shiny env \
  OPPORTUNITY_DB=/var/lib/vims-opportunity-board-dev/opportunities.sqlite \
  Rscript ops/dev_data.R pending
```
To approve exactly one chosen pending record:
```bash
sudo -u shiny env \
  OPPORTUNITY_DB=/var/lib/vims-opportunity-board-dev/opportunities.sqlite \
  Rscript ops/dev_data.R approve 'PASTE-EXACT-ID-HERE'
```
The script prints the title and requires typing **YES**. Use your actual test record ID, not the placeholder.

To remove only the three named demo fixtures after testing:
```bash
sudo -u shiny env \
  OPPORTUNITY_DB=/var/lib/vims-opportunity-board-dev/opportunities.sqlite \
  Rscript ops/dev_data.R remove-demo
```
This requires typing **DELETE DEMO**. It does not remove other test submissions.

## 3. Optional: use the admin GUI against development without publishing it

When you want to test edit/approve/close workflows or their accessibility, start a temporary loopback-only copy of the existing admin app:

On the VIMS server, in one SSH session:
```bash
cd /home/risdell/vims-opportunity-board-dev/admin
sudo -u shiny env \
  OPPORTUNITY_DB=/var/lib/vims-opportunity-board-dev/opportunities.sqlite \
  Rscript -e "shiny::runApp('.', host='127.0.0.1', port=4863, launch.browser=FALSE)"
```
The admin password file must remain readable by the shiny user. Leave that SSH session running while using the admin app.

On your own computer, in another terminal:
```bash
ssh -N -L 4863:127.0.0.1:4863 risdell@shiny.vims.edu
```
Then browse to http://localhost:4863, sign in using the existing administrator password, and confirm that only *development* records are present. Press Ctrl+C in both terminal sessions afterward. Do **not** link the development admin to a public /srv/shiny-server/ URL.

## 4. Accessibility changes in this iteration

- A visually revealed **Skip to main content** link is inserted as the first focusable link. It locates the active Shiny tab's main landmark.
- Submission and change-request forms report errors in persistent, focusable summaries with per-field messages.
- Invalid inputs receive aria-invalid and aria-describedby; required inputs receive aria-required.
- Form error summaries get focus; each linked message can focus its input.
- The application URL gets a clear format error when it does not start with http:// or https://.
- A browser-side script (public/www/accessibility.js) handles the focus and error display, with an ordinary Shiny warning fallback.
- No changes to SQLite schema or production admin configuration.

## 5. Manual acceptance checks

Do these on the **development** URL. Source inspection alone cannot prove WCAG conformance.

| Test | Action | Expected result |
| --- | --- | --- |
| Skip navigation | Refresh, press Tab once, then Enter | Visible skip link appears; focus moves into the current tab's main region; next Tab proceeds through content |
| Tab-aware skip | Select Submit, Request a change, and About; use the skip link from the top | Focus goes to the currently selected tab, never a hidden tab |
| Sample cards | Tab through three DEMO cards and open their details with Enter/Space | Each control has visible focus; screen-reader labels identify the relevant opportunity |
| Required inputs | On Submit, leave fields blank and click Submit for review | One error summary identifies each missing field; linked messages focus inputs |
| Dates | Enter a missing or expired deadline; an end date before the start | Appropriate date-specific inline messages and aria-invalid |
| Invalid URL | Enter `example.org/apply` | Form identifies the required http(s) prefix |
| Change requests | Submit without email, details, or posting title | Each invalid field gets specific guidance; valid input can be submitted (to dev only) |
| Keyboard | Test hamburger, nav tabs, filters, Selectize, calendar input, details, modal dialog, and Escape | No keyboard trap; focus order and focus ring remain usable |
| Zoom | Browser zoom at 200% and 400%, and width near 320 CSS pixels | No loss of content/functionality; ordinary text does not require horizontal scrolling |
| Color | Run axe or WAVE on each visible tab, and inspect computed colors | No unaddressed AA text or focus contrast defects |
| Screen readers | NVDA + Firefox on Windows; ideally VoiceOver on iOS | Headings, form errors, live results, cards, links and modal announcements make sense |
| Admin | Run the optional localhost admin against dev; edit/approve a fake record | Focus and status messages remain usable; no production records appear |

Note: A native HTML control or Bootstrap component may be accessible in principle yet still require checks in the deployed version and browser/assistive technology combination.

## 6. Remaining work after this round

1. **Test and repair real browser widget behavior.** If the Selectize, date picker, hamburger, or modal has keyboard/focus issues, file a concrete issue with browser, control and steps to reproduce; avoid speculative code fixes.
2. **Full admin accessibility pass.** When time allows, test the authenticated dashboard's tabsets, editing controls, validation, save/close notifications, and rerender focus behavior. Reuse the development-only SSH tunnel above.
3. **Zoom, color, and target-size checks.** Use real computed styles and mobile viewport measurements, not code-only assumptions.
4. **Reduce disruptive announcements.** Verify that five-minute auto refresh and filter changes do not repeatedly announce unchanged result counts.
5. **Institutional review.** Ask W&M/VIMS accessibility support to review the public board before any formal conformance statement.

WCAG 2.2 AA is the target for improvements, not a certification. See W3C WCAG: https://www.w3.org/TR/WCAG22/ and skip navigation technique G1: https://www.w3.org/WAI/WCAG21/Techniques/general/G1.

## 7. Promote after tests pass

```bash
bash ~/oppboard-deploy.sh promote
bash ~/oppboard-deploy.sh status
```
Production remains unchanged until you run promotion and confirm the browser smoke test. The helper backs up the production database and reloads only the production app. If anything fails, do not force-push or rerun promotion blindly; inspect Git status and the Shiny Server logs.
