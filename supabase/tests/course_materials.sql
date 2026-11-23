-- Materiales del curso (todo se revierte).
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/course_materials.sql
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id) values
 ('11111111-1111-1111-1111-111111111111','ana@test.com', now(), '{"full_name":"Ana"}','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
 ('44444444-4444-4444-4444-444444444444','sin@test.com', now(), '{"full_name":"Sin matricula"}','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
 ('33333333-3333-3333-3333-333333333333','jefe@test.com', now(), '{"full_name":"Jefe"}','authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-000000000001','11111111-1111-1111-1111-111111111111'),
 ('aaaaaaaa-aaaa-aaaa-aaaa-000000000004','44444444-4444-4444-4444-444444444444'),
 ('aaaaaaaa-aaaa-aaaa-aaaa-000000000003','33333333-3333-3333-3333-333333333333');
insert into auth.identities (user_id, provider, provider_id, identity_data)
 values ('33333333-3333-3333-3333-333333333333','google','g-jefe','{"email":"jefe@test.com","email_verified":"true"}');
insert into public.academy_members (user_id, role) values
 ('11111111-1111-1111-1111-111111111111','student'),('44444444-4444-4444-4444-444444444444','student'),('33333333-3333-3333-3333-333333333333','admin');
insert into public.academy_enrollments (student_id, course_id, enrolled_at, status)
 select '11111111-1111-1111-1111-111111111111', id, now(), 'active' from public.academy_courses where status = 'published' limit 1;
create temp table t_course as select id from public.academy_courses where status = 'published' limit 1; grant all on t_course to public;
-- la clase 1 ya se abrió; la 2 no
update public.academy_class_plan set class_day = date '2026-01-05' where class_no = 1;
update public.academy_class_plan set class_day = date '2099-01-05' where class_no = 2;

-- el alumno no puede crear ni borrar materiales
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001","amr":[{"method":"password"}]}', true);
do $$ begin
  begin perform public.academy_admin_save_material(null, (select id from t_course), 'meta', 'x', 'https://drive.google.com/file/d/abc/view', null, 1); raise exception 'DEBIO FALLAR';
  exception when insufficient_privilege then raise notice 'alumno no crea materiales OK'; end;
end $$;

-- el administrador carga materiales
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000003","amr":[{"method":"oauth"}]}', true);
select public.academy_admin_save_material(null, (select id from t_course), 'meta', 'Manual de configuración de Facebook (Meta)', 'https://drive.google.com/file/d/META123/view', null, 1);
create temp table t_codex as select public.academy_admin_save_material(null, (select id from t_course), 'codex', 'Guía de Codex', 'https://drive.google.com/file/d/CODEX1/view', null, 1) as id;
grant all on t_codex to public;
select public.academy_admin_save_material(null, (select id from t_course), 'prompts', 'Prompts de la clase 1', 'https://drive.google.com/file/d/P1/view', 1, 1);
select public.academy_admin_save_material(null, (select id from t_course), 'prompts', 'Prompts de la clase 2', 'https://drive.google.com/file/d/P2/view', 2, 1);
do $$ begin
  begin perform public.academy_admin_save_material(null, (select id from t_course), 'meta', 'Malo', 'https://malo.example.com/x', null, 1); raise exception 'DEBIO FALLAR';
  exception when check_violation then raise notice 'solo enlaces de Google Drive/Docs OK'; end;
  begin perform public.academy_admin_save_material(null, (select id from t_course), 'prompts', 'Sin clase', 'https://drive.google.com/file/d/P/view', null, 1); raise exception 'DEBIO FALLAR';
  exception when check_violation then raise notice 'los prompts deben pertenecer a una clase OK'; end;
  -- reemplazar el PDF de la clase 1 no duplica
  perform public.academy_admin_save_material(null, (select id from t_course), 'prompts', 'Prompts de la clase 1 (v2)', 'https://drive.google.com/file/d/P1B/view', 1, 1);
  if (select count(*) from jsonb_array_elements(public.academy_course_materials()->'items') x where x->>'category' = 'prompts' and (x->>'class_no')::int = 1) <> 1 then raise exception 'duplico el PDF de la clase 1'; end if;
  if (public.academy_course_materials()->>'admin')::boolean is not true or jsonb_array_length(public.academy_course_materials()->'items') <> 4 then raise exception 'el admin debe ver los 4 materiales'; end if;
  raise notice 'el administrador carga y reemplaza materiales OK';
end $$;
reset role;

-- el alumno ve lo general y los prompts de clases abiertas; la clase 2 aun esta bloqueada
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001","amr":[{"method":"password"}]}', true);
do $$ declare r jsonb; i jsonb; begin
  r := public.academy_course_materials();
  if r->'classes' is not null and r->>'classes' <> 'null' then raise exception 'el alumno no debe ver la lista de clases del admin'; end if;
  select x into i from jsonb_array_elements(r->'items') x where x->>'category' = 'meta';
  if i->>'url' <> 'https://drive.google.com/file/d/META123/view' then raise exception 'el alumno debe ver el manual de Meta'; end if;
  select x into i from jsonb_array_elements(r->'items') x where (x->>'class_no')::int = 1;
  if i->>'url' <> 'https://drive.google.com/file/d/P1B/view' or (i->>'locked')::boolean then raise exception 'prompts de la clase 1 abiertos'; end if;
  select x into i from jsonb_array_elements(r->'items') x where (x->>'class_no')::int = 2;
  if (i->>'locked')::boolean is not true or i->>'url' is not null then raise exception 'prompts de la clase 2 deben estar bloqueados y sin enlace: %', i; end if;
  if r::text like '%P2/view%' then raise exception 'filtra el enlace de una clase bloqueada'; end if;
  raise notice 'el alumno ve sus materiales; los de clases cerradas salen sin enlace OK';
end $$;
-- sin matrícula: nada
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000004","amr":[{"method":"password"}]}', true);
do $$ begin
  if public.academy_course_materials() is not null then raise exception 'sin matricula no debe ver materiales'; end if;
  begin perform * from public.academy_course_materials; raise exception 'DEBIO FALLAR (lectura directa)';
  exception when insufficient_privilege then raise notice 'sin matricula no ve nada y no lee la tabla OK'; end;
end $$;
reset role;

-- borrar
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001","amr":[{"method":"password"}]}', true);
do $$ begin
  begin perform public.academy_admin_delete_material((select id from t_codex)); raise exception 'DEBIO FALLAR';
  exception when insufficient_privilege then raise notice 'alumno no borra materiales OK'; end;
end $$;
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000003","amr":[{"method":"oauth"}]}', true);
select public.academy_admin_delete_material((select id from t_codex));
do $$ begin
  if jsonb_array_length(public.academy_course_materials()->'items') <> 3 then raise exception 'debia quedar 3 materiales'; end if;
  raise notice 'borrar un material OK';
end $$;
reset role;
rollback;
