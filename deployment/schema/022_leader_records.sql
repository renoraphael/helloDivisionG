-- Per-record leader data. The shared snapshot and dashboard routing are unchanged.
begin;

create function hdg_sync_private.leader_scope(p_division text, p_area text, p_write boolean)
returns boolean language sql stable security definer set search_path to ''
as $$
 select auth.uid() is not null and (
  hdg_sync_private.is_maintainer() or hdg_sync_private.is_district_admin()
  or exists(select 1 from hdg_sync_private.my_roles() r where
   (r.role='division_director' and r.scope_code=p_division)
   or (r.role='area_director' and left(r.scope_code,1)=p_division
       and (r.scope_code=p_area or (p_area is null and not p_write))))
  or p_division in (select hdg_sync_private.my_council_divisions(p_write))
 )
$$;

-- Each event is independently versioned. Club performance supplements public 009 figures.
create table public.hdg_leader_records (
 id uuid primary key default gen_random_uuid(),
 kind text not null check (kind in ('tli_session','contest','club_performance','area_visit')),
 year_start int not null references public.hdg_program_years,
 division_code text not null references public.hdg_divisions(code),
 area_code text,
 area_codes text[] not null default '{}',
 club_number text references public.hdg_clubs,
 title text not null check (length(btrim(title)) between 1 and 200),
 occurred_on date not null,
 details jsonb not null default '{}' check (jsonb_typeof(details)='object' and octet_length(details::text)<100000),
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid references auth.users on delete set null,
 unique(id,kind),
 foreign key (year_start,area_code) references public.hdg_areas(year_start,code),
 check (area_code is null or left(area_code,1)=division_code),
 check (cardinality(area_codes)=0 or
   (cardinality(area_codes)>1 and area_code is null and club_number is null and kind in ('tli_session','contest'))),
 check (kind not in ('club_performance','area_visit') or (area_code is not null and club_number is not null))
);
create index hdg_leader_records_scope on public.hdg_leader_records(division_code,year_start,area_code,kind);

create function hdg_sync_private.validate_leader_areas() returns trigger
language plpgsql set search_path to '' as $$
begin
 if cardinality(new.area_codes) <> (select count(*) from public.hdg_areas
   where year_start=new.year_start and division_code=new.division_code and code=any(new.area_codes)) then
  raise exception 'Event coverage must contain only distinct areas in its division and program year' using errcode='22023';
 end if;
 return new;
end $$;
revoke all on function hdg_sync_private.validate_leader_areas() from public,anon,authenticated;
create trigger validate_leader_areas before insert or update of area_codes,year_start,division_code
 on public.hdg_leader_records for each row execute function hdg_sync_private.validate_leader_areas();

create table public.hdg_tli_attendance (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null,
 session_kind text generated always as ('tli_session') stored,
 membership_id uuid not null references public.hdg_memberships on delete cascade,
 present boolean not null,
 updated_at timestamptz not null default clock_timestamp(),
 unique(session_id,membership_id),
 foreign key(session_id,session_kind) references public.hdg_leader_records(id,kind) on delete cascade
);
create index hdg_tli_attendance_membership on public.hdg_tli_attendance(membership_id);

-- An officer's round flag does not establish attendance at a particular session.
create table public.hdg_tli_round_attendance (
 membership_id uuid not null references public.hdg_memberships on delete cascade,
 year_start int not null references public.hdg_program_years,
 round_no smallint not null check (round_no in (1,2)),
 present boolean not null,
 primary key(membership_id,year_start,round_no)
);

-- Personal tasks retain scope for filtering but only the owner can read or modify them.
create table public.hdg_personal_tasks (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users on delete cascade,
 division_code text references public.hdg_divisions(code),
 year_start int references public.hdg_program_years,
 area_code text,
 title text not null check(length(btrim(title)) between 1 and 200),
 notes text not null default '' check(length(notes)<=4000),
 due_on date,
 completed boolean not null default false,
 updated_at timestamptz not null default clock_timestamp(),
 foreign key(year_start,area_code) references public.hdg_areas(year_start,code),
 check(area_code is null or (division_code is not null and year_start is not null and left(area_code,1)=division_code))
);
create index hdg_personal_tasks_owner on public.hdg_personal_tasks(owner_id);
alter table public.hdg_leader_records enable row level security;
alter table public.hdg_tli_attendance enable row level security;
alter table public.hdg_tli_round_attendance enable row level security;
alter table public.hdg_personal_tasks enable row level security;
create policy hdg_leader_records_read on public.hdg_leader_records for select to authenticated
 using (case when cardinality(area_codes)=0 then
   hdg_sync_private.leader_scope(division_code,area_code,false)
   else exists(select 1 from unnest(area_codes) a(code)
     where hdg_sync_private.leader_scope(division_code,a.code,false)) end);
