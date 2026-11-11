create policy hdg_approved_v475_download on storage.objects
for select to authenticated
using (
 bucket_id='hdg-private-app'
 and name='v475.html'
 and exists (
  select 1 from public.hdg_officer_access a
  where a.user_id=(select auth.uid()) and a.division_code='G' and a.active
 )
);
select 'Only approved Division G accounts can download v475' as result;
