begin;

-- ============================================================
-- Cronograma académico: 4 semanas · 8 temas · 20 clases (lunes a viernes, 2 horas).
-- Es un módulo nuevo y aislado: no modifica cursos, matrículas, pagos ni lecciones existentes.
-- REVERSIÓN (solo borra lo de este módulo):
--   drop table public.academy_schedule_audit, public.academy_class_progress, public.academy_class_plan,
--     public.academy_schedule_topics, public.academy_schedule_weeks, public.academy_schedule_settings cascade;
--   drop function public.academy_schedule(uuid), public.academy_set_class_done(uuid, boolean),
--     public.academy_admin_save_class(uuid, jsonb), public.academy_admin_save_settings(uuid, date, time, text),
--     public.academy_admin_save_week(uuid, integer, text, text, jsonb), public.academy_admin_schedule_students(uuid),
--     academy_private.class_date(public.academy_class_plan), academy_private.class_unlock_at(public.academy_class_plan),
--     academy_private.class_unlocked(public.academy_class_plan), academy_private.class_executed(public.academy_class_plan);
-- ============================================================

-- Configuración de la edición del curso (fecha de inicio, hora de desbloqueo y zona horaria).
create table public.academy_schedule_settings (
  course_id uuid primary key references public.academy_courses (id) on delete cascade,
  start_date date check (start_date is null or extract(isodow from start_date) = 1),
  unlock_time time not null default '08:00',
  timezone text not null default 'America/Lima',
  updated_at timestamptz not null default now()
);

create table public.academy_schedule_weeks (
  course_id uuid not null references public.academy_courses (id) on delete cascade,
  week_no integer not null check (week_no between 1 and 12),
  title text not null check (btrim(title) <> ''),
  objective text not null default '',
  updated_at timestamptz not null default now(),
  primary key (course_id, week_no)
);

create table public.academy_schedule_topics (
  course_id uuid not null references public.academy_courses (id) on delete cascade,
  topic_no integer not null check (topic_no between 1 and 24),
  week_no integer not null,
  title text not null check (btrim(title) <> ''),
  updated_at timestamptz not null default now(),
  primary key (course_id, topic_no),
  foreign key (course_id, week_no) references public.academy_schedule_weeks (course_id, week_no) on delete cascade
);

