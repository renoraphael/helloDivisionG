-- Enable separately from the schema migration, after the test matrix and release approval.
-- Supabase schedules in UTC by default. This runs at 02:30 in Singapore and Bali.
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('hdg-privacy-retention', '30 18 * * *', 'select hdg_sync_private.privacy_nightly_erase()');
