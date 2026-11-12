# Deployment and rollback

## Public launcher
GitHub Pages publishes main / docs automatically. Work on task branches and review the public files before merging. Verify the Pages workflow and hosted URL after publication. A change outside docs normally does not alter the served launcher, though GitHub may still run a Pages build.

## Protected full app
Changes to private-app/v484.html do not travel through GitHub. Keep a private copy of the previous asset, record old/new SHA-256 values, test the updated app, and upload the intended file to private Supabase bucket hdg-private-app as v484.html using the owner's authorized access. Do not change the bucket to public. Verify an approved account can load it and unapproved/anonymous/revoked accounts cannot.

The full app includes an inline cloud adapter. Changes to docs/cloud-sync.js do not automatically update that inline copy. Rebuild or carefully integrate the same adapter in the protected app and test both paths. Do not run the original builder against an already modified private HTML; it rejects already connected files to avoid double injection.

Document which public commit and private asset hash form a release. Never claim GitHub alone deployed the whole app. To roll back, restore the prior public commit through a normal revert when appropriate and restore the privately retained app asset; preserve the database unless a separately reviewed data migration requires rollback.

## Database and iPhone
Do not rerun bootstrap/schema scripts blindly. Review existing objects and migrations first. iPhone source changes require an Xcode build and a separate distribution step; GitHub Pages never updates an installed app.

## Current verification limits
The public sign-in page and deployment were verified. Database/queue/storage access checks passed using synthetic test identities and rollback. Actual officer login, password-reset completion, a browser edit/reload sync round-trip, and a complete iPhone build remain to be verified with the owner.

## Building a new offline release

Run `python3 deployment/build_connected_app.py /private/path/HelloDivisionG_v484.html private-app/v484.html --version v484` from the checkout. The builder reads the current adapter/styles from `docs`, refuses public output in `docs`, preserves the raw source, and requires the three known storage/boot integration hooks. Before a later version, point the launcher at the intended versioned private object, then rebuild, verify, upload, and deploy together.

Retain `hdg-private-app/v475.html` for the current rollback baseline. Do not overwrite a versioned object as an incidental documentation change.
