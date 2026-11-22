begin;

alter table public.academy_lessons
  add column objective text,
  add column instructions text,
  add column deliverable text,
  add column validation_criteria text;

alter table public.academy_materials add column drive_file_id text generated always as (
  coalesce(
    substring(drive_url from '/d/([A-Za-z0-9_-]+)(?:[/?#]|$)'),
    substring(drive_url from '[?&]id=([A-Za-z0-9_-]+)(?:[&#]|$)')
  )
) stored;
alter table public.academy_materials add constraint academy_materials_drive_file_required
  check (drive_file_id is not null) not valid;

create table public.academy_program_page (
  singleton boolean primary key default true check (singleton),
  title text not null check (btrim(title) <> ''),
  introduction text not null check (btrim(introduction) <> ''),
  description text not null check (btrim(description) <> ''),
  benefits text[] not null default '{}',
  duration_text text not null check (btrim(duration_text) <> ''),
  launch_price numeric(12,2) check (launch_price >= 0),
  currency text check (currency ~ '^[A-Z]{3}$'),
  registration_text text not null check (btrim(registration_text) <> ''),
  registration_url text not null check (registration_url ~ '^https://[^[:space:]]+$'),
  welcome_drive_file_id text check (welcome_drive_file_id ~ '^[A-Za-z0-9_-]+$'),
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((launch_price is null) = (currency is null))
);

alter table public.academy_program_page enable row level security;
revoke all on public.academy_program_page from public, anon, authenticated;
grant select on public.academy_program_page to anon, authenticated;
grant insert, update on public.academy_program_page to authenticated;
create policy public_program on public.academy_program_page for select to anon, authenticated using (published);
create policy admin_program on public.academy_program_page for all to authenticated
  using ((select academy_private.is_admin())) with check ((select academy_private.is_admin()));
create trigger touch_updated_at before update on public.academy_program_page
  for each row execute function academy_private.touch_updated_at();

grant insert (student_id, subject, body) on public.academy_inquiries to authenticated;
create policy student_create_inquiry on public.academy_inquiries for insert to authenticated
  with check (student_id = (select auth.uid()) and (select academy_private.is_active_student())
    and course_id is null and status = 'open'
    and char_length(btrim(subject)) <= 160 and char_length(btrim(body)) <= 5000);

create function public.academy_campus_home()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'name', (select full_name from public.academy_students where user_id = (select auth.uid())),
    'courses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'description', c.description, 'image_path', c.image_path,
        'duration_minutes', c.duration_minutes, 'progress', e.overall_progress
      ) order by c.name, c.id)
      from public.academy_enrollment_overview e
      join public.academy_courses c on c.id = e.course_id and c.status = 'published'
      where e.student_id = (select auth.uid()) and e.status = 'active'
    ), '[]'::jsonb),
    'next_session', (
      select jsonb_build_object('title', s.title, 'course', c.name, 'starts_at', s.starts_at,
        'ends_at', s.ends_at, 'meet_url', s.meet_url)
      from public.academy_live_sessions s join public.academy_courses c on c.id = s.course_id
      join public.academy_enrollments e on e.course_id = c.id and e.student_id = (select auth.uid())
      where s.status = 'scheduled' and s.ends_at > now() and e.status = 'active' and c.status = 'published'
      order by s.starts_at, s.id limit 1
    ),
    'pending', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.day_number, p.course, p.module_position, p.lesson_position, p.id)
      from (
        select l.id, l.course_id, l.title, l.day_number, c.name as course,
               m.position as module_position, l.position as lesson_position
        from public.academy_lessons l
        join public.academy_modules m on m.id = l.module_id and m.status = 'published'
        join public.academy_courses c on c.id = l.course_id and c.status = 'published'
        join public.academy_enrollments e on e.course_id = c.id and e.student_id = (select auth.uid()) and e.status = 'active'
        left join public.academy_progress p on p.lesson_id = l.id and p.student_id = (select auth.uid())
        where l.status = 'published' and p.completed is not true
        order by l.day_number, c.name, m.position, l.position, l.id limit 8
      ) p
    ), '[]'::jsonb)
  );
$$;

create function public.academy_course_content(course uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'id', c.id, 'name', c.name, 'description', c.description,
    'image_path', c.image_path, 'duration_minutes', c.duration_minutes,
    'modules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'title', m.title,
        'lessons', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', l.id, 'title', l.title, 'day_number', l.day_number, 'description', l.description,
            'objective', l.objective, 'instructions', l.instructions, 'deliverable', l.deliverable,
            'validation_criteria', l.validation_criteria, 'prompt', l.prompt,
            'completed', coalesce(p.completed, false),
            'materials', coalesce((
              select jsonb_agg(jsonb_build_object(
                'id', a.id, 'title', a.title, 'kind', a.kind, 'drive_url', a.drive_url, 'drive_file_id', a.drive_file_id
              ) order by a.position)
              from public.academy_materials a where a.lesson_id = l.id
            ), '[]'::jsonb)
          ) order by l.position)
          from public.academy_lessons l
          left join public.academy_progress p on p.lesson_id = l.id and p.student_id = (select auth.uid())
          where l.module_id = m.id and l.status = 'published'
        ), '[]'::jsonb)
      ) order by m.position)
      from public.academy_modules m where m.course_id = c.id and m.status = 'published'
    ), '[]'::jsonb)
  )
  from public.academy_courses c where c.id = course and c.status = 'published';
$$;

create function public.academy_complete_lesson(target_lesson uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  student uuid := auth.uid();
  course uuid;
begin
  if not academy_private.is_active_student() then return false; end if;
  select l.course_id into course
  from public.academy_lessons l
  join public.academy_modules m on m.id = l.module_id and m.status = 'published'
  join public.academy_courses c on c.id = l.course_id and c.status = 'published'
  join public.academy_enrollments e on e.course_id = c.id and e.student_id = student and e.status = 'active'
  where l.id = target_lesson and l.status = 'published';
  if not found then return false; end if;
  insert into public.academy_progress as p (student_id, lesson_id, course_id, completed, completed_at)
  values (student, target_lesson, course, true, statement_timestamp())
  on conflict (student_id, lesson_id) do update
    set completed = true, completed_at = excluded.completed_at where not p.completed;
  return true;
end;
$$;

revoke execute on function public.academy_campus_home(), public.academy_course_content(uuid),
  public.academy_complete_lesson(uuid) from public, anon, authenticated;
grant execute on function public.academy_campus_home(), public.academy_course_content(uuid),
  public.academy_complete_lesson(uuid) to authenticated;
commit;
