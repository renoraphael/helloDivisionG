begin;
create policy hdg_approved_v652_community_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v652-community.html'
        and (select public.hdg_access_mode()) = 'leader');
create policy hdg_approved_v652_community_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v652-community.html.gz'
        and (select public.hdg_access_mode()) = 'leader');
create policy hdg_approved_v652_member_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v652-member.html'
        and (select public.hdg_access_mode()) = 'member');
create policy hdg_approved_v652_member_gz_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v652-member.html.gz'
        and (select public.hdg_access_mode()) = 'member');
commit;
