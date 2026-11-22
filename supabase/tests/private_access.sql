-- Run as database owner on an isolated test project. All test rows are rolled back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, email_confirmed_at)
values
  ('ff000000-0000-4000-8000-000000000001', 'admin@example.invalid', now()),
  ('ff000000-0000-4000-8000-000000000002', 'student@example.invalid', now()),
  ('ff000000-0000-4000-8000-000000000003', 'peer@example.invalid', now()),
  ('ff000000-0000-4000-8000-000000000004', 'denied@example.invalid', now());

insert into auth.identities (user_id, provider_id, provider, identity_data)
select id, id::text, 'google', jsonb_build_object('email', email, 'email_verified', true)
from auth.users where id in (
  'ff000000-0000-4000-8000-000000000001', 'ff000000-0000-4000-8000-000000000002',
  'ff000000-0000-4000-8000-000000000003', 'ff000000-0000-4000-8000-000000000004'
);
insert into auth.sessions (id, user_id, created_at, updated_at)
select id, id, now(), now() from auth.users where email like '%@example.invalid';

insert into public.academy_members (user_id, role)
values ('ff000000-0000-4000-8000-000000000001', 'admin');

insert into public.academy_courses (id, name, description, image_path, status, duration_minutes)
values
  ('ff000000-0000-4000-8000-000000000011', 'Course A', '', '/images/a.webp', 'published', 60),
  ('ff000000-0000-4000-8000-000000000012', 'Course B', '', '/images/b.webp', 'published', 60);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ff000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"ff000000-0000-4000-8000-000000000001","session_id":"ff000000-0000-4000-8000-000000000001","amr":[{"method":"oauth"}]}', true);
do $$
begin
  if public.academy_resolve_access() <> 'admin' then raise exception 'Admin access denied'; end if;
  insert into public.academy_authorized_emails(email)
  values ('student@example.invalid'), ('peer@example.invalid');
  perform public.academy_assign_email_enrollment(
    'student@example.invalid', 'ff000000-0000-4000-8000-000000000011',
    encode(sha256(convert_to(repeat('A', 32), 'UTF8')), 'hex')
  );
  perform public.academy_assign_email_enrollment(
    'peer@example.invalid', 'ff000000-0000-4000-8000-000000000012', null
  );
end;
$$;

set local role supabase_auth_admin;
do $$
begin
  if public.academy_before_user_created('{"user":{"email":"student@example.invalid","app_metadata":{"provider":"google"}}}') <> '{}'::jsonb
      or not (public.academy_before_user_created('{"user":{"email":"denied@example.invalid","app_metadata":{"provider":"google"}}}') ? 'error')
      or not (public.academy_before_user_created('{"user":{"email":"student@example.invalid","app_metadata":{"provider":"email"}}}') ? 'error') then
    raise exception 'Unexpected account creation decision';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ff000000-0000-4000-8000-000000000004', true);
select set_config('request.jwt.claims', '{"sub":"ff000000-0000-4000-8000-000000000004","session_id":"ff000000-0000-4000-8000-000000000004","amr":[{"method":"oauth"}]}', true);
do $$ begin
  if public.academy_resolve_access() <> 'denied' then raise exception 'Unauthorized email accepted'; end if;
end $$;

select set_config('request.jwt.claim.sub', 'ff000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"ff000000-0000-4000-8000-000000000003","session_id":"ff000000-0000-4000-8000-000000000003","amr":[{"method":"oauth"}]}', true);
do $$
begin
  if public.academy_redeem_access_code(repeat('A', 32)) then raise exception 'Code works for a different email'; end if;
  if public.academy_resolve_access() <> 'student' then raise exception 'Automatic enrollment failed'; end if;
end;
$$;

select set_config('request.jwt.claim.sub', 'ff000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"ff000000-0000-4000-8000-000000000002","session_id":"ff000000-0000-4000-8000-000000000002","amr":[{"method":"oauth"}]}', true);
do $$
begin
  if public.academy_resolve_access() <> 'enrollment-required'
      or exists (select 1 from public.academy_courses) then
    raise exception 'An active enrollment was not required';
  end if;
  if public.academy_redeem_access_code(repeat('B', 32)) then raise exception 'Wrong code accepted'; end if;
  if not public.academy_redeem_access_code(repeat('A', 32)) then raise exception 'Assigned code rejected'; end if;
  if public.academy_redeem_access_code(repeat('A', 32)) then raise exception 'Code reused'; end if;
  if public.academy_resolve_access() <> 'student'
      or (select array_agg(id) from public.academy_courses) is distinct from array['ff000000-0000-4000-8000-000000000011'::uuid]
      or (select array_agg(google_email) from public.academy_student_profiles) is distinct from array['student@example.invalid'] then
    raise exception 'Student access or row isolation failed';
  end if;
  begin
    update public.academy_members set role = 'admin' where user_id = auth.uid();
    raise exception 'Student could modify a role';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.academy_assign_email_enrollment(
      'student@example.invalid', 'ff000000-0000-4000-8000-000000000012', null
    );
    raise exception 'Student could assign enrollment';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', 'ff000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"ff000000-0000-4000-8000-000000000001","session_id":"ff000000-0000-4000-8000-000000000001","amr":[{"method":"oauth"}]}', true);
do $$
begin
  if (select count(*) from public.academy_student_profiles where google_email in ('student@example.invalid','peer@example.invalid')) <> 2 then
    raise exception 'Admin cannot see both students';
  end if;
  update public.academy_authorized_emails set active = false where email = 'student@example.invalid';
end;
$$;

select set_config('request.jwt.claim.sub', 'ff000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"ff000000-0000-4000-8000-000000000002","session_id":"ff000000-0000-4000-8000-000000000002","amr":[{"method":"oauth"}]}', true);
do $$
begin
  if public.academy_resolve_access() <> 'denied' or exists (select 1 from public.academy_courses) then
    raise exception 'Revoked email retained access';
  end if;
end;
$$;

reset role;
delete from auth.sessions where id = 'ff000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ff000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"ff000000-0000-4000-8000-000000000003","session_id":"ff000000-0000-4000-8000-000000000003","amr":[{"method":"oauth"}]}', true);
do $$
begin
  if public.academy_resolve_access() <> 'denied' or exists (select 1 from public.academy_courses) then
    raise exception 'Closed session retained access';
  end if;
end;
$$;

rollback;
