-- Prueba del flujo de pagos (todo se revierte). Usa un secreto de prueba propio.
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/payments.sql
\set ON_ERROR_STOP on
begin;
update public.academy_course_slots set active = false;  -- estas pruebas no dependen de los turnos
delete from public.academy_internal_secrets where name = 'payments';
insert into public.academy_internal_secrets(name, digest) values ('payments', encode(sha256(convert_to('secreto-de-prueba','UTF8')),'hex'));


insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id)
values ('11111111-1111-1111-1111-111111111111','alumno@test.com', now(), '{"full_name":"Alumno Test"}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
       ('44444444-4444-4444-4444-444444444444','otro@test.com', now(), '{}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id, created_at, updated_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111', now(), now()),
       ('dddddddd-dddd-dddd-dddd-dddddddddddd','44444444-4444-4444-4444-444444444444', now(), now());

create temp table t_course as select id from public.academy_courses limit 1;
grant all on t_course to public;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","amr":[{"method":"password"}]}', true);
create temp table t_pay as select * from public.academy_start_payment((select id from t_course),'Alumno Test','+51999888777','Perú',null,'v1','culqi');
grant all on t_pay to public;
select 'inicio de pago' as paso, amount, currency, course_name from t_pay;
select 'reserva para cobrar' as paso, amount, email, full_name from public.academy_begin_charge((select payment_id from t_pay));
select 'segundo intento (doble clic)' as paso, count(*) from public.academy_begin_charge((select payment_id from t_pay));
-- otro alumno no ve el pago
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","session_id":"dddddddd-dddd-dddd-dddd-dddddddddddd","amr":[{"method":"password"}]}', true);
select 'otro alumno puede reservar el pago?' as paso, count(*) from public.academy_begin_charge((select payment_id from t_pay));
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","amr":[{"method":"password"}]}', true);
-- el alumno NO puede confirmarse a si mismo el pago (secreto incorrecto)
do $$ begin
  begin perform public.academy_confirm_payment('adivinando', (select payment_id from t_pay), 'culqi', 'chr_x', 199, 'USD'); raise exception 'DEBIO FALLAR';
  exception when insufficient_privilege then raise notice 'secreto incorrecto rechazado OK'; end;
end $$;
select 'sin matricula antes de pagar' as paso, count(*) from public.academy_enrollments;
-- confirmacion del backend (rol anon + secreto)
reset role; set local role anon;
do $$ begin
  begin perform public.academy_confirm_payment('secreto-de-prueba', (select payment_id from t_pay), 'culqi', 'chr_x', 1, 'USD'); raise exception 'DEBIO FALLAR monto';
  exception when check_violation then raise notice 'monto distinto rechazado OK'; end;
end $$;
select public.academy_confirm_payment('secreto-de-prueba', (select payment_id from t_pay), 'culqi', 'chr_live_123', 199, 'USD') as resultado;
select public.academy_confirm_payment('secreto-de-prueba', (select payment_id from t_pay), 'culqi', 'chr_live_123', 199, 'USD') as idempotente;
reset role;
select 'matricula activa' as paso, status from public.academy_enrollments;
select 'solicitud' as paso, status, review_note from public.academy_enrollment_requests;
select 'pago' as paso, status, external_id from public.academy_payments;
rollback;
