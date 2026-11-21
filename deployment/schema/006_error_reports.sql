-- 006: error reports reach the maintainer, grouped by error, without member data (Phase 0, step 9; rule 32).
-- TEST project first; production only after the owner approves.
-- Any page (signed in or not, including the ballot page) can send a report. The server scrubs it again:
-- emails, long numbers (member IDs, phone numbers), IDs and anything after ? or # in the page address are
-- removed, so a report never carries member data or ballot links. No account ID is stored.
-- Identical errors are grouped into one row with a count. At most 300 new kinds of error are accepted per day.

create table hdg_sync_private.error_reports (
 fingerprint text primary key,
 first_at timestamptz not null default now(),
 last_at timestamptz not null default now(),
 times int not null default 1,
 release text,
 page text,
 message text not null,
 stack text,
 browser text,
 signed_in boolean not null default false,
 resolved_at timestamptz,
 resolved_in text);
alter table hdg_sync_private.error_reports enable row level security;
revoke all on hdg_sync_private.error_reports from public, anon, authenticated;

create function hdg_sync_private.scrub(t text, max_len int) returns text language sql immutable set search_path to ''
as $$
 select left(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(t, ''),
   '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g'),
   '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '[id]', 'g'),
   '(eyJ|sb_)[A-Za-z0-9_.-]{10,}', '[key]', 'g'),
   '\+?[0-9][0-9 .-]{5,}[0-9]', '[number]', 'g'), max_len)
$$;

create function public.hdg_report_error(p_release text, p_page text, p_message text, p_stack text, p_browser text)
returns void language plpgsql security definer set search_path to ''
as $$
declare msg text := hdg_sync_private.scrub(p_message, 500);
 stk text := hdg_sync_private.scrub(p_stack, 2000);
 pg text := left(regexp_replace(coalesce(p_page, ''), '[?#].*$', ''), 200);
 fp text;
begin
 if btrim(msg) = '' then return; end if;
 -- Group by message and the first stack line, ignoring line numbers that change between releases.
 fp := encode(sha256(convert_to(pg || '|' || msg || '|' || regexp_replace(split_part(stk, E'\n', 1), ':[0-9]+', '', 'g'), 'UTF8')), 'hex');
 update hdg_sync_private.error_reports set times = times + 1, last_at = now(),
   release = left(p_release, 40), resolved_at = null, resolved_in = null
 where fingerprint = fp;
 if found then return; end if;
 if (select count(*) from hdg_sync_private.error_reports where first_at > now() - interval '1 day') >= 300 then return; end if;
 insert into hdg_sync_private.error_reports(fingerprint, release, page, message, stack, browser, signed_in)
 values (fp, left(p_release, 40), pg, msg, stk, left(p_browser, 200), auth.uid() is not null)
 on conflict (fingerprint) do update set times = hdg_sync_private.error_reports.times + 1, last_at = now();
end $$;

-- Reports page for the maintainer: open errors first, newest first.
create function public.hdg_error_reports(p_include_resolved boolean default false)
returns table(fingerprint text, first_at timestamptz, last_at timestamptz, times int, release text, page text, message text,
  stack text, browser text, signed_in boolean, resolved_at timestamptz, resolved_in text)
language plpgsql stable security definer set search_path to ''
as $$
#variable_conflict use_column
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 return query select * from hdg_sync_private.error_reports r
   where p_include_resolved or r.resolved_at is null order by r.resolved_at nulls first, r.last_at desc limit 300;
end $$;

-- Mark an error fixed. If it happens again it reopens automatically.
create function public.hdg_resolve_error(p_fingerprint text, p_release text default null)
returns void language plpgsql security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 update hdg_sync_private.error_reports set resolved_at = now(), resolved_in = left(p_release, 40) where fingerprint = p_fingerprint;
end $$;

revoke execute on function hdg_sync_private.scrub(text, int), public.hdg_report_error(text, text, text, text, text),
  public.hdg_error_reports(boolean), public.hdg_resolve_error(text, text) from public, anon, authenticated;
grant execute on function public.hdg_report_error(text, text, text, text, text) to anon, authenticated;
grant execute on function public.hdg_error_reports(boolean), public.hdg_resolve_error(text, text) to authenticated;
