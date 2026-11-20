begin;
create policy hdg_approved_v639_community_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v639-community.html'
        and (select public.hdg_access_mode()) = 'leader');
create policy hdg_approved_v639_community_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v639-community.html.gz'
        and (select public.hdg_access_mode()) = 'leader');
commit;
