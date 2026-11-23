-- Consultas: el administrador las ve y responde; el alumno ve la respuesta (todo se revierte).
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/admin_inquiries.sql
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id) values
 ('11111111-1111-1111-1111-111111111111','ana@test.com', now(), '{"full_name":"Ana"}','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
 ('22222222-2222-2222-2222-222222222222','beto@test.com', now(), '{"full_name":"Beto"}','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
 ('33333333-3333-3333-3333-333333333333','jefe@test.com', now(), '{"full_name":"Jefe"}','authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-000000000001','11111111-1111-1111-1111-111111111111'),
 ('aaaaaaaa-aaaa-aaaa-aaaa-000000000002','22222222-2222-2222-2222-222222222222'),
 ('aaaaaaaa-aaaa-aaaa-aaaa-000000000003','33333333-3333-3333-3333-333333333333');
insert into auth.identities (user_id, provider, provider_id, identity_data)
 values ('33333333-3333-3333-3333-333333333333','google','g-jefe','{"email":"jefe@test.com","email_verified":"true"}');
insert into public.academy_members (user_id, role) values
 ('11111111-1111-1111-1111-111111111111','student'),('22222222-2222-2222-2222-222222222222','student'),('33333333-3333-3333-3333-333333333333','admin');
insert into public.academy_enrollments (student_id, course_id, enrolled_at, status)
 select u, c.id, now(), 'active' from public.academy_courses c, (values ('11111111-1111-1111-1111-111111111111'::uuid), ('22222222-2222-2222-2222-222222222222'::uuid)) v(u) where c.status = 'published' limit 2;
insert into public.academy_inquiries (student_id, subject, body) values ('11111111-1111-1111-1111-111111111111','Duda clase 3','No veo el enlace');
create temp table t_inq as select id from public.academy_inquiries; grant all on t_inq to public;

-- el alumno no puede usar las funciones de administración
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001","amr":[{"method":"password"}]}', true);
do $$ begin
  begin perform public.academy_admin_inquiries('open', 1); raise exception 'DEBIO FALLAR (alumno lista)';
  exception when insufficient_privilege then raise notice 'alumno no puede listar consultas ajenas OK'; end;
  begin perform * from public.academy_admin_reply_inquiry((select id from t_inq), 'hola'); raise exception 'DEBIO FALLAR (alumno responde)';
  exception when insufficient_privilege then raise notice 'alumno no puede responder OK'; end;
end $$;

-- el administrador ve, valida y responde
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000003","amr":[{"method":"oauth"}]}', true);
do $$ declare r jsonb; m record; begin
  r := public.academy_admin_inquiries('open', 1);
  if jsonb_array_length(r->'items') <> 1 or r->'items'->0->>'student_email' <> 'ana@test.com' then raise exception 'debia verse 1 consulta abierta de Ana: %', r; end if;
  begin perform public.academy_admin_inquiries('cualquiera', 1); raise exception 'DEBIO FALLAR (filtro)';
  exception when sqlstate '22023' then raise notice 'filtro invalido rechazado OK'; end;
  begin perform * from public.academy_admin_reply_inquiry((select id from t_inq), '   '); raise exception 'DEBIO FALLAR (vacia)';
  exception when check_violation then raise notice 'respuesta vacia rechazada OK'; end;
  select * into m from public.academy_admin_reply_inquiry((select id from t_inq), 'Revisa el cronograma, ya esta el enlace.');
  if m.student_email <> 'ana@test.com' or m.subject <> 'Duda clase 3' then raise exception 'datos para el correo mal: %', m; end if;
  if jsonb_array_length(public.academy_admin_inquiries('open', 1)->'items') <> 0 then raise exception 'ya no debe estar abierta'; end if;
  if jsonb_array_length(public.academy_admin_inquiries('answered', 1)->'items') <> 1 then raise exception 'debe estar en respondidas'; end if;
  raise notice 'el administrador responde y la consulta pasa a respondida OK';
end $$;
reset role;

-- la alumna ve la respuesta en su historial; otro alumno no
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001","amr":[{"method":"password"}]}', true);
do $$ begin
  if (select count(*) from public.academy_inquiry_replies) <> 1 then raise exception 'la alumna debe ver su respuesta'; end if;
  if (select status from public.academy_inquiries limit 1) <> 'answered' then raise exception 'estado respondida'; end if;
  raise notice 'la alumna ve la respuesta OK';
end $$;
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000002","amr":[{"method":"password"}]}', true);
do $$ begin
  if (select count(*) from public.academy_inquiries) <> 0 or (select count(*) from public.academy_inquiry_replies) <> 0 then raise exception 'otro alumno ve consultas ajenas'; end if;
  raise notice 'otro alumno no ve consultas ajenas OK';
end $$;
rollback;
