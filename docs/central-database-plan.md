# Central database migration

## Confirmed requirements
- Prioritize the website; support the iPhone app under development.
- Store member records centrally in a SQL database, outside GitHub and app bundles.
- Use the current website data as the authority when web and iPhone data disagree.
- Allow access only to approved Division G officers. An account alone does not grant access.

## Current state verified from supplied files
The website uses IndexedDB and local browser storage. Its exportData() function waits for durable saves and exports canonical JSON containing updated, settings, ui, and database. Use that function in the same browser and file/origin where the current records live. The supplied HTML file is not a substitute for a fresh export of that browser's IndexedDB.

The iPhone app loads a bundled BundledStarterData.json and persists a local archive. That older snapshot must not initialize or replace the central database. Xcode recognized the supplied project and scheme; a full build was not verified.

Neither supplied application has been uploaded to this repository: both contain bundled personal records. Original source files on the Mac are unchanged.

## Proposed service
Supabase PostgreSQL with Supabase Auth. This is a recommendation, not a provisioned project. The Supabase connection and project still need setup.

## Data model and migration approach
1. Obtain a fresh canonical JSON export from the authoritative website. Preserve a private, dated original and verify counts before any transformation.
2. Inventory all collections and identifiers before writing a migration. The supplied iPhone snapshot contains 31 database fields, including areas, clubs, memberships, officers (exco), agendas, events, identity aliases, imports, and meeting tools. Its record counts are not authoritative web counts.
3. Use normalized SQL tables for core entities: divisions, areas, clubs, people, memberships, officer assignments, and approved app users. A person can belong to multiple clubs; do not treat one membership row as one person or deduplicate by display name alone.
4. Preserve original source identifiers and unmapped fields in staging/JSONB during migration. Review identity aliases before merging records. Do not discard reports, historical memberships, source metadata, or meeting-tool records when normalizing core tables.
5. Keep per-device interface preferences outside shared member records.
6. Validate totals and relationships against the web export in a staging database. Back up before promoting to live data. No destructive import or deletion without a verified backup and a reviewed migration result.

## Officer access
Require login plus an explicit, server-managed approval tied to the authenticated user ID and division. Separate app users from officer roster data: appearing in exco is not login approval. Use row-level policies for all exposed tables, deny unauthenticated access, and prevent clients from approving themselves or changing roles. Only designated administrators approve or revoke officers. Never put database passwords or service-role keys in browser code, the iPhone app, or GitHub.

## Web authority and synchronization
Initial import: the fresh web export wins. Keep iPhone-only records separate for review; do not silently replace web values or discard unique records.

After migration: central records are shared by both apps. Every write must carry the last server-issued record revision and be applied atomically only if it still matches. Reject stale saves rather than uploading an entire cached snapshot over current records. Record actor, server time, revision, and changed values for review.

If web and iPhone edits conflict, retain the accepted web value and present the iPhone change for officer review. Do not use device timestamps or a client-supplied source label as proof of priority. Implement this through a controlled server-side workflow; database policies must prevent clients from bypassing revision and conflict checks. Preserve queued local changes on failed saves and show unsynced/conflict status.

## Before release
- Confirm an unapproved signed-in user and an anonymous user cannot read member data.
- Confirm approved officers can access only their authorized division.
- Confirm approval revocation blocks further server access.
- Confirm duplicate/out-of-order saves do not overwrite newer records.
- Exercise web/iPhone conflicts in both arrival orders and verify web priority without silently losing the iPhone proposal.
- Compare migrated counts and sampled records with the authoritative export.
- Remove bundled personal records from distributable website/iPhone source copies, then verify startup with an empty cache and authenticated database loading.
- Check desktop and mobile web layouts and verify an iPhone build once the database adapters are implemented.

## Next inputs
Connect Supabase and select/create the project. Export the current web database from the browser where it is used. Supply the initial administrator identity and approved officer identities through the private setup process, not a committed file.

## Status
Planning only. No live database, data import, app synchronization, or source sanitization has been completed. No member data is committed in this change.
