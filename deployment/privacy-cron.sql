-- Enable the nightly 020 retention schedule. UTC 18:30 is 02:30 in Singapore and Bali.
begin;
create extension if not exists pg_cron with schema pg_catalog;
do $$ begin
 if has_schema_privilege('anon','cron','USAGE') or has_schema_privilege('authenticated','cron','USAGE') then
  raise exception 'HDG cron namespace must be private';
 end if;
end $$;
select cron.schedule('hdg-privacy-retention','30 18 * * *','select hdg_sync_private.privacy_nightly_erase()');
commit;
