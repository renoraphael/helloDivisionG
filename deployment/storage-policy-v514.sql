create policy hdg_approved_v514_download on storage.objects
for select to authenticated
using (
 bucket_id='hdg-private-app'
 and name='v514.html'
 and exists (
  select 1 from public.hdg_officer_access a
  where a.user_id=(select auth.uid()) and a.division_code='G' and a.active
 )
);
select 'Only approved Division G accounts can download v514' as result;
