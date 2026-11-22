-- Prueba del flujo de registro abierto (todo se revierte al final).
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/open_registration.sql
\set ON_ERROR_STOP on
begin;
-- usuarios de prueba
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id)
values ('11111111-1111-1111-1111-111111111111','alumno@test.com', now(), '{"full_name":"Alumno Test"}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
       ('22222222-2222-2222-2222-222222222222','admin@test.com', now(), '{}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id, created_at, updated_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111', now(), now()),
       ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','22222222-2222-2222-2222-222222222222', now(), now());
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values ('22222222-2222-2222-2222-222222222222','22222222-2222-2222-2222-222222222222','admin@test.com','google','{"email":"admin@test.com","email_verified":"true"}', now(), now(), now());
insert into public.academy_members(user_id, role) values ('22222222-2222-2222-2222-222222222222','admin');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","amr":[{"method":"password"}]}', true);
select 'alumno sin curso ->' as paso, public.academy_resolve_access() as acceso;
select 'catalogo' as paso, name, price_regular, price_offer, currency, enrolled, request_status from public.academy_catalog();
select 'solicitud id' as paso, public.academy_request_enrollment((select id from public.academy_catalog() limit 1),'Alumno Test','+51999888777','Perú','Quiero empezar','v1') is not null as ok;
select 'catalogo tras solicitud' as paso, request_status from public.academy_catalog();
do $$ begin
  begin perform public.academy_request_enrollment((select id from public.academy_catalog() limit 1),'Otra','+51999888777','Perú',null,'v1'); raise exception 'DEBIO FALLAR duplicado';
  exception when unique_violation then raise notice 'duplicado pendiente rechazado OK'; end;
end $$;
select 'alumno ve contenido?' as paso, count(*) as cursos_visibles from public.academy_courses;

select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","session_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","amr":[{"method":"oauth"}]}', true);
select 'admin acceso' as paso, public.academy_resolve_access();
select 'admin ve solicitudes' as paso, count(*) from public.academy_enrollment_requests;
select public.academy_review_enrollment_request((select id from public.academy_enrollment_requests limit 1), true, 'pago verificado');

select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","amr":[{"method":"password"}]}', true);
select 'alumno tras aprobar ->' as paso, public.academy_resolve_access() as acceso;
select 'alumno ve contenido?' as paso, count(*) as cursos_visibles from public.academy_courses;
rollback;
