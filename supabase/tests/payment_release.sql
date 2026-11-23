-- 3D Secure: el pago vuelve de "processing" a "pending" para reintentar (todo se revierte).
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f supabase/tests/payment_release.sql
\set ON_ERROR_STOP on
begin;
update public.academy_course_slots set active = false;  -- estas pruebas no dependen de los turnos
delete from public.academy_internal_secrets where name = 'payments';
insert into public.academy_internal_secrets(name, digest) values ('payments', encode(sha256(convert_to('secreto-de-prueba','UTF8')),'hex'));
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, aud, role, instance_id)
values ('11111111-1111-1111-1111-111111111111','alumno@test.com', now(), '{"full_name":"Alumno Test"}', 'authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into auth.sessions (id, user_id, created_at, updated_at) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111', now(), now());
create temp table t_course as select id from public.academy_courses limit 1; grant all on t_course to public;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","amr":[{"method":"password"}]}', true);
create temp table t_pay as select * from public.academy_start_payment((select id from t_course),'Alumno Test','+51999888777','Perú',null,'v1','culqi');
grant all on t_pay to public;
do $$ begin
  if (select count(*) from public.academy_begin_charge((select payment_id from t_pay))) <> 1 then raise exception 'primera reserva debia funcionar'; end if;
  if (select count(*) from public.academy_begin_charge((select payment_id from t_pay))) <> 0 then raise exception 'doble reserva no debe funcionar'; end if;
  begin perform public.academy_release_payment('adivinando', (select payment_id from t_pay)); raise exception 'DEBIO FALLAR (secreto)';
  exception when insufficient_privilege then raise notice 'liberar con secreto incorrecto rechazado OK'; end;
end $$;
reset role; set local role anon;
select public.academy_release_payment('secreto-de-prueba', (select payment_id from t_pay));
reset role; set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","amr":[{"method":"password"}]}', true);
do $$ begin
  if (select count(*) from public.academy_begin_charge((select payment_id from t_pay))) <> 1 then raise exception 'tras liberar debe poder reservarse otra vez (reintento 3DS)'; end if;
  raise notice 'liberar y reintentar el mismo pago tras 3D Secure OK';
end $$;
reset role;
do $$ begin
  -- un pago ya pagado no se puede liberar
  update public.academy_payments set status = 'paid', paid_at = now(), external_id = 'x' where id = (select payment_id from t_pay);
  perform public.academy_release_payment('secreto-de-prueba', (select payment_id from t_pay));
  if (select status from public.academy_payments where id = (select payment_id from t_pay)) <> 'paid' then raise exception 'un pago pagado no debe volver a pending'; end if;
  raise notice 'pago pagado no se libera OK';
end $$;
rollback;
