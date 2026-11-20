# Hello Division G — changes from v475 to v487

Baseline: `HelloDivisionG_v475_simple_time_input.html`
Latest: `HelloDivisionG_v487.html` (single-file app, ~11.7 MB)

> **Privacy — read first.** The v487 HTML still contains embedded member records, just like v475. The GitHub repository is **public**: do **not** commit the v487 HTML (or any copy of it) to the repo. Use it only as a local reference. The repo should only contain documentation, the sync adapter and schema code (see `sync/README.md`), never the app HTML.
>
> If the private Supabase-hosted copy needs updating, rebuild it from v487 with `python3 sync/build_website.py HelloDivisionG_v487.html PRIVATE_OUTPUT/index.html` and upload the result to the private `hdg-private-app` bucket. The three integration strings the builder looks for (`tm_division_g_dashboard_v56` storage key, `hello_division_g_durable_v1` database name, `DURABLE_INIT_PROMISE=initializeDurableStorage()`) are unchanged in v487.

## How the changes are built

- All changes are **additive**: new `<style id="v476…">`–`<style id="v486…">` blocks and new `<script id="v477…">`–`<script id="v485…">` blocks near the end of the file. They wrap or extend existing functions, and only a few targeted lines were edited in place (listed below).
- No change to the stored data format, except a few new optional fields (see "Data additions").
- Desktop-first. The phone layout was **not** changed: the app is still deliberately desktop-only (`min-width: 1180px`).

---

## v476 — Interface consistency and fixes

**Layout fixes**
- IG Schedule: the setup panel is wider, field columns are even, and the design-card labels no longer break one letter per line.
- Community: all 9 tabs wrap onto two rows instead of being hidden off-screen.
- Clubs / Officers filters match the Members page size (44px, 14px text).
- Area page: the three summary tiles sit in one row.
- Database & Imports: removed the internal build label ("v244 DURABLE IMPORT").
- Duplicate page headings removed on 7 pages (Area, Officers, Members, TLI, Contests, IG Schedule, Database). The page title is kept and the repeated second title is hidden.

**Consistency system**
- Buttons: 2 sizes only, standard (40px tall, 13px text) and compact for tables and toolbars (32px, 12px). Previously there were 61 variants, with text from 8px to 15px.
- Section headings: one size (21px), except the Overview greeting.
- Badges and status chips: one style (11px, pill).
- Row actions (Clubs / Officers / Members): Edit and Delete are faded until you hover a row, and Delete only turns red on hover. Touch screens show them fully. The action columns are wide enough to keep both on one line.

**Data fix**
- TLI: "Main TLI 2 — Bali" corrected to **6 Dec 2026**. An older migration had rewritten 6 Dec to 6 Nov, and another reset this session on every load. Now there's a one-time correction (`meta.v476BaliTli2December`), and user edits to the session are no longer overwritten.
- TLI: past-dated sessions are not counted as "Upcoming", and they show "Past date · update status".

## v477 — Overview, Area and Contest pages

- Overview: hid the "Division Snapshot" card, which repeated the headline cards, and the duplicate name in the greeting. The Club Standing donut sits beside its counts.
- Area: AD Club Visit Reports now come before the import tools, and the section title is left-aligned.
- Contest Update: a **step switcher** (1 Club results · 2 Area results · 3 Division result) shows one stage at a time. The page went from 4,855px to 2,881px. The chosen stage is remembered (localStorage `hdg_contest_stage_v476`), and printing still includes all stages.
- Contest rows: repeated "1st/2nd/3rd place" labels removed, and ineligible clubs shown as a calm single line.

## v478 — Overview restructure, report deck, Area Directors

