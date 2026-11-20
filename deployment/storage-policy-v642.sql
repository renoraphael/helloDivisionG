begin;
create policy hdg_approved_v642_community_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v642-community.html'
        and (select public.hdg_access_mode()) = 'leader');
create policy hdg_approved_v642_community_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v642-community.html.gz'
        and (select public.hdg_access_mode()) = 'leader');
create policy hdg_approved_v642_member_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v642-member.html'
        and (select public.hdg_access_mode()) = 'member');
create policy hdg_approved_v642_member_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v642-member.html.gz'
        and (select public.hdg_access_mode()) = 'member');
commit;
