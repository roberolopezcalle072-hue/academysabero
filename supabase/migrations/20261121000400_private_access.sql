begin;

create table public.academy_email_enrollments (
  email text not null references public.academy_authorized_emails(email),
  course_id uuid not null references public.academy_courses(id),
  code_digest text unique check (code_digest ~ '^[0-9a-f]{64}$'),
  claimed_by uuid references public.academy_students(user_id),
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (email, course_id),
  check ((claimed_by is null) = (claimed_at is null))
);
create index academy_email_enrollment_course_idx on public.academy_email_enrollments(course_id);
create index academy_email_enrollment_claim_idx on public.academy_email_enrollments(claimed_by);
alter table public.academy_email_enrollments enable row level security;
revoke all on public.academy_email_enrollments from public, anon, authenticated;
grant select (email, course_id, claimed_at, created_at) on public.academy_email_enrollments to authenticated;
create policy admin_read on public.academy_email_enrollments to authenticated
  using ((select academy_private.is_admin()));
create trigger touch_updated_at before update on public.academy_email_enrollments
  for each row execute function academy_private.touch_updated_at();

create function public.academy_before_user_created(event jsonb)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when event #>> '{user,app_metadata,provider}' = 'google'
    and exists (
      select 1 from public.academy_authorized_emails
      where email = lower(btrim(event #>> '{user,email}')) and active
    )
  then '{}'::jsonb
  else jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Academy access is private'))
  end;
$$;
revoke execute on function public.academy_before_user_created(jsonb) from public, anon, authenticated;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.academy_before_user_created(jsonb) to supabase_auth_admin;

-- Use provider-owned identity data, the current Auth email and a live Auth session.
create function academy_private.google_email()
returns text language sql stable security definer set search_path = '' as $$
  select lower(btrim(u.email))
  from auth.users u
  where u.id = (select auth.uid()) and u.email_confirmed_at is not null
    and auth.jwt()->'amr' @> '[{"method":"oauth"}]'::jsonb
    and exists (
      select 1 from auth.identities i where i.user_id = u.id and i.provider = 'google'
        and lower(btrim(i.identity_data->>'email')) = lower(btrim(u.email))
        and i.identity_data->>'email_verified' = 'true'
    )
    and exists (
      select 1 from auth.sessions s where s.user_id = u.id
        and s.id = nullif(auth.jwt()->>'session_id', '')::uuid
        and (s.not_after is null or s.not_after > now())
    );
$$;

create or replace function academy_private.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select academy_private.google_email() is not null and exists (
    select 1 from public.academy_members
    where user_id = (select auth.uid()) and active and role = 'admin'
  );
$$;

create function academy_private.authorized_student()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.academy_members m
    join public.academy_students s using (user_id)
    join public.academy_authorized_emails a on a.email = s.google_email
    where m.user_id = (select auth.uid()) and m.role = 'student' and m.active
      and a.active and s.google_email = (select academy_private.google_email())
  );
$$;

create or replace function academy_private.is_active_student()
returns boolean language sql stable security definer set search_path = '' as $$
  select academy_private.authorized_student() and exists (
    select 1 from public.academy_enrollments
    where student_id = (select auth.uid()) and status = 'active'
  );
$$;

drop policy "Members read their own active membership" on public.academy_members;
create policy student_read_membership on public.academy_members for select to authenticated
  using (user_id = (select auth.uid()) and (select academy_private.is_active_student()));
drop policy student_read_course on public.academy_courses;
create policy student_read_course on public.academy_courses for select to authenticated using (
  status = 'published' and exists (
    select 1 from public.academy_enrollments e
    where e.course_id = academy_courses.id and e.student_id = (select auth.uid())
      and e.status = 'active'
  )
);

-- Keep codes issued under the previous model redeemable before the first active enrollment.
alter function public.academy_redeem_enrollment_code(text) set schema academy_private;
create or replace function academy_private.academy_redeem_enrollment_code(p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  student uuid := auth.uid();
  digest text := encode(sha256(convert_to(p_code, 'UTF8')), 'hex');
  course uuid;
begin
  if not academy_private.authorized_student() then return null; end if;
  select c.course_id into course from public.academy_enrollment_codes c
  where c.code_digest = digest and c.student_id = student and c.status = 'active' for update;
  if not found then return null; end if;
  update public.academy_enrollments set status = 'active', enrolled_at = statement_timestamp()
  where student_id = student and course_id = course and status = 'pending';
  if not found then return null; end if;
  update public.academy_enrollment_codes set status = 'used', used_at = statement_timestamp()
  where code_digest = digest;
  return course;
end;
$$;

create function academy_private.prepare_student()
returns text language plpgsql set search_path = '' as $$
declare
  student_email text := academy_private.google_email();
begin
  perform 1 from public.academy_authorized_emails
  where email = student_email and active for share;
  if not found then return null; end if;

  insert into public.academy_members(user_id, role)
  values (auth.uid(), 'student') on conflict (user_id) do nothing;
  perform academy_private.create_google_student(auth.uid());
  if not academy_private.authorized_student() then return null; end if;
  return student_email;
end;
$$;

create function academy_private.claim_email_enrollments(student_email text, digest text)
returns boolean language sql set search_path = '' as $$
  with requested as (
    select a.email, a.course_id, a.code_digest
    from public.academy_email_enrollments a
    where a.email = student_email and a.claimed_at is null
      and a.code_digest is not distinct from digest
    order by a.course_id
    for update
  ), enrolled as (
    insert into public.academy_enrollments as e (student_id, course_id, enrolled_at, status)
    select auth.uid(), course_id, statement_timestamp(), 'active' from requested
    on conflict (student_id, course_id) do update
      set status = 'active', enrolled_at = coalesce(e.enrolled_at, excluded.enrolled_at)
      where e.status in ('pending', 'active')
    returning course_id
  ), claimed as (
    update public.academy_email_enrollments a
    set claimed_by = auth.uid(), claimed_at = statement_timestamp()
    from enrolled e
    where a.email = student_email and a.course_id = e.course_id
    returning 1
  )
  select exists (select 1 from claimed);
$$;

create function public.academy_resolve_access()
returns text language plpgsql security definer set search_path = '' as $$
declare
  student_email text;
begin
  if academy_private.is_admin() then return 'admin'; end if;
  student_email := academy_private.prepare_student();
  if student_email is null then return 'denied'; end if;
  perform academy_private.claim_email_enrollments(student_email, null);
  if academy_private.is_active_student() then return 'student'; end if;
  return 'enrollment-required';
end;
$$;

create function public.academy_redeem_access_code(p_code text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  student_email text;
begin
  if p_code is null or p_code !~ '^[A-Za-z0-9_-]{32,128}$' then return false; end if;
  student_email := academy_private.prepare_student();
  if student_email is null then return false; end if;
  return academy_private.claim_email_enrollments(student_email, encode(sha256(convert_to(p_code, 'UTF8')), 'hex'))
    or academy_private.academy_redeem_enrollment_code(p_code) is not null;
end;
$$;

-- Preserve the previous public RPC contract for existing enrollment codes.
create function public.academy_redeem_enrollment_code(p_code text)
returns uuid language sql security definer set search_path = '' as $$
  select academy_private.academy_redeem_enrollment_code(p_code)
  where p_code ~ '^[A-Za-z0-9_-]{32,128}$';
$$;

create function public.academy_assign_email_enrollment(p_email text, p_course uuid, p_digest text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not academy_private.is_admin() then raise insufficient_privilege; end if;
  perform 1 from public.academy_authorized_emails where email = p_email and active for share;
  if not found then raise exception 'Email is not authorized' using errcode = '23514'; end if;
  insert into public.academy_email_enrollments(email, course_id, code_digest)
  values (p_email, p_course, p_digest);
end;
$$;

revoke execute on all functions in schema academy_private from public, anon, authenticated;
grant execute on function academy_private.is_admin(), academy_private.is_active_student() to authenticated;
revoke execute on function public.academy_resolve_access(), public.academy_redeem_access_code(text),
  public.academy_redeem_enrollment_code(text), public.academy_assign_email_enrollment(text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.academy_resolve_access(), public.academy_redeem_access_code(text),
  public.academy_redeem_enrollment_code(text), public.academy_assign_email_enrollment(text, uuid, text)
  to authenticated;

commit;
