begin;
create policy hdg_approved_v638_member_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v638-member.html.gz'
        and (select public.hdg_access_mode()) = 'member');
create policy hdg_approved_v638_community_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v638-community.html.gz'
        and (select public.hdg_access_mode()) = 'leader');
commit;