create table public.academy_class_plan (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.academy_courses (id) on delete cascade,
  class_no integer not null check (class_no between 1 and 60),
  week_no integer not null,
  topic_no integer not null,
  weekday smallint not null check (weekday between 1 and 5),
  title text not null check (btrim(title) <> ''),
  description text not null default '',
  objectives text not null default '',
  content text not null default '',
  activity text not null default '',
  outcome text not null default '',
  duration_minutes integer not null default 120 check (duration_minutes between 15 and 600),
  meet_url text check (meet_url is null or meet_url ~ '^https://meet\.google\.com/[^[:space:]]+$'),
  recording_url text check (recording_url is null or recording_url ~ '^https://(drive|docs)\.google\.com/[^[:space:]]+$'),
  material_url text check (material_url is null or material_url ~ '^https://(drive|docs)\.google\.com/[^[:space:]]+$'),
  access text not null default 'auto' check (access in ('auto', 'enabled', 'blocked')),
  held text not null default 'auto' check (held in ('auto', 'held', 'pending')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (course_id, class_no),
  unique (id, course_id),
  foreign key (course_id, week_no) references public.academy_schedule_weeks (course_id, week_no) on delete cascade,
  foreign key (course_id, topic_no) references public.academy_schedule_topics (course_id, topic_no) on delete cascade
);

-- Progreso individual por matrícula (una fila por alumno y clase; no se duplica).
create table public.academy_class_progress (
  student_id uuid not null,
  class_id uuid not null,
  course_id uuid not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (student_id, class_id),
  foreign key (student_id, course_id) references public.academy_enrollments (student_id, course_id),
  foreign key (class_id, course_id) references public.academy_class_plan (id, course_id) on delete cascade
);

-- Historial de cambios de disponibilidad y de calendario.
create table public.academy_schedule_audit (
  id bigserial primary key,
  course_id uuid not null,
  actor uuid,
  action text not null,
  class_no integer,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Nadie accede a las tablas directamente desde la API: solo mediante las funciones de abajo.
do $$
declare t text;
begin
  foreach t in array array['academy_schedule_settings', 'academy_schedule_weeks', 'academy_schedule_topics',
                           'academy_class_plan', 'academy_class_progress', 'academy_schedule_audit'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;
revoke all on sequence public.academy_schedule_audit_id_seq from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Calendario: la clase 1 es el primer lunes; solo lunes a viernes; sin feriados automáticos.
-- ---------------------------------------------------------------------------
create function academy_private.class_date(p_class public.academy_class_plan)
returns date language sql stable security definer set search_path = '' as $$
  select s.start_date + ((p_class.week_no - 1) * 7 + (p_class.weekday - 1))
  from public.academy_schedule_settings s where s.course_id = p_class.course_id;
$$;

create function academy_private.class_unlock_at(p_class public.academy_class_plan)
returns timestamptz language sql stable security definer set search_path = '' as $$
  select ((s.start_date + ((p_class.week_no - 1) * 7 + (p_class.weekday - 1)) + s.unlock_time)::timestamp
          at time zone s.timezone)
  from public.academy_schedule_settings s where s.course_id = p_class.course_id and s.start_date is not null;
$$;

-- Disponible = habilitada a mano, o llegó su fecha y hora (salvo que la administración la bloquee).
create function academy_private.class_unlocked(p_class public.academy_class_plan)
returns boolean language sql stable security definer set search_path = '' as $$
  select case p_class.access
    when 'enabled' then true
    when 'blocked' then false
    else coalesce(now() >= academy_private.class_unlock_at(p_class), false)
  end;
$$;

-- Ejecutada = marcada por la administración, o ya pasó el día de la clase.
create function academy_private.class_executed(p_class public.academy_class_plan)
returns boolean language sql stable security definer set search_path = '' as $$
  select case p_class.held
    when 'held' then true
    when 'pending' then false
    else coalesce((select ((d + 1)::timestamp at time zone s.timezone) <= now()
                   from public.academy_schedule_settings s,
                        lateral (select academy_private.class_date(p_class) as d) x
                   where s.course_id = p_class.course_id and x.d is not null), false)
  end;
$$;

-- ---------------------------------------------------------------------------
-- Lectura (alumno matriculado o administrador). El contenido y los enlaces de una clase
-- bloqueada NO salen del servidor: no basta con cambiar la URL.
-- ---------------------------------------------------------------------------
create function public.academy_schedule(p_course uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  is_adm boolean := coalesce((select academy_private.is_admin()), false);
  cid uuid;
  st public.academy_schedule_settings;
  result jsonb;
begin
  if uid is null then raise insufficient_privilege; end if;

  if is_adm then
    cid := coalesce(p_course, (select c.course_id from public.academy_class_plan c order by c.created_at limit 1));
  else
    if not (select academy_private.authorized_student()) then raise insufficient_privilege; end if;
    select e.course_id into cid from public.academy_enrollments e
    where e.student_id = uid and e.status in ('active', 'completed')
      and (p_course is null or e.course_id = p_course)
      and exists (select 1 from public.academy_class_plan c where c.course_id = e.course_id)
    order by e.enrolled_at limit 1;
  end if;
  if cid is null then return null; end if;

  select * into st from public.academy_schedule_settings where course_id = cid;
  if not found then st.course_id := cid; st.unlock_time := '08:00'; st.timezone := 'America/Lima'; end if;

  with base as (
    select c.*, academy_private.class_date(c) as class_date, academy_private.class_unlock_at(c) as unlock_at,
           academy_private.class_unlocked(c) as unlocked, academy_private.class_executed(c) as executed
    from public.academy_class_plan c where c.course_id = cid
  ), phased as (
    select b.*, pr.completed_at,
           (select min(x.class_no) from base x where not x.executed) as next_no
    from base b
    left join public.academy_class_progress pr on pr.class_id = b.id and pr.student_id = uid
  ), shaped as (
    select p.week_no, p.class_no, (p.completed_at is not null) as done,
      jsonb_build_object(
        'id', p.id, 'class_no', p.class_no, 'week_no', p.week_no, 'topic_no', p.topic_no, 'weekday', p.weekday,
        'title', p.title, 'description', p.description, 'duration_minutes', p.duration_minutes,
        'date', p.class_date, 'unlock_at', p.unlock_at, 'unlocked', p.unlocked, 'executed', p.executed,
        'manual', p.access,
        'phase', case when p.executed then 'executed'
                      when p.class_no = p.next_no then
                        case when p.class_date = (now() at time zone st.timezone)::date then 'today' else 'next' end
                      else 'pending' end,
        'completed', p.completed_at is not null, 'completed_at', p.completed_at
      )
      || case when is_adm or p.unlocked then jsonb_build_object(
           'objectives', p.objectives, 'content', p.content, 'activity', p.activity, 'outcome', p.outcome,
           'meet_url', p.meet_url, 'recording_url', p.recording_url, 'material_url', p.material_url)
         else '{}'::jsonb end
      || case when is_adm then jsonb_build_object('held', p.held) else '{}'::jsonb end as js
    from phased p
  )
  select jsonb_build_object(
    'course', jsonb_build_object('id', co.id, 'name', co.name),
    'admin', is_adm,
    'settings', jsonb_build_object('start_date', st.start_date, 'unlock_time', to_char(st.unlock_time, 'HH24:MI'),
                                   'timezone', st.timezone),
    'total', (select count(*) from shaped),
    'completed', (select count(*) filter (where done) from shaped),
    'percent', (select case when count(*) = 0 then 0 else round(100.0 * count(*) filter (where done) / count(*)) end from shaped),
    'next', (select s.js from shaped s where (s.js->>'executed')::boolean = false order by s.class_no limit 1),
    'weeks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'week_no', w.week_no, 'title', w.title, 'objective', w.objective,
        'total', (select count(*) from shaped s where s.week_no = w.week_no),
        'completed', (select count(*) filter (where s.done) from shaped s where s.week_no = w.week_no),
        'topics', coalesce((select jsonb_agg(jsonb_build_object('topic_no', t.topic_no, 'title', t.title) order by t.topic_no)
                            from public.academy_schedule_topics t where t.course_id = cid and t.week_no = w.week_no), '[]'::jsonb),
        'classes', coalesce((select jsonb_agg(s.js order by s.class_no) from shaped s where s.week_no = w.week_no), '[]'::jsonb)
      ) order by w.week_no)
      from public.academy_schedule_weeks w where w.course_id = cid), '[]'::jsonb)
  ) into result
  from public.academy_courses co where co.id = cid;
  return result;
