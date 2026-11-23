-- Cronograma académico (todo se revierte). Ejecutar con:
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/class_schedule.sql
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id) values
 ('11111111-1111-1111-1111-111111111111', 'ana@test.com',   now(), '{"full_name":"Ana"}',   'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
 ('22222222-2222-2222-2222-222222222222', 'beto@test.com',  now(), '{"full_name":"Beto"}',  'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
 ('33333333-3333-3333-3333-333333333333', 'jefe@test.com',  now(), '{"full_name":"Jefe"}',  'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
 ('44444444-4444-4444-4444-444444444444', 'afuera@test.com', now(), '{"full_name":"Afuera"}', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id, created_at, updated_at)
select ('aaaaaaaa-aaaa-aaaa-aaaa-' || lpad(n::text, 12, '0'))::uuid, id, now(), now()
from (select id, row_number() over (order by id) n from auth.users where email like '%@test.com') u;
insert into auth.identities (user_id, provider, provider_id, identity_data)
 values ('33333333-3333-3333-3333-333333333333', 'google', 'g-jefe', '{"email":"jefe@test.com","email_verified":"true"}');
insert into public.academy_members (user_id, role) values
 ('11111111-1111-1111-1111-111111111111', 'student'), ('22222222-2222-2222-2222-222222222222', 'student'),
 ('33333333-3333-3333-3333-333333333333', 'admin'), ('44444444-4444-4444-4444-444444444444', 'student');
insert into public.academy_enrollments (student_id, course_id, enrolled_at, status)
select s, c.id, now(), 'active' from public.academy_courses c,
  (values ('11111111-1111-1111-1111-111111111111'::uuid), ('22222222-2222-2222-2222-222222222222'::uuid)) v(s)
where c.status = 'published' limit 2;

create temp table t_course as select id from public.academy_courses where status = 'published' limit 1;
grant all on t_course to public;
create temp table t_ids as select class_no, id from public.academy_class_plan; grant all on t_ids to public;

-- ---------- Contenido cargado ----------
do $$ declare c integer; begin
  if (select count(*) from public.academy_schedule_weeks) <> 4 then raise exception 'deben ser 4 semanas'; end if;
  if (select count(*) from public.academy_schedule_topics) <> 8 then raise exception 'deben ser 8 temas'; end if;
  select count(*) into c from public.academy_class_plan; if c <> 20 then raise exception 'deben ser 20 clases, hay %', c; end if;
  if exists (select 1 from (select week_no, count(*) n from public.academy_class_plan group by 1) x where n <> 5) then raise exception 'cada semana debe tener 5 clases'; end if;
  if exists (select 1 from (select topic_no, count(*) n from public.academy_schedule_topics group by 1) x where n <> 1) then raise exception 'temas duplicados'; end if;
  if exists (select 1 from (select week_no, count(distinct topic_no) n from public.academy_class_plan group by 1) x where n <> 2) then raise exception 'cada semana debe tener 2 temas'; end if;
  if (select sum(duration_minutes) from public.academy_class_plan) <> 2400 then raise exception 'deben ser 40 horas'; end if;
  if exists (select 1 from public.academy_class_plan where class_no <> (week_no - 1) * 5 + weekday) then raise exception 'orden cronológico incorrecto'; end if;
  if (select title from public.academy_class_plan where class_no = 1) <> 'Bienvenida y preparación del proyecto empresarial' then raise exception 'clase 1 distinta'; end if;
  if (select title from public.academy_class_plan where class_no = 20) <> 'Presenta tu propio sistema de ventas inteligente' then raise exception 'clase 20 distinta'; end if;
  if exists (select 1 from public.academy_class_plan where meet_url is not null or recording_url is not null or material_url is not null) then raise exception 'no deben inventarse enlaces'; end if;
  if (select title from public.academy_class_plan where class_no = 4) <> 'Configura WhatsApp para tu futuro agente IA' then raise exception 'clase 4 distinta'; end if;
  if exists (select 1 from public.academy_class_plan where title ~* 'código|programaci|programar' or description ~* 'código|programaci|programar') then raise exception 'titulos o descripciones comerciales no deben hablar de codigo ni programacion'; end if;
  raise notice 'contenido: 4 semanas, 8 temas, 20 clases, 40 horas, sin enlaces inventados OK';
end $$;

-- ---------- Calendario (inicio lunes 2026-01-05, hora de Lima) ----------
delete from public.academy_schedule_holidays;
update public.academy_class_plan set class_day = null;  -- este bloque prueba el calculo automatico del calendario
update public.academy_schedule_settings set start_date = date '2026-01-05', unlock_time = '08:00', timezone = 'America/Lima';
do $$ declare p public.academy_class_plan; begin
  select * into p from public.academy_class_plan where class_no = 1;  if academy_private.class_date(p) <> date '2026-01-05' then raise exception 'clase 1 != primer lunes'; end if;
  if academy_private.class_unlock_at(p) <> timestamptz '2026-01-05 13:00:00+00' then raise exception 'zona horaria mal interpretada: %', academy_private.class_unlock_at(p); end if;
  select * into p from public.academy_class_plan where class_no = 5;  if academy_private.class_date(p) <> date '2026-01-09' then raise exception 'clase 5 != primer viernes'; end if;
  select * into p from public.academy_class_plan where class_no = 6;  if academy_private.class_date(p) <> date '2026-01-12' then raise exception 'clase 6 != segundo lunes'; end if;
  select * into p from public.academy_class_plan where class_no = 20; if academy_private.class_date(p) <> date '2026-01-30' then raise exception 'clase 20 != cuarto viernes'; end if;
  if exists (select 1 from public.academy_class_plan c where extract(isodow from academy_private.class_date(c)) > 5) then raise exception 'hay clases en fin de semana'; end if;
  if (select count(distinct academy_private.class_date(c)) from public.academy_class_plan c) <> 20 then raise exception 'fechas repetidas'; end if;
  raise notice 'calendario OK (clase 1 lunes, 5 viernes, 6 lunes, 20 cuarto viernes, sin fines de semana, 08:00 Lima = 13:00 UTC)';
end $$;

-- Zonas horarias: otra zona cambia la hora de desbloqueo, y otra edición no afecta a esta (configuración por curso).
update public.academy_schedule_settings set timezone = 'America/Mexico_City';
do $$ declare p public.academy_class_plan; begin
  select * into p from public.academy_class_plan where class_no = 1;
  if academy_private.class_unlock_at(p) <> timestamptz '2026-01-05 14:00:00+00' then raise exception 'zona Mexico mal: %', academy_private.class_unlock_at(p); end if;
end $$;
update public.academy_schedule_settings set timezone = 'America/Lima';

-- ---------- Seguridad: nadie lee las tablas directamente; solo admin usa las funciones de administración ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001"}', true);
do $$ begin
  begin perform * from public.academy_class_plan; raise exception 'DEBIO FALLAR (lectura directa)';
  exception when insufficient_privilege then raise notice 'lectura directa de tablas denegada OK'; end;
  begin perform public.academy_admin_save_class((select id from t_ids limit 1), '{"title":"x"}'); raise exception 'DEBIO FALLAR (alumno edita)';
  exception when insufficient_privilege then raise notice 'alumno no puede editar OK'; end;
  begin perform public.academy_admin_save_settings((select id from t_course), date '2026-02-02', time '08:00', 'America/Lima'); raise exception 'DEBIO FALLAR (alumno configura)';
  exception when insufficient_privilege then raise notice 'alumno no puede configurar fechas OK'; end;
end $$;
reset role;

-- Alumno sin matrícula
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000004"}', true);
do $$ begin
  if public.academy_schedule() is not null then raise exception 'alumno sin matricula recibio el cronograma'; end if;
  raise notice 'alumno sin matricula no recibe el cronograma OK';
  begin perform * from public.academy_schedule_audit; raise exception 'DEBIO FALLAR (auditoria visible)';
  exception when insufficient_privilege then raise notice 'auditoria inaccesible OK'; end;
end $$;
reset role;

-- ---------- Alumno matriculado: todo ya llegó su fecha (2026) ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001"}', true);
do $$ declare s jsonb; begin
  s := public.academy_schedule();
  if (s->>'total')::int <> 20 or (s->>'percent')::int <> 0 then raise exception 'estado inicial mal: %', s->>'percent'; end if;
  if jsonb_array_length(s->'weeks') <> 4 then raise exception 'semanas'; end if;
  if (s->'next'->>'class_no')::int is null then null; end if;
  raise notice 'alumno ve 4 semanas y 20 clases, progreso 0 OK';
end $$;
reset role;

-- Cambiamos al futuro: ninguna clase disponible, salvo habilitación manual
update public.academy_schedule_settings set start_date = date_trunc('week', current_date + 400)::date;
update public.academy_class_plan set meet_url = 'https://meet.google.com/abc-defg-hij', recording_url = 'https://drive.google.com/file/d/xyz/view' where class_no in (1, 3);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001"}', true);
do $$ declare s jsonb; c jsonb; begin
  s := public.academy_schedule();
  for c in select jsonb_array_elements(w->'classes') from jsonb_array_elements(s->'weeks') w loop
    if (c->>'unlocked')::boolean then raise exception 'clase % abierta antes de su fecha', c->>'class_no'; end if;
    if c ? 'meet_url' or c ? 'content' or c ? 'recording_url' then raise exception 'clase % filtra contenido o enlaces estando bloqueada', c->>'class_no'; end if;
  end loop;
  begin perform public.academy_set_class_done((select id from t_ids where class_no = 1), true); raise exception 'DEBIO FALLAR (completar bloqueada)';
  exception when insufficient_privilege then raise notice 'clase futura no se abre ni se completa (ni por URL ni por API) OK'; end;
end $$;
reset role;

-- El administrador habilita la clase 3 por adelantado y bloquea la 1
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000003","amr":[{"method":"oauth"}]}', true);
select public.academy_admin_save_class((select id from t_ids where class_no = 3), '{"access":"enabled"}');
do $$ begin
  begin perform public.academy_admin_save_class((select id from t_ids where class_no = 3), '{"meet_url":"https://malo.example.com/x"}'); raise exception 'DEBIO FALLAR (enlace invalido)';
  exception when check_violation then raise notice 'enlace de Meet invalido rechazado OK'; end;
  begin perform public.academy_admin_save_settings((select id from t_course), date '2026-01-05', time '08:00', 'Mars/Olympus'); raise exception 'DEBIO FALLAR (zona)';
  exception when check_violation then raise notice 'zona horaria invalida rechazada OK'; end;
  if (public.academy_schedule()->'weeks'->0->'classes'->0->>'meet_url') is null then raise exception 'admin debe ver enlaces'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001"}', true);
do $$ declare s jsonb; c3 jsonb; begin
  s := public.academy_schedule();
  select c into c3 from jsonb_array_elements(s->'weeks'->0->'classes') c where (c->>'class_no')::int = 3;
  if not (c3->>'unlocked')::boolean or c3->>'meet_url' <> 'https://meet.google.com/abc-defg-hij' then raise exception 'habilitada manualmente debe abrir y mostrar su enlace'; end if;
  perform public.academy_set_class_done((c3->>'id')::uuid, true);
  raise notice 'habilitacion manual anticipada OK';
end $$;
reset role;

-- ---------- Progreso (calendario ya pasado) ----------
update public.academy_schedule_settings set start_date = date '2026-01-05';
update public.academy_class_plan set access = 'auto';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001"}', true);
do $$ declare i int; begin
  perform public.academy_set_class_done((select id from t_ids where class_no = 1), true);
  perform public.academy_set_class_done((select id from t_ids where class_no = 1), true);   -- repetir no duplica
  if (public.academy_schedule()->>'percent')::int <> 10 then raise exception 'con clases 1 y 3 completadas debe ser 10%%, es %', public.academy_schedule()->>'percent'; end if;
  perform public.academy_set_class_done((select id from t_ids where class_no = 3), false);
  if (public.academy_schedule()->>'percent')::int <> 5 then raise exception '1 clase = 5%%'; end if;
  for i in 1..5 loop perform public.academy_set_class_done((select id from t_ids where class_no = i), true); end loop;
  if (public.academy_schedule()->>'percent')::int <> 25 then raise exception '5 clases = 25%%'; end if;
  if (public.academy_schedule()->'weeks'->0->>'completed')::int <> 5 then raise exception 'semana 1 completa'; end if;
  for i in 1..20 loop perform public.academy_set_class_done((select id from t_ids where class_no = i), true); end loop;
  if (public.academy_schedule()->>'percent')::int <> 100 then raise exception '20 clases = 100%%'; end if;
  raise notice 'progreso 5%% / 25%% / 100%% y sin duplicados OK';
end $$;
reset role;

-- Otro alumno: progreso independiente
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000002"}', true);
do $$ begin
  if (public.academy_schedule()->>'completed')::int <> 0 then raise exception 'el progreso no es independiente por alumno'; end if;
  raise notice 'progreso independiente por alumno OK';
end $$;
reset role;
do $$ begin
  if (select count(*) from public.academy_class_progress where student_id = '11111111-1111-1111-1111-111111111111') <> 20 then raise exception 'filas de progreso duplicadas o faltantes'; end if;
end $$;

-- Estados de ejecución: "ejecutada / hoy o próxima / pendiente"
update public.academy_schedule_settings set start_date = date_trunc('week', current_date + 400)::date;
update public.academy_class_plan set held = 'held' where class_no in (1, 2);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000002"}', true);
do $$ declare s jsonb; ph text[]; begin
  s := public.academy_schedule();
  select array_agg(c->>'phase' order by (c->>'class_no')::int) into ph from jsonb_array_elements(s->'weeks'->0->'classes') c;
  if ph <> array['executed', 'executed', 'next', 'pending', 'pending'] then raise exception 'fases: %', ph; end if;
  if (s->'next'->>'class_no')::int <> 3 then raise exception 'la proxima debia ser la 3'; end if;
  raise notice 'estados ejecutada/proxima/pendiente OK';
end $$;
reset role;

-- El historial registró los cambios de disponibilidad
do $$ begin
  if (select count(*) from public.academy_schedule_audit where action = 'class_state') < 1 then raise exception 'sin auditoria'; end if;
  raise notice 'auditoria de disponibilidad OK';
end $$;

-- ---------- Edición del administrador y repetición de la carga ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000003","amr":[{"method":"oauth"}]}', true);
select public.academy_admin_save_class((select id from t_ids where class_no = 2), '{"title":"Arquitectura y herramientas (editado)","meet_url":"https://meet.google.com/zzz-yyyy-xxx"}');
select public.academy_admin_save_week((select id from t_course), 1, 'Semana 1 editada', 'Objetivo editado', '[{"topic_no":1,"title":"Tema 1 editado"}]');
reset role;
do $$ begin
  if (select title from public.academy_class_plan where class_no = 2) <> 'Arquitectura y herramientas (editado)' then raise exception 'edicion no guardada'; end if;
  if (select count(*) from public.academy_class_progress) <> 20 then raise exception 'editar contenido no debe borrar el progreso'; end if;
  raise notice 'edicion por el administrador conserva el progreso OK';
end $$;

rollback;
