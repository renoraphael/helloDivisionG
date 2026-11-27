-- Consent, self-service privacy rights and retention for the per-record database.
-- Install and test before publishing the first reviewed notice or enabling production erasure.
begin;

create table hdg_sync_private.onboarding_seen (
 user_id uuid not null references auth.users on delete cascade,
 step text not null check (step ~ '^[a-z][a-z0-9_-]{0,63}$'),
 seen_at timestamptz not null default clock_timestamp(),
 primary key (user_id, step)
);
alter table hdg_sync_private.onboarding_seen enable row level security;
revoke all on hdg_sync_private.onboarding_seen from public, anon, authenticated;

create function public.hdg_mark_onboarding_seen(p_step text) returns timestamptz
language plpgsql security definer set search_path to ''
as $$
declare actor uuid := auth.uid(); seen timestamptz;
begin
 if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if p_step is null or p_step !~ '^[a-z][a-z0-9_-]{0,63}$' then
   raise exception 'Invalid onboarding step' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('hdg_onboarding:'||actor::text,0));
 select seen_at into seen from hdg_sync_private.onboarding_seen where user_id=actor and step=p_step;
 if seen is not null then return seen; end if;
 if (select count(*) from hdg_sync_private.onboarding_seen where user_id=actor)>=128 then
  raise exception 'Onboarding step limit reached' using errcode='22023';
 end if;
 insert into hdg_sync_private.onboarding_seen(user_id,step) values(actor,p_step) returning seen_at into seen;
 return seen;
end $$;

