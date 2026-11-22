-- Run as a database owner on an isolated project. All test fixtures are rolled back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, email_confirmed_at)
values
  ('fe000000-0000-4000-8000-000000000001', 'editor@example.invalid', now()),
  ('fe000000-0000-4000-8000-000000000002', 'learner@example.invalid', now());

insert into auth.identities (user_id, provider_id, provider, identity_data)
select id, id::text, 'google', jsonb_build_object('email', email, 'email_verified', true)
from auth.users where id in ('fe000000-0000-4000-8000-000000000001', 'fe000000-0000-4000-8000-000000000002');

insert into auth.sessions (id, user_id, created_at, updated_at)
select id, id, now(), now()
from auth.users where id in ('fe000000-0000-4000-8000-000000000001', 'fe000000-0000-4000-8000-000000000002');

insert into public.academy_members (user_id, role)
values ('fe000000-0000-4000-8000-000000000001', 'admin'), ('fe000000-0000-4000-8000-000000000002', 'student');
insert into public.academy_authorized_emails (email) values ('learner@example.invalid');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fe000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"fe000000-0000-4000-8000-000000000001","session_id":"fe000000-0000-4000-8000-000000000001","amr":[{"method":"oauth"}]}', true);

insert into public.academy_program_page (title, introduction, description, duration_text, registration_text, registration_url)
values ('Test program', 'Introduction', 'Description', '1 week', 'Registration', 'https://example.invalid/register');

insert into public.academy_courses (id, name, description, image_path, status, duration_minutes)
values
  ('fe000000-0000-4000-8000-000000000011', 'Private A', '', '/images/a.webp', 'published', 60),
  ('fe000000-0000-4000-8000-000000000012', 'Private B', '', '/images/b.webp', 'published', 60);

insert into public.academy_modules (id, course_id, title, position, status) values
  ('fe000000-0000-4000-8000-000000000021', 'fe000000-0000-4000-8000-000000000011', 'Module A', 1, 'published'),
  ('fe000000-0000-4000-8000-000000000022', 'fe000000-0000-4000-8000-000000000012', 'Module B', 1, 'published');

insert into public.academy_lessons (id, module_id, course_id, title, description, day_number, position, status, objective) values
  ('fe000000-0000-4000-8000-000000000031', 'fe000000-0000-4000-8000-000000000021', 'fe000000-0000-4000-8000-000000000011', 'Published lesson', 'Explanation', 1, 1, 'published', 'Objective'),
  ('fe000000-0000-4000-8000-000000000032', 'fe000000-0000-4000-8000-000000000021', 'fe000000-0000-4000-8000-000000000011', 'Draft lesson', 'Explanation', 2, 2, 'draft', 'Objective'),
  ('fe000000-0000-4000-8000-000000000033', 'fe000000-0000-4000-8000-000000000022', 'fe000000-0000-4000-8000-000000000012', 'Other lesson', 'Explanation', 1, 1, 'published', 'Objective');

insert into public.academy_materials (lesson_id, title, kind, drive_url, position)
values ('fe000000-0000-4000-8000-000000000031', 'Resource', 'document', 'https://docs.google.com/document/d/Test_Drive_Identifier/edit', 1);
insert into public.academy_enrollments (student_id, course_id, enrolled_at, status)
values ('fe000000-0000-4000-8000-000000000002', 'fe000000-0000-4000-8000-000000000011', now(), 'active');
insert into public.academy_live_sessions (course_id, title, starts_at, ends_at, meet_url, status)
values ('fe000000-0000-4000-8000-000000000011', 'Upcoming', now() + interval '1 day', now() + interval '1 day 1 hour',
  'https://meet.google.com/aaa-bbbb-ccc', 'scheduled');

set local role anon;
do $$
begin
  if exists (select 1 from public.academy_program_page where title = 'Test program') then
    raise exception 'Draft program is public';
  end if;
  if has_function_privilege('anon', 'public.academy_course_content(uuid)', 'execute') then
    raise exception 'Anonymous course RPC access';
  end if;
end;
$$;
set local role authenticated;
update public.academy_program_page set published = true where title = 'Test program';
set local role anon;
do $$ begin
  if not exists (select 1 from public.academy_program_page where title = 'Test program') then
    raise exception 'Published program did not appear';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fe000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"fe000000-0000-4000-8000-000000000002","session_id":"fe000000-0000-4000-8000-000000000002","amr":[{"method":"oauth"}]}', true);

do $$
declare
  content jsonb;
  home jsonb;
begin
  home := public.academy_campus_home();
  if jsonb_array_length(home->'pending') <> 1 or home #>> '{next_session,title}' <> 'Upcoming'
      or jsonb_array_length(home->'courses') <> 1 then
    raise exception 'Campus summary does not reflect the active enrollment';
  end if;
  content := public.academy_course_content('fe000000-0000-4000-8000-000000000011');
  if jsonb_array_length(content #> '{modules,0,lessons}') is distinct from 1
      or content #>> '{modules,0,lessons,0,objective}' is distinct from 'Objective'
      or content #>> '{modules,0,lessons,0,materials,0,drive_file_id}' is distinct from 'Test_Drive_Identifier'
      or public.academy_course_content('fe000000-0000-4000-8000-000000000012') is not null then
    raise exception 'Content filtering or Drive identifier failed';
  end if;
  if public.academy_complete_lesson('fe000000-0000-4000-8000-000000000032')
      or public.academy_complete_lesson('fe000000-0000-4000-8000-000000000033') then
    raise exception 'Student marked an unpublished or foreign lesson as completed';
  end if;
  if not public.academy_complete_lesson('fe000000-0000-4000-8000-000000000031')
      or not public.academy_complete_lesson('fe000000-0000-4000-8000-000000000031') then
    raise exception 'Progress update failed';
  end if;
  home := public.academy_campus_home();
  if jsonb_array_length(home->'pending') <> 0 or (home #>> '{courses,0,progress}')::numeric <> 100 then
    raise exception 'Progress did not update the campus';
  end if;
  insert into public.academy_inquiries (student_id, subject, body)
  values (auth.uid(), 'Campus test', 'Test content');
  if not exists (select 1 from public.academy_inquiries where subject = 'Campus test') then
    raise exception 'Own inquiry could not be read';
  end if;
end;
$$;

rollback;
