-- Precio especial por correo (todo se revierte). Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/price_overrides.sql
\set ON_ERROR_STOP on
begin;
update public.academy_course_slots set active = false;  -- estas pruebas no dependen de los turnos
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id) values
 ('11111111-1111-1111-1111-111111111111','prueba@test.com', now(), '{"full_name":"Prueba"}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
 ('22222222-2222-2222-2222-222222222222','otro@test.com', now(), '{"full_name":"Otro"}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id, created_at, updated_at) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111', now(), now()),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','22222222-2222-2222-2222-222222222222', now(), now());
insert into academy_private.price_overrides (email, course_id, amount, expires_at)
 select 'prueba@test.com', id, 2, now() + interval '1 day' from public.academy_courses limit 1;
create temp table t_course as select id from public.academy_courses limit 1; grant all on t_course to public;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', true);
do $$ declare r record; begin
  select * into r from public.academy_catalog(); if r.price_offer <> 2 then raise exception 'catalogo debia mostrar 2, mostro %', r.price_offer; end if;
  select * into r from public.academy_start_payment((select id from t_course),'Prueba','+51999888777','Perú',null,'v1','culqi');
  if r.amount <> 2 or r.currency <> 'USD' then raise exception 'pago debia ser 2 USD, fue % %', r.amount, r.currency; end if;
  raise notice 'cuenta con precio especial: cobra 2 USD OK';
  begin perform * from academy_private.price_overrides; raise exception 'DEBIO FALLAR (tabla visible)';
  exception when insufficient_privilege then raise notice 'tabla de precios inaccesible desde la API OK'; end;
end $$;

select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","session_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', true);
do $$ declare r record; begin
  select * into r from public.academy_catalog(); if r.price_offer = 2 then raise exception 'otra cuenta vio el precio especial'; end if;
  select * into r from public.academy_start_payment((select id from t_course),'Otro','+51999888777','Perú',null,'v1','culqi');
  if r.amount = 2 then raise exception 'otra cuenta pago el precio especial'; end if;
  raise notice 'otra cuenta paga el precio normal (%) OK', r.amount;
end $$;
reset role;

update academy_private.price_overrides set expires_at = now() - interval '1 minute';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', true);
do $$ declare r record; begin
  select * into r from public.academy_catalog(); if r.price_offer = 2 then raise exception 'precio vencido sigue activo'; end if;
  raise notice 'precio vencido vuelve al normal OK';
end $$;
rollback;