- **Division Overview** regrouped: headline cards → **Needs attention** (Attention List with Club Standing and Standing Action Summary) → **Areas** (Area Readiness 2×2 next to Area Membership Movement) → Renewal Outlook (duplicate "Mar 2027 secured" tile hidden) → Recognition.
- **My Area** (Area Director home), Full view: Priority Actions next to Division updates → Club Performance (full width) → Operational Progress → Recognition.
  - G2 and G4 use the standard Full view.
  - G1 (Quick view) and G3 (Simplified view) keep their custom simple views. The only change is that G1's Quick view shows Priority Actions before Club Performance, matching its own intro text.
- **Report deck** (Division and all 4 Areas): the overflowing 8-tile "Snapshot" slide is replaced by an **"at a Glance"** executive summary: 4 headline numbers, "Needs action" and "Going well". The Area Performance slide is now a 2×2 grid, and every slide fits the 16:9 frame. The Canva/PPTX export uses the same summary as slide 2 (`pptxExecSummaryV477`).

## v479 — Member tools (Agenda, TTM, Slides, Timer, Ballot)

- **Bug: the ballot was invisible in Meeting Tools for every user.** A CSS specificity conflict hid the active step. Build ballot, Enter votes and Private results now work.
- **Bug: the active meeting was forgotten on reload**, leaving Meeting Tools with "Select a meeting first" and no picker. The last meeting is now remembered (localStorage `hdg_active_meeting_v478`) and restored.
- Executive summary: CSP removed from "Needs action" (the 30 Sep deadline has passed). The fourth card shows Round 2 visits.
- AD Visit Status slide enlarged to fill the frame.
- Agenda: removed a stray literal `\n\n` printed on the page, reworded a stale "Click Parse WhatsApp" message, and renamed "Secondary information" to "Meeting setup".
- TTM tool: the picture board comes first, import comes second, and "Clear imported deck" only shows when a deck exists.
- Timer: the manual time input is styled, and the ballot "add candidate" row no longer clips.

## v480 — Bali Speakers Club slides (first pass)

- The real BSC logo (converted to white on transparent, embedded as a data URI `BSC_LOGO_WHITE_V480`): small in the top-left corner of every slide, large on the welcome slide.
- Simpler slides:
  - Evaluator slide: name plus "Evaluating X".
  - Theme: split at the colon into title and subtitle.
  - Tonight at a glance: TOM / GE / TTM only, with parenthetical notes removed.
  - Roles, GE report, Table Topics: tidy column grids.
- Details are readable (up to 30px instead of 21px), and the speaker slide shows project, time and evaluator.

## v481 — BSC deck follows the club's real Canva deck, plus hiding slides

- The deck order mirrors the club's Canva deck: Welcome → House Rules → President's opening (logo backdrop) → Toastmaster of the Evening → Theme / WOD → GE Team → Speakers (1st/2nd/3rd) → Timer's Report → Break → Table Topics™ + timing + prompts → Timer's Report → Pick the next theme → Speech Evaluation (evaluator ↔ speaker grid) → Timer's Report → Let's VOTE → GE Report → Club Business → Membership / Pathways™ / Interested to join → Hall of Fame → Group Photo → Thank you.
- The club's 3 original QR codes are embedded unchanged (`BSC_QR_V481`):
  - **Meeting agenda:** large on Welcome and House Rules, small top-right on recurring slides.
  - **Next-theme vote** (Tally).
  - **Ballot** (Tally).
- **Hide / Show any slide**, per meeting, in the Slides storyboard. Hidden slides are skipped in Present mode and the PPTX export (localStorage `hdg_hidden_slides_v481`). Five slides start hidden by default, and the bar reads "X of Y slides will be shown".
- The Slides storyboard opens on the active meeting without regenerating the agenda.

## v482 — Next-theme reveal and Hall of Fame winners

