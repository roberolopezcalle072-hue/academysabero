-- Prueba del restablecimiento de contraseña por administración (todo se revierte).
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/admin_password_reset.sql
\set ON_ERROR_STOP on
begin;
-- usuarios de prueba
insert into auth.users (id, email, email_confirmed_at, encrypted_password, raw_user_meta_data, aud, role, instance_id)
values ('11111111-1111-1111-1111-111111111111','alumno@test.com', now(), extensions.crypt('ClaveVieja123', extensions.gen_salt('bf', 10)), '{"full_name":"Alumno Test"}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
       ('22222222-2222-2222-2222-222222222222','admin@test.com', now(), null, '{}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id, created_at, updated_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111', now(), now()),
       ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','22222222-2222-2222-2222-222222222222', now(), now());
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values ('22222222-2222-2222-2222-222222222222','22222222-2222-2222-2222-222222222222','admin@test.com','google','{"email":"admin@test.com","email_verified":"true"}', now(), now(), now());
insert into public.academy_members(user_id, role) values ('22222222-2222-2222-2222-222222222222','admin');
insert into public.academy_members(user_id, role) values ('11111111-1111-1111-1111-111111111111','student');

set local role authenticated;
-- 1) un alumno NO puede restablecer
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","amr":[{"method":"password"}]}', true);
do $$ begin
  begin perform public.academy_admin_set_password('11111111-1111-1111-1111-111111111111','OtraClave12345'); raise exception 'DEBIO FALLAR (alumno)';
  exception when insufficient_privilege then raise notice 'alumno rechazado OK'; end;
end $$;
-- 2) el admin SI puede, y no sobre otro admin
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","session_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","amr":[{"method":"oauth"}]}', true);
do $$ begin
  begin perform public.academy_admin_set_password('22222222-2222-2222-2222-222222222222','OtraClave12345'); raise exception 'DEBIO FALLAR (admin objetivo)';
  exception when foreign_key_violation then raise notice 'no se permite sobre administradores OK'; end;
  begin perform public.academy_admin_set_password('11111111-1111-1111-1111-111111111111','corta'); raise exception 'DEBIO FALLAR (corta)';
  exception when sqlstate '22023' then raise notice 'clave corta rechazada OK'; end;
end $$;
select public.academy_admin_set_password('11111111-1111-1111-1111-111111111111','ClaveNueva12345');
reset role;
select 'clave nueva valida' as paso, (encrypted_password = extensions.crypt('ClaveNueva12345', encrypted_password)) as ok,
       'clave vieja ya no' as paso2, (encrypted_password = extensions.crypt('ClaveVieja123', encrypted_password)) as vieja_valida from auth.users where id='11111111-1111-1111-1111-111111111111';
select 'sesiones del alumno tras restablecer' as paso, count(*) from auth.sessions where user_id='11111111-1111-1111-1111-111111111111';
select 'registro de auditoria' as paso, count(*) from public.academy_password_resets;
rollback;
