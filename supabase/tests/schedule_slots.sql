-- Calendario real (inicio 15 dic, receso 24 dic - 1 ene) y turnos con cupo (todo se revierte).
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/schedule_slots.sql
\set ON_ERROR_STOP on
begin;
delete from public.academy_internal_secrets where name = 'payments';
insert into public.academy_internal_secrets(name, digest) values ('payments', encode(sha256(convert_to('secreto-de-prueba','UTF8')),'hex'));

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id) values
 ('11111111-1111-1111-1111-111111111111','ana@test.com',   now(), '{"full_name":"Ana"}',   'authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
 ('22222222-2222-2222-2222-222222222222','beto@test.com',  now(), '{"full_name":"Beto"}',  'authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
 ('55555555-5555-5555-5555-555555555555','carla@test.com', now(), '{"full_name":"Carla"}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
 ('66666666-6666-6666-6666-666666666666','dario@test.com', now(), '{"full_name":"Dario"}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
 ('33333333-3333-3333-3333-333333333333','jefe@test.com',  now(), '{"full_name":"Jefe"}',  'authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id)
select ('aaaaaaaa-aaaa-aaaa-aaaa-' || lpad(right(id::text, 12), 12, '0'))::uuid, id from auth.users where email like '%@test.com';
insert into auth.identities (user_id, provider, provider_id, identity_data)
 values ('33333333-3333-3333-3333-333333333333','google','g-jefe','{"email":"jefe@test.com","email_verified":"true"}');
insert into public.academy_members (user_id, role) values
 ('11111111-1111-1111-1111-111111111111','student'),('22222222-2222-2222-2222-222222222222','student'),
 ('55555555-5555-5555-5555-555555555555','student'),('66666666-6666-6666-6666-666666666666','student'),
 ('33333333-3333-3333-3333-333333333333','admin');
create temp table t_course as select id from public.academy_courses where status = 'published' limit 1; grant all on t_course to public;
create temp table t_ids as select class_no, id from public.academy_class_plan; grant all on t_ids to public;

-- ---------- Fechas: inicio martes 15 dic, receso 24 dic - 1 ene, fin miércoles 20 ene ----------
do $$ declare p public.academy_class_plan; r record; begin
  select * into p from public.academy_class_plan where class_no = 1;  if academy_private.class_date(p) <> date '2026-12-15' then raise exception 'clase 1 debia ser 15 dic: %', academy_private.class_date(p); end if;
  select * into p from public.academy_class_plan where class_no = 7;  if academy_private.class_date(p) <> date '2026-12-23' then raise exception 'clase 7 debia ser 23 dic'; end if;
  select * into p from public.academy_class_plan where class_no = 8;  if academy_private.class_date(p) <> date '2027-01-04' then raise exception 'clase 8 debia ser 4 ene (tras el receso)'; end if;
  select * into p from public.academy_class_plan where class_no = 20; if academy_private.class_date(p) <> date '2027-01-20' then raise exception 'clase 20 debia ser 20 ene'; end if;
  if exists (select 1 from public.academy_class_plan c where extract(isodow from academy_private.class_date(c)) > 5) then raise exception 'hay clases en fin de semana'; end if;
  if exists (select 1 from public.academy_class_plan c join public.academy_schedule_holidays h on h.day = academy_private.class_date(c)) then raise exception 'hay clases en feriado'; end if;
  if (select count(distinct academy_private.class_date(c)) from public.academy_class_plan c) <> 20 then raise exception 'fechas repetidas'; end if;
  if (select count(*) from public.academy_schedule_holidays) <> 9 then raise exception 'receso: deben ser 9 dias (24 dic al 1 ene)'; end if;
  raise notice 'calendario 15 dic al 20 ene con receso de fin de ano OK';
end $$;

-- ---------- Turnos visibles: tardes primero; la mañana solo si las tardes se llenan ----------
do $$ declare s jsonb; begin
  s := public.academy_public_schedule();
  if (select count(*) from jsonb_array_elements(s->'slots')) <> 2 then raise exception 'solo deben verse 2 turnos de tarde: %', s->'slots'; end if;
  if exists (select 1 from jsonb_array_elements(s->'slots') x where x->>'label' = 'Mañana') then raise exception 'la mañana no debe verse aun'; end if;
  if (s->>'start_date') <> '2026-12-15' or (s->>'end_date') <> '2027-01-20' then raise exception 'inicio/fin mal: % %', s->>'start_date', s->>'end_date'; end if;
  if jsonb_array_length(s->'holidays') <> 9 or jsonb_array_length(s->'classes') <> 20 then raise exception 'feriados/clases mal'; end if;
  raise notice 'solo se ofrecen los turnos de la tarde al comenzar OK';
end $$;

-- cupos de prueba pequeños: 1 por turno
update public.academy_course_slots set capacity = 1 where slot_no in (1, 2, 3);

-- Ana elige la tarde (turno 1); la mañana (3) todavía no se ofrece
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-111111111111","amr":[{"method":"password"}]}', true);
do $$ begin
  begin perform * from public.academy_start_payment((select id from t_course),'Ana','+51999888777','Perú',null,'v1','culqi', 3); raise exception 'DEBIO FALLAR (mañana oculta)';
  exception when check_violation then raise notice 'turno de la mañana no se ofrece todavia OK'; end;
  begin perform * from public.academy_start_payment((select id from t_course),'Ana','+51999888777','Perú',null,'v1','culqi', null); raise exception 'DEBIO FALLAR (sin turno)';
  exception when check_violation then raise notice 'el turno es obligatorio OK'; end;
end $$;
create temp table t_ana as select * from public.academy_start_payment((select id from t_course),'Ana','+51999888777','Perú',null,'v1','culqi', 1);
grant all on t_ana to public;
reset role;

-- Confirmación del pago: la matrícula guarda el turno
set local role anon;
select public.academy_confirm_payment('secreto-de-prueba', (select payment_id from t_ana), 'culqi', 'chr_ana', (select amount from t_ana), (select currency from t_ana));
reset role;
do $$ begin
  if (select slot_no from public.academy_enrollments where student_id = '11111111-1111-1111-1111-111111111111') <> 1 then raise exception 'la matricula debia guardar el turno 1'; end if;
  raise notice 'la matricula guarda el turno elegido OK';
end $$;

-- Turno 1 lleno: Beto no puede tomarlo; sí el 2 (tarde noche)
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-222222222222","amr":[{"method":"password"}]}', true);
do $$ begin
  begin perform * from public.academy_start_payment((select id from t_course),'Beto','+51999888777','Perú',null,'v1','culqi', 1); raise exception 'DEBIO FALLAR (turno lleno)';
  exception when sqlstate '54000' then raise notice 'turno lleno rechazado OK'; end;
end $$;
create temp table t_beto as select * from public.academy_start_payment((select id from t_course),'Beto','+51999888777','Perú',null,'v1','culqi', 2);
grant all on t_beto to public;
-- la reserva temporal impide que otra persona tome el mismo cupo mientras Beto paga
select set_config('request.jwt.claims','{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-555555555555","amr":[{"method":"password"}]}', true);
do $$ begin
  begin perform * from public.academy_start_payment((select id from t_course),'Carla','+51999888777','Perú',null,'v1','culqi', 2); raise exception 'DEBIO FALLAR (reserva)';
  exception when sqlstate '54000' then raise notice 'cupo reservado mientras otro paga OK'; end;
end $$;
reset role;
set local role anon;
select public.academy_confirm_payment('secreto-de-prueba', (select payment_id from t_beto), 'culqi', 'chr_beto', (select amount from t_beto), (select currency from t_beto));
reset role;

-- Las dos tardes están llenas: ahora SÍ se ofrece la mañana
do $$ declare s jsonb; begin
  s := public.academy_public_schedule();
  if not exists (select 1 from jsonb_array_elements(s->'slots') x where x->>'label' = 'Mañana') then raise exception 'la mañana debia aparecer: %', s->'slots'; end if;
  if (select count(*) from jsonb_array_elements(s->'slots') x where (x->>'full')::boolean) <> 2 then raise exception 'las dos tardes deben salir llenas'; end if;
  raise notice 'con las tardes llenas aparece el turno de la mañana OK';
end $$;

-- Carla toma la mañana
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-555555555555","amr":[{"method":"password"}]}', true);
create temp table t_carla as select * from public.academy_start_payment((select id from t_course),'Carla','+51999888777','Perú',null,'v1','culqi', 3);
reset role;

-- ---------- El alumno ve su turno y el enlace de Meet del turno ----------
update public.academy_course_slots set meet_url = 'https://meet.google.com/aaa-bbbb-ccc' where slot_no = 1;
update public.academy_schedule_settings set start_date = date '2026-01-05';
update public.academy_class_plan set meet_url = null;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-111111111111","amr":[{"method":"password"}]}', true);
do $$ declare s jsonb; c jsonb; begin
  s := public.academy_schedule();
  if s->'slot'->>'label' <> 'Tarde' or s->'slot'->>'starts' <> '15:00' then raise exception 'debia ver su turno: %', s->'slot'; end if;
  select x into c from jsonb_array_elements(s->'weeks'->0->'classes') x where (x->>'class_no')::int = 1;
  if c->>'meet_url' <> 'https://meet.google.com/aaa-bbbb-ccc' then raise exception 'debia usar el Meet del turno: %', c->>'meet_url'; end if;
  if s->'slots' is not null and s->>'slots' <> 'null' then raise exception 'el alumno no debe ver todos los turnos'; end if;
  raise notice 'el alumno ve su turno y el Meet de su turno OK';
end $$;
reset role;

-- ---------- Administración: feriados y turnos ----------
update public.academy_schedule_settings set start_date = date '2026-12-15';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-222222222222","amr":[{"method":"password"}]}', true);
do $$ begin
  begin perform public.academy_admin_set_holiday((select id from t_course), date '2026-12-16', 'x', false); raise exception 'DEBIO FALLAR';
  exception when insufficient_privilege then raise notice 'un alumno no puede crear feriados OK'; end;
  begin perform public.academy_admin_save_slot((select id from t_course), 4, 'x', time '09:00', time '11:00', null, 10, 1, true); raise exception 'DEBIO FALLAR';
  exception when insufficient_privilege then raise notice 'un alumno no puede crear turnos OK'; end;
end $$;
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-333333333333","amr":[{"method":"oauth"}]}', true);
select public.academy_admin_set_holiday((select id from t_course), date '2026-12-16', 'Feriado de prueba', false);
do $$ declare s jsonb; c jsonb; begin
  s := public.academy_schedule();
  select x into c from jsonb_array_elements(s->'weeks'->0->'classes') x where (x->>'class_no')::int = 2;
  if c->>'date' <> '2026-12-17' then raise exception 'con feriado el 16, la clase 2 debia pasar al 17: %', c->>'date'; end if;
  if jsonb_array_length(s->'slots') <> 3 then raise exception 'el admin debe ver los 3 turnos'; end if;
  raise notice 'un feriado nuevo corre las clases siguientes OK';
end $$;
select public.academy_admin_set_holiday((select id from t_course), date '2026-12-16', null, true);
select public.academy_admin_save_slot((select id from t_course), 4, 'Sábado', time '09:00', time '11:00', 'https://meet.google.com/zzz-yyyy-xxx', 10, 2, false);
do $$ begin
  begin perform public.academy_admin_save_slot((select id from t_course), 4, 'x', time '09:00', time '11:00', 'https://malo.example/x', 10, 2, true); raise exception 'DEBIO FALLAR';
  exception when check_violation then raise notice 'enlace de Meet invalido en turno rechazado OK'; end;
end $$;
reset role;
rollback;