- A new form on the Slides page (BSC only) with **Next theme** (theme and question) and **Hall of Fame** (Favourite Speaker / Evaluator / Table Topics). It is pre-filled from the in-app ballot when votes were counted there, and can be typed manually when voting happens in Tally.
- New slides: "Next Theme is…" (with the next meeting date), the Hall of Fame title slide, and **one slide per winner** (the speaker slide adds the speech title). Empty ones stay hidden automatically, and winner thumbnails are blurred in the storyboard.
- Long titles push their subtitle down instead of overlapping.
- *Known defect in the v482 file: its closing `</style></body>` tags were removed by mistake. It still worked. This is fixed in v483.*

## v483 — Agenda "Roles at a glance" and Poster Generator rebuild

- **Agenda: "Roles at a glance" panel** at the top of step 2. Every parsed role and speaker is in one compact, editable table, grouped by role logic:
  - **Meeting leadership:** TOM · TTM · GE.
  - **GE's team:** Grammarian · Ah Counter · Timer · Ballot Counter · Table Topics Evaluator.
  - **Exco on duty:** President · SAA, each with "+ Appoint acting".
  - **Supporting roles** (optional): Documentation · Registration · Guest Greeter.
  - **Speakers:** name · title · evaluator · project and time.

  It edits the same fields as the full editor, with a filled count, a list of empty required roles, and Save.
- **Poster Generator rebuilt** (`posterSvgV483`): 6 layouts modelled on real Division G club posters (Split editorial, Bold colour field, Photo + info panel, Event card, Minimal illustration, Full-bleed photo), a featured / host photo upload, a vector QR code for the registration link, club colours, and per-club default layouts. It keeps the existing form, auto-fill and saved state. Export is a 1080×1350 PNG with Montserrat outlined.

## v484 — More poster templates

- 6 more layouts, for **12 in total**: Big typography, Headline banner, Date first, Pill title, Half & half, Big question.
- **Colour picker** with 7 options (club colours, Navy, Maroon, Teal, Orange, Royal blue, Black), applied to any layout, for 84 combinations.

## v485 — Poster title/subtitle, registration & contact, cleaner panels