create table hdg_sync_private.privacy_notices (
 version text primary key check (version ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$'),
 body text not null check (length(btrim(body)) between 1 and 30000),
 published_at timestamptz not null default clock_timestamp(),
 current_notice boolean not null default true
);
create unique index privacy_notice_current on hdg_sync_private.privacy_notices (current_notice) where current_notice;

create table hdg_sync_private.privacy_acceptances (
 user_id uuid not null references auth.users on delete cascade,
 version text not null references hdg_sync_private.privacy_notices,
 accepted_at timestamptz not null default clock_timestamp(),
 primary key (user_id, version)
);

create table hdg_sync_private.privacy_deletion_requests (
 id uuid primary key default gen_random_uuid(),
 user_id uuid references auth.users on delete set null,
 requested_at timestamptz not null default clock_timestamp(),
 due_at timestamptz not null default (clock_timestamp() + interval '30 days'),
 completed_at timestamptz,
 check (completed_at is not null or user_id is not null)
);
create unique index privacy_deletion_one_pending on hdg_sync_private.privacy_deletion_requests (user_id)
 where completed_at is null;
alter table hdg_sync_private.privacy_notices enable row level security;
alter table hdg_sync_private.privacy_acceptances enable row level security;
alter table hdg_sync_private.privacy_deletion_requests enable row level security;
revoke all on hdg_sync_private.privacy_notices, hdg_sync_private.privacy_acceptances,
 hdg_sync_private.privacy_deletion_requests from public, anon, authenticated;

-- A published version is immutable through this API. Use a new version even for a small notice edit.
create function public.hdg_publish_privacy_notice(p_version text, p_body text) returns void
language plpgsql security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode='42501'; end if;
 lock table hdg_sync_private.privacy_notices in share row exclusive mode;
 update hdg_sync_private.privacy_notices set current_notice=false where current_notice;
 insert into hdg_sync_private.privacy_notices(version, body) values (p_version, p_body);
end $$;

create function public.hdg_privacy_notice() returns jsonb
language sql stable security definer set search_path to ''
as $$
 select jsonb_build_object('version', n.version, 'body', n.body, 'publishedAt', n.published_at,
   'acceptedAt', a.accepted_at)
 from hdg_sync_private.privacy_notices n
 left join hdg_sync_private.privacy_acceptances a on a.version=n.version and a.user_id=auth.uid()
 where n.current_notice and auth.uid() is not null
$$;

create function public.hdg_accept_privacy_notice(p_version text) returns timestamptz
language plpgsql security definer set search_path to ''
as $$
declare accepted timestamptz;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 lock table hdg_sync_private.privacy_notices in share mode;
 if not exists(select 1 from hdg_sync_private.privacy_notices where current_notice and version=p_version) then
  raise exception 'The privacy notice changed. Read the current version before accepting.' using errcode='22023';
 end if;
 insert into hdg_sync_private.privacy_acceptances(user_id, version) values (auth.uid(), p_version)
 on conflict (user_id, version) do nothing;
 select accepted_at into accepted from hdg_sync_private.privacy_acceptances where user_id=auth.uid() and version=p_version;
 return accepted;
end $$;

-- Keep a dedicated end date. A subsequent import must not restart the retention clock.
alter table public.hdg_memberships add column ended_on date;
update public.hdg_memberships set ended_on=case when status='lapsed' then coalesce(paid_until, source_as_of)
 else coalesce(source_as_of, paid_until) end where status<>'active';
create function hdg_sync_private.privacy_membership_end() returns trigger
language plpgsql set search_path to ''
as $$
begin
 if new.status='active' then new.ended_on := null;
 elsif tg_op='INSERT' then
  new.ended_on := coalesce(new.ended_on, new.paid_until, new.source_as_of, hdg_sync_private.today());
 elsif old.status='active' or old.ended_on is null then
  new.ended_on := coalesce(new.ended_on, case when new.status='past' then new.source_as_of end,
     new.paid_until, new.source_as_of, hdg_sync_private.today());
 elsif new.paid_until > old.ended_on then
  new.ended_on := new.paid_until;
 end if;
 return new;
end $$;
create trigger hdg_privacy_membership_end before insert or update of status, paid_until, source_as_of, ended_on
 on public.hdg_memberships for each row execute function hdg_sync_private.privacy_membership_end();

-- History retains the seat and dates after the identifying link is removed.
alter table public.hdg_roles alter column person_id drop not null;
alter table public.hdg_roles add column former_member boolean not null default false;
alter table public.hdg_roles add constraint hdg_role_person_or_former_member
 check ((person_id is null) = former_member);
alter table public.hdg_roles add column former_member_name text
 generated always as (case when former_member then 'Former member' end) stored;

-- The legacy Division G shared record and copies are outside the per-record cutover.
-- An exact structured identity match stops erasure rather than leaving an old copy behind.
create function hdg_sync_private.privacy_json_matches(p_document jsonb, p_identity text[]) returns boolean
language sql immutable set search_path to ''
as $$
 select exists (
  select 1 from jsonb_path_query(p_document, 'strict $.** ? (@.type() == "string" || @.type() == "number")') v
  where lower(btrim(v #>> '{}'))=any(p_identity)
 )
$$;

create function hdg_sync_private.privacy_legacy_pending(p_people uuid[], p_user uuid) returns boolean
language plpgsql stable security definer set search_path to ''
as $$
declare identifiers text[];
begin
 select coalesce(array_agg(distinct v) filter (where v is not null and v<>''), '{}') into identifiers
 from (
  select unnest(array[p.id::text, lower(p.email), lower(p.ti_member_id), ltrim(lower(p.ti_member_id),'0')]) v
  from public.hdg_people p where p.id=any(p_people)
  union all select unnest(array[u.id::text, lower(btrim(u.email))]) from auth.users u where u.id=p_user
 ) x;
 return exists(select 1 from public.hdg_sync_state s where hdg_sync_private.privacy_json_matches(s.payload, identifiers))
   or exists(select 1 from hdg_sync_private.revision_history s where hdg_sync_private.privacy_json_matches(s.payload, identifiers))
   or exists(select 1 from hdg_sync_private.superseded_saves s where hdg_sync_private.privacy_json_matches(s.payload, identifiers))
   or exists(select 1 from hdg_private.web_imports s where hdg_sync_private.privacy_json_matches(s.payload, identifiers))
   or exists(select 1 from hdg_private.import_collections s where hdg_sync_private.privacy_json_matches(s.value, identifiers))
   or exists(select 1 from hdg_sync_private.legacy_records s where hdg_sync_private.privacy_json_matches(s.data, identifiers));
end $$;

create function hdg_sync_private.privacy_active(p_people uuid[]) returns boolean
language sql stable security definer set search_path to ''
as $$
 select exists(select 1 from public.hdg_memberships where person_id=any(p_people) and status='active')
$$;

create function hdg_sync_private.privacy_people(p_user uuid) returns uuid[]
language sql stable security definer set search_path to ''
as $$
 select coalesce(array_agg(p.id), '{}') from auth.users u
 join public.hdg_people p on p.user_id=u.id
   or (p.user_id is null and u.email_confirmed_at is not null and p.email=lower(btrim(u.email)))
 where u.id=p_user
$$;

create function public.hdg_my_privacy() returns jsonb
language plpgsql stable security definer set search_path to ''
as $$
declare people uuid[] := hdg_sync_private.privacy_people(auth.uid());
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 return jsonb_build_object('activeMembership', hdg_sync_private.privacy_active(people),
   'profileCount', cardinality(people), 'maintainer', hdg_sync_private.is_maintainer(),
   'pending', (select to_jsonb(r) - 'user_id' from hdg_sync_private.privacy_deletion_requests r
     where r.user_id=auth.uid() and completed_at is null));
end $$;

-- Self-export uses an explicit allowlist for Auth and never includes other participants' meeting or ballot data.
create function public.hdg_export_my_data() returns jsonb
language plpgsql stable security definer set search_path to ''
as $$
declare actor uuid := auth.uid(); people uuid[] := hdg_sync_private.privacy_people(actor); record_keys text[];
begin
 if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
 select array(select unnest(people)::text union select id::text from public.hdg_memberships where person_id=any(people)
   union select id::text from public.hdg_roles where person_id=any(people)) into record_keys;
 return jsonb_build_object(
  'exportedAt', clock_timestamp(),
  'account', (select jsonb_build_object('id',u.id,'email',u.email,'phone',u.phone,'createdAt',u.created_at,
    'confirmedAt',u.confirmed_at,'lastSignInAt',u.last_sign_in_at,'profile',u.raw_user_meta_data)
    from auth.users u where u.id=actor),
  'people', coalesce((select jsonb_agg(to_jsonb(p)-'updated_by') from public.hdg_people p where p.id=any(people)), '[]'),
  'memberships', coalesce((select jsonb_agg(to_jsonb(m)-'updated_by') from public.hdg_memberships m where m.person_id=any(people)), '[]'),
  'roles', coalesce((select jsonb_agg(to_jsonb(r)-'entered_by') from public.hdg_roles r where r.person_id=any(people)), '[]'),
  'access', coalesce((select jsonb_agg(to_jsonb(a)-'user_id') from public.hdg_officer_access a where a.user_id=actor), '[]'),
  'betaAccess', exists(select 1 from hdg_community_private.beta_members where user_id=actor),
  'onboarding', coalesce((select jsonb_object_agg(o.step,o.seen_at) from hdg_sync_private.onboarding_seen o where o.user_id=actor), '{}'),
  'consents', coalesce((select jsonb_agg(to_jsonb(a)-'user_id' order by a.accepted_at) from hdg_sync_private.privacy_acceptances a where a.user_id=actor), '[]'),
  'deletionRequests', coalesce((select jsonb_agg(to_jsonb(r)-'user_id') from hdg_sync_private.privacy_deletion_requests r where r.user_id=actor), '[]'),
  'recordHistory', coalesce((select jsonb_agg(jsonb_build_object('table',h.table_name,'at',h.at,'action',h.op,
    'before',h.before-array['updated_by','entered_by','hand_corrected'], 'after',h.after-array['updated_by','entered_by','hand_corrected'])
    order by h.id) from hdg_sync_private.edit_history h where h.table_name in ('hdg_people','hdg_memberships','hdg_roles')
    and (h.row_key=any(record_keys) or h.before->>'person_id'=any(people::text[]) or h.after->>'person_id'=any(people::text[]))), '[]'),
  'legacyRecordsRequireReview', hdg_sync_private.privacy_legacy_pending(people, actor)
 );
end $$;

create function public.hdg_remove_my_details() returns integer
language plpgsql security definer set search_path to ''
as $$
declare people uuid[] := hdg_sync_private.privacy_people(auth.uid()); changed integer;
 fields text[] := array['nickname','aliases','pronunciation','photo_path','photo_consent'];
 cleared jsonb := '{"nickname":null,"aliases":[],"pronunciation":null,"photo_path":null,"photo_consent":false}';
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 update public.hdg_people set nickname=null, aliases='{}', pronunciation=null, photo_path=null, photo_consent=false,
  updated_at=clock_timestamp(), updated_by=auth.uid()
 where id=any(people) and (nickname is not null or aliases<>'{}' or pronunciation is not null or photo_path is not null or photo_consent);
 get diagnostics changed=row_count;
 update hdg_sync_private.edit_history set before=before||cleared, after=after||cleared
 where table_name='hdg_people' and row_key=any(people::text[]);
 update hdg_sync_private.superseded_edits set patch=patch-fields
 where table_name='hdg_people' and row_key=any(people::text[]);
 update hdg_sync_private.member_import_changes set before=before||cleared
 where table_name='hdg_people' and row_id=any(people) and before is not null;
 return changed;
end $$;

create function public.hdg_request_deletion() returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare actor uuid := auth.uid(); r hdg_sync_private.privacy_deletion_requests;
begin
 if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if hdg_sync_private.privacy_active(hdg_sync_private.privacy_people(actor)) then
  raise exception 'Full deletion is available after your last active membership ends.' using errcode='42501';
 end if;
 insert into hdg_sync_private.privacy_deletion_requests(user_id) values (actor)
 on conflict (user_id) where completed_at is null do nothing;
 select * into r from hdg_sync_private.privacy_deletion_requests where user_id=actor and completed_at is null;
 return to_jsonb(r)-'user_id';
end $$;

create function public.hdg_privacy_deletion_queue() returns jsonb
language plpgsql volatile security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode='42501'; end if;
 insert into hdg_sync_private.access_log(actor, action) values (auth.uid(),'privacy_deletion_queue');
 return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'requestedAt',r.requested_at,'dueAt',r.due_at,
  'email',u.email,'blocked',case
    when exists(select 1 from public.hdg_roles where person_id=any(p.ids) and role='maintainer') then 'maintainer'
    when hdg_sync_private.privacy_active(p.ids) then 'active'
    when hdg_sync_private.privacy_legacy_pending(p.ids,r.user_id) then 'legacy' end)
  order by r.due_at) from hdg_sync_private.privacy_deletion_requests r join auth.users u on u.id=r.user_id
  cross join lateral (select hdg_sync_private.privacy_people(r.user_id) ids) p where r.completed_at is null), '[]');
