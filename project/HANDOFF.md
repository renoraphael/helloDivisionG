# Current handoff

Updated: 11 November 2026 (Asia/Makassar).

## Owner's objective
Let Claude, Grok, Antigravity, Codex, and other assistants work on the same Hello Division G project without losing changes, leaking member data, or relying on one chat's memory.

## Current state
- Repository is public by explicit owner approval.
- GitHub Pages main / docs serves the officer sign-in launcher.
- The connected full v475 app is private in Supabase Storage; PostgreSQL holds shared web records.
- The web backup is authoritative. iPhone downloads only.
- First-administrator preapproval and the owner's confirmed account exist. The owner can use email-link sign-in or password recovery. Never store their email/password in this handoff.
- An existing draft PR on setup/central-database-plan holds backend/iPhone setup and earlier integration notes. Check actual status before reusing it.
- A local shared project copy includes ignored private-app/v475.html. This file is absent from GitHub by design.

## Verified
Pages deployment and live sign-in gate; synthetic database access/revision/retry tests; private bucket and approved/unapproved/anonymous/revoked download rules; simulated authentication and app-loader behavior. No member records were committed.

## Still open
1. Owner-assisted real login/password-reset and authenticated browser sync round-trip.
2. Full iPhone build and download verification in Xcode.
3. Extract all embedded member data from legacy v475 so the entire application source can be tracked safely and rebuilt from GitHub.
4. Reconcile the draft backend branch with the deployed launcher before treating any draft source as production.

## Next assistant entry
Read START_HERE.md and AGENTS.md. Inspect git status and the current commit. Ask for the owner's specific next task if none is provided. Use a task branch. Do not overwrite the protected app or database as an incidental part of a small UI change.

## Update this record after work
Record the task, branch/commit, files changed, checks actually run, deployment state, private asset hash if it changed, unresolved problems, and the exact next step. No member records, passwords, tokens, or private exports.
