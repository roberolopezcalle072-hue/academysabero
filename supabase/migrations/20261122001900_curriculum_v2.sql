begin;

-- ============================================================
-- Malla curricular v2: «Crea tu propio Mini CRM con Agente de Inteligencia Artificial y WhatsApp».
-- Solo cambia el contenido del cronograma y su presentación pública; no toca pagos, matrículas ni cupos.
-- La malla (módulos y clases) es pública; los enlaces de reunión, grabaciones y materiales siguen siendo solo para matriculados.
-- ============================================================

alter table public.academy_schedule_weeks add column result text not null default '';
alter table public.academy_schedule_settings add column program_title text, add column tagline text;

-- ---------------------------------------------------------------------------
-- Vista pública: ahora incluye la malla (sin enlaces ni materiales).
-- ---------------------------------------------------------------------------
create or replace function public.academy_public_schedule(p_course uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  cid uuid := p_course;
  result jsonb;
begin
  if cid is null then
    select c.id into cid from public.academy_courses c
    where c.status = 'published' and exists (select 1 from public.academy_class_plan k where k.course_id = c.id)
    order by c.created_at limit 1;
  end if;
  if cid is null then return null; end if;

  with k as (
    select p.*, academy_private.class_date(p) as day from public.academy_class_plan p where p.course_id = cid
  )
  select jsonb_build_object(
    'course', jsonb_build_object('id', c.id, 'name', c.name),
    'program', jsonb_build_object(
      'title', coalesce((select program_title from public.academy_schedule_settings where course_id = cid), c.name),
      'tagline', coalesce((select tagline from public.academy_schedule_settings where course_id = cid), '')),
    'start_date', (select start_date from public.academy_schedule_settings where course_id = cid),
    'end_date', (select max(day) from k),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('class_no', class_no, 'date', day) order by class_no) from k), '[]'::jsonb),
    'holidays', coalesce((select jsonb_agg(jsonb_build_object('day', h.day, 'label', h.label) order by h.day)
                          from public.academy_schedule_holidays h where h.course_id = cid), '[]'::jsonb),
    'weeks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'week_no', w.week_no, 'title', w.title, 'objective', w.objective, 'result', w.result,
        'start', (select min(day) from k where k.week_no = w.week_no), 'end', (select max(day) from k where k.week_no = w.week_no),
        'topics', coalesce((select jsonb_agg(jsonb_build_object('topic_no', t.topic_no, 'title', t.title) order by t.topic_no)
                            from public.academy_schedule_topics t where t.course_id = cid and t.week_no = w.week_no), '[]'::jsonb),
        'classes', coalesce((select jsonb_agg(jsonb_build_object(
            'class_no', k.class_no, 'topic_no', k.topic_no, 'date', k.day, 'title', k.title, 'description', k.description,
            'objectives', k.objectives, 'content', k.content, 'activity', k.activity, 'outcome', k.outcome,
            'duration_minutes', k.duration_minutes) order by k.class_no)
          from k where k.week_no = w.week_no), '[]'::jsonb)
      ) order by w.week_no)
      from public.academy_schedule_weeks w where w.course_id = cid), '[]'::jsonb),
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object(
        'slot_no', s.slot_no, 'label', s.label, 'starts', to_char(s.starts, 'HH24:MI'), 'ends', to_char(s.ends, 'HH24:MI'),
        'capacity', s.capacity, 'remaining', greatest(s.capacity - academy_private.slot_taken(cid, s.slot_no), 0),
        'full', academy_private.slot_taken(cid, s.slot_no) >= s.capacity
      ) order by s.starts)
      from public.academy_course_slots s
      where s.course_id = cid and academy_private.slot_open(cid, s.slot_no)), '[]'::jsonb)
  ) into result
  from public.academy_courses c where c.id = cid;
  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Cronograma del alumno / administración: agrega el resultado del módulo y el título del programa.
