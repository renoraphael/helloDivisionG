begin;
create policy hdg_approved_v632_member_poster_roster_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v632-member-poster-roster.html'
        and (select public.hdg_access_mode()) = 'member');
commit;
