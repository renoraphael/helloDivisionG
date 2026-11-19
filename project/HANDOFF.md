# Current handoff

Updated 19 November 2026 (Asia/Makassar).

## Owner's objective
Let Claude, Grok, Antigravity, Codex, and other assistants work on the same Hello Division G project without losing changes, leaking member data, or relying on one chat's memory.

## Current state
- Repository is public by explicit owner approval.
- GitHub Pages main / docs serves the sign-in and registration screens and the standalone ballot page.
- Supabase Storage holds the protected v632 build. PostgreSQL holds shared web records.
- The web backup is authoritative. iPhone downloads only.
- First-administrator preapproval and the owner's confirmed account exist. The owner can use email-link sign-in or password recovery. Never store their email/password in this handoff.
- An existing draft PR on setup/central-database-plan holds backend/iPhone setup and earlier integration notes. Check actual status before reusing it.
- The generated private-app/v632.html is ignored by Git.

## Member Community and link ballots

The Member header uses the signed-in account’s active roster name. The Member-only build omits the sidebar’s Community / Member tools heading and uses the shorter District 87 · Region 9 subbrand. The release uses `v632-member-profile.html` with a version-specific Storage policy. Keep the prior asset available for rollback.


The v632 Community release uses the same Supabase Auth instance. Confirmed active roster emails open the member Community view. The signed-in Member view runs the original v632 markup, styles, and meeting tools. Build it using `deployment/build_member_v632.py` and the exact supplied source, then upload the ignored artifact as `hdg-private-app/v632-member.html`. The builder strips the offline roster, officer contacts, personal aliases, reports, examples containing private records, and historical meeting image/QR references. Supabase sends only the Community projection. Its storage policy lets members download the Member artifact and keeps the officer snapshot and full app protected. The original Member workspace saves its drafts in a per-account browser namespace. Leadership access still requires approval, and leaders retain the existing shared dashboard. Temporary beta access is granted by account ID. The unsigned ballot page receives only the ballot title and candidate choices. The officer who publishes the ballot can refresh the private link tally from Timer & Ballot.

Apply `deployment/community-access.sql`, upload the private `v632-community.html` build, and run `deployment/test-community-access.sql` before enabling the launcher. Keep the original `v632.html` and prior launcher for rollback. Member email registration requires custom SMTP for external delivery. The live pilot confirmed the member login. A leadership login smoke test found a local IndexedDB write race between startup activity and the first shared-state load. The adapter serializes writes in a tab and uses a Web Lock across tabs when available. The native iPhone app is outside this release.

## Brand constitution update (19 November 2026)