end $$;

-- Serialize with roster writes. Eligibility must be checked again in the same transaction that erases.
create function hdg_sync_private.privacy_erase(p_people uuid[], p_user uuid) returns boolean
language plpgsql security definer set search_path to ''
as $$
declare record_keys text[]; user_email text;
begin
 lock table public.hdg_memberships in share row exclusive mode;
 if p_user is not null then
  select email into user_email from auth.users where id=p_user for update;
  if not found then return false; end if;
  p_people := hdg_sync_private.privacy_people(p_user);
 end if;
 if hdg_sync_private.privacy_active(p_people)
   or hdg_sync_private.privacy_legacy_pending(p_people,p_user)
   or exists(select 1 from public.hdg_roles where person_id=any(p_people) and role='maintainer') then return false; end if;
 perform 1 from public.hdg_people where id=any(p_people) for update;
 select array(select unnest(p_people)::text union select id::text from public.hdg_memberships where person_id=any(p_people)
  union select id::text from public.hdg_roles where person_id=any(p_people)) into record_keys;
 update public.hdg_roles set person_id=null, former_member=true, entered_by=null
 where person_id=any(p_people) and ends_on < hdg_sync_private.today();
 update hdg_sync_private.privacy_deletion_requests set completed_at=clock_timestamp(),user_id=null
 where user_id=p_user and completed_at is null;
 delete from public.hdg_people where id=any(p_people);
 delete from hdg_sync_private.edit_history where
  (table_name in ('hdg_people','hdg_memberships','hdg_roles') and row_key=any(record_keys))
  or before->>'person_id'=any(p_people::text[]) or after->>'person_id'=any(p_people::text[]);
 delete from hdg_sync_private.superseded_edits where table_name in ('hdg_people','hdg_memberships','hdg_roles') and row_key=any(record_keys);
 delete from hdg_sync_private.member_import_changes where row_id=any(record_keys::uuid[]);
 if p_user is not null then
  delete from hdg_sync_private.initial_administrators where lower(email)=lower(user_email);
  delete from public.hdg_officer_access where user_id=p_user;
  delete from hdg_community_private.beta_members where user_id=p_user;
  update hdg_sync_private.edit_history set actor=null where actor=p_user;
  update hdg_sync_private.edit_history set undone_by=null where undone_by=p_user;
  update hdg_sync_private.superseded_edits set actor=null where actor=p_user;
  update hdg_sync_private.member_imports set imported_by=null where imported_by=p_user;
  update hdg_sync_private.member_imports set undone_by=null where undone_by=p_user;
  delete from hdg_sync_private.access_log where actor=p_user;
  update public.hdg_sync_state set updated_by=null where updated_by=p_user;
  update hdg_sync_private.revision_history set updated_by=null where updated_by=p_user;
  delete from hdg_sync_private.save_receipts where actor=p_user;
  delete from hdg_sync_private.superseded_saves where actor=p_user;
  delete from hdg_community_private.votes where ballot_id in (select id from hdg_community_private.ballots where owner_id=p_user);
  delete from hdg_community_private.ballots where owner_id=p_user;
  delete from auth.users where id=p_user;
 end if;
 return true;
