begin;

alter table public.academy_live_sessions
  add column program_day integer check (program_day between 1 and 30),
  add column description text not null default '',
  alter column meet_url drop not null,
  add constraint scheduled_session_requires_meet check (status <> 'scheduled' or meet_url is not null);

create index academy_sessions_schedule_idx
  on public.academy_live_sessions (starts_at, id) where status = 'scheduled';

create table public.academy_session_recovery (
  session_id uuid primary key references public.academy_live_sessions(id),
  recording_url text check (recording_url ~ '^https://drive\.google\.com/[^[:space:]]+$'),
  material_url text check (material_url ~ '^https://(drive|docs)\.google\.com/[^[:space:]]+$'),
  recording_file_id text generated always as (
    coalesce(substring(recording_url from '/d/([A-Za-z0-9_-]+)(?:[/?#]|$)'),
      substring(recording_url from '[?&]id=([A-Za-z0-9_-]+)(?:[&#]|$)'))
  ) stored,
  material_file_id text generated always as (
    coalesce(substring(material_url from '/d/([A-Za-z0-9_-]+)(?:[/?#]|$)'),
      substring(material_url from '[?&]id=([A-Za-z0-9_-]+)(?:[&#]|$)'))
  ) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (recording_url is null or recording_file_id is not null),
  check (material_url is null or material_file_id is not null)
);

alter table public.academy_session_recovery enable row level security;
revoke all on public.academy_session_recovery from public, anon, authenticated;
grant select, insert, update on public.academy_session_recovery to authenticated;
create policy admin_session_recovery on public.academy_session_recovery to authenticated
  using ((select academy_private.is_admin())) with check ((select academy_private.is_admin()));
create policy student_read_session_recovery on public.academy_session_recovery
  for select to authenticated using (
    exists (
      select 1 from public.academy_live_sessions s
      where s.id = academy_session_recovery.session_id and s.status = 'completed' and s.ends_at <= now()
    )
  );
create trigger touch_updated_at before update on public.academy_session_recovery
  for each row execute function academy_private.touch_updated_at();

create function public.academy_save_live_session(
  p_session uuid, p_course uuid, p_title text, p_day integer, p_description text,
  p_starts timestamptz, p_ends timestamptz, p_meet text, p_status text,
  p_recording text, p_material text
)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  target uuid;
begin
  if not academy_private.is_admin() then raise insufficient_privilege; end if;
  if p_status is null or p_status not in ('draft', 'scheduled', 'completed') or
      p_day is null or p_day not between 1 and 30 or
      nullif(btrim(p_title), '') is null or nullif(btrim(p_description), '') is null or
      (p_status = 'completed' and p_ends > statement_timestamp()) then
    raise check_violation using message = 'Invalid live session details';
  end if;

  if p_session is null then
    insert into public.academy_live_sessions (
      course_id, title, program_day, description, starts_at, ends_at, meet_url, status
    ) values (
      p_course, p_title, p_day, p_description, p_starts, p_ends, p_meet, p_status
    ) returning id into target;
  else
    update public.academy_live_sessions set
      title = p_title, program_day = p_day, description = p_description, starts_at = p_starts,
      ends_at = p_ends, meet_url = p_meet, status = p_status
    where id = p_session and course_id = p_course and status <> 'cancelled'
      and (status <> 'completed' or p_status = 'completed')
    returning id into target;
    if not found then return null; end if;
  end if;

  insert into public.academy_session_recovery(session_id, recording_url, material_url)
    values (target, p_recording, p_material)
    on conflict (session_id) do update set
      recording_url = excluded.recording_url, material_url = excluded.material_url;

  return target;
end;
$$;

create function public.academy_save_attendance(p_session uuid, p_student uuid, p_status text)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare
  target_course uuid;
begin
  if not academy_private.is_admin() then raise insufficient_privilege; end if;
  select course_id into target_course from public.academy_live_sessions
  where id = p_session and status in ('scheduled', 'completed') and starts_at <= statement_timestamp()
  for share;
  if not found then return false; end if;

  perform 1 from public.academy_enrollments e
  where e.student_id = p_student and e.course_id = target_course and (
    e.status in ('active', 'completed') or exists (
      select 1 from public.academy_attendance a where a.session_id = p_session and a.student_id = p_student
    )
  ) for share;
  if not found then return false; end if;
  insert into public.academy_attendance(student_id, session_id, course_id, status)
    values (p_student, p_session, target_course, p_status)
    on conflict (student_id, session_id) do update set status = excluded.status;
  return true;
end;
$$;

create function public.academy_session_roster(p_session uuid, p_present_only boolean, p_offset integer)
returns table (
  student_id uuid, full_name text, google_email text, attendance text
) language sql stable security invoker set search_path = '' as $$
  select e.student_id, p.full_name, p.google_email, a.status
  from public.academy_live_sessions s
  join public.academy_enrollments e on e.course_id = s.course_id
  join public.academy_student_profiles p on p.user_id = e.student_id
  left join public.academy_attendance a on a.session_id = s.id and a.student_id = e.student_id
  where (select academy_private.is_admin()) and s.id = p_session
    and (e.status in ('active', 'completed') or a.student_id is not null)
    and (not p_present_only or a.status = 'present')
  order by p.full_name, e.student_id
  limit 26 offset greatest(p_offset, 0);
$$;

revoke execute on function public.academy_save_live_session(uuid, uuid, text, integer, text, timestamptz, timestamptz, text, text, text, text),
  public.academy_save_attendance(uuid, uuid, text), public.academy_session_roster(uuid, boolean, integer)
  from public, anon, authenticated;
grant execute on function public.academy_save_live_session(uuid, uuid, text, integer, text, timestamptz, timestamptz, text, text, text, text),
  public.academy_save_attendance(uuid, uuid, text), public.academy_session_roster(uuid, boolean, integer) to authenticated;

commit;
