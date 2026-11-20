> Public reference copy: member names and private contact details have been omitted. The original supplied notes remain on the owner’s Mac. The supplied notes retain an older v491 header; this release uses the actual v514 HTML.

# Hello Division G — changes from v487 to v514

Previous: `HelloDivisionG_v486.html`
Latest: `HelloDivisionG_v491.html` (single-file app, ~11.8 MB)

> **Privacy — read first.** The v491 HTML still contains embedded member records. The GitHub repository is **public**: do **not** commit the v491 HTML (or any copy of it) to the repo. Use it only as a local reference. The repo should only contain documentation, the sync adapter and schema code (see `sync/README.md`), never the app HTML.
>
> If the private Supabase-hosted copy needs updating, rebuild it from v491 with `python3 sync/build_website.py HelloDivisionG_v491.html PRIVATE_OUTPUT/index.html` and upload the result to the private `hdg-private-app` bucket. The three integration strings the builder looks for (`tm_division_g_dashboard_v56` storage key, `hello_division_g_durable_v1` database name, `DURABLE_INIT_PROMISE=initializeDurableStorage()`) are unchanged in v491.

## How the changes are built

- All changes are **additive** `<style id="v4xx…">` / `<script id="v4xx…">` blocks near the end of the file (ids `v487`–`v491`, plus edits inside the existing `v483-poster-engine`, `v483-roles-at-a-glance` and `v485-poster-panels-js` blocks). They wrap or extend existing functions; nothing in the stored data format is removed.
- Desktop-first. The phone layout is unchanged (the app is still desktop-only, `min-width: 1180px`).

---

## v487 — Poster: featured person, address, member / guest fee

- **Featured person is the TOM (default) or the Educational speaker**, never other roles. The TOM is read from the Agenda (`roles.tom`) and the educational speaker from `education.speaker`. A "Who" picker switches between them and fills the name. Old saved roles such as "Prepared Speaker" become TOM. Layout labels follow the choice ("Toastmaster of the Meeting" / "Educational Speaker"; Headline banner: "WITH TOASTMASTER" / "EDUCATION SESSION BY").
- **Address under the venue:** a new "Address / area" field sits under Venue in Meeting details → Where (it reuses the existing location-note field). The venue name and a trailing ", Indonesia" are stripped. Every layout prints the address smaller, directly under the venue (Split editorial now puts its location under the photo).
- **Meeting fee:** new **Members** and **Guests / non-members** fields, plus an optional fee note (the old fee field). Type "Free" or a number (75000 → IDR 75K). Posters print e.g. "Members free · Guests IDR 75K". **Online meetings with no fee show "Free"**; hybrid and in-person don't. The fee was moved to a visible spot on crowded layouts (Event card: top strip; Headline banner: info strip).
- The "People & contact" panel is now just **Featured person**.

## v488 — Fee memory per club and venue

- Each club's fee system (members, guests, fee note) is **remembered per club and per venue** and filled in automatically on the next poster.
  - **Same venue:** that venue's fee is used.
  - **New venue:** the club's usual fee is used, then remembered for that venue once edited.
  - **No saved fee yet:** the fields start empty.
- It is restored only when the club, meeting or venue changes, so it never overwrites typing. A meeting-specific fee note from the Agenda still wins over the remembered note.
- **"Remember this fee for the club's next posters"** checkbox (on by default): untick it for a one-off special-event price. A status line shows where the fee came from, e.g. "Remembered for Bali Speakers Club at 70 Fahrenheit Jimbaran · last saved 2026-11-12".
- Stored in `db.ui.posterFeeMemoryV488` (included in backups). v487's per-club fees are migrated into it automatically.

## v489 — Agenda step 2 without duplicates