end $$;

create function public.hdg_complete_deletion(p_request uuid) returns boolean
language plpgsql security definer set search_path to ''
as $$
declare target uuid;
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode='42501'; end if;
 lock table public.hdg_memberships in share row exclusive mode;
 select user_id into target from hdg_sync_private.privacy_deletion_requests
 where id=p_request and completed_at is null for update;
 if not found then return false; end if;
 if target=auth.uid() then raise exception 'A maintainer cannot erase their own account.' using errcode='42501'; end if;
 if not hdg_sync_private.privacy_erase(hdg_sync_private.privacy_people(target),target) then
  raise exception 'This request is blocked by an active role, membership or legacy record.' using errcode='42501';
 end if;
 insert into hdg_sync_private.access_log(actor, action, detail)
 values (auth.uid(),'privacy_deletion_completed',jsonb_build_object('request',p_request));
 return true;
end $$;

-- One execution per night. A multi-profile account is retained until all its membership end dates qualify.
create function hdg_sync_private.privacy_nightly_erase() returns integer
language plpgsql security definer set search_path to ''
as $$
declare p record; ids uuid[]; erased integer := 0; cutoff date := (hdg_sync_private.today()-interval '12 months')::date;
begin
 lock table public.hdg_memberships in share row exclusive mode;
 for p in select distinct pp.id, coalesce(pp.user_id, (select u.id from auth.users u
    where u.email_confirmed_at is not null and lower(btrim(u.email))=pp.email limit 1)) as account
  from public.hdg_people pp join public.hdg_memberships m on m.person_id=pp.id
  where m.ended_on<=cutoff order by pp.id
 loop
  ids := case when p.account is null then array[p.id] else hdg_sync_private.privacy_people(p.account) end;
  if exists(select 1 from public.hdg_memberships where person_id=any(ids))
   and not exists(select 1 from public.hdg_memberships where person_id=any(ids)
     and (status='active' or ended_on is null or ended_on>cutoff))
   and hdg_sync_private.privacy_erase(ids,p.account) then erased:=erased+1; end if;
 end loop;
 return erased;
