# Hello Division G v632

The supplied desktop release adds the Projects & Meetings workspace and DCP tracking. It also refines meeting roster and speech imports, agenda production, poster controls, Community page headers, and the Overview. Two Toastmasters themes join Classic blue.

## Protected release

| Asset | SHA-256 |
| --- | --- |
| Supplied offline v632 HTML | `f25b7f5edd31d9b77c3b244dcb1016f67c88be482d54d7ef222bfdad1e096aa9` |
| Connected v632 HTML | `9280e1836dbe980b6d3a19b98a3fb8f61a73003d5579e4f8e9c46f125b309a6f` |

The connected build uses the existing Supabase Auth, officer approval, and revisioned save flow. It omits embedded November roster migrations and startup nickname, attendance, and past-officer inserts. The release package contains no database import. Review any historical data updates separately against the current shared records.

The hosted build disables Projects & Meetings because its director-only notes would otherwise be stored in the officer-readable snapshot. The shared serializer drops workspace records, including those in imported backups. The supplied offline file retains its workspace. Re-enable the hosted workspace when director authorization can be enforced on its own records in Supabase.

The build was uploaded as `hdg-private-app/v632.html`. The version-specific storage policy passed transaction-scoped checks for approved, unapproved, revoked, and anonymous access. All 151 inline scripts parsed. Mocked tests covered the sign-in gate, release marker, save retry and conflict handling, and exclusion of director workspace records from the shared snapshot. Real officer sign-in, browser sync, and iPhone verification remain pilot tasks. Revert the launcher change to return to the retained v514 object.

## Website and native iPhone app

1. Use the existing GitHub Pages site for an officer pilot. Verify approved login, access denial, restore from a backup, and an edit that survives reload. Check narrow layouts, especially Overview and Data Hub.
2. Extract member-bearing defaults, embedded contacts and attachments, and startup data patches from the legacy HTML. Keep the reusable source in Git and the records behind Supabase Auth and row-level security. Rebuild releases from a clean checkout.
3. Connect the current Swift app using the same Supabase account and approval checks. Adapt the earlier download-only prototype to the current import mapping, using the shared revision to detect changes and preserving a device recovery copy. Start with clubs, members, events, DCP, and meeting agendas.
4. Enable writes one workflow at a time. Start with a meeting that can be edited on web and opened on iPhone. Then support phone edits with revision checks, retry IDs, and conflicts that preserve both users' work. Move toward record-level writes so the phone never needs to replace the desktop snapshot. Verify the round trip on a real iPhone before wider distribution.
