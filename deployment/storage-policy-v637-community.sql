begin;
create policy hdg_approved_v637_community_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v637-community.html'
        and (select public.hdg_access_mode()) = 'leader');
commit;
