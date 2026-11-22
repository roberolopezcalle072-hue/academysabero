begin;

create function academy_private.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.academy_members
    where user_id = (select auth.uid()) and role = 'admin' and active
  );
$$;

create function academy_private.is_active_student()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.academy_members m
    join public.academy_students s using (user_id)
    where m.user_id = (select auth.uid()) and m.active
  );
$$;

revoke execute on all functions in schema academy_private from public, anon, authenticated;
grant usage on schema academy_private to authenticated;
grant execute on function academy_private.is_admin(), academy_private.is_active_student() to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'academy_members', 'academy_students', 'academy_authorized_emails',
    'academy_courses', 'academy_modules', 'academy_lessons', 'academy_materials',
    'academy_live_sessions', 'academy_enrollments', 'academy_enrollment_codes',
    'academy_progress', 'academy_attendance', 'academy_inquiries', 'academy_inquiry_replies'
  ] loop
    execute format('grant select on table public.%I to authenticated', table_name);
    execute format('create policy admin_read on public.%I for select to authenticated
      using ((select academy_private.is_admin()))', table_name);
  end loop;

  foreach table_name in array array[
    'academy_authorized_emails', 'academy_courses', 'academy_modules', 'academy_lessons',
    'academy_materials', 'academy_live_sessions', 'academy_enrollments', 'academy_progress',
    'academy_attendance', 'academy_inquiries'
  ] loop
    execute format('grant insert, update on table public.%I to authenticated', table_name);
    execute format('create policy admin_insert on public.%I for insert to authenticated
      with check ((select academy_private.is_admin()))', table_name);
    execute format('create policy admin_update on public.%I for update to authenticated
      using ((select academy_private.is_admin())) with check ((select academy_private.is_admin()))', table_name);
  end loop;
end;
$$;

create policy student_read_profile on public.academy_students
  for select to authenticated
  using ((select academy_private.is_active_student()) and user_id = (select auth.uid()));

create policy student_read_enrollment on public.academy_enrollments
  for select to authenticated
  using ((select academy_private.is_active_student()) and student_id = (select auth.uid()));

create policy student_read_course on public.academy_courses
  for select to authenticated using (
    status = 'published' and exists (
      select 1 from public.academy_enrollments e
      where e.course_id = academy_courses.id and e.student_id = (select auth.uid())
        and e.status in ('active', 'completed')
    )
  );

create policy student_read_module on public.academy_modules
  for select to authenticated using (
    status = 'published' and exists (
      select 1 from public.academy_courses c where c.id = academy_modules.course_id
    )
  );

create policy student_read_lesson on public.academy_lessons
  for select to authenticated using (
    status = 'published' and exists (
      select 1 from public.academy_modules m where m.id = academy_lessons.module_id
    )
  );

create policy student_read_material on public.academy_materials
  for select to authenticated using (
    exists (select 1 from public.academy_lessons l where l.id = academy_materials.lesson_id)
  );

create policy student_read_session on public.academy_live_sessions
  for select to authenticated using (
    status in ('scheduled', 'completed') and exists (
      select 1 from public.academy_courses c where c.id = academy_live_sessions.course_id
    )
  );

create policy student_read_progress on public.academy_progress
  for select to authenticated
  using ((select academy_private.is_active_student()) and student_id = (select auth.uid()));

create policy student_read_attendance on public.academy_attendance
  for select to authenticated
  using ((select academy_private.is_active_student()) and student_id = (select auth.uid()));

create policy student_read_inquiry on public.academy_inquiries
  for select to authenticated
  using ((select academy_private.is_active_student()) and student_id = (select auth.uid()));

create policy student_read_reply on public.academy_inquiry_replies
  for select to authenticated using (
    exists (select 1 from public.academy_inquiries i where i.id = academy_inquiry_replies.inquiry_id)
  );

grant insert (inquiry_id, administrator_id, body) on public.academy_inquiry_replies to authenticated;
create policy admin_insert_reply on public.academy_inquiry_replies
  for insert to authenticated
  with check ((select academy_private.is_admin()) and administrator_id = (select auth.uid()));

grant insert (code_digest, student_id, course_id), update (status)
  on public.academy_enrollment_codes to authenticated;

create policy admin_issue_code on public.academy_enrollment_codes
  for insert to authenticated with check (
    (select academy_private.is_admin()) and status = 'active' and exists (
      select 1 from public.academy_enrollments e
      where (e.student_id, e.course_id) =
        (academy_enrollment_codes.student_id, academy_enrollment_codes.course_id)
        and e.status = 'pending'
    )
  );

create policy admin_revoke_code on public.academy_enrollment_codes
  for update to authenticated
  using ((select academy_private.is_admin()) and status = 'active')
  with check ((select academy_private.is_admin()) and status = 'revoked');

create function public.academy_redeem_enrollment_code(p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  target_student uuid := auth.uid();
  target_digest text;
  target_course uuid;
  redeemed_at timestamptz := statement_timestamp();
begin
  if not academy_private.is_active_student()
      or p_code is null or p_code !~ '^[A-Za-z0-9_-]{32,128}$' then
    return null;
  end if;

  target_digest := encode(sha256(convert_to(p_code, 'UTF8')), 'hex');

  select c.course_id into target_course
  from public.academy_enrollment_codes c
  where c.code_digest = target_digest and c.student_id = target_student and c.status = 'active'
  for update;
  if not found then return null; end if;

  update public.academy_enrollments
  set status = 'active', enrolled_at = redeemed_at
  where student_id = target_student and course_id = target_course and status = 'pending';
  if not found then return null; end if;

  update public.academy_enrollment_codes
  set status = 'used', used_at = redeemed_at
  where code_digest = target_digest;

  return target_course;
end;
$$;

revoke execute on function public.academy_redeem_enrollment_code(text) from public, anon, authenticated;
grant execute on function public.academy_redeem_enrollment_code(text) to authenticated;

create view public.academy_administrators with (security_invoker = true) as
  select user_id, active, created_at, updated_at
  from public.academy_members where role = 'admin';

create view public.academy_student_profiles with (security_invoker = true) as
  select s.user_id, s.full_name, s.google_email, m.active as access_active,
         s.created_at as registered_at, greatest(s.updated_at, m.updated_at) as updated_at
  from public.academy_students s
  join public.academy_members m using (user_id);

create view public.academy_enrollment_overview with (security_invoker = true) as
  select e.*,
         coalesce(round(100.0 * totals.completed_lessons / nullif(totals.total_lessons, 0), 2), 0)
           as overall_progress
  from public.academy_enrollments e
  cross join lateral (
    select count(*) as total_lessons, count(*) filter (where p.completed) as completed_lessons
    from public.academy_lessons l
    join public.academy_modules m on m.id = l.module_id and m.status = 'published'
    join public.academy_courses c on c.id = l.course_id and c.status = 'published'
    left join public.academy_progress p on p.lesson_id = l.id and p.student_id = e.student_id
    where l.course_id = e.course_id and l.status = 'published'
      and e.status in ('active', 'completed')
  ) totals;

revoke all on public.academy_administrators, public.academy_student_profiles,
  public.academy_enrollment_overview from public, anon, authenticated;
grant select on public.academy_administrators, public.academy_student_profiles,
  public.academy_enrollment_overview to authenticated;

commit;
