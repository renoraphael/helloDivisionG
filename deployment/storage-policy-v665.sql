begin;
create policy hdg_approved_v665_community_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v665-community.html'
        and (select public.hdg_access_mode()) = 'leader');
create policy hdg_approved_v665_community_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v665-community.html.gz'
        and (select public.hdg_access_mode()) = 'leader');
create policy hdg_approved_v665_member_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v665-member.html'
        and (select public.hdg_access_mode()) = 'member');
create policy hdg_approved_v665_member_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v665-member.html.gz'
        and (select public.hdg_access_mode()) = 'member');
commit;
