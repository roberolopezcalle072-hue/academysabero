begin;

-- 3D Secure: cuando la tarjeta exige una verificación adicional, el pago vuelve de "processing" a "pending"
-- para poder reintentar el mismo cobro con el resultado de la autenticación (sin crear otro pago).
create function public.academy_release_payment(p_secret text, p_payment uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not academy_private.check_payments_secret(p_secret) then raise insufficient_privilege; end if;
  update public.academy_payments set status = 'pending' where id = p_payment and status = 'processing';
end;
$$;

revoke execute on function public.academy_release_payment(text, uuid) from public, anon, authenticated;
grant execute on function public.academy_release_payment(text, uuid) to anon, authenticated;

commit;
