begin;
create policy hdg_approved_v640_community_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v640-community.html'
        and (select public.hdg_access_mode()) = 'leader');
create policy hdg_approved_v640_community_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v640-community.html.gz'
        and (select public.hdg_access_mode()) = 'leader');
commit;