-- ---------------------------------------------------------------------------
create or replace function public.academy_schedule(p_course uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  is_adm boolean := coalesce((select academy_private.is_admin()), false);
  cid uuid;
  st public.academy_schedule_settings;
  my_slot public.academy_course_slots;
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

  if not is_adm then
    select s.* into my_slot from public.academy_course_slots s
    join public.academy_enrollments e on e.course_id = s.course_id and e.slot_no = s.slot_no
    where e.student_id = uid and e.course_id = cid;
  end if;

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
    select p.week_no, p.class_no, (p.completed_at is not null) as done, p.class_date,
      jsonb_build_object(
        'id', p.id, 'class_no', p.class_no, 'week_no', p.week_no, 'topic_no', p.topic_no,
        'weekday', coalesce(extract(isodow from p.class_date)::int, p.weekday),
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
           'meet_url', case when is_adm then p.meet_url else coalesce(p.meet_url, my_slot.meet_url) end,
           'recording_url', p.recording_url, 'material_url', p.material_url)
         else '{}'::jsonb end
      || case when is_adm then jsonb_build_object('held', p.held) else '{}'::jsonb end as js
    from phased p
  )
  select jsonb_build_object(
    'course', jsonb_build_object('id', co.id, 'name', co.name),
    'program', jsonb_build_object('title', coalesce(st.program_title, co.name), 'tagline', coalesce(st.tagline, '')),
    'admin', is_adm,
    'settings', jsonb_build_object('start_date', st.start_date, 'unlock_time', to_char(st.unlock_time, 'HH24:MI'),
                                   'timezone', st.timezone, 'program_title', st.program_title, 'tagline', st.tagline),
    'holidays', coalesce((select jsonb_agg(jsonb_build_object('day', h.day, 'label', h.label) order by h.day)
                          from public.academy_schedule_holidays h where h.course_id = cid), '[]'::jsonb),
    'slot', case when my_slot.slot_no is null then null else jsonb_build_object(
      'slot_no', my_slot.slot_no, 'label', my_slot.label,
      'starts', to_char(my_slot.starts, 'HH24:MI'), 'ends', to_char(my_slot.ends, 'HH24:MI'), 'meet_url', my_slot.meet_url) end,
    'slots', case when is_adm then coalesce((
      select jsonb_agg(jsonb_build_object(
        'slot_no', s.slot_no, 'label', s.label, 'starts', to_char(s.starts, 'HH24:MI'), 'ends', to_char(s.ends, 'HH24:MI'),
        'meet_url', s.meet_url, 'capacity', s.capacity, 'tier', s.tier, 'active', s.active,
        'taken', academy_private.slot_taken(cid, s.slot_no)) order by s.starts)
      from public.academy_course_slots s where s.course_id = cid), '[]'::jsonb) else null end,
    'total', (select count(*) from shaped),
    'completed', (select count(*) filter (where done) from shaped),
    'percent', (select case when count(*) = 0 then 0 else round(100.0 * count(*) filter (where done) / count(*)) end from shaped),
    'next', (select s.js from shaped s where (s.js->>'executed')::boolean = false order by s.class_no limit 1),
    'weeks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'week_no', w.week_no, 'title', w.title, 'objective', w.objective, 'result', w.result,
        'start', (select min(s.class_date) from shaped s where s.week_no = w.week_no),
        'end', (select max(s.class_date) from shaped s where s.week_no = w.week_no),
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

-- ---------------------------------------------------------------------------
-- Administración: el módulo guarda también su resultado; el programa, su título y frase comercial.
-- ---------------------------------------------------------------------------
drop function public.academy_admin_save_week(uuid, integer, text, text, jsonb);
create function public.academy_admin_save_week(p_course uuid, p_week integer, p_title text, p_objective text, p_topics jsonb, p_result text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare t jsonb;
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  update public.academy_schedule_weeks
     set title = coalesce(nullif(btrim(p_title), ''), title), objective = coalesce(btrim(p_objective), objective),
         result = coalesce(btrim(p_result), result), updated_at = now()
   where course_id = p_course and week_no = p_week;
  if not found then raise exception 'Week unavailable' using errcode = '23503'; end if;
  for t in select * from jsonb_array_elements(coalesce(p_topics, '[]'::jsonb)) loop
    update public.academy_schedule_topics
       set title = coalesce(nullif(btrim(t->>'title'), ''), title), updated_at = now()
     where course_id = p_course and week_no = p_week and topic_no = (t->>'topic_no')::integer;
  end loop;
end;
$$;
revoke execute on function public.academy_admin_save_week(uuid, integer, text, text, jsonb, text) from public, anon;
grant execute on function public.academy_admin_save_week(uuid, integer, text, text, jsonb, text) to authenticated;

drop function public.academy_admin_save_settings(uuid, date, time, text);
create function public.academy_admin_save_settings(
  p_course uuid, p_start date, p_time time, p_timezone text, p_program_title text default null, p_tagline text default null
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'Zona horaria no válida' using errcode = '23514';
  end if;
  insert into public.academy_schedule_settings (course_id, start_date, unlock_time, timezone, program_title, tagline)
  values (p_course, p_start, p_time, p_timezone, nullif(btrim(coalesce(p_program_title, '')), ''), nullif(btrim(coalesce(p_tagline, '')), ''))
  on conflict (course_id) do update
    set start_date = excluded.start_date, unlock_time = excluded.unlock_time, timezone = excluded.timezone,
        program_title = coalesce(excluded.program_title, public.academy_schedule_settings.program_title),
        tagline = coalesce(excluded.tagline, public.academy_schedule_settings.tagline), updated_at = now();
  insert into public.academy_schedule_audit (course_id, actor, action, detail)
  values (p_course, (select auth.uid()), 'settings',
          jsonb_build_object('start_date', p_start, 'unlock_time', p_time, 'timezone', p_timezone));
end;
$$;
revoke execute on function public.academy_admin_save_settings(uuid, date, time, text, text, text) from public, anon;
grant execute on function public.academy_admin_save_settings(uuid, date, time, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Carga de la malla: reemplaza el contenido de ejemplo anterior (se ejecuta una sola vez al aplicar esta migración).
-- ---------------------------------------------------------------------------
do $$
declare cid uuid; n integer;
begin
  select count(*), min(id::text)::uuid into n, cid
  from public.academy_courses where status = 'published' and lower(name) like '%agente%';
  if n <> 1 then
    raise notice 'Malla: no se cargó (cursos coincidentes: %).', n;
    return;
  end if;

  update public.academy_schedule_settings set
    program_title = 'Crea tu propio Mini CRM con Agente de Inteligencia Artificial y WhatsApp',
    tagline = '¡Crea tu propio sistema de ventas inteligente y transforma la atención de tu negocio!',
    start_date = date '2026-12-15'
  where course_id = cid;

  -- Días sin clase. Con ellos, las 20 clases caen exactamente en las fechas de la malla.
  delete from public.academy_schedule_holidays where course_id = cid;
  insert into public.academy_schedule_holidays (course_id, day, label) values
    (cid, date '2026-12-24', 'Día reservado (sin clases)'),
    (cid, date '2026-12-25', 'Navidad'),
    (cid, date '2026-12-31', 'Día reservado (sin clases)'),
    (cid, date '2027-01-01', 'Año Nuevo'),
    (cid, date '2027-01-11', 'Sin clases'),
    (cid, date '2027-01-14', 'Sin clases'),
    (cid, date '2027-01-15', 'Sin clases');

  -- Módulos
  update public.academy_schedule_weeks w set title = v.title, objective = v.objective, result = v.result, updated_at = now()
  from (values
    (1, $d$Prepara tu negocio para la inteligencia artificial$d$, $d$Que todos los estudiantes descarguen sus materiales de estudio, comprendan el funcionamiento del proyecto y preparen las cuentas y servicios necesarios antes de comenzar a construir su sistema.$d$, $d$El estudiante comprende el proyecto, tiene sus materiales y herramientas preparados y ha iniciado las configuraciones necesarias de Meta y WhatsApp.$d$),
    (2, $d$Construye tu propio mini CRM$d$, $d$Contratar y preparar el VPS y dominio, comenzar la construcción guiada del sistema y crear los módulos esenciales del mini CRM.$d$, $d$Cada estudiante cuenta con su propia infraestructura y un mini CRM funcional en pruebas.$d$),
    (3, $d$Da vida a tu agente de IA y WhatsApp$d$, $d$Crear un agente de inteligencia artificial adaptado al negocio e integrarlo con WhatsApp y el mini CRM.$d$, $d$El estudiante dispone de un agente IA personalizado e integrado con su mini CRM, con WhatsApp operativo o probado según las autorizaciones externas.$d$),
    (4, $d$Publica, valida y presenta tu sistema$d$, $d$Publicar el sistema, preparar su administración y dedicar las tres últimas clases exclusivamente a pruebas, correcciones y validación.$d$, $d$Cada estudiante presenta su sistema comercial y demuestra las funcionalidades implementadas.$d$)
  ) as v(week_no, title, objective, result) where w.course_id = cid and w.week_no = v.week_no;
  -- Temas
  update public.academy_schedule_topics t set title = v.title, updated_at = now()
  from (values
    (1, $d$Preparación académica y herramientas de IA$d$),
    (2, $d$Configuración de Meta y WhatsApp empresarial$d$),
    (3, $d$Infraestructura y creación del sistema$d$),
    (4, $d$Gestión de clientes y oportunidades comerciales$d$),
    (5, $d$Creación y personalización del agente inteligente$d$),
    (6, $d$Integración y automatización comercial$d$),
    (7, $d$Publicación y administración empresarial$d$),
    (8, $d$Pruebas y evaluación final$d$)
  ) as v(topic_no, title) where t.course_id = cid and t.topic_no = v.topic_no;
  -- Clases
  update public.academy_class_plan c set title = v.title, description = v.description, objectives = v.objectives,
    content = v.content, activity = v.activity, outcome = v.outcome, updated_at = now()
  from (values
    (1, $d$Bienvenida y preparación del proyecto empresarial$d$, $d$Conoce cómo funcionará el curso, qué vas a construir y cómo se conectan WhatsApp, el agente de IA y tu mini CRM.$d$, $d$Entender el proyecto completo y dejar listos tus materiales de estudio.$d$, $d$Presentación de Sabero Academy y metodología del curso.
Qué es un mini CRM y para qué sirve.
Cómo funciona un agente de ventas con inteligencia artificial.
Cómo se conectarán WhatsApp, el agente y el mini CRM.
Presentación de los resultados esperados.
Descarga del material visual de estudio.
Organización de carpetas y recursos académicos.$d$, $d$Descargar los materiales e identificar las necesidades del negocio.$d$, $d$Materiales descargados y ficha del proyecto empresarial.$d$),
    (2, $d$Conoce las herramientas que harán realidad tu proyecto$d$, $d$Prepara tu acceso a Codex y a las herramientas de IA que usarás durante todo el curso.$d$, $d$Acceder a las herramientas de IA y realizar los primeros ejercicios guiados.$d$, $d$Introducción a Codex como asistente de creación.
Preparación del acceso personal.
Uso de instrucciones guiadas.
Interpretación de resultados.
Revisión de los materiales visuales.
Organización de las herramientas del estudiante.
Preparación de las cuentas necesarias.$d$, $d$Acceder a las herramientas y realizar ejercicios iniciales.$d$, $d$Herramientas de IA preparadas.$d$),
    (3, $d$Prepara tu empresa en Meta$d$, $d$Deja lista la cuenta empresarial de Meta que necesita WhatsApp Business Platform.$d$, $d$Configurar tu entorno empresarial en Meta e identificar las verificaciones pendientes.$d$, $d$Acceso a Meta Business Suite.
Creación o revisión del portafolio empresarial.
Datos de la empresa.
Configuración de administradores.
Seguridad de la cuenta.
Revisión de los requisitos de WhatsApp Business Platform.
Identificación de posibles verificaciones empresariales.$d$, $d$Preparar el entorno empresarial de Meta.$d$, $d$Cuenta empresarial de Meta configurada o requisitos pendientes identificados.$d$),
    (4, $d$Configura WhatsApp para tu futuro agente IA$d$, $d$Prepara WhatsApp Business Platform y presenta las solicitudes necesarias. Las aprobaciones dependen de Meta: no se prometen plazos.$d$, $d$Dejar WhatsApp preparado y documentar el estado de aprobación.$d$, $d$Introducción a WhatsApp Business Platform.
Requisitos del número telefónico.
Preparación de la cuenta de WhatsApp Business.
Configuración inicial en Meta.
Revisión de permisos.
Preparación de la integración.
Solicitudes de verificación cuando correspondan.$d$, $d$Preparar WhatsApp Business Platform y presentar las solicitudes necesarias.$d$, $d$Configuración de WhatsApp preparada y estado de aprobación documentado.$d$),
    (5, $d$Verifica que todo esté listo para comenzar$d$, $d$Revisa de punta a punta que materiales, herramientas y cuentas estén listos para empezar a construir.$d$, $d$Completar la lista de verificación y organizar los pendientes externos.$d$, $d$Revisión de materiales descargados.
Comprobación de herramientas de IA.
Verificación de la cuenta empresarial.
Revisión de WhatsApp.
Organización de credenciales.
Identificación de servicios pendientes.
Preparación del plan de trabajo de la segunda semana.$d$, $d$Completar una lista de verificación inicial.$d$, $d$Preparación académica y cuentas verificadas, con pendientes externos documentados.$d$),
    (6, $d$Tu servidor y dominio propio$d$, $d$Contrata y prepara tu propio VPS y dominio: la base donde vivirá tu sistema.$d$, $d$Tener infraestructura propia contratada y con accesos disponibles.$d$, $d$Selección del proveedor de VPS.
Opciones de Contabo y RackNerd.
Elección de un dominio.
Namecheap u otro proveedor.
Contratación de servicios.
Acceso al servidor.
Preparación de la infraestructura.$d$, $d$Contratar y preparar el VPS y dominio.$d$, $d$Infraestructura propia contratada y accesos disponibles.$d$),
    (7, $d$Crea la base de tu sistema empresarial$d$, $d$Con ayuda de la IA, crea la estructura principal de tu mini CRM y haz la primera prueba.$d$, $d$Dejar el sistema inicial funcionando en pruebas.$d$, $d$Organización de los módulos del mini CRM.
Creación de la estructura inicial.
Configuración del almacenamiento de información.
Acceso de usuarios.
Administración de permisos.
Primera ejecución del sistema.$d$, $d$Crear la estructura principal con asistencia de IA.$d$, $d$Sistema inicial funcionando en pruebas.$d$),
    (8, $d$Diseña tu panel de administración$d$, $d$Construye el panel desde donde administrarás clientes, usuarios e indicadores.$d$, $d$Contar con un panel principal navegable.$d$, $d$Panel principal.
Navegación.
Gestión de usuarios.
Indicadores comerciales.
Diseño adaptable.
Organización de funcionalidades.$d$, $d$Crear el panel administrativo del mini CRM.$d$, $d$Panel principal navegable.$d$),
    (9, $d$Organiza clientes y oportunidades$d$, $d$Crea los módulos para registrar clientes, contactos y oportunidades de venta.$d$, $d$Gestionar contactos y oportunidades de forma funcional.$d$, $d$Registro de clientes.
Contactos.
Clientes potenciales.
Oportunidades comerciales.
Etapas de venta.
Seguimiento de interesados.$d$, $d$Crear los módulos comerciales.$d$, $d$Gestión de contactos y oportunidades funcional.$d$),
    (10, $d$Completa y verifica tu mini CRM$d$, $d$Agrega actividades, notas e historial, y verifica que todo funcione antes de sumar el agente.$d$, $d$Dejar el mini CRM básico listo para integrar el agente IA.$d$, $d$Actividades comerciales.
Notas.
Historial de clientes.
Filtros.
Seguimiento de ventas.
Pruebas de funcionamiento.
Corrección de errores.$d$, $d$Verificar el funcionamiento de los módulos desarrollados.$d$, $d$Mini CRM básico listo para integrar el agente IA.$d$),
    (11, $d$Crea tu agente de inteligencia artificial$d$, $d$Elige tu proveedor de IA, crea tu agente y mantén tus primeras conversaciones de prueba.$d$, $d$Tener un agente de IA respondiendo en pruebas.$d$, $d$Selección del proveedor de IA.
Preparación de la cuenta y acceso al servicio.
Configuración del agente.
Identidad y personalidad.
Instrucciones de atención.
Primeras conversaciones.$d$, $d$Crear el agente con asistencia de Codex.$d$, $d$Agente IA respondiendo en pruebas.$d$),
    (12, $d$Enseña a tu agente sobre tu empresa$d$, $d$Entrena al agente con la información de tu negocio: productos, precios, preguntas frecuentes y reglas comerciales.$d$, $d$Lograr un agente especializado en tu negocio.$d$, $d$Información empresarial.
Productos y servicios.
Precios.
Preguntas frecuentes.
Reglas comerciales.
Atención de consultas.
Límites y derivación humana.$d$, $d$Personalizar el agente.$d$, $d$Agente especializado en el negocio.$d$),
    (13, $d$Conecta tu agente con WhatsApp$d$, $d$Conecta el agente al canal de WhatsApp o pruébalo en un entorno de pruebas, según las autorizaciones de Meta.$d$, $d$Dejar el canal conectado o la integración probada.$d$, $d$Revisión de la configuración de Meta.
Estado de solicitudes.
Configuración del canal.
Preparación de mensajes.
Pruebas de recepción y respuesta.
Resolución de incidencias.$d$, $d$Realizar la conexión o pruebas en el entorno permitido.$d$, $d$Canal conectado o integración probada en un entorno de pruebas.$d$),
    (14, $d$Integra las conversaciones con tu mini CRM$d$, $d$Haz que cada conversación se registre en tu CRM como contacto y oportunidad.$d$, $d$Tener el flujo entre conversaciones y CRM funcionando en pruebas.$d$, $d$Registro de conversaciones.
Identificación de contactos.
Creación de oportunidades.
Historial de atención.
Actualización de datos.
Relación entre el agente y el CRM.$d$, $d$Conectar la atención automatizada con la gestión comercial.$d$, $d$Flujo integrado en pruebas.$d$),
    (15, $d$Automatiza la atención y el seguimiento comercial$d$, $d$Automatiza la atención, el seguimiento de interesados y las notificaciones comerciales.$d$, $d$Contar con un flujo automatizado de ventas.$d$, $d$Atención automatizada.
Clasificación de clientes.
Seguimiento de interesados.
Notificaciones.
Actualización de oportunidades.
Derivación a un asesor.
Pruebas de automatización.$d$, $d$Configurar y verificar los procesos comerciales.$d$, $d$Flujo automatizado de ventas.$d$),
    (16, $d$Publica tu sistema en Internet$d$, $d$Publica tu mini CRM y tu agente en tu propio servidor y dominio, con conexiones seguras.$d$, $d$Tener el sistema accesible desde tu dominio.$d$, $d$Preparación del servidor.
Configuración del dominio.
Publicación del mini CRM.
Publicación del agente IA.
Conexiones seguras.
Comprobación de acceso.$d$, $d$Publicar el sistema en la infraestructura propia.$d$, $d$Sistema accesible desde su dominio.$d$),
    (17, $d$Aprende a administrar y proteger tu sistema$d$, $d$Aprende a administrar usuarios, copias de seguridad, monitoreo y costos de tu sistema.$d$, $d$Dejar la administración operativa lista para la evaluación final.$d$, $d$Administración del sistema.
Usuarios y permisos.
Copias de seguridad.
Monitoreo.
Costos de servicios.
Actualizaciones.
Seguridad básica.$d$, $d$Preparar la administración operativa.$d$, $d$Sistema preparado para la evaluación final.$d$),
    (18, $d$Prueba tu sistema como un cliente real$d$, $d$Recorre tu sistema como lo haría un cliente: acceso, registro, conversaciones y automatizaciones.$d$, $d$Ejecutar pruebas integrales y documentar un informe.$d$, $d$Pruebas de acceso.
Registro de clientes.
Gestión de oportunidades.
Conversaciones con el agente.
Atención mediante WhatsApp.
Automatizaciones.
Registro de resultados.$d$, $d$Ejecutar pruebas funcionales integrales.$d$, $d$Informe de pruebas.$d$),
    (19, $d$Corrige y valida tu solución empresarial$d$, $d$Corrige los problemas encontrados y valida la información, la seguridad y las automatizaciones.$d$, $d$Entregar un sistema revisado, con los pendientes documentados.$d$, $d$Identificación de errores.
Corrección de problemas.
Validación de información.
Seguridad.
Comprobación de automatizaciones.
Revisión de funcionamiento general.$d$, $d$Validar el proyecto final.$d$, $d$Sistema revisado y pendientes documentados.$d$),
    (20, $d$Presenta tu propio sistema de ventas inteligente$d$, $d$Presenta tu mini CRM y tu agente IA funcionando, y recibe tu evaluación final.$d$, $d$Presentar el sistema y recibir recomendaciones de mejora.$d$, $d$Presentación del mini CRM.
Demostración del agente IA.
Simulación de atención comercial.
Registro de oportunidades.
Explicación de la administración.
Evaluación final.
Recomendaciones de mejora.$d$, $d$Presentar el sistema desarrollado.$d$, $d$Proyecto final evaluado.$d$)
  ) as v(class_no, title, description, objectives, content, activity, outcome) where c.course_id = cid and c.class_no = v.class_no;
end $$;

commit;