Branch docs/ti-brand-constitution adds project/TI_BRAND_CONSTITUTION.md (Toastmasters colours, gradients, transparencies, fonts, and the owner's colour/type hierarchy rules) and project/TI_BRAND_MANUAL_NOTES.md (summary of the 41-page Brand Manual v2.0), with a pointer in AGENTS.md. The full manual PDF stays local in project/reference/, which is git-ignored because it is third-party copyrighted material. Documentation only: no app, launcher, database, or protected-asset changes, and nothing deployed. The owner's Division G logo is a recorded exception to the manual's rule against custom Division logos. The owner-approved Toastmasters themes in the separate private v632 build were not touched. Next step: owner reviews and merges; future visual work follows the constitution.

## Sign-up screen redesign (19 November 2026)

Branch feat/signup-screen-redesign (stacked on fix/launcher-match-offline-design) redesigns only the Create account screen: a two-panel layout with a short "how sign-up works" panel and the same form, stacking on phones. The sign-in screen, the Member Community and Leadership views, Supabase settings, and all sign-up logic (fields, validation messages, request, confirmation message) are unchanged. Added presentation only: a mode attribute on the gate, a live "12 characters" check mark, and the side panel markup. Checked locally in Classic, Toastmasters blue and maroon at desktop and 375 px, toggling between sign-in and sign-up, and the short-password validation path with no network request. Not run: a real account creation (it would create a live Supabase user and send an email), email confirmation, or the live site. Nothing deployed.

## Launcher design follows the offline v632 (19 November 2026)

Branch fix/launcher-match-offline-design restyles the public sign-in shell, status bar and ballot page (docs/cloud-sync.css, docs/index.html, docs/ballot.html) to match the offline v632 design: Classic blue by default, Toastmasters blue or maroon when chosen, Montserrat headings and Source Sans 3 body text, Happy Yellow only as the card accent. Colours were read from the offline v632 build running locally. The inline boot script reads the same localStorage key the app writes (hdg_theme_v622), so the choice carries over on the same browser and origin. Montserrat and Source Sans 3 (SIL Open Font License) are added as woff2 files under docs/fonts/. The offline v632 file and the protected Supabase build were not modified or rebuilt, and nothing was deployed. Checked locally: sign-in page in all three themes at desktop and 375 px width, no horizontal scroll, text contrast at least 5:1. Not checked: a real sign-in, the private connected app on the live site, or the member Community pages. The connected app on the site must be rebuilt from the latest offline v632 only if its hash differs from f25b7f5e (see V632_RELEASE.md); that needs the owner's private file and Supabase access.

## v632 update

See [V632_RELEASE.md](V632_RELEASE.md) for source hashes, rollout order, and the mobile integration path. The connected build omits offline roster, nickname, and historical attendance backfills so those updates can be reviewed independently against the shared database. The v632 storage policy passed approval and access tests. The hosted build disables Projects & Meetings and filters that workspace out of shared snapshots because the notes are director-only. Keep v514 available for rollback.

## v514 update
Owner supplied v514 and v487–v514 change notes; the interrupted v491 release was superseded. The connected build preserves all offline source except the three established connection hooks and injected adapter/styles/release marker. v514 adds agenda format/education parsing, meeting-order memory, poster branding/series/layout refinements, and transparent picture import. No manual offline database import is performed. The supplied app includes automatic v504 history additions and a conditional v509 address correction; these remain active. Protected v487 is retained for rollback. All 104 inline scripts parse and 26/26 synthetic browser checks pass, including shared saves, education/date parsing, remembered meeting order and transparent PNG/opaque JPEG imports. Protected v514 upload completed; storage access tests pass for approved, anonymous, unapproved and revoked roles, with test identities rolled back. Branch update/v514 switches the launcher; verify Pages after merge. Existing local deletions of the v484/v487 public alias files predated this task and are left unstaged.

## Prior v487 update
The owner supplied v487 and v476–v487 notes. New changes refine poster title/subtitle, optional registration, per-club contacts/fees, featured TOM/educational speaker, and venue addresses. Protected v484 and v475 remain available for rollback. The v487 build preserves the supplied source outside the established cloud injection and three hooks. No database import is performed. All 86 inline scripts parse. Synthetic tests pass 26/28: all 17 prior cloud integration checks pass. The source omits fees in Full-bleed photo, Big typography, Pill title and Half & half, and Split editorial truncates a long WhatsApp number with a QR present. These source limitations are recorded in V487_RELEASE.json. The protected v487 object is uploaded and storage access tests pass for approved, unapproved, revoked and anonymous roles; synthetic identities rolled back. Branch update/v487 activates it through the public launcher when merged. Retain v484 for rollback; verify the Pages workflow and live sign-in gate after merge.

## Prior v484 update
The owner supplied an offline Opus-refined v484 HTML and v476–v484 change notes. The private build preserves the source outside the three required connection hooks and injected adapter/styles/version marker. Integration initializes an otherwise implicit agendaGeneratedRecordId before restored meeting selection. All 85 inline scripts parse; 17 synthetic browser checks passed, including all 84 poster layout/palette SVG combinations, roles edits reaching shared saves, meeting extras, slide hiding, active-meeting storage, and the one-time TLI correction without overwriting a later user date.

This release changes app code only. It does not import the offline app's bundled data over the authoritative Supabase snapshot. Browser-only preferences remain local. The offline HTML and generated connected HTML are ignored and never committed. Keep the prior protected v475 object for rollback.

## Verified
Pages deployment and live sign-in gate; synthetic database access/revision/retry tests; private bucket and approved/unapproved/anonymous/revoked download rules; simulated authentication and app-loader behavior. No member records were committed.

## Still open
1. Owner-assisted real login/password-reset and authenticated browser sync round-trip.
2. Full iPhone build and download verification in Xcode.
3. Extract all embedded member data from legacy v514 so the entire application source can be tracked safely and rebuilt from GitHub.
4. Reconcile the draft backend branch with the deployed launcher before treating any draft source as production.

## Additional verification limits for v484
The provided author's notes report more extensive standalone desktop checks. Our independent checks use mocked Supabase transport and synthetic records. Real account end-to-end testing, actual PowerPoint file opening, dictionary lookup, phone voting, photo-based posters, and a full iPhone build remain unverified. The app remains desktop-only as supplied.

## Next assistant entry
Read START_HERE.md and AGENTS.md. Inspect git status and the current commit. Ask for the owner's specific next task if none is provided. Use a task branch. Do not overwrite the protected app or database as an incidental part of a small UI change.

## Update this record after work
Record the task, branch/commit, files changed, checks actually run, deployment state, private asset hash if it changed, unresolved problems, and the exact next step. No member records, passwords, tokens, or private exports.
