begin;
create policy hdg_approved_v641_member_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v641-member.html'
        and (select public.hdg_access_mode()) = 'member');
create policy hdg_approved_v641_member_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v641-member.html.gz'
        and (select public.hdg_access_mode()) = 'member');
commit;
