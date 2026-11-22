-- Prueba de precios por país y Libro de Reclamaciones (todo se revierte).
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/peru_pricing.sql
\set ON_ERROR_STOP on
begin;
-- datos de prueba
update public.academy_courses set price_regular_pen = 1499, price_offer_pen = 749;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id)
values ('11111111-1111-1111-1111-111111111111','alumno@test.com', now(), '{"full_name":"Alumno Test"}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id, created_at, updated_at) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111', now(), now());
create temp table t_course as select id from public.academy_courses limit 1; grant all on t_course to public;
select 'regla Peru' as paso, academy_private.is_peru('Perú') as peru, academy_private.is_peru(' PERU ') as peru2, academy_private.is_peru('PE') as pe, academy_private.is_peru('Bolivia') as bolivia, academy_private.is_peru('Guatemala') as guatemala, academy_private.is_peru(null) as nulo;

-- precios publicos sin sesion
set local role anon;
select 'precios publicos (anon)' as paso, price_offer, currency, price_offer_pen from public.academy_public_prices();
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","amr":[{"method":"password"}]}', true);
create temp table t_pe as select * from public.academy_start_payment((select id from t_course),'Alumno Test','+51999888777','Perú',null,'v1','culqi');
select 'pago desde Peru' as paso, amount, currency from t_pe;
create temp table t_bo as select * from public.academy_start_payment((select id from t_course),'Alumno Test','+59171234567','Bolivia',null,'v1','culqi');
select 'pago desde Bolivia' as paso, amount, currency from t_bo;
create temp table t_gt as select * from public.academy_start_payment((select id from t_course),'Alumno Test','+50255551234','Guatemala',null,'v1','culqi');
select 'pago desde Guatemala' as paso, amount, currency from t_gt;
select 'solicitud pendiente (ultimo pais)' as paso, price_offer, currency, country from public.academy_enrollment_requests;
select 'catalogo trae ambos precios' as paso, price_offer, price_offer_pen from public.academy_catalog();
reset role;

-- Libro de reclamaciones sin sesion
set local role anon;
select 'reclamo' as paso, public.academy_submit_complaint('reclamo','Maria Perez','DNI','12345678','Av. Lima 123, Lima','+51987654321','maria@test.com',false,null,'Curso Agente de IA para ventas','S/ 749.00','No pude acceder al campus despues de pagar','Quiero que activen mi acceso') as codigo;
select 'queja' as paso, public.academy_submit_complaint('queja','Juan Soto','CE','001234567','Calle 1','+51987654322','juan@test.com',false,null,'Atencion al cliente',null,'Demoraron mucho en responder mis mensajes','Una disculpa y mejor atencion') as codigo;
do $$ begin
  begin perform public.academy_submit_complaint('reclamo','Menor','DNI','12345678','Direccion 1','+51987654321','menor@test.com',true,null,'Servicio','', 'Detalle suficiente largo','Pedido'); raise exception 'DEBIO FALLAR (menor sin apoderado)';
  exception when check_violation then raise notice 'menor sin apoderado rechazado OK'; end;
  for i in 1..5 loop perform public.academy_submit_complaint('reclamo','Spam','DNI','12345678','Direccion 1','+51987654321','spam@test.com',false,null,'Servicio',null,'Detalle suficiente largo','Pedido'); end loop;
  begin perform public.academy_submit_complaint('reclamo','Spam','DNI','12345678','Direccion 1','+51987654321','spam@test.com',false,null,'Servicio',null,'Detalle suficiente largo','Pedido'); raise exception 'DEBIO FALLAR (limite)';
  exception when sqlstate '54000' then raise notice 'limite de 5 por correo OK'; end;
  begin perform public.academy_answer_complaint((select id from public.academy_complaints limit 1), 'respuesta'); raise exception 'DEBIO FALLAR';
  exception when others then raise notice 'anon no puede responder reclamos OK'; end;
end $$;
reset role;
select 'total reclamos' as paso, count(*), min(code), max(code) from public.academy_complaints;
rollback;
