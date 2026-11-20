begin;
create policy hdg_approved_v638_member_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v638-member.html'
        and (select public.hdg_access_mode()) = 'member');
commit;