end $$;

revoke execute on function hdg_sync_private.privacy_membership_end(), hdg_sync_private.privacy_json_matches(jsonb,text[]),
 hdg_sync_private.privacy_legacy_pending(uuid[],uuid), hdg_sync_private.privacy_active(uuid[]), hdg_sync_private.privacy_people(uuid),
 hdg_sync_private.privacy_erase(uuid[],uuid), hdg_sync_private.privacy_nightly_erase()
 from public, anon, authenticated;
revoke execute on function public.hdg_publish_privacy_notice(text,text), public.hdg_privacy_notice(),
 public.hdg_accept_privacy_notice(text), public.hdg_my_privacy(), public.hdg_export_my_data(),
 public.hdg_remove_my_details(), public.hdg_request_deletion(), public.hdg_privacy_deletion_queue(), public.hdg_complete_deletion(uuid)
 from public, anon, authenticated;
grant execute on function public.hdg_publish_privacy_notice(text,text), public.hdg_privacy_notice(),
 public.hdg_accept_privacy_notice(text), public.hdg_my_privacy(), public.hdg_export_my_data(),
 public.hdg_remove_my_details(), public.hdg_request_deletion(), public.hdg_privacy_deletion_queue(), public.hdg_complete_deletion(uuid)
 to authenticated;
