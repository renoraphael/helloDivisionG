begin;
create policy hdg_approved_v638_community_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v638-community.html'
        and (select public.hdg_access_mode()) = 'leader');
commit;
