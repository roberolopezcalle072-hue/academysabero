begin;

create schema academy_private;
revoke all on schema academy_private from public, anon, authenticated;

alter table public.academy_members
  add column updated_at timestamptz not null default now(),
  add constraint academy_members_user_role_key unique (user_id, role);

create table public.academy_students (
  user_id uuid primary key,
  member_role text generated always as ('student'::text) stored,
  full_name text not null check (btrim(full_name) <> ''),
  google_email text not null unique
    check (google_email = lower(btrim(google_email)) and position('@' in google_email) > 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (user_id, member_role)
    references public.academy_members (user_id, role) on delete restrict
);

create table public.academy_authorized_emails (
  email text primary key
    check (email = lower(btrim(email)) and position('@' in email) > 1),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.academy_courses (
  id uuid primary key default gen_random_uuid(),
  name text not null check (btrim(name) <> ''),
  description text not null,
  image_path text not null check (image_path ~ '^/images/[a-zA-Z0-9_/-]+\.[a-zA-Z0-9]+$'),
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  duration_minutes integer not null check (duration_minutes > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.academy_modules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.academy_courses (id),
  title text not null check (btrim(title) <> ''),
  position integer not null check (position > 0),
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (course_id, position),
  unique (id, course_id)
);

create table public.academy_lessons (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null,
  course_id uuid not null,
  title text not null check (btrim(title) <> ''),
  description text not null,
  day_number integer not null check (day_number > 0),
  prompt text,
  position integer not null check (position > 0),
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (module_id, course_id) references public.academy_modules (id, course_id),
  unique (module_id, position),
  unique (id, course_id)
);

create table public.academy_materials (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.academy_lessons (id),
  title text not null check (btrim(title) <> ''),
  kind text not null check (kind in ('document', 'recording', 'prompt', 'other')),
  drive_url text not null check (drive_url ~ '^https://(drive|docs)\.google\.com/[^[:space:]]+$'),
  position integer not null check (position > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_id, position)
);

create table public.academy_live_sessions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.academy_courses (id),
  title text not null check (btrim(title) <> ''),
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at),
  meet_url text not null check (meet_url ~ '^https://meet\.google\.com/[^[:space:]]+$'),
  status text not null default 'draft' check (status in ('draft', 'scheduled', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, course_id)
);

create table public.academy_enrollments (
  student_id uuid not null references public.academy_students (user_id),
  course_id uuid not null references public.academy_courses (id),
  enrolled_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'active', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (student_id, course_id),
  check (status not in ('active', 'completed') or enrolled_at is not null)
);

create table public.academy_enrollment_codes (
  code_digest text primary key check (code_digest ~ '^[0-9a-f]{64}$'),
  student_id uuid not null,
  course_id uuid not null,
  status text not null default 'active' check (status in ('active', 'used', 'revoked')),
  used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (student_id, course_id) references public.academy_enrollments (student_id, course_id),
  check ((status = 'used') = (used_at is not null))
);

create table public.academy_progress (
  student_id uuid not null,
  lesson_id uuid not null,
  course_id uuid not null,
  completed boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (student_id, lesson_id),
  foreign key (student_id, course_id) references public.academy_enrollments (student_id, course_id),
  foreign key (lesson_id, course_id) references public.academy_lessons (id, course_id),
  check (completed = (completed_at is not null))
);

create table public.academy_attendance (
  student_id uuid not null,
  session_id uuid not null,
  course_id uuid not null,
  status text not null check (status in ('present', 'absent', 'excused')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (student_id, session_id),
  foreign key (student_id, course_id) references public.academy_enrollments (student_id, course_id),
  foreign key (session_id, course_id) references public.academy_live_sessions (id, course_id)
);

create table public.academy_inquiries (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.academy_students (user_id),
  course_id uuid,
  subject text not null check (btrim(subject) <> ''),
  body text not null check (btrim(body) <> ''),
  status text not null default 'open' check (status in ('open', 'answered', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (student_id, course_id) references public.academy_enrollments (student_id, course_id)
);

create table public.academy_inquiry_replies (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null references public.academy_inquiries (id),
  administrator_id uuid not null,
  member_role text generated always as ('admin'::text) stored,
  body text not null check (btrim(body) <> ''),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (administrator_id, member_role) references public.academy_members (user_id, role)
);

create index academy_lessons_course_idx on public.academy_lessons (course_id, status);
create index academy_sessions_course_schedule_idx on public.academy_live_sessions (course_id, starts_at);
create index academy_enrollments_course_idx on public.academy_enrollments (course_id);
create index academy_codes_enrollment_idx on public.academy_enrollment_codes (student_id, course_id);
create unique index academy_codes_one_issued_idx
  on public.academy_enrollment_codes (student_id, course_id) where status in ('active', 'used');
create index academy_progress_enrollment_idx on public.academy_progress (student_id, course_id);
create index academy_progress_lesson_idx on public.academy_progress (lesson_id, course_id);
create index academy_attendance_enrollment_idx on public.academy_attendance (student_id, course_id);
create index academy_attendance_session_idx on public.academy_attendance (session_id, course_id);
create index academy_inquiries_student_course_idx on public.academy_inquiries (student_id, course_id, created_at);
create index academy_replies_inquiry_idx on public.academy_inquiry_replies (inquiry_id, created_at);
create index academy_replies_admin_idx on public.academy_inquiry_replies (administrator_id);

create function academy_private.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := statement_timestamp();
  return new;
end;
$$;

create function academy_private.validate_enrollment_code()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'active' then
      raise exception 'A new enrollment code must be active' using errcode = '23514';
    end if;
  elsif (new.code_digest, new.student_id, new.course_id)
      is distinct from (old.code_digest, old.student_id, old.course_id)
      or old.status <> 'active' then
    raise exception 'An enrollment code cannot be reassigned or changed after use or revocation'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger validate_enrollment_code before insert or update
on public.academy_enrollment_codes
for each row execute function academy_private.validate_enrollment_code();

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
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('create trigger touch_updated_at before update on public.%I
      for each row execute function academy_private.touch_updated_at()', table_name);
  end loop;
end;
$$;

grant select on public.academy_members to authenticated;

-- Existing Google students and subsequent membership grants share the same profile rules.
create function academy_private.create_google_student(target_user uuid)
returns void language sql set search_path = '' as $$
  insert into public.academy_students (user_id, full_name, google_email, created_at)
  select m.user_id,
         coalesce(nullif(btrim(i.identity_data->>'full_name'), ''),
                  nullif(btrim(i.identity_data->>'name'), ''),
                  lower(btrim(i.identity_data->>'email'))),
         lower(btrim(i.identity_data->>'email')), m.created_at
  from public.academy_members m
  join auth.identities i on i.user_id = m.user_id and i.provider = 'google'
  where m.user_id = target_user and m.role = 'student'
    and nullif(btrim(i.identity_data->>'email'), '') is not null
  on conflict (user_id) do nothing;
$$;

select academy_private.create_google_student(user_id)
from public.academy_members where role = 'student';

create function academy_private.ensure_student_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform academy_private.create_google_student(new.user_id);
  if not exists (select 1 from public.academy_students where user_id = new.user_id) then
    raise exception 'Student membership requires a Google identity with an email'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger ensure_student_profile after insert
on public.academy_members for each row when (new.role = 'student')
execute function academy_private.ensure_student_profile();

revoke execute on all functions in schema academy_private from public, anon, authenticated;

commit;