Order is now **Meeting essentials → Meeting roles → Prepared speakers** (the page is ~1,000px shorter).
- **Meeting roles:** the large card-style role editor is hidden. It duplicated "Roles at a glance", which edits the same 17 fields, including the acting President / SAA switches. The compact grouped table (leadership · GE's team · exco on duty · supporting) is now the only roles editor, renamed "Meeting roles" and placed where the old one was. The old inputs stay in the page (hidden) because saving reads them, so nothing changes in saved data. Its duplicate speaker rows were removed; speakers are edited only in Prepared speakers.
- **Meeting essentials:**
  - Removed the duplicate "Meeting order" dropdown line (the 3 option cards set the same value) and the "Refresh definition" button (same action as Lookup).
  - Meeting setup is now: order cards, then one row of Agenda template · Venue · Table Topics speakers · Break (min), with the **TM / DTM toggle kept** below it.
- **Prepared speakers:** unchanged. It is the only place for Pathway, project and timing.

## v490 — Each club's meeting order is remembered

- Clubs run their meetings in different orders. The 3 **Meeting order** options are:
  - Option 1: Speeches → Evaluations → Break → Table Topics → GE.
  - Option 2: Speeches → Table Topics → Break → Evaluations → GE.
  - Option 3: Speeches → Break → Table Topics → Evaluations → GE.
- Choosing an option now also saves it as **that club's usual order**. The club's upcoming meetings without an explicit choice start with it. Past meetings keep their stored order, so printed agendas don't change.
- The card shows a "Club's usual" badge, and the note under Meeting order says it is remembered.
- Stored in `db.ui.agendaClubFlowV490` (`{clubNumber: flow}`). A meeting where the order was picked by hand gets `record.agendaFlowChosenV490 = true`.

## v491 — Meeting format linked to the form, education sessions, plain stepper

- **Meeting format** replaces the separate "Agenda template" dropdown (Meeting essentials) and the "Structure" dropdown (A4 agenda section). Both set the same `record.template`.
  - One control: **Regular · Education session · Installation · Speech marathon**, placed above Meeting order.
  - **The number of speakers follows the Prepared speakers list.** Adding or removing a speaker updates the template (Regular 1–5, Education 2–3), so the printed agenda always lists every speaker. A warning appears if a format can't list them all (e.g. more than 5 on Regular).
  - **Education session** shows Presenter and Session title fields, saved to `record.education` (the poster's "Educational speaker" option reads it).
  - **Speech marathon** hides the Table Topics speakers field and the TTM / Table Topics Evaluator roles (their values are kept).
  - The A4 section's Structure is now a read-only line ("Follows Meeting format and the speakers list · change") linking back to the form. The original selects stay in the page, hidden, because saving reads them.
- **WhatsApp parser reads the Education session block.** It recognises "Education session" / "Educational session" / "Edu session" headers, inline or followed by `Speaker / Title / Project / Time / Silent Evaluator` lines, until the next section (Prepared Speakers, Speaker 1, Roles…). It fills `record.education` = `{speaker, title, project, time, evaluator}` and picks Education + 2 or + 3 Speakers. The education speaker is not counted as a prepared speaker, and rosters without the block parse as before. Tested with the Bali Speakers Club 24 Nov 2026 roster: [example person omitted] "Creating the Best Club Climate" · Successful Club Series · 10–15 mins, plus 3 prepared speakers and an empty Speaker 4 ignored → Education + 3 Speakers.
- **Agenda stepper:** the 1 · 2 · 3 at the top (Start meeting / Review & complete / Generate) are plain numbers now, not blue buttons, so they aren't confused with the numbered section buttons below.

---

## v492 — Roster dates with a comma after the day

- The WhatsApp parser left the date blank for "📅 Friday, November 13th, 2026": the ordinal suffix was only removed when the year followed directly, so the comma broke it.
- `agendaParseDate` now removes ordinals before a comma, treats commas as spaces, and strips short or full weekday names (Fri, / Friday / Wed).
- Checked in the browser: "Friday, November 13th, 2026", "Fri, 13 Nov 2026", "13 November, 2026", "Nov 13, 2026", "Wed 2nd December 2026", "October 9th2026", "13/11/2026" and "2026-11-13" all parse correctly.

## v493 — Poster: picture as background, registration as QR or link text

- **Big typography layout:** the main picture now fills the whole poster behind the text, with a colour fade at the top, a dark fade at the bottom and a soft text shadow. When both a theme picture and a host photo are set, the host shows as a circle next to "by …". The member/guest fee is now shown in this layout too.
- **Registration "Show as" choice** (QR code / Link text) under the registration link, remembered per club (`db.ui.posterClubContactV485[club].regStyle`).
  - Link text prints the link in large type in a card sized to it, breaking long links at "/". The labels change to "REGISTER HERE" / "SIGN UP HERE".
  - Split, Field, Photo + info, Banner, Pill, Question, Typography and Minimal have their own link-text arrangement; the others reuse the shared call-to-action block.
- **Blank QR box fixed:** the QR library used to be downloaded only when another panel needed it, so a poster could show an empty "Scan to register" box. The poster now loads the library itself and redraws; while it loads, or if it can't (offline), the link is printed as text instead of leaving a blank box.
- The field label is now "Registration link (optional)".

## v494 — Toastmasters logo choice, colour or white automatically

- **Toastmasters logo** picker under the colour row: Globe (default) · Globe + Since 1924 · Wordmark + Since 1924. All are transparent PNGs embedded in the file (about 350 KB), so nothing prints in a box.
  - Colour and white versions. Globe + Since 1924's white version keeps the globe in colour and turns the "Since 1924" side white. The colour wordmark was recoloured from the high-resolution white file using the official navy and maroon.
  - **Auto / Colour / White.** Auto renders the poster without the logo, samples what is behind the logo and uses white when it is dark. The result is cached per layout, club, colour and picture. The globe always prints in full colour.
- **Consistent proportions:** each logo keeps its own aspect ratio. In Globe + Since 1924 the globe is exactly the size of the standalone globe, and the logo grows sideways. The wordmark is 72% of the globe's height and runs as wide as its artwork.
- Text next to the logo moves over by however much wider the logo is (Field, Full-bleed, Big typography, Headline banner, Pill, Question, Event header, Minimal tagline). Half & half puts the club name under a wide logo; Date first caps the logo at its colour column. Full-bleed drops its own divider line when the logo already has one.

## v495 — Saved member photos for posters

- **Featured person** (Poster → Fine-tune → Featured person) now has a photo panel for whoever is featured: **Main photo** and **2nd photo**.
  - Add a photo once and it is saved for that member. The next poster that features them gets it automatically; no re-uploading.
  - Click either photo to choose which one goes on the poster. The choice is remembered for that member.
  - Replace / Delete per photo. "No photo on this poster" leaves this poster without a photo but keeps the saved ones.
  - When the featured person changes, the previous person's photo is removed from the poster.
- Matching uses the club plus the name, ignoring "TM", "DTM" and bracketed notes, so "TM [example person omitted]" finds Sam's photos. If that club has no match, the same name saved under another club is used.
- **Saved member photos** list (in the same panel) shows everyone with saved photos, with Delete for each person.
- Photos are resized to at most 640 px (JPEG) before saving: about 40–80 KB each.
- **Privacy:** photos are stored in `db.ui.memberPhotosV495` inside the app's private storage on this device (IndexedDB), so they are also included in backups you export. They are never part of the HTML file and must not be committed to the public repo.
- The old "Featured person photo" upload in "Main picture & host photo" is hidden; the panel above replaces it.

## v496 — Photo + info layout: balanced details panel

- The bottom-right details panel uses one type scale: time 24 px semi-bold, venue 26 px bold (the only bold line), address 19 px, fee 20 px in the club colour, small print 14–16 px.
- Every line wraps or shrinks inside the panel (x 640–1040). The fee ("Members 55K · Guests 65K · dinner included") no longer runs off the edge.
- Link-text mode: a small "REGISTER HERE" label, the link on one line (shrinks to fit), then WhatsApp / IG on one line.
- QR mode: the QR sits at the right of the panel with "SCAN TO REGISTER" and the contacts on the left, sized to whatever space is left.
- Date cell: the day number is measured, and "NEXT MEETING / month / weekday" start after it, so two-digit days like 24 no longer touch "TUESDAY". Long weekdays shrink to fit.

## v497 — Headline banner: picture up to the top, colour wash

- The main picture now starts at the top of the poster and runs behind the title; its bottom edge is unchanged, above the yellow info strip.
- A club-colour fade covers the title area (almost solid at the very top, easing off just below the title), so the title stays readable on any photo.
- Light colour wash on the picture: about 20% less saturation plus a soft tint in the poster colour, so different photos look consistent with the club / palette colour.
- Without a picture the layout is unchanged.

## v498 — Club logo and tagline per club; Minimal and Full-bleed rebalanced

- **Club branding** panel (under the Toastmasters logo row), saved per club in `db.ui.clubBrandV498[clubId]`:
  - **Club logo:** upload a PNG with a transparent background (resized to 600 px, kept as PNG). Replace / Remove. "Print in poster colour" turns it into one colour that matches the poster (off by default for uploaded logos).
  - **Club tagline:** free text. Defaults: Bali Speakers Club keeps "level up your career through communication & public speaking", and Bali Toastmasters Club gets "Brave To Change". Other clubs have no tagline until one is typed; an empty tagline prints nothing.
  - Bali Speakers Club keeps its built-in logo (tinted) until a club logo is uploaded.
- **Minimal illustration header:** club logo, or the club name sized so its longest word fits (fixes "Bali Toastmasters Club" running into the tagline). The club's own tagline sits in the middle and makes room for wide Toastmasters logos.
- **Minimal illustration bottom:** one scale. Left: "word of the day" 22, the word 44, venue 28 with a smaller dot, address 19 (2 lines), fee 19 bold. Right: date pill 72 px tall, time 28, social pill 56 px tall, aligned.
- **Full-bleed bottom panel:** heading 30, the programme on one line ("Prepared Speech · Table Topics · Evaluation"), venue 19 bold, address 16, a thin divider, and registration on the right. The QR is capped at 136 px, so it no longer runs off the bottom.
- **Full-bleed date:** date and time stay clear of the "Toastmaster of the Meeting" text and drop to two lines only when they don't fit.
- Shared registration block (link-text mode): calmer scale (label 16, link 28, contacts 17).

## v499 — Subtitles fit everywhere; tighter letter spacing

- **Minimal illustration with a subtitle:** the title and subtitle are measured first and always end above the details section (y 1050). The picture gets shorter to make room, so the subtitle no longer runs into "word of the day" and the date pill. Without a subtitle it looks as before.
- **Half & half with a subtitle:** the right column (title, subtitle, word of the day, when, where) is laid out at decreasing sizes until it ends above the registration block, so the date and venue no longer collide with "Scan to register".
- **Denser lettering on all posters:** headlines (60 px+) −3.5% tracking, 34–59 px −2.5%, 20–33 px −1.5%, small print −0.5%. Text measuring includes the tracking, so wrapping and fitting stay exact.
- All 12 layouts rechecked with a long subtitle ("Can an affair of the heart become a threat to an entire nation?").

## v500 — Sister branches / extra meeting series (BTC Canggu, STC networking)

- Uses each club profile's existing **Additional meeting series** (shown on the club's information page): Bali Toastmasters in Canggu (Tropical Nomad, 1st & 3rd Wednesday 7 PM) and STC Networking Meeting (last Saturday 4 PM, venue varies). Only clubs with a series show the new controls.
- **Poster → Meeting series** (under the Club / Meeting pickers): Main or the series.
  - A series has its own **venue, address, time and next date** (taken from the series schedule, e.g. last Saturday → 28 Nov 2026), its own **registration link, WhatsApp and Instagram**, and its own **Name on the poster** (e.g. "Bali Toastmasters in Canggu", or rename STC's to "Saturnet Coworking").
  - Switching back to Main restores the main club's link and contacts; each side remembers its own. The fee is remembered per venue (v488), so Canggu and ZodiacXII keep separate prices.
  - Picking a saved Agenda meeting switches the poster to that meeting's series automatically. Meetings without a series count as main.
- **Agenda → Meeting setup → Meeting series** (next to Venue): marks a meeting as main or a series and moves the venue to the series venue when it was still the default.
- **WhatsApp parser:** a roster that mentions the series (e.g. "Canggu", "Tropical Nomad", or the poster name you gave it, such as "Saturnet") is saved as that series with its venue.
- Data: `db.ui.posterSeriesV500[clubId] = {active, stash: {__main | seriesKey: contacts}, names: {seriesKey: poster name}}`; meeting records get `meetingSeriesV500`.
- Not changed: a series doesn't yet have its own meeting order (Option 1/2/3) or its own logo / tagline; it uses the club's.

## v501 — Event card rebuilt on STC's real posters; STC and SATURNET logos

- **Event card layout** now follows Surabaya Toastmasters Club's posters (regular meeting and SATURNET), top to bottom:
  - Top banner: headline, two-line text and the sessions line.
  - Header row: Toastmasters logo with the club name and "#number | AREA | DIVISION G", or the series logo; the club logo sits top right.
  - Yellow meeting label, then the title (subtitle in yellow when there is one).
  - A word-of-the-day line: "WORD OF THE DAY (WoD)", the word in bold, then part of speech / pronunciation.
  - Yellow date box: date plus time with GMT offset (WIB +7, WITA +8, WIT +9).
  - Middle row: host photo with "TM name" and the role, then meeting location, a participation fee box (members / guests, or "FREE OF CHARGE"; a fee note below) and dress code, then the theme picture in a circle bleeding off the right edge.
  - Bottom: "Join online from anywhere · FREE · Zoom…" for hybrid / online meetings, a note for in-person series (e.g. "Let's network at SATURNET!"), otherwise "Guests welcome". Next to it, a dark **Info & registration** panel with contact name + WA number, IG and the QR (or the link as text).
  - "Follow us on social media" footer with the Instagram handle.
  - The middle row compresses slightly when a long title and subtitle need the space.
- **Logos cut from the posters** (transparent PNG, embedded): the Surabaya Toastmasters Club wordmark is now STC's built-in club logo, and the SATURNET logo is the built-in logo of the STC networking series. Both can be replaced in Club / Series branding.
- **Series branding:** while a sister series is active on the poster, the branding panel edits that series' own logo and tagline (`db.ui.clubBrandV498["clubId#seriesKey"]`).
- **Event card wording** (in the Meeting series panel): label, banner headline / text, sessions line, host role and bottom note per club or series, with suggestions shown in grey. Networking series default to the SATURNET wording ("JOIN US FOR A FUN NETWORKING EVENT!", "Sessions : Group Discussion + Networking", "Event Host", label "STC SATURDAY NETWORKING EVENT").
- The poster **colour** is remembered per series (e.g. SATURNET navy, STC maroon).
- Mixed-weight lines are drawn as separate measured texts so they export cleanly to PNG.

## v502 — SATURNET set up; its venue changes every month

- STC's networking series is called **SATURNET** by default: in the series buttons, the Agenda's Meeting series list, the branding panel, the poster ("Let's network at SATURNET!") and roster detection (a roster saying "SATURNET" is filed as that series).
- SATURNET starts with the contacts from its poster: **[example person omitted] · WA [contact number omitted] · IG @surabaya_toastmasters**. These are built-in defaults in the app file, so they work in any browser; anything typed in the panel replaces them.
- **Venue changes every month** (series whose location says "varies"):
  - Switching to the series always clears the venue; last month's venue is never reused.
  - The venue box shows "This month's venue (changes every month)" on the poster and in the Agenda.
  - The Meeting series panel shows a yellow reminder until a venue is entered, then "This month's venue: … check it before downloading".
  - A pasted roster without a venue leaves it empty instead of taking STC's regular venue; a roster with a venue keeps it.
- Fix: switching from a series back to the main meeting now restores the main contacts (falling back to the club profile's public contact) instead of keeping the series' contacts.

## v503 — Minimal layout = Bali Speakers Club's real template

- Rebuilt on BSC's own posters:
  - **Header:** club logo (club number under it on orange), the two-line tagline, and the Toastmasters globe top right.
  - **Picture:** a large picture in the middle.
  - **Title and subtitle:** a lowercase title in medium weight with a lighter subtitle.
  - **Bottom left:** "word of the day" and the word, then a location pin with venue and area, "recommended order …" (the fee note), and "and for non-member · meeting fee : 10k per person" (from the guest fee when members are free).
  - **Bottom right:** "networking starts from …", the outlined date pill ("tue may 12"), the time as "7.15 - 9.15 pm", and the "contact us:" box with an Instagram icon. When there's a registration link: the QR beside the box, or the link inside it.
- **Minimal layout style** panel (shown when this layout is picked, saved per club in `db.ui.posterStyleV503`):
  - **Background:** light cream (#FAF7F2, terracotta text) or orange (#D4512C, white text). For other clubs, "Poster colour" uses the chosen palette.
  - **Picture:** *Match the poster* recolours it (pink line-art look on cream, light/deep orange on orange) with feathered edges so it blends in, like BSC's illustrations; *Original colours* keeps the photo as is in a rounded frame.
  - **Networking from:** optional time ("6:45 pm" by default for BSC).
- The title and subtitle are measured first; the picture takes the remaining height, so long titles never collide with the details.

## v504 — Poster history per club; BTC logo, colour and Headline banner

- **Meeting history from the published posters**, added once to `db.database.meetingAgendaRecords` (the app's meeting records; flag `db.ui.posterHistoryV504`) the first time v504 opens with saved data loaded. Existing meetings with the same id are never overwritten; only empty fields are filled.
  - STC: 16 Sep, 21 Oct and 4 Nov 2026 regular meetings (theme, word of the day, TOM, Mahameru Restaurant, hybrid, business casual); 31 Oct 2026 SATURNET "Hype vs Habit" ([example person omitted], Mooi Ondomohen Food Court, filed under the SATURNET series).
  - BSC: 12 May, 26 May, 9 Jun, 23 Jun (chartering special meeting) and 14 Jul 2026 (themes with subtitles, word of the day, 70 Fahrenheit Koffie, 7:15–9:15 PM, "recommended order 50k per pax").
  - BTC: 10 Oct 2025 "Growing Together" (education session by [member detail omitted], DTM), 24 Oct 2025 "Turning Fear into Fuel" (education "The Power of Silence" by [member detail omitted]), 24 Apr 2026 "Retro Vibe" (TOM [example person omitted], word Nostalgia).
  - Member / guest amounts are not stored as notes (they belong in the per-venue fee memory), so they never print twice.
- **BTC logos** (club-supplied, transparent): 3-line in white and logo blue, and one-line in white and blue. The 3-line white logo is BTC's built-in club logo (Event card top right; tinted on the Minimal layout). The one-line logo is used in the Bold colour field header. Banner and Big typography keep the bold "BALI TOASTMASTERS CLUB PRESENTS" text, as on BTC's own posters (the thin one-line logo read worse there).
- **BTC colour:** posters default to the logo blue **#063BB2** (white and yellow text stay readable) unless another palette is picked.
- **Headline banner**, modelled on "Retro Vibe" / "Growing Together":
  - One bold info line in the yellow strip, e.g. "FRI, 24 APR 2026 · 7PM @ ZODIACXII, DPS · M: 55K, G: 65K", with contacts in a small line under it. A city is added only as a known code (Denpasar → DPS).
  - The host box shows the host photo when there is one ("WITH TOASTMASTER" / "FEATURING EDUCATION BY").
- **Fix:** picking another saved meeting now replaces the fee note with that meeting's own note (it used to carry over from the previous meeting).

## v505 — Visiting education speakers fit on posters

- Speaker lines like "[example person omitted] from Tung Chung Toastmasters Club (20-30 mins)" are split into **name** ([example person omitted]), **club** (Tung Chung Toastmasters Club) and **duration**. Also handled: "Name (Kuta Toastmasters Club)", "Name, X Toastmasters Club", "Name - 15 mins".
- **The duration is never printed on posters.** The WhatsApp parser now stores it as the education session's time (`education.time`) for the agenda and timer, and keeps the speaker as "[example person omitted] from Tung Chung Toastmasters Club".
- A small credit replaces the long name:
  - **Headline banner:** "EDUCATION SESSION BY" (small) / "DTM BHARAT" / "from Tung Chung Toastmasters Club" (small, white).
  - **Big typography:** "education session by" / "[example person omitted]" / "from …", with the venue moved down to make room.
  - **Event card and Full-bleed:** the name without an extra "TM" in front, and the club in small text under it.
- Every other layout prints just the name.

## v506 — Big typography: readable text on photos, link without a box

- Two soft, partly transparent dark radial gradients (bottom right behind the speaker / venue / registration, bottom left behind the date and fee) make the text readable on busy photos without adding boxes.
- The venue stays bold yellow; the address is now clearer white text (weight 500, up to 2 lines).
- **Link-text registration** no longer uses a white card: a small yellow "REGISTER HERE", the link in bold white (breaks at "/", up to 2 lines) and a thin yellow rule under it. QR mode is unchanged (a QR needs its white background to scan).

## v507 — Headline banner: condensed one-line title

- "BALI TOASTMASTERS CLUB PRESENTS" (or any club) is smaller (26 px, was 32) and starts further left (x 44, was 60).
- The title is set in a **condensed** style: the poster font squeezed to 56% width (a transform, so it exports exactly like the preview; no extra font file). Short themes like "PLOT TWIST" / "RETRO VIBE" sit on **one line** at up to 330 px tall; long themes still wrap to two lines.

## v508 — Big typography: bottom columns end level; no link underline

- The bottom-left column (fee, date, contacts) and the bottom-right column (speaker, venue, address, registration) are now stacked upward from the same bottom line, so both end at the same height. The QR (QR mode) ends on that line too. The host photo, when there is one, sits above the right column.
- The yellow line under the link text is removed (a printed link isn't clickable).

## v509 — Fee on separate lines; BTC address cleaned up

- **Big typography:** the fee prints as separate lines without "IDR": "Members 55K" / "Guests 65K" / "dinner included".
- **Big typography:** the address prints as street / city: "Jl. Raya Puputan No. 54" / "Denpasar, Bali".
- **BTC address** in the club profile is now "ZodiacXII · Jl. Raya Puputan No. 54, Denpasar, Bali" (no "Coffee & Eatery", no "Dangin Puri Kelod"); `locationAddress` is "Jl. Raya Puputan No. 54, Denpasar, Bali". Changed in the embedded club data and, once, in saved data (only while it still has the old wording), including a BTC poster that still had the old note.

## v510 — Big typography: even top and bottom margins

- Both bottom columns now end about 88 px above the bottom edge (was about 54 px), roughly matching the header's top margin.

## v511 — No white strip under layout thumbnails

- The "Choose a design" thumbnails had a white frame background; when a mini-poster's height rounded to a fraction of a pixel, a thin white line showed under it (only visible on light-bottomed layouts). The frame is now transparent and fixed to the poster's 4:5 shape, with the poster filling it exactly. The posters themselves were never affected.

## v512 — Theme picture panel redesigned

- "Main picture & host photo" is now **Theme picture** (Optional · the main picture on most layouts).
- **No picture:** a dashed drop area, "Drop a picture here, or choose a file", with "JPG or PNG. It is cropped automatically to fit each layout." Click it or drag a picture onto it.
- **With a picture:** a preview thumbnail, the file name, **Replace** and **Remove** buttons; dropping another picture replaces it.
- A note points to **Featured person** for the Toastmaster / education speaker photo (the link opens that section).
- Hidden: the bare file button, the separate "Remove photo" button, the filename line and the "Brand overlay strength" slider, which the current poster engine no longer uses.

## v513 — Poster purpose wired into every layout

- The purpose shows in each layout's natural label spot: Open House, Special Event, Join Us (Membership), Networking Event, Featured Session (Speaker). **Regular Meeting** keeps the usual labels.
  - Split editorial and Half & half: the small label above the title (as before).
  - Bold colour field and Full-bleed: replaces "Theme:" / "Meeting Theme:" (e.g. "Open House:").
  - Photo + info and Pill title: "CLUB · OPEN HOUSE" in the header.
  - Headline banner: "CLUB PRESENTS · OPEN HOUSE".
  - Big typography: the purpose above the word of the day (top right).
  - Date first: under the club number.
  - Minimal (BSC): a small lowercase label above the title.
  - Big question: "Join our open house:" / "Become a member. Join us for:" / "Join us for a featured session:" etc.
- **Event card:** the label ("BSC OPEN HOUSE", "BSC JOIN US", …) and the banner wording follow the purpose (e.g. "JOIN OUR OPEN HOUSE!", "JOIN US AS A MEMBER!", "JOIN US FOR A FEATURED SESSION!"). Networking series keep their own SATURNET wording, and anything typed in Event card wording still wins.
- **Speaker / Featured Session** now makes the education speaker the featured person.
- Picking a meeting no longer forces "Speaker" just because it has an education speaker; it starts as Regular Meeting.

## v514 — Transparent pictures import correctly

- **Cause:** the picture import always flattened pictures to JPEG, which can't hold transparency, so a transparent background became black. "Match the poster" then recoloured that black block into a pink (cream) or dark-orange (orange) block, and the oval fade made it look like a bulb.
- **Import:** a picture with a transparent background (PNG / WebP / GIF / SVG with see-through pixels) is now kept as PNG (up to 1400 px); ordinary photos stay JPEG (up to 1800 px). `backgroundImageAlpha` records which.
- **Minimal layout, Match the poster:** transparent line art has only its lines recoloured, with no fade: pink lines on cream, light-orange lines on orange (like BSC's own posters). Photos get a soft, even rectangular edge instead of the oval.
- **Original colours** shows transparent pictures with the poster background showing through.
- Pictures uploaded before v514 were already converted to JPEG, so a transparent picture needs to be uploaded again once.

## Data additions in v487–v491 (all optional, backward compatible)

| Where | Field | Purpose |
|---|---|---|
| `db.ui.clubPosterGenerator` | `feeMember`, `feeGuest`, `v487Feature`, `v487Tom`, `v487Edu` | Poster member / guest fee and featured-person choice |
| `db.ui.posterFeeMemoryV488` | `{clubId: {club: {feeMember, feeGuest, fee}, venues: {venueKey: {…}}, updated}}` | Remembered fee system per club and venue |
| `db.ui.agendaClubFlowV490` | `{clubNumber: flow}` | Each club's usual meeting order |
| Meeting record | `agendaFlowChosenV490` | The order was picked by hand for this meeting |
| Meeting record | `education.{speaker, title, project, time, evaluator}` | Education session (from the parser or the form) |

## Verified / not verified

**Verified in a desktop browser (1366×850) with sample data:**
- No console errors.
- Posters:
  - Featured person switches TOM ↔ Educational speaker.
  - The address prints under the venue and the member/guest fee prints on all 12 layouts.
  - Online meetings with no fee show "Free"; hybrid ones don't.
  - The fee memory restores per club and venue, and a club with no saved fee starts empty.
- Agenda:
  - The single Meeting roles editor saves to the record, and the TM/DTM toggle is still present.
  - The club meeting order is remembered for upcoming meetings only.
  - Meeting format follows speaker add/remove; the Education and Speech marathon formats work.
  - The education roster parses into Education + 3 Speakers, and the A4 agenda shows the session.
  - Roster dates written as "Friday, November 13th, 2026" parse (v492).
- Picture import (v514): the club's line-art WebP (transparent) kept as PNG and rendered on cream / orange in both picture styles; a JPEG photo stays JPEG with a soft edge; settings restored; no console errors.
- Poster purpose (v513): Open House rendered in all 12 layouts; Event card label/banner for Regular, Membership, Speaker, Networking; Speaker switches the featured person; settings restored; no console errors.
- Theme picture (v512): drag-and-drop upload, preview with Replace / Remove, Remove back to the empty state; the poster picks up the picture; no console errors.
- Thumbnails (v511): all 12 thumbnails measured with 0 px gap to their frame.
- Margins (v510): Plot Twist rendered with BTC data; bottom lines end ~88 px from the edge; no console errors.
- Fee / address (v509): BTC profile updated after reload; Plot Twist shows "Members 55K / Guests 65K / dinner included" and the two-line address; settings restored; no console errors.
- Big typography (v508): Plot Twist with an education speaker + link text, and with a TOM + QR; columns end level; settings restored; no console errors.
- Headline banner (v507): Plot Twist, Retro Vibe (one line) and When Love Meets National Security (two lines) with Globe + Since 1924; settings restored; no console errors.
- Big typography (v506): Plot Twist with a test photo in link-text and QR mode; settings restored; no console errors.
- Edu speaker (v505): the Plot Twist roster with "[example person omitted] from Tung Chung Toastmasters Club (20-30 mins)" checked in the parser (time 20-30 mins) and on Headline banner, Big typography, Event card and Full-bleed; settings restored; no console errors.
- History / BTC (v504): 12 poster meetings added once and not duplicated after reload; BTC Retro Vibe checked in Headline banner, Big typography and Bold colour field; BSC banner checked; poster settings restored from a backup; no console errors.
- Minimal / BSC (v503): rebuilt "marriage versus money" and "AI, influencer & fake lifestyles" on cream and orange, picture matched and original; state restored from a backup afterwards; no console errors.
- SATURNET (v502): name and contacts appear by default; venue cleared on every switch with the reminder shown; main contacts restored when switching back; rosters (SATURNET with / without a venue, STC regular, Canggu) parse correctly; state restored afterwards; no console errors.
- Event card (v501): rebuilt STC "Beyond the Echo Chamber", SATURNET "Hype vs Habit" and Bali Speakers Club (with a long subtitle) in the browser and compared them with the real posters; state restored from a backup afterwards; no console errors.
- Series (v500): BTC main ↔ Canggu on the poster (venue, time, name, separate registration links restored on each switch), STC networking renamed to Saturnet (4:00 PM, last Saturday 28 Nov 2026, Surabaya), agenda series select and venue swap, parser detects a Canggu roster; all test data removed and saved contacts restored; no console errors.
- Posters (v499): all 12 layouts with and without a long subtitle; tighter letter spacing on all text; test values restored; no console errors.
- Posters (v498): Minimal checked for Bali Speakers Club and Bali Toastmasters Club; club logo upload / Remove tested (test logo deleted); Full-bleed checked with QR and link text; no console errors.
- Posters (v497): Headline banner checked with a test picture in club colour, navy and teal; title readable, bottom edge unchanged; no console errors.
- Posters (v496): Photo + info details panel checked with link text, QR and no registration, and with 13 Friday / 25 Wednesday / 11 Wednesday dates; test values restored; no console errors.
- Posters (v495): saving main and 2nd photos, automatic use when the person is featured again (including "TM [example person omitted]"), switching people clears the photo, "No photo" sticks across redraws, photos survive a reload; test photos deleted afterwards; no console errors.
- Posters (v494): all 12 layouts checked with the three logo styles; auto picked white on dark backgrounds and colour on light ones; the Globe + Since 1924 globe matches the standalone globe; no console errors.
- Posters (v493): all 12 layouts rendered through the PNG export in QR mode and link-text mode, with and without a picture; QR library loads on a fresh page; no console errors.

**Not verified:**
- Opening exported PPTX files in PowerPoint.
- Posters with real photos.
- Phone layout (unchanged, desktop-only).
