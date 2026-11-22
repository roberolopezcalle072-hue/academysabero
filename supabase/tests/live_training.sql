-- Run on an isolated database after migrations. This file rolls back all fixtures.
\set ON_ERROR_STOP on
begin;

insert into auth.users(id, email, email_confirmed_at) values
  ('fd000000-0000-4000-8000-000000000001', 'host@example.invalid', now()),
  ('fd000000-0000-4000-8000-000000000002', 'attendee@example.invalid', now()),
  ('fd000000-0000-4000-8000-000000000003', 'outside@example.invalid', now());
insert into auth.identities(user_id, provider_id, provider, identity_data)
select id, id::text, 'google', jsonb_build_object('email', email, 'email_verified', true)
from auth.users where id in (
  'fd000000-0000-4000-8000-000000000001', 'fd000000-0000-4000-8000-000000000002',
  'fd000000-0000-4000-8000-000000000003'
);
insert into auth.sessions(id, user_id, created_at, updated_at)
select id, id, now(), now() from auth.users where id in (
  'fd000000-0000-4000-8000-000000000001', 'fd000000-0000-4000-8000-000000000002',
  'fd000000-0000-4000-8000-000000000003'
);
insert into public.academy_members(user_id, role) values
  ('fd000000-0000-4000-8000-000000000001', 'admin'),
  ('fd000000-0000-4000-8000-000000000002', 'student'),
  ('fd000000-0000-4000-8000-000000000003', 'student');
insert into public.academy_authorized_emails(email)
values ('attendee@example.invalid'), ('outside@example.invalid');
insert into public.academy_courses(id, name, description, image_path, status, duration_minutes) values
  ('fd000000-0000-4000-8000-000000000011', 'Live test A', 'Course', '/images/live-a.webp', 'published', 60),
  ('fd000000-0000-4000-8000-000000000012', 'Live test B', 'Course', '/images/live-b.webp', 'published', 60);
insert into public.academy_enrollments(student_id, course_id, enrolled_at, status) values
  ('fd000000-0000-4000-8000-000000000002', 'fd000000-0000-4000-8000-000000000011', now(), 'active'),
  ('fd000000-0000-4000-8000-000000000003', 'fd000000-0000-4000-8000-000000000012', now(), 'active');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fd000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"session_id":"fd000000-0000-4000-8000-000000000001","amr":[{"method":"oauth"}]}', true);
do $$
declare
  course uuid := 'fd000000-0000-4000-8000-000000000011';
  learner uuid := 'fd000000-0000-4000-8000-000000000002';
  outsider uuid := 'fd000000-0000-4000-8000-000000000003';
  ready uuid;
  future uuid;
  cancelled uuid;
  draft uuid;
begin
  draft := public.academy_save_live_session(null, course, 'Test draft', 1, 'Description',
    now() + interval '2 days', now() + interval '2 days 1 hour', null, 'draft', null, null);
  future := public.academy_save_live_session(null, course, 'Test future', 3, 'Description',
    now() + interval '1 day', now() + interval '1 day 1 hour', 'https://meet.google.com/aaa-bbbb-ccc',
    'scheduled', 'https://drive.google.com/file/d/Future_Recording/view', null);
  ready := public.academy_save_live_session(null, course, 'Test finished', 2, 'Description',
    now() - interval '2 hours', now() - interval '1 hour', 'https://meet.google.com/aaa-bbbb-ccc',
    'scheduled', null, null);
  cancelled := public.academy_save_live_session(null, course, 'Test cancelled', 4, 'Description',
    now() + interval '3 days', now() + interval '3 days 1 hour', 'https://meet.google.com/aaa-bbbb-ccc',
    'scheduled', null, null);
  update public.academy_live_sessions set status = 'cancelled' where id = cancelled;
  if draft is null or future is null or ready is null or cancelled is null
      or public.academy_save_attendance(future, learner, 'present')
      or public.academy_save_attendance(ready, outsider, 'present')
      or exists (select 1 from public.academy_session_roster(ready, true, 0)) then
    raise exception 'Session creation or attendance eligibility failed';
  end if;
  if not public.academy_save_attendance(ready, learner, 'absent')
      or not public.academy_save_attendance(ready, learner, 'present') then
    raise exception 'Manual attendance insert or correction failed';
  end if;
  if (select attendance from public.academy_session_roster(ready, true, 0)) is distinct from 'present' then
    raise exception 'The present-only roster did not include the attendee';
  end if;
  if public.academy_save_live_session(ready, course, 'Test finished', 2, 'Description',
      now() - interval '2 hours', now() - interval '1 hour', 'https://meet.google.com/aaa-bbbb-ccc',
      'completed', 'https://drive.google.com/file/d/Private_Recording/view',
      'https://docs.google.com/document/d/Private_Material/edit') is distinct from ready then
    raise exception 'Could not finish the session and save the resources';
  end if;
  if public.academy_save_live_session(cancelled, course, 'Test cancelled', 4, 'Description',
      now() + interval '3 days', now() + interval '3 days 1 hour', 'https://meet.google.com/aaa-bbbb-ccc',
      'scheduled', null, null) is not null then
    raise exception 'A cancelled session could be republished';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', 'fd000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"session_id":"fd000000-0000-4000-8000-000000000002","amr":[{"method":"oauth"}]}', true);
do $$
begin
  if (select array_agg(title order by title) from public.academy_live_sessions where title like 'Test %')
      is distinct from array['Test finished', 'Test future'] then
    raise exception 'Incorrect visibility for scheduled, draft or cancelled sessions';
  end if;
  if (select array_agg(recording_file_id) from public.academy_session_recovery where recording_file_id is not null)
      is distinct from array['Private_Recording']
      or not exists (select 1 from public.academy_session_recovery where material_file_id = 'Private_Material') then
    raise exception 'Recovery resources were missing or leaked before the live class';
  end if;
  begin
    perform public.academy_save_attendance(
      (select id from public.academy_live_sessions where title = 'Test finished'), auth.uid(), 'present'
    );
    raise exception 'Student could enter attendance';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', 'fd000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"session_id":"fd000000-0000-4000-8000-000000000003","amr":[{"method":"oauth"}]}', true);
do $$
begin
  if exists (select 1 from public.academy_live_sessions where title like 'Test %')
      or exists (select 1 from public.academy_session_recovery where recording_file_id = 'Private_Recording') then
    raise exception 'Session or recovery data leaked to a student enrolled in a different course';
  end if;
end;
$$;

rollback;
