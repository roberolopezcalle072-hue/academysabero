-- Prueba de la constancia de pago (todo se revierte). Usa un secreto de prueba propio.
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/receipts.sql
\set ON_ERROR_STOP on
begin;
delete from public.academy_internal_secrets where name = 'payments';
insert into public.academy_internal_secrets(name, digest) values ('payments', encode(sha256(convert_to('secreto-de-prueba','UTF8')),'hex'));
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id)
values ('11111111-1111-1111-1111-111111111111','alumno@test.com', now(), '{"full_name":"Alumno Test"}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
       ('44444444-4444-4444-4444-444444444444','otro@test.com', now(), '{}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id, created_at, updated_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111', now(), now()),
       ('dddddddd-dddd-dddd-dddd-dddddddddddd','44444444-4444-4444-4444-444444444444', now(), now());
create temp table t_course as select id from public.academy_courses limit 1; grant all on t_course to public;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","amr":[{"method":"password"}]}', true);
create temp table t_pay as select * from public.academy_start_payment((select id from t_course),'Alumno Test','+51999888777','Bolivia',null,'v1','culqi');
grant all on t_pay to public;
select 'constancia antes de pagar' as paso, count(*) from public.academy_payment_receipt((select payment_id from t_pay));
select 'mis pagos antes de pagar' as paso, count(*) from public.academy_my_payments();
reset role; set local role anon;
select public.academy_confirm_payment('secreto-de-prueba', (select payment_id from t_pay), 'culqi', 'chr_test_1', 199, 'USD') as resultado;
reset role; set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","amr":[{"method":"password"}]}', true);
select 'constancia del alumno' as paso, receipt_number, amount, currency, course_name, full_name, country from public.academy_payment_receipt((select payment_id from t_pay));
select 'mis pagos' as paso, receipt_number, status, amount from public.academy_my_payments();
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","session_id":"dddddddd-dddd-dddd-dddd-dddddddddddd","amr":[{"method":"password"}]}', true);
select 'constancia de OTRO alumno' as paso, count(*) from public.academy_payment_receipt((select payment_id from t_pay));
rollback;