create function hdg_sync_private.can_read_tli_attendance(p_session uuid,p_membership uuid)
returns boolean language sql stable security definer set search_path to ''
as $$
 select exists(select 1 from public.hdg_leader_records s
  join public.hdg_memberships m on m.id=p_membership
  cross join lateral (select hdg_sync_private.club_area(m.club_number,s.year_start) as area) scope
  where s.id=p_session and s.kind='tli_session' and left(scope.area,1)=s.division_code
   and (s.area_code is null or s.area_code=scope.area)
   and (cardinality(s.area_codes)=0 or scope.area=any(s.area_codes))
   and hdg_sync_private.leader_scope(s.division_code,scope.area,false))
$$;
create policy hdg_tli_attendance_read on public.hdg_tli_attendance for select to authenticated
 using (hdg_sync_private.can_read_tli_attendance(session_id,membership_id));

create function hdg_sync_private.can_read_tli_round(p_membership uuid,p_year int)
returns boolean language sql stable security definer set search_path to '' as $$
 select exists(select 1 from public.hdg_memberships m
  cross join lateral (select hdg_sync_private.club_area(m.club_number,p_year) as area) scope
  where m.id=p_membership and scope.area is not null
    and hdg_sync_private.leader_scope(left(scope.area,1),scope.area,false))
$$;
revoke all on function hdg_sync_private.can_read_tli_round(uuid,int) from public,anon;
grant execute on function hdg_sync_private.can_read_tli_round(uuid,int) to authenticated;
create policy hdg_tli_round_attendance_read on public.hdg_tli_round_attendance for select to authenticated
 using (hdg_sync_private.can_read_tli_round(membership_id,year_start));
create policy hdg_personal_tasks_owner on public.hdg_personal_tasks for select to authenticated using (owner_id=(select auth.uid()));

