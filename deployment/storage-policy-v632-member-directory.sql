begin;
create policy hdg_approved_v632_member_directory_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v632-member-directory.html'
        and (select public.hdg_access_mode()) = 'member');
commit;