create or replace function public.hdg_my_context()
returns jsonb language sql stable security definer set search_path to ''
as $$
 with me as (select p.id, p.name, p.nickname, p.provisional from public.hdg_people p
             where p.id in (select hdg_sync_private.my_people()) order by p.provisional limit 1),
 r as (select * from hdg_sync_private.my_roles()),
 y as (select hdg_sync_private.year_of(hdg_sync_private.today()) yr),
 divs as (
   select distinct d.code from public.hdg_divisions d, y
   where exists (select 1 from r where r.role in ('maintainer', 'district_director', 'pqd', 'cgd', 'am', 'prm', 'fm', 'lm', 'alignment_chair'))
      or exists (select 1 from r where r.role in ('division_director', 'division_council') and r.scope_code = d.code)
      or exists (select 1 from r where r.role = 'area_director' and left(r.scope_code, 1) = d.code)
      or exists (select 1 from r join public.hdg_club_alignment a on a.club_number = r.scope_code and a.year_start = y.yr
                 where r.scope_type = 'club' and left(a.area_code, 1) = d.code))
 select jsonb_build_object(
   'accessMode', public.hdg_access_mode(),
   'onboardingSeen', coalesce((select jsonb_object_agg(o.step,o.seen_at)
     from hdg_sync_private.onboarding_seen o where o.user_id=auth.uid()), '{}'),
   'name', (select coalesce(nickname, name) from me),
   'provisional', coalesce((select provisional from me), false),
   'roles', coalesce((select jsonb_agg(jsonb_build_object('role', rr.role, 'scopeType', rr.scope_type, 'scope', rr.scope_code, 'title', rr.title) order by rr.role)
                      from public.hdg_roles rr where rr.person_id in (select hdg_sync_private.my_people())
                        and rr.starts_on <= hdg_sync_private.today() and (rr.ends_on is null or rr.ends_on >= hdg_sync_private.today())), '[]'),
   'divisions', coalesce((select jsonb_agg(jsonb_build_object(
       'code', d.code, 'name', dv.name,
       'clubs', (select count(*) from public.hdg_club_alignment a, y where a.year_start = y.yr and a.status = 'approved' and left(a.area_code, 1) = d.code),
       'areas', (select count(*) from public.hdg_areas ar, y where ar.year_start = y.yr and ar.division_code = d.code),
       'members', (select count(distinct m.person_id) from public.hdg_memberships m join public.hdg_club_alignment a
                     on a.club_number = m.club_number join y on a.year_start = y.yr
                   where left(a.area_code, 1) = d.code and m.status = 'active')) order by d.code)
     from divs d join public.hdg_divisions dv on dv.code = d.code), '[]'))
 where auth.uid() is not null
$$;
revoke execute on function public.hdg_mark_onboarding_seen(text), public.hdg_my_context() from public, anon;
grant execute on function public.hdg_mark_onboarding_seen(text), public.hdg_my_context() to authenticated;

-- Imports for a new division require a published notice and enabled retention first.
create or replace function public.hdg_set_division_import(p_division text, p_open boolean) returns void
language plpgsql security definer set search_path to ''
as $$
declare retention_ready boolean := false;
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode='42501'; end if;
 if p_open and p_division<>'G' then
  if to_regclass('cron.job') is not null then
   execute 'select exists(select 1 from cron.job where jobname=$1 and active)'
    into retention_ready using 'hdg-privacy-retention';
  end if;
  if not retention_ready or not exists(select 1 from hdg_sync_private.privacy_notices where current_notice) then
   raise exception 'Publish the privacy notice and enable nightly retention before opening imports.'
    using errcode='42501';
  end if;
 end if;
 update public.hdg_divisions set config = config || jsonb_build_object('memberImport', case when p_open then 'open' else 'closed' end),
   updated_at=now(), updated_by=auth.uid() where code=p_division;
 if not found then raise exception 'Unknown division' using errcode='22023'; end if;
end $$;

notify pgrst, 'reload schema';
commit;
