-- Resumen del panel de administración (todo se revierte).
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/admin_summary.sql
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id) values
 ('11111111-1111-1111-1111-111111111111','ana@test.com', now(), '{"full_name":"Ana"}','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
 ('33333333-3333-3333-3333-333333333333','jefe@test.com', now(), '{"full_name":"Jefe"}','authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-000000000001','11111111-1111-1111-1111-111111111111'),
 ('aaaaaaaa-aaaa-aaaa-aaaa-000000000003','33333333-3333-3333-3333-333333333333');
insert into auth.identities (user_id, provider, provider_id, identity_data)
 values ('33333333-3333-3333-3333-333333333333','google','g-jefe','{"email":"jefe@test.com","email_verified":"true"}');
insert into public.academy_members (user_id, role) values
 ('11111111-1111-1111-1111-111111111111','student'),('33333333-3333-3333-3333-333333333333','admin');
insert into public.academy_enrollments (student_id, course_id, enrolled_at, status)
 select '11111111-1111-1111-1111-111111111111', id, now(), 'active' from public.academy_courses where status = 'published' limit 1;
insert into public.academy_payments (student_id, course_id, provider, amount, currency, status, paid_at, external_id)
 select '11111111-1111-1111-1111-111111111111', id, 'culqi', 7, 'PEN', 'paid', now(), 'chr_test' from public.academy_courses where status = 'published' limit 1;
insert into public.academy_inquiries (student_id, subject, body) values ('11111111-1111-1111-1111-111111111111', 'Duda', 'Hola');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000001","amr":[{"method":"password"}]}', true);
do $$ begin
  begin perform public.academy_admin_summary(); raise exception 'DEBIO FALLAR (alumno)';
  exception when insufficient_privilege then raise notice 'alumno no ve el resumen OK'; end;
end $$;
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-000000000003","amr":[{"method":"oauth"}]}', true);
do $$ declare r jsonb; begin
  r := public.academy_admin_summary();
  if (r->>'students')::int <> 1 or (r->>'paid_count')::int <> 1 or (r->>'open_inquiries')::int <> 1 then raise exception 'cifras mal: %', r; end if;
  if r->'revenue'->0->>'currency' <> 'PEN' or (r->'revenue'->0->>'total')::numeric <> 7 then raise exception 'ingresos mal: %', r->'revenue'; end if;
  if jsonb_array_length(r->'payments') <> 1 or r->'payments'->0->>'email' <> 'ana@test.com' then raise exception 'pagos recientes mal: %', r->'payments'; end if;
  raise notice 'resumen del administrador OK';
end $$;
rollback;
