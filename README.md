# Hello Division G — v475

Officer dashboard and meeting tools.

## Website

The GitHub Pages entry point is https://renoraphael.github.io/helloDivisionG/ once Pages finishes deploying. It is published from `main` / `docs`.

The public files contain only the sign-in launcher and sync adapter. After officer sign-in, the launcher downloads the connected v475 app from the private `hdg-private-app` Supabase bucket. The original HTML embeds member records and is intentionally absent from this public repository.

Use **Sign in**, **Create account**, **Forgot password?**, or **Email me a sign-in link**. A confirmed login also needs explicit Division G officer approval. The first administrator has been preapproved privately.

Shared records are in Supabase PostgreSQL. Browser-local preferences stay on the device. The website uses revision checks, idempotent retries, and conflict recovery. The iPhone adapter is download-only so older phone data cannot overwrite web records.

## Privacy and validation

Do not commit original member-bearing HTML, database exports, passwords, or secret keys. Only the publishable client key belongs in browser code. The private storage bucket and current approval registry protect the full legacy app as well as shared data.

The repository history and new public files were scanned against known member names, IDs, email addresses, and private-key patterns before publication. Storage access tests passed for approved download and denial to anonymous, unapproved, and revoked accounts; fixtures rolled back. The loader passed simulated authorization/download tests. A real officer sign-in and end-to-end sync test still needs the owner.

Read `AGENTS.md` before editing. The larger backend and iPhone setup is available in the existing draft pull request.
