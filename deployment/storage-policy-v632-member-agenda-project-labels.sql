begin;
create policy hdg_approved_v632_member_agenda_project_labels_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v632-member-agenda-project-labels.html'
        and (select public.hdg_access_mode()) = 'member');
commit;
