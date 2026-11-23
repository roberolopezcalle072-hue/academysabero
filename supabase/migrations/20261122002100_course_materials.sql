begin;

-- ============================================================
-- Materiales del curso: manual de Meta/Facebook, Codex y un PDF de prompts por clase.
-- Los archivos viven en tu Google Drive; aquí solo se guardan los enlaces. Solo los ven alumnos matriculados.
-- Un material de una clase (prompts) se habilita cuando esa clase se abre.
-- REVERSIÓN: drop table public.academy_course_materials cascade; drop function public.academy_course_materials(uuid),
--   public.academy_admin_save_material(uuid, uuid, text, text, text, integer, integer), public.academy_admin_delete_material(uuid);
-- ============================================================
create table public.academy_course_materials (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.academy_courses (id) on delete cascade,
  category text not null check (category in ('meta', 'codex', 'prompts')),
  title text not null check (btrim(title) <> ''),
  url text not null check (url ~ '^https://(drive|docs)\.google\.com/[^[:space:]]+$'),
  class_no integer check (class_no between 1 and 60),
  position integer not null default 1 check (position > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Los prompts siempre pertenecen a una clase; Meta y Codex son generales.
  check ((category = 'prompts') = (class_no is not null))
);
-- Un solo PDF de prompts por clase.
create unique index academy_course_materials_one_prompt_per_class
  on public.academy_course_materials (course_id, class_no) where category = 'prompts';
create index academy_course_materials_course_idx on public.academy_course_materials (course_id, category, position);

alter table public.academy_course_materials enable row level security;
revoke all on public.academy_course_materials from public, anon, authenticated;

-- Lista para el alumno matriculado o el administrador. Los prompts de una clase que todavía no se abre salen sin enlace.
create function public.academy_course_materials(p_course uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  is_adm boolean := coalesce((select academy_private.is_admin()), false);
  cid uuid;
  result jsonb;
begin
  if uid is null then raise insufficient_privilege; end if;
  if is_adm then
    cid := coalesce(p_course, (select c.course_id from public.academy_class_plan c order by c.created_at limit 1));
  else
    if not (select academy_private.authorized_student()) then raise insufficient_privilege; end if;
    select e.course_id into cid from public.academy_enrollments e
    where e.student_id = uid and e.status in ('active', 'completed') and (p_course is null or e.course_id = p_course)
    order by e.enrolled_at limit 1;
  end if;
  if cid is null then return null; end if;

  select jsonb_build_object(
    'course', jsonb_build_object('id', co.id, 'name', co.name),
    'admin', is_adm,
    'classes', case when is_adm then coalesce((
      select jsonb_agg(jsonb_build_object('class_no', p.class_no, 'title', p.title, 'date', academy_private.class_date(p)) order by p.class_no)
      from public.academy_class_plan p where p.course_id = cid), '[]'::jsonb) else null end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'category', m.category, 'title', m.title, 'class_no', m.class_no, 'position', m.position,
        'class_title', p.title, 'date', academy_private.class_date(p),
        'locked', (m.class_no is not null and not is_adm and not academy_private.class_unlocked(p)),
        'url', case when m.class_no is not null and not is_adm and not academy_private.class_unlocked(p) then null else m.url end
      ) order by case m.category when 'meta' then 1 when 'codex' then 2 else 3 end, coalesce(m.class_no, 0), m.position, m.created_at)
      from public.academy_course_materials m
      left join public.academy_class_plan p on p.course_id = m.course_id and p.class_no = m.class_no
      where m.course_id = cid), '[]'::jsonb)
  ) into result
  from public.academy_courses co where co.id = cid;
  return result;
end;
$$;

-- Crear o editar un material. Los prompts reemplazan al PDF anterior de esa clase.
create function public.academy_admin_save_material(
  p_id uuid, p_course uuid, p_category text, p_title text, p_url text, p_class_no integer, p_position integer
) returns uuid language plpgsql security definer set search_path = '' as $$
declare saved uuid;
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  if p_category = 'prompts' then
    insert into public.academy_course_materials (course_id, category, title, url, class_no, position)
    values (p_course, 'prompts', btrim(p_title), btrim(p_url), p_class_no, 1)
    on conflict (course_id, class_no) where category = 'prompts'
    do update set title = excluded.title, url = excluded.url, updated_at = now()
    returning id into saved;
  elsif p_id is null then
    insert into public.academy_course_materials (course_id, category, title, url, class_no, position)
    values (p_course, p_category, btrim(p_title), btrim(p_url), null, coalesce(p_position, 1))
    returning id into saved;
  else
    update public.academy_course_materials
       set title = btrim(p_title), url = btrim(p_url), position = coalesce(p_position, position), updated_at = now()
     where id = p_id and course_id = p_course and category = p_category
    returning id into saved;
    if saved is null then raise exception 'Material unavailable' using errcode = '23503'; end if;
  end if;
  return saved;
end;
$$;

create function public.academy_admin_delete_material(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  delete from public.academy_course_materials where id = p_id;
end;
$$;

revoke execute on function public.academy_course_materials(uuid), public.academy_admin_save_material(uuid, uuid, text, text, text, integer, integer),
  public.academy_admin_delete_material(uuid) from public, anon;
grant execute on function public.academy_course_materials(uuid), public.academy_admin_save_material(uuid, uuid, text, text, text, integer, integer),
  public.academy_admin_delete_material(uuid) to authenticated;

commit;
