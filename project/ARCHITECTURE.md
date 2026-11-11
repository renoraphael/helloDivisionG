# Current architecture

- **Public entry:** GitHub Pages publishes main / docs. The HTML files are sign-in launchers, not the complete legacy app.
- **Client adapter:** docs/cloud-sync.js implements password/email-link login, account creation, password recovery, officer approval UI, and shared-state sync. docs/cloud-sync.css styles it. docs/entry.js starts loader mode.
- **Protected app:** Supabase Storage bucket hdg-private-app is private. Its v475.html object contains the connected full app and legacy embedded records. Only currently approved Division G officers can download it. The local editing copy is private-app/v475.html when supplied by the owner; it is ignored by Git.
- **Canonical records:** Supabase PostgreSQL public.hdg_sync_state holds the shared web snapshot with server revisions. hdg_officer_access controls approved user IDs. Private schemas retain imports, save receipts, and revision history. Client access uses a publishable key, authenticated sessions, and RLS; privileged keys never belong in the app.
- **iPhone:** A separate Xcode project copy and adapter were prepared. Downloads replace the phone working copy only after a recovery backup. Phone writes are not uploaded. Full Xcode build and authenticated end-to-end tests still need verification.

## Needed architectural improvement
Extract member-bearing defaults, historical seed arrays, embedded private attachments, and migration snapshots from the legacy HTML into protected data. Then check the complete clean app source and a reproducible build into GitHub. Verify that a clean approved login reproduces existing functionality before switching production. Until then, the public repository alone cannot rebuild the full app.

Keep data changes distinct from code changes. Editing a member record does not require redeploying the website; editing a function in the protected HTML does.
