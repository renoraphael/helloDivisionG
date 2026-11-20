begin;
create policy hdg_approved_v634_member_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v634-member.html'
        and (select public.hdg_access_mode()) = 'member');
commit;