end;
$$;

-- El alumno marca (o desmarca) una clase como completada. Solo si ya está disponible.
create function public.academy_set_class_done(p_class uuid, p_done boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  cls public.academy_class_plan;
begin
  if uid is null or not (select academy_private.authorized_student()) then raise insufficient_privilege; end if;
  select * into cls from public.academy_class_plan where id = p_class;
  if not found then raise exception 'Class unavailable' using errcode = '23503'; end if;
  if not exists (select 1 from public.academy_enrollments e
                 where e.student_id = uid and e.course_id = cls.course_id and e.status in ('active', 'completed')) then
    raise insufficient_privilege;
  end if;
  if not academy_private.class_unlocked(cls) then raise insufficient_privilege; end if;

  insert into public.academy_class_progress (student_id, class_id, course_id, completed_at)
  values (uid, p_class, cls.course_id, case when p_done then now() end)
  on conflict (student_id, class_id) do update
    set completed_at = case when p_done then coalesce(public.academy_class_progress.completed_at, now()) end,
        updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Administración (solo administradores).
-- ---------------------------------------------------------------------------
create function public.academy_admin_save_class(p_id uuid, p_data jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  old public.academy_class_plan;
  cur public.academy_class_plan;
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  select * into old from public.academy_class_plan where id = p_id;
  if not found then raise exception 'Class unavailable' using errcode = '23503'; end if;

  update public.academy_class_plan c set
    title = coalesce(nullif(btrim(p_data->>'title'), ''), c.title),
    description = case when p_data ? 'description' then btrim(p_data->>'description') else c.description end,
    objectives = case when p_data ? 'objectives' then btrim(p_data->>'objectives') else c.objectives end,
    content = case when p_data ? 'content' then btrim(p_data->>'content') else c.content end,
    activity = case when p_data ? 'activity' then btrim(p_data->>'activity') else c.activity end,
    outcome = case when p_data ? 'outcome' then btrim(p_data->>'outcome') else c.outcome end,
    meet_url = case when p_data ? 'meet_url' then nullif(btrim(p_data->>'meet_url'), '') else c.meet_url end,
    recording_url = case when p_data ? 'recording_url' then nullif(btrim(p_data->>'recording_url'), '') else c.recording_url end,
    material_url = case when p_data ? 'material_url' then nullif(btrim(p_data->>'material_url'), '') else c.material_url end,
    access = coalesce(nullif(p_data->>'access', ''), c.access),
    held = coalesce(nullif(p_data->>'held', ''), c.held),
    updated_at = now()
  where c.id = p_id returning * into cur;

  if cur.access is distinct from old.access or cur.held is distinct from old.held then
    insert into public.academy_schedule_audit (course_id, actor, action, class_no, detail)
    values (cur.course_id, (select auth.uid()), 'class_state', cur.class_no,
            jsonb_build_object('access', jsonb_build_array(old.access, cur.access), 'held', jsonb_build_array(old.held, cur.held)));
  end if;
end;
$$;

create function public.academy_admin_save_settings(p_course uuid, p_start date, p_time time, p_timezone text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  if p_start is not null and extract(isodow from p_start) <> 1 then
    raise exception 'La fecha de inicio debe ser un lunes' using errcode = '23514';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'Zona horaria no válida' using errcode = '23514';
  end if;
  insert into public.academy_schedule_settings (course_id, start_date, unlock_time, timezone)
  values (p_course, p_start, p_time, p_timezone)
  on conflict (course_id) do update
    set start_date = excluded.start_date, unlock_time = excluded.unlock_time,
        timezone = excluded.timezone, updated_at = now();
  insert into public.academy_schedule_audit (course_id, actor, action, detail)
  values (p_course, (select auth.uid()), 'settings',
          jsonb_build_object('start_date', p_start, 'unlock_time', p_time, 'timezone', p_timezone));
end;
$$;

create function public.academy_admin_save_week(p_course uuid, p_week integer, p_title text, p_objective text, p_topics jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare t jsonb;
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  update public.academy_schedule_weeks
     set title = coalesce(nullif(btrim(p_title), ''), title), objective = coalesce(btrim(p_objective), objective), updated_at = now()
   where course_id = p_course and week_no = p_week;
  if not found then raise exception 'Week unavailable' using errcode = '23503'; end if;
  for t in select * from jsonb_array_elements(coalesce(p_topics, '[]'::jsonb)) loop
    update public.academy_schedule_topics
       set title = coalesce(nullif(btrim(t->>'title'), ''), title), updated_at = now()
     where course_id = p_course and week_no = p_week and topic_no = (t->>'topic_no')::integer;
  end loop;
end;
$$;

-- Avance de cada alumno matriculado.
create function public.academy_admin_schedule_students(p_course uuid)
returns table (student_id uuid, full_name text, email text, completed bigint, total bigint, percent integer, last_activity timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  return query
  select e.student_id, s.full_name, s.google_email,
         count(pr.class_id) filter (where pr.completed_at is not null),
         (select count(*) from public.academy_class_plan c where c.course_id = p_course),
         case when (select count(*) from public.academy_class_plan c where c.course_id = p_course) = 0 then 0
              else round(100.0 * count(pr.class_id) filter (where pr.completed_at is not null)
                         / (select count(*) from public.academy_class_plan c where c.course_id = p_course))::integer end,
         max(pr.updated_at)
  from public.academy_enrollments e
  join public.academy_students s on s.user_id = e.student_id
  left join public.academy_class_progress pr on pr.student_id = e.student_id and pr.course_id = e.course_id
  where e.course_id = p_course and e.status in ('active', 'completed')
  group by e.student_id, s.full_name, s.google_email
  order by s.full_name;
end;
$$;

-- Solo las cuatro funciones auxiliares nuevas (no se tocan los permisos de las que ya existían).
revoke execute on function academy_private.class_date(public.academy_class_plan), academy_private.class_unlock_at(public.academy_class_plan),
  academy_private.class_unlocked(public.academy_class_plan), academy_private.class_executed(public.academy_class_plan)
  from public, anon, authenticated;
revoke execute on function public.academy_schedule(uuid), public.academy_set_class_done(uuid, boolean),
  public.academy_admin_save_class(uuid, jsonb), public.academy_admin_save_settings(uuid, date, time, text),
  public.academy_admin_save_week(uuid, integer, text, text, jsonb), public.academy_admin_schedule_students(uuid)
  from public, anon;
grant execute on function public.academy_schedule(uuid), public.academy_set_class_done(uuid, boolean),
  public.academy_admin_save_class(uuid, jsonb), public.academy_admin_save_settings(uuid, date, time, text),
  public.academy_admin_save_week(uuid, integer, text, text, jsonb), public.academy_admin_schedule_students(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Carga inicial (idempotente): solo si hay un único curso publicado «Agente de IA…».
-- No toca cursos, matrículas ni pagos. Si se ejecuta de nuevo, no sobrescribe lo que edite la administración.
-- ---------------------------------------------------------------------------
do $$
declare cid uuid; found_count integer;
begin
  select count(*), min(id::text)::uuid into found_count, cid
  from public.academy_courses where status = 'published' and lower(name) like '%agente%';
  if found_count <> 1 then
    raise notice 'Cronograma: no se cargó (cursos coincidentes: %). Cárgalo luego con el id del curso.', found_count;
    return;
  end if;

  insert into public.academy_schedule_settings (course_id) values (cid) on conflict do nothing;
  -- Semanas
  insert into public.academy_schedule_weeks (course_id, week_no, title, objective) values (cid, 1, $d$Fundamentos y configuración inicial$d$, $d$Comprender cómo funcionan los agentes de IA y configurar uno sin necesidad de programar.$d$) on conflict do nothing;
  insert into public.academy_schedule_weeks (course_id, week_no, title, objective) values (cid, 2, $d$Personalización y conocimiento empresarial$d$, $d$Conseguir que el agente conozca el negocio y responda correctamente a los clientes.$d$) on conflict do nothing;
  insert into public.academy_schedule_weeks (course_id, week_no, title, objective) values (cid, 3, $d$Integraciones y automatización$d$, $d$Conectar el agente con canales de atención y procesos comerciales.$d$) on conflict do nothing;
  insert into public.academy_schedule_weeks (course_id, week_no, title, objective) values (cid, 4, $d$Administración, optimización y lanzamiento$d$, $d$Aprender a administrar el agente y demostrar su funcionamiento.$d$) on conflict do nothing;
  -- Temas
  insert into public.academy_schedule_topics (course_id, topic_no, week_no, title) values (cid, 1, 1, $d$Fundamentos de agentes de IA$d$) on conflict do nothing;
  insert into public.academy_schedule_topics (course_id, topic_no, week_no, title) values (cid, 2, 1, $d$Configuración inicial del agente$d$) on conflict do nothing;
  insert into public.academy_schedule_topics (course_id, topic_no, week_no, title) values (cid, 3, 2, $d$Conocimiento empresarial$d$) on conflict do nothing;
  insert into public.academy_schedule_topics (course_id, topic_no, week_no, title) values (cid, 4, 2, $d$Conversaciones comerciales$d$) on conflict do nothing;
  insert into public.academy_schedule_topics (course_id, topic_no, week_no, title) values (cid, 5, 3, $d$Canales digitales$d$) on conflict do nothing;
  insert into public.academy_schedule_topics (course_id, topic_no, week_no, title) values (cid, 6, 3, $d$Automatización comercial$d$) on conflict do nothing;
  insert into public.academy_schedule_topics (course_id, topic_no, week_no, title) values (cid, 7, 4, $d$Administración y métricas$d$) on conflict do nothing;
  insert into public.academy_schedule_topics (course_id, topic_no, week_no, title) values (cid, 8, 4, $d$Proyecto final$d$) on conflict do nothing;
  -- Clases
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 1, 1, 1, 1, $d$Introducción a los agentes de IA$d$, $d$Primer contacto con la inteligencia artificial aplicada al negocio: qué es un agente y en qué se diferencia de un chatbot tradicional.$d$, $d$Entender qué es la inteligencia artificial y qué es un agente de IA.
Distinguir un chatbot tradicional de un agente inteligente.
Identificar oportunidades de uso en ventas y atención al cliente.$d$, $d$Qué es la inteligencia artificial.
Qué es un agente IA.
Diferencia entre chatbot tradicional y agente inteligente.
Aplicaciones en ventas y atención al cliente.
Ejemplos empresariales.
Identificación de necesidades del negocio.$d$, $d$Definir el objetivo del agente que cada estudiante quiere crear.$d$, $d$Objetivo y caso de uso empresarial definidos.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 2, 1, 1, 2, $d$Arquitectura y herramientas$d$, $d$Cómo funcionan por dentro los modelos de IA y qué herramientas se usan para configurar agentes, sin entrar en programación.$d$, $d$Comprender el funcionamiento general de los modelos de IA, las APIs y los tokens.
Conocer las herramientas, canales y paneles de administración disponibles.
Estimar los costos de utilizar modelos de IA.$d$, $d$Funcionamiento general de los modelos de IA.
Conceptos básicos de API y tokens.
Herramientas para configurar agentes.
Canales de comunicación.
Paneles de administración.
Costos de utilización de modelos.$d$, $d$Seleccionar el caso de uso y reconocer las herramientas que se utilizarán.$d$, $d$Herramientas y necesidades identificadas.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 3, 1, 2, 3, $d$Creación del primer agente$d$, $d$Se entra al entorno de configuración y se crea el primer agente funcional con su identidad básica.$d$, $d$Acceder al entorno de configuración de agentes.
Crear un agente con nombre, idioma y objetivo empresarial.
Mantener una primera conversación de prueba.$d$, $d$Acceso al entorno de configuración.
Creación del agente.
Nombre e identidad.
Idioma.
Objetivo empresarial.
Configuración inicial.
Primera conversación de prueba.$d$, $d$Crear un agente funcional básico.$d$, $d$Primer agente creado.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 4, 1, 2, 4, $d$Personalidad e instrucciones$d$, $d$Se define cómo habla y cómo se comporta el agente: tono, reglas comerciales y cuándo pasar con una persona.$d$, $d$Definir la personalidad y el tono de comunicación del agente.
Redactar las instrucciones principales y sus límites de respuesta.
Establecer cuándo derivar a atención humana.$d$, $d$Personalidad del agente.
Tono de comunicación.
Saludos.
Instrucciones principales.
Límites de respuesta.
Reglas comerciales.
Derivación a atención humana.$d$, $d$Personalizar el comportamiento del agente.$d$, $d$Agente con identidad empresarial.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 5, 1, 2, 5, $d$Pruebas y correcciones$d$, $d$Se prueba el agente con distintos escenarios de clientes y se corrigen las respuestas que no son adecuadas.$d$, $d$Simular conversaciones reales con clientes.
Detectar respuestas incorrectas y corregir las instrucciones.
Aplicar mejoras iniciales al comportamiento.$d$, $d$Simulación de conversaciones.
Detección de respuestas incorrectas.
Corrección de instrucciones.
Evaluación del comportamiento.
Mejoras iniciales.$d$, $d$Probar diferentes escenarios de clientes.$d$, $d$Agente básico configurado y validado.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 6, 2, 3, 1, $d$Información de la empresa$d$, $d$Se reúne y ordena la información que el agente necesita saber sobre el negocio.$d$, $d$Reunir la información institucional y comercial del negocio.
Organizarla en una ficha de conocimiento empresarial.$d$, $d$Nombre comercial.
Productos y servicios.
Horarios de atención.
Ubicación.
Políticas comerciales.
Preguntas frecuentes.
Información institucional.$d$, $d$Crear la ficha de conocimiento empresarial.$d$, $d$Información empresarial organizada.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 7, 2, 3, 2, $d$Base de conocimientos$d$, $d$Se carga y organiza la información en la base de conocimientos del agente y se verifica que responda con ella.$d$, $d$Organizar documentos, catálogos y listas de precios para el agente.
Cargar y actualizar la información de la base de conocimientos.
Verificar que las respuestas del agente sean correctas.$d$, $d$Organización de documentos.
Catálogos.
Listas de precios.
Preguntas frecuentes.
Actualización de información.
Verificación de respuestas.$d$, $d$Cargar y organizar información para el agente.$d$, $d$Base de conocimientos configurada.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 8, 2, 4, 3, $d$Flujos de atención$d$, $d$Se diseña el recorrido de la conversación: desde el saludo hasta la derivación a un asesor.$d$, $d$Diseñar el flujo de atención según el tipo de cliente.
Definir preguntas de calificación y cuándo derivar a un asesor.$d$, $d$Saludos iniciales.
Identificación de necesidades.
Preguntas de calificación.
Atención según tipo de cliente.
Manejo de consultas frecuentes.
Derivación a un asesor.$d$, $d$Diseñar un flujo de atención empresarial.$d$, $d$Flujo de atención configurado.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 9, 2, 4, 4, $d$Agente especializado en ventas$d$, $d$El agente aprende a presentar productos, manejar objeciones y llevar al cliente hacia una acción concreta.$d$, $d$Configurar la presentación de productos y las recomendaciones comerciales.
Preparar respuestas a objeciones y la captura de datos del cliente.
Incluir llamados a la acción y solicitud de reuniones.$d$, $d$Presentación de productos.
Recomendaciones comerciales.
Manejo de objeciones.
Captura de datos.
Llamados a la acción.
Solicitud de reuniones.$d$, $d$Configurar un proceso comercial.$d$, $d$Agente preparado para atender oportunidades de venta.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 10, 2, 4, 5, $d$Simulación comercial$d$, $d$Se ejecutan simulaciones de ventas con distintos tipos de cliente y se ajustan las respuestas.$d$, $d$Probar el agente con clientes interesados, indecisos y casos complejos.
Corregir las respuestas según los resultados.$d$, $d$Clientes interesados.
Clientes indecisos.
Preguntas sobre precios.
Consultas fuera de horario.
Solicitudes complejas.
Corrección de respuestas.$d$, $d$Ejecutar simulaciones comerciales.$d$, $d$Agente empresarial personalizado.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 11, 3, 5, 1, $d$Configuración de canales$d$, $d$Se identifican los canales donde atenderá el agente y los requisitos para conectarlos.$d$, $d$Identificar los canales de atención del negocio.
Conocer los requisitos, permisos y credenciales de cada canal.$d$, $d$Canales de atención.
WhatsApp Business Platform.
Requisitos de Meta.
Canales web.
Permisos y credenciales.
Preparación de integraciones.$d$, $d$Identificar y preparar los canales del negocio.$d$, $d$Canales y requisitos definidos.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 12, 3, 5, 2, $d$Integración con WhatsApp$d$, $d$Se prepara o conecta WhatsApp al agente. La conexión activa depende de las verificaciones y aprobaciones de Meta, que no controla la academia.$d$, $d$Conocer el proceso de configuración en Meta y la vinculación del canal.
Probar mensajes y reconocer los errores frecuentes.$d$, $d$Configuración de Meta.
Números telefónicos.
Permisos.
Vinculación del canal.
Pruebas de mensajes.
Errores frecuentes.$d$, $d$Preparar o conectar WhatsApp al agente.$d$, $d$Integración configurada o preparada, según los accesos y aprobaciones disponibles.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 13, 3, 6, 3, $d$Gestión de clientes y CRM$d$, $d$Se organiza el seguimiento de los clientes interesados: contactos, etapas y oportunidades.$d$, $d$Entender qué es un lead y cómo registrarlo.
Clasificar interesados y definir las etapas comerciales.$d$, $d$Qué es un lead.
Registro de contactos.
Clasificación de interesados.
Etapas comerciales.
Seguimiento de oportunidades.
Organización de información.$d$, $d$Configurar un flujo de gestión de clientes.$d$, $d$Proceso comercial estructurado.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 14, 3, 6, 4, $d$Automatización de ventas$d$, $d$Se automatizan avisos, seguimientos y derivaciones para que ninguna oportunidad se pierda.$d$, $d$Configurar notificaciones, seguimiento y derivación a vendedores.
Definir reglas y condiciones de automatización.$d$, $d$Notificaciones.
Seguimiento comercial.
Solicitudes de reunión.
Derivación a vendedores.
Automatización de tareas.
Reglas y condiciones.$d$, $d$Configurar una automatización comercial de prueba.$d$, $d$Flujo automatizado funcional.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 15, 3, 6, 5, $d$Pruebas de integración$d$, $d$Se prueba de punta a punta una atención comercial: conversación, captura del cliente y automatizaciones.$d$, $d$Verificar que la conversación, el registro y las automatizaciones funcionen juntos.
Identificar errores y corregirlos.$d$, $d$Pruebas de conversaciones.
Captura de clientes potenciales.
Registro de información.
Verificación de automatizaciones.
Identificación de errores.
Correcciones.$d$, $d$Simular una atención comercial completa.$d$, $d$Flujo integral probado.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 16, 4, 7, 1, $d$Administración del agente$d$, $d$Se aprende a operar el agente día a día: conversaciones, información, instrucciones y accesos.$d$, $d$Gestionar conversaciones y actualizar la información del agente.
Modificar instrucciones y controlar usuarios y accesos.$d$, $d$Panel administrativo.
Gestión de conversaciones.
Actualización de información.
Modificación de instrucciones.
Gestión de usuarios.
Control de accesos.$d$, $d$Administrar y actualizar el agente.$d$, $d$Configuración administrativa revisada.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 17, 4, 7, 2, $d$Costos, seguridad y métricas$d$, $d$Se revisa cuánto cuesta operar el agente, qué tan bien responde y cómo proteger los datos.$d$, $d$Interpretar el consumo de tokens, los costos de API y los indicadores comerciales.
Aplicar medidas de protección de datos y seguridad.$d$, $d$Consumo de tokens.
Costos de API.
Indicadores comerciales.
Calidad de respuestas.
Protección de datos.
Seguridad.
Optimización del consumo.$d$, $d$Revisar indicadores y definir controles.$d$, $d$Plan de administración y optimización.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 18, 4, 8, 3, $d$Optimización empresarial$d$, $d$Se mejora el agente con base en los resultados de las pruebas y se deja listo para operar.$d$, $d$Detectar errores y mejorar instrucciones, conversaciones y flujos.
Realizar las pruebas finales y la preparación operativa.$d$, $d$Identificación de errores.
Mejoras de instrucciones.
Ajuste de conversaciones.
Optimización de flujos.
Pruebas finales.
Preparación operativa.$d$, $d$Mejorar el agente según resultados.$d$, $d$Agente optimizado.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 19, 4, 8, 4, $d$Preparación del proyecto final$d$, $d$Se verifican las configuraciones, se documenta el agente y se prepara la demostración.$d$, $d$Realizar pruebas integrales y verificar todas las configuraciones.
Documentar el agente y preparar la demostración final.$d$, $d$Pruebas integrales.
Verificación de configuraciones.
Documentación.
Preparación de demostración.
Revisión de resultados.$d$, $d$Preparar la presentación final.$d$, $d$Proyecto listo para evaluación.$d$) on conflict do nothing;
  insert into public.academy_class_plan (course_id, class_no, week_no, topic_no, weekday, title, description, objectives, content, activity, outcome) values (cid, 20, 4, 8, 5, $d$Presentación y evaluación final$d$, $d$Cada estudiante presenta su agente empresarial funcionando y explica cómo lo configuró.$d$, $d$Presentar y demostrar el agente en funcionamiento.
Explicar su configuración y recibir recomendaciones finales.$d$, $d$Presentación del agente.
Demostración práctica.
Explicación de su configuración.
Evaluación de funcionamiento.
Preguntas y respuestas.
Recomendaciones finales.$d$, $d$Demostrar el agente empresarial.$d$, $d$Proyecto final presentado y evaluado.$d$) on conflict do nothing;
end $$;

commit;
