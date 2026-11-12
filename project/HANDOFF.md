# Current handoff

Updated: 12 November 2026 (Asia/Makassar).

## Owner's objective
Let Claude, Grok, Antigravity, Codex, and other assistants work on the same Hello Division G project without losing changes, leaking member data, or relying on one chat's memory.

## Current state
- Repository is public by explicit owner approval.
- GitHub Pages main / docs serves the officer sign-in launcher.
- The connected full v487 app is private in Supabase Storage; PostgreSQL holds shared web records.
- The web backup is authoritative. iPhone downloads only.
- First-administrator preapproval and the owner's confirmed account exist. The owner can use email-link sign-in or password recovery. Never store their email/password in this handoff.
- An existing draft PR on setup/central-database-plan holds backend/iPhone setup and earlier integration notes. Check actual status before reusing it.
- A local shared project copy includes ignored private-app/v487.html. This file is absent from GitHub by design.

## v487 update
The owner supplied v487 and v476–v487 notes. New changes refine poster title/subtitle, optional registration, per-club contacts/fees, featured TOM/educational speaker, and venue addresses. Protected v484 and v475 remain available for rollback. The v487 build preserves the supplied source outside the established cloud injection and three hooks. No database import is performed. All 86 inline scripts parse. Synthetic tests pass 26/28: all 17 prior cloud integration checks pass. The source omits fees in Full-bleed photo, Big typography, Pill title and Half & half, and Split editorial truncates a long WhatsApp number with a QR present. These source limitations are recorded in V487_RELEASE.json. The protected v487 object is uploaded and storage access tests pass for approved, unapproved, revoked and anonymous roles; synthetic identities rolled back. Branch update/v487 activates it through the public launcher when merged. Retain v484 for rollback; verify the Pages workflow and live sign-in gate after merge.

## Prior v484 update
The owner supplied an offline Opus-refined v484 HTML and v476–v484 change notes. The private build preserves the source outside the three required connection hooks and injected adapter/styles/version marker. Integration initializes an otherwise implicit agendaGeneratedRecordId before restored meeting selection. All 85 inline scripts parse; 17 synthetic browser checks passed, including all 84 poster layout/palette SVG combinations, roles edits reaching shared saves, meeting extras, slide hiding, active-meeting storage, and the one-time TLI correction without overwriting a later user date.

This release changes app code only. It does not import the offline app's bundled data over the authoritative Supabase snapshot. Browser-only preferences remain local. The offline HTML and generated connected HTML are ignored and never committed. Keep the prior protected v475 object for rollback.

## Verified
Pages deployment and live sign-in gate; synthetic database access/revision/retry tests; private bucket and approved/unapproved/anonymous/revoked download rules; simulated authentication and app-loader behavior. No member records were committed.

## Still open
1. Owner-assisted real login/password-reset and authenticated browser sync round-trip.
2. Full iPhone build and download verification in Xcode.
3. Extract all embedded member data from legacy v487 so the entire application source can be tracked safely and rebuilt from GitHub.
4. Reconcile the draft backend branch with the deployed launcher before treating any draft source as production.

## Additional verification limits for v484
The provided author's notes report more extensive standalone desktop checks. Our independent checks use mocked Supabase transport and synthetic records. Real account end-to-end testing, actual PowerPoint file opening, dictionary lookup, phone voting, photo-based posters, and a full iPhone build remain unverified. The app remains desktop-only as supplied.

## Next assistant entry
Read START_HERE.md and AGENTS.md. Inspect git status and the current commit. Ask for the owner's specific next task if none is provided. Use a task branch. Do not overwrite the protected app or database as an incidental part of a small UI change.

## Update this record after work
Record the task, branch/commit, files changed, checks actually run, deployment state, private asset hash if it changed, unresolved problems, and the exact next step. No member records, passwords, tokens, or private exports.
