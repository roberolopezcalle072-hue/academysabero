-- Run as the database owner after applying the migrations. This script writes no data.
begin;

do $$
declare
  relation_name text;
  relation_oid regclass;
begin
  foreach relation_name in array array[
    'academy_members', 'academy_students', 'academy_authorized_emails',
    'academy_courses', 'academy_modules', 'academy_lessons', 'academy_materials',
    'academy_live_sessions', 'academy_enrollments', 'academy_enrollment_codes',
    'academy_progress', 'academy_attendance', 'academy_inquiries', 'academy_inquiry_replies'
  ] loop
    relation_oid := to_regclass('public.' || relation_name);
    if relation_oid is null
        or not exists (select 1 from pg_class where oid = relation_oid and relrowsecurity)
        or not has_table_privilege('authenticated', relation_oid, 'SELECT')
        or has_any_column_privilege('anon', relation_oid, 'SELECT,INSERT,UPDATE')
        or has_table_privilege('anon', relation_oid, 'DELETE,TRUNCATE')
        or not exists (
          select 1 from pg_trigger where tgrelid = relation_oid and tgname = 'touch_updated_at'
            and tgenabled = 'O'
        )
        or not exists (
          select 1 from pg_policy where polrelid = relation_oid and polname = 'admin_read'
        ) then
      raise exception 'Unexpected RLS, grants or update trigger for %', relation_name;
    end if;
  end loop;

  foreach relation_name in array array[
    'academy_administrators', 'academy_student_profiles', 'academy_enrollment_overview'
  ] loop
    relation_oid := to_regclass('public.' || relation_name);
    if relation_oid is null
        or not has_table_privilege('authenticated', relation_oid, 'SELECT')
        or has_table_privilege('anon', relation_oid, 'SELECT')
        or not exists (
          select 1 from pg_class where oid = relation_oid
            and 'security_invoker=true' = any(reloptions)
        ) then
      raise exception 'Unexpected view security for %', relation_name;
    end if;
  end loop;

  if exists (
    select 1
    from (
      values
        ('academy_students', 'academy_members', 2),
        ('academy_lessons', 'academy_modules', 2),
        ('academy_enrollment_codes', 'academy_enrollments', 2),
        ('academy_progress', 'academy_enrollments', 2),
        ('academy_progress', 'academy_lessons', 2),
        ('academy_attendance', 'academy_enrollments', 2),
        ('academy_attendance', 'academy_live_sessions', 2),
        ('academy_inquiries', 'academy_enrollments', 2),
        ('academy_inquiry_replies', 'academy_members', 2)
    ) expected(child, parent, key_size)
    where not exists (
      select 1 from pg_constraint
      where contype = 'f' and convalidated
        and conrelid = to_regclass('public.' || expected.child)
        and confrelid = to_regclass('public.' || expected.parent)
        and cardinality(conkey) = expected.key_size
    )
  ) then
    raise exception 'Missing or invalid composite foreign key';
  end if;

  if has_column_privilege('authenticated', 'public.academy_members', 'role', 'UPDATE')
      or has_table_privilege('authenticated', 'public.academy_enrollment_codes', 'DELETE')
      or has_function_privilege('anon', 'public.academy_redeem_enrollment_code(text)', 'EXECUTE')
      or not has_function_privilege('authenticated', 'public.academy_redeem_enrollment_code(text)', 'EXECUTE')
      or has_function_privilege('authenticated', 'academy_private.create_google_student(uuid)', 'EXECUTE') then
    raise exception 'Unexpected privilege on a membership or code operation';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);

do $$
begin
  if exists (select 1 from public.academy_student_profiles)
      or exists (select 1 from public.academy_administrators)
      or exists (select 1 from public.academy_enrollment_overview)
      or exists (select 1 from public.academy_materials)
      or exists (select 1 from public.academy_live_sessions)
      or exists (select 1 from public.academy_inquiry_replies)
      or public.academy_redeem_enrollment_code(null) is not null then
    raise exception 'A session without an academy identity can access protected data';
  end if;
end;
$$;

rollback;