create function public.hdg_save_leader_record(p_kind text,p_id uuid,p_year int,p_division text,p_area text,p_club text,
 p_title text,p_date date,p_details jsonb,p_expected_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare old_row public.hdg_leader_records; saved public.hdg_leader_records;
begin
 if not hdg_sync_private.leader_scope(p_division,p_area,true) then
  raise exception 'Outside your leader edit scope' using errcode='42501';
 end if;
 if p_club is not null and (p_area is null or hdg_sync_private.club_area(p_club,p_year) is distinct from p_area) then
  raise exception 'Club does not belong to the approved area in this program year' using errcode='22023';
 end if;
 if p_id is null then
  insert into public.hdg_leader_records(kind,year_start,division_code,area_code,club_number,title,occurred_on,details,updated_by)
   values(p_kind,p_year,p_division,p_area,p_club,p_title,p_date,p_details,auth.uid()) returning * into saved;
 else
  select * into old_row from public.hdg_leader_records where id=p_id for update;
  if not found or not hdg_sync_private.leader_scope(old_row.division_code,old_row.area_code,true) then
   raise exception 'Outside your leader edit scope' using errcode='42501';
  end if;
  if (old_row.kind,old_row.year_start,old_row.division_code,old_row.area_code,old_row.club_number)
   is distinct from (p_kind,p_year,p_division,p_area,p_club) then
   raise exception 'An existing record keeps its original scope' using errcode='22023';
  end if;
  if old_row.updated_at is distinct from p_expected_at then
   return jsonb_build_object('applied',false,'record',to_jsonb(old_row));
  end if;
  update public.hdg_leader_records set title=p_title,occurred_on=p_date,details=p_details,
   updated_by=auth.uid(),updated_at=clock_timestamp() where id=p_id returning * into saved;
 end if;
 return jsonb_build_object('applied',true,'record',to_jsonb(saved));
end $$;

create function public.hdg_save_tli_attendance(p_session uuid,p_membership uuid,p_present boolean,p_expected_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare s public.hdg_leader_records; saved public.hdg_tli_attendance; member_area text;
begin
 select * into s from public.hdg_leader_records where id=p_session and kind='tli_session';
 select hdg_sync_private.club_area(club_number,s.year_start) into member_area from public.hdg_memberships where id=p_membership;
 if s.id is null or member_area is null or left(member_area,1)<>s.division_code
    or (s.area_code is not null and member_area<>s.area_code)
    or (cardinality(s.area_codes)>0 and not member_area=any(s.area_codes))
    or not hdg_sync_private.leader_scope(s.division_code,member_area,true) then
  raise exception 'Outside your attendance edit scope' using errcode='42501';
 end if;
 if p_expected_at is null then
  insert into public.hdg_tli_attendance(session_id,membership_id,present) values(p_session,p_membership,p_present)
  on conflict(session_id,membership_id) do nothing returning * into saved;
 else
  update public.hdg_tli_attendance set present=p_present,updated_at=clock_timestamp()
   where session_id=p_session and membership_id=p_membership and updated_at=p_expected_at returning * into saved;
 end if;
 if saved.id is null then return jsonb_build_object('applied',false); end if;
 return jsonb_build_object('applied',true,'record',to_jsonb(saved));
end $$;

create function public.hdg_save_personal_task(p_id uuid,p_division text,p_year int,p_area text,p_title text,
 p_notes text,p_due date,p_completed boolean,p_expected_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare saved public.hdg_personal_tasks;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if p_id is null then
  insert into public.hdg_personal_tasks(division_code,year_start,area_code,title,notes,due_on,completed)
   values(p_division,p_year,p_area,p_title,p_notes,p_due,p_completed) returning * into saved;
 else
  update public.hdg_personal_tasks set division_code=p_division,year_start=p_year,area_code=p_area,
   title=p_title,notes=p_notes,due_on=p_due,completed=p_completed,updated_at=clock_timestamp()
   where id=p_id and owner_id=auth.uid() and updated_at=p_expected_at returning * into saved;
 end if;
 if saved.id is null then return jsonb_build_object('applied',false); end if;
 return jsonb_build_object('applied',true,'record',to_jsonb(saved));
end $$;

create function public.hdg_delete_personal_task(p_id uuid,p_expected_at timestamptz)
returns boolean language plpgsql security definer set search_path to ''
as $$
begin
 delete from public.hdg_personal_tasks where id=p_id and owner_id=auth.uid() and updated_at=p_expected_at;
 return found;
end $$;

-- Privacy 020 deletes tasks and attendance through foreign keys. Extend its self-export as well.
alter function public.hdg_export_my_data() set schema hdg_sync_private;
revoke execute on function hdg_sync_private.hdg_export_my_data() from public,anon,authenticated;
create function public.hdg_export_my_data() returns jsonb
language sql stable security definer set search_path to ''
as $$
 select hdg_sync_private.hdg_export_my_data() || jsonb_build_object(
  'personalTasks', coalesce((select jsonb_agg(to_jsonb(t)-'owner_id') from public.hdg_personal_tasks t
    where t.owner_id=auth.uid()),'[]'),
  'tliAttendance', coalesce((select jsonb_agg(to_jsonb(a)-'session_kind') from public.hdg_tli_attendance a
    join public.hdg_memberships m on m.id=a.membership_id where m.person_id in (select hdg_sync_private.my_people())), '[]'),
  'tliRoundAttendance', coalesce((select jsonb_agg(to_jsonb(a)) from public.hdg_tli_round_attendance a
    join public.hdg_memberships m on m.id=a.membership_id where m.person_id in (select hdg_sync_private.my_people())), '[]'))
$$;
revoke execute on function public.hdg_export_my_data(),public.hdg_delete_personal_task(uuid,timestamptz) from public,anon;
grant execute on function public.hdg_export_my_data(),public.hdg_delete_personal_task(uuid,timestamptz) to authenticated;

-- Existing 009 figures stay the source of public dashboard snapshots. This leader-only
-- projection groups them with their approved historical area without changing 009 visibility.
create function public.hdg_leader_club_figures(p_year int,p_division text,p_area text default null)
returns setof public.hdg_club_figures language sql stable security definer set search_path to ''
as $$
 select f.* from public.hdg_club_figures f join public.hdg_club_alignment a
  on a.club_number=f.club_number and a.year_start=f.year_start and a.status='approved'
 where f.year_start=p_year and left(a.area_code,1)=p_division
  and (p_area is null or a.area_code=p_area)
  and hdg_sync_private.leader_scope(p_division,a.area_code,false)
$$;

revoke all on public.hdg_leader_records,public.hdg_tli_attendance,public.hdg_tli_round_attendance,public.hdg_personal_tasks from public,anon,authenticated;
grant select on public.hdg_leader_records,public.hdg_tli_attendance,public.hdg_tli_round_attendance,public.hdg_personal_tasks to authenticated;
revoke execute on function hdg_sync_private.leader_scope(text,text,boolean), hdg_sync_private.can_read_tli_attendance(uuid,uuid) from public,anon;
grant execute on function hdg_sync_private.leader_scope(text,text,boolean), hdg_sync_private.can_read_tli_attendance(uuid,uuid) to authenticated;
revoke execute on function public.hdg_save_leader_record(text,uuid,int,text,text,text,text,date,jsonb,timestamptz),
 public.hdg_save_tli_attendance(uuid,uuid,boolean,timestamptz),
 public.hdg_save_personal_task(uuid,text,int,text,text,text,date,boolean,timestamptz),
 public.hdg_leader_club_figures(int,text,text) from public,anon;
grant execute on function public.hdg_save_leader_record(text,uuid,int,text,text,text,text,date,jsonb,timestamptz),
 public.hdg_save_tli_attendance(uuid,uuid,boolean,timestamptz),
 public.hdg_save_personal_task(uuid,text,int,text,text,text,date,boolean,timestamptz),
 public.hdg_leader_club_figures(int,text,text) to authenticated;
notify pgrst, 'reload schema';
commit;
