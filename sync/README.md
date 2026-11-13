# Hello Division G — central sync

## Status
The protected sync dataset is initialized from the verified 11 November web backup. The website adapter supports officer login, server-acknowledged saves, revision polling, local unsynced drafts, conflict recovery, and administrator approval/revocation. The phone adapter downloads web data only. It cannot upload a phone snapshot or replace the authoritative dataset.

First administrator preapproval is enabled and the account email is confirmed. A real account sign-in still needs owner participation. End-to-end authenticated browser/phone testing remains pending until the owner completes sign-in. Do not describe this as production-ready.

## Private local website
Run `python3 sync/build_website.py ORIGINAL_V475.html PRIVATE_OUTPUT/index.html`, then serve PRIVATE_OUTPUT locally with `python3 -m http.server 3000 --bind 127.0.0.1 --directory PRIVATE_OUTPUT`. Open `http://localhost:3000/`.

The builder changes the browser cache names, adds the adapter, and defers storage initialization until approval is verified. The supplied original and its IndexedDB database remain unchanged. Per-device interface preferences are excluded from shared writes.

**The supplied HTML contains legacy embedded personal records. The generated file remains a private development copy. Do not upload or publicly host it.** Remove legacy data embedded throughout the app before distribution. This repository stores adapter/schema code only, never the original HTML, backup JSON, or generated private import statements.

## Officer access
Use **Sign in** for an existing app password, **Forgot password?** to choose/reset a password through a verified email link, **Create account** for a new login, or **Email me a sign-in link** for passwordless web access. Recovery links open a dedicated page to enter and confirm a new password; only the user submits it. The email-link and recovery buttons send email only when clicked by the user. Create and confirm new app logins through the connected website. This is separate from a Supabase dashboard login. A verified account has no data access until its user ID is approved. The first administrator is activated privately; email addresses are not committed. Administrators can use **Officer access** in the sync bar to approve or revoke another confirmed account by email. Approval does not send an invitation. Officers create their own logins first. Existing dashboard preview profiles do not grant access.

Only the publishable client key is in the adapters. Do not substitute a secret or service-role key. Supabase Auth validates sessions; database policies check the current approval registry on every read. The save function and officer management function check current approval server-side. App clients cannot write the approval registry or shared table directly. Revocation blocks future server operations; already downloaded data is still present in local recovery caches.

## Saves and conflicts
The website uploads shared database/settings snapshots through a guarded server function. The server locks the shared row and verifies the expected server revision. A unique request ID makes retrying the same request idempotent. Prior revisions remain in a private history table. Invalid/empty replacements, missing database fields, and shared device UI are rejected.

Pending local drafts use separate per-document IndexedDB records, so concurrent tabs do not overwrite one another's pending record. Network failures retain the same request ID and payload. Stale saves freeze instead of overwriting a newer revision. The user can download local edits or preserve them in recovery and load the shared state. Multiple recovered drafts remain in IndexedDB recovery records; the current download button exports the first recovered draft. Further draft-management UI is not yet implemented.

An online, clean website checks for newer revisions every 30 seconds and when it becomes visible. A changed local snapshot, local save in progress, pending write, or unresolved conflict blocks automatic replacement. Approval is rechecked on reads; offline revocation cannot erase already cached records. Authentication sessions are stored in browser sessionStorage, not permanent localStorage.

## iPhone adapter
`ios/HDGCloudSync.swift` and the two patch files describe the changes to the supplied project. A complete private project copy is delivered locally. The copy removes BundledStarterData.json, accepts web schemas 3 and 4, and gates the app behind a verified officer login. Tokens remain in memory. First sign-in downloads the web snapshot after backing up existing phone data. The Sync tab checks for a new revision every 45 seconds and offers explicit refresh; phone changes are not uploaded. Before every refresh the previous phone data is copied to the app's Application Support/CloudRecovery folder. A failed backup stops replacement.

## Database setup
Apply `database/bootstrap.sql` first, import the web data privately, and then apply `sync/schema.sql` once, followed by `sync/officer-management.sql`. The schema initializes the shared state only if it is absent; it never overwrites an existing state. The private source import remains unchanged.

For a different deployment, parameterize the initial import selection and replace the project URL/publishable key in both adapters. Administrator email activation stays outside source control. Configure Supabase Auth redirect URLs for any eventual hosted website; local testing uses the default localhost:3000 origin.

## Validation performed
- Live PostgreSQL transaction tests passed: unapproved/anonymous reads and writes blocked; approved read/save allowed; revision advances; stale save rejected; retry idempotency; direct-write bypass blocked; revoked officer blocked. Synthetic users and writes rolled back.
- Live officer-management tests passed: self-approval blocked; administrator approval enables access; revocation removes access. Synthetic users and approvals rolled back.
- Real REST API anonymous request returned HTTP 401 / PostgreSQL 42501.
- Sync queue tests passed: unchanged saves skipped, immutable snapshots, edit coalescing, edits reversing an in-flight save, offline retry identity, conflict preservation.
- Browser sign-in gate inspected at desktop and 390px mobile width. No startup error was observed.
- Modified Swift files parsed. The isolated network layer type-checked. Full simulator build was attempted but blocked by this environment's inability to run Xcode macro/plugin and simulator services; verify the full project in Xcode before using it.
- Real account login, authenticated browser edit/reload, and phone download remain to be tested with the owner.

Authentication request tests passed with mock transport: passwordless email request, recovery request, recovery-link callback, password mismatch rejection, and authenticated PUT password update. These tests send no real email and change no real credentials. Real email-link/reset completion still needs the owner.