- **Bug fix (since v483): the poster's top panel was hidden**, including the club and meeting pickers, Title, Word of the Day and Registration link. Only the old "Pick a look" buttons are hidden now.
- **Title and subtitle are separate.** The poster uses the Title field (it used to use the hidden full Agenda theme). Typing "Title: subtitle" in Title splits it automatically. The subtitle no longer gets filled with the meeting mode ("In-person") or the speech title. **All 12 layouts** show the subtitle under the title (Bold colour field, Full-bleed photo, Headline banner and Pill title didn't before; Event card and Big typography moved it under the title).
- **Registration & contact, next to the title:** registration link → QR code, WhatsApp contact and number, Instagram, and call to action. Any or all can be filled. **Every layout** shows the QR code together with WhatsApp and/or Instagram (before, the QR replaced the contacts, and 4 layouts had no QR at all). The link, WhatsApp and Instagram are **remembered per club** (`db.ui.posterClubContactV485`) and reused on that club's next posters. The auto-filled "Club #number" is no longer shown as a WhatsApp number. The club number stays small.
- **Fine-tune panels regrouped:**
  - **Meeting details:** When (date · start · end on one row) / Where / Word of the Day / Extras.
  - **Poster purpose:** replaces "Design & format". It now sets the small label above the title (Open House, Special Event, Join Us, Networking Event). Family, variant, logo and 1:1 ratio were removed, since the 12 layouts never used them.
  - **Featured person & location.**
  - The unused Badge, Description, Footer and Brand line fields are hidden.
- **Saved meeting card:** the theme is shown as title + subtitle, and TOM / TTM / GE as small cards.
- **Actions:** "Download poster PNG" is the main button. The redundant "Refresh Poster" button is gone (the preview is live).

## v486 — Tools out of beta, one-row Community tabs, optional registration

- **Out of beta:** Slides, Timer & Ballot and Poster Generator. All BETA tags were removed (sidebar, tab row and page titles).
- **"Meeting Tools" renamed to "Timer & Ballot"** everywhere users see it (the internal panel id `meetingTools` is unchanged).
- **Community tabs on one row** (director / admin view): Events · Agenda · TTM Tool · Slides · Timer & Ballot · Posters · District 87 · Recognition · Leaders. The shorter labels keep the full name as a tooltip. They fit at the app's 1180px minimum width. The member view is unchanged (its sidebar list).
- **Posters: registration link is optional.** With no link (e.g. Bali Speakers Club), posters show WhatsApp / Instagram only, "Register now" is dropped from the call to action, and Big question says "GUESTS WELCOME" instead of "SIGN UP NOW". With a link, the QR code is the main call to action (made bigger on Big question).
- **Toastmasters logo always at the top** (top-left or top-right) on all 12 layouts. Big typography, Headline banner and Event card were moved.

## v487 — Poster: featured person, address, member / guest fee

- **Featured person is the TOM (default) or the Educational speaker**, never other roles. The TOM is read from the Agenda (`roles.tom`) and the educational speaker from `education.speaker`. A "Who" picker switches between them and fills the name. Old saved roles such as "Prepared Speaker" become TOM. Layout labels follow the choice ("Toastmaster of the Meeting" / "Educational Speaker"; Headline banner: "WITH TOASTMASTER" / "EDUCATION SESSION BY").
- **Address under the venue:** a new "Address / area" field sits under Venue in Meeting details → Where (it reuses the existing location-note field). The venue name and a trailing ", Indonesia" are stripped. Every layout prints the address smaller, directly under the venue (Split editorial now puts its location under the photo).
- **Meeting fee:** new **Members** and **Guests / non-members** fields, plus an optional fee note (the old fee field). Type "Free" or a number (75000 → IDR 75K). Posters print e.g. "Members free · Guests IDR 75K". **Online meetings with no fee show "Free"**; hybrid and in-person don't. Fees are remembered per club. The fee was moved to a visible spot on crowded layouts (Event card: top strip; Headline banner: info strip).
- The "People & contact" panel is now just **Featured person**.

---

## Data additions (all optional, backward compatible)

| Where | Field | Purpose |
|---|---|---|
| `db.tlis` meta | `meta.v476BaliTli2December` | One-time Bali TLI 2 date correction flag |
| Meeting tool data | `v482Extras` `{theme, question, winners:{prepared, evaluation, topics}}` | Next-theme reveal and Hall of Fame slides (included in Full JSON backup) |
| `db.ui.clubPosterGenerator` | `v483Layout`, `v484Palette`, `personPhoto` | Poster layout, colour and host photo |
| `db.ui.clubPosterGenerator` | `feeMember`, `feeGuest`, `v487Feature`, `v487Tom`, `v487Edu` | Member / guest fee and featured-person choice |
| `db.ui.posterClubContactV485` | `{clubId: {registerUrl, contactName, contactValue, instagram, feeMember, feeGuest}}` | Per-club registration link and contacts, reused across posters |

**Browser-only conveniences (localStorage):**
- `hdg_contest_stage_v476`
- `hdg_active_meeting_v478`
- `hdg_hidden_slides_v481`

## Verified / not verified

**Verified in a desktop browser (1366×850) with sample data:**
- All pages render with no console errors.
- Division and all 4 Area decks fit the 16:9 frame.
- Hiding slides works in Present mode and the export.
- QR codes in exported images scan correctly.
- Roles-at-a-glance edits save to the meeting record.
- All 12 poster layouts render and export for all 16 clubs.
- v485: the subtitle shows on all 12 layouts; the QR code plus WhatsApp and Instagram show on all 12; the exported QR scans; the per-club link is restored after switching clubs.

**Not verified:**
- Opening the exported PPTX files in PowerPoint.
- The Word-of-the-Day online dictionary lookup.
- Voting from a real phone.
- Posters with real club photos.
- Phone layout (unchanged, desktop-only).
