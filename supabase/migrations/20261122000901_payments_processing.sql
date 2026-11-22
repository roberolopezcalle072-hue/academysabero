begin;

-- Estado "processing": solo un cobro a la vez por pago (evita cargos dobles si el alumno pulsa dos veces).
alter table public.academy_payments drop constraint academy_payments_status_check;
alter table public.academy_payments add constraint academy_payments_status_check
  check (status in ('pending', 'processing', 'paid', 'failed', 'refunded'));

drop function public.academy_payment_for_charge(uuid);

-- Reserva el pago para cobrarlo (pending -> processing) y devuelve los datos. Una segunda llamada no devuelve nada.
create function public.academy_begin_charge(p_payment uuid)
returns table (
  payment_id uuid, amount numeric, currency text, course_name text, email text,
  full_name text, phone text, country text
)
language plpgsql security definer set search_path = '' as $$
begin
  return query
  with claimed as (
    update public.academy_payments p
    set status = 'processing'
    where p.id = p_payment and p.student_id = (select auth.uid()) and p.status = 'pending'
      and (select academy_private.account_email()) is not null
    returning p.id, p.amount, p.currency, p.course_id, p.request_id
  )
  select c.id, c.amount, c.currency, co.name, r.email, r.full_name, r.phone, r.country
  from claimed c
  join public.academy_courses co on co.id = c.course_id
  join public.academy_enrollment_requests r on r.id = c.request_id;
end;
$$;

create or replace function public.academy_confirm_payment(
  p_secret text, p_payment uuid, p_provider text, p_external text, p_amount numeric, p_currency text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  pay public.academy_payments;
begin
  if not academy_private.check_payments_secret(p_secret) then raise insufficient_privilege; end if;

  select * into pay from public.academy_payments where id = p_payment for update;
  if not found then raise exception 'Payment not found' using errcode = '23503'; end if;
  if pay.status = 'paid' then return 'paid'; end if;
  if pay.status not in ('pending', 'processing') then raise exception 'Payment is not open' using errcode = '23514'; end if;
  if pay.amount <> p_amount or pay.currency <> p_currency then
    raise exception 'Amount mismatch' using errcode = '23514';
  end if;

  update public.academy_payments
  set status = 'paid', provider = p_provider, external_id = p_external, paid_at = statement_timestamp()
  where id = p_payment;

  insert into public.academy_enrollments as e (student_id, course_id, status, enrolled_at)
  values (pay.student_id, pay.course_id, 'active', statement_timestamp())
  on conflict (student_id, course_id) do update
    set status = 'active', enrolled_at = coalesce(e.enrolled_at, excluded.enrolled_at);

  update public.academy_enrollment_requests
  set status = 'approved', review_note = 'Pago confirmado automáticamente', reviewed_at = statement_timestamp()
  where id = pay.request_id and status = 'pending';

  return 'paid';
end;
$$;

create or replace function public.academy_fail_payment(p_secret text, p_payment uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not academy_private.check_payments_secret(p_secret) then raise insufficient_privilege; end if;
  update public.academy_payments
  set status = 'failed', failure_reason = left(coalesce(p_reason, 'Pago rechazado'), 300)
  where id = p_payment and status in ('pending', 'processing');
end;
$$;

revoke execute on function public.academy_begin_charge(uuid) from public, anon, authenticated;
grant execute on function public.academy_begin_charge(uuid) to authenticated;
revoke execute on function public.academy_confirm_payment(text, uuid, text, text, numeric, text),
  public.academy_fail_payment(text, uuid, text) from public, anon, authenticated;
grant execute on function public.academy_confirm_payment(text, uuid, text, text, numeric, text),
  public.academy_fail_payment(text, uuid, text) to anon, authenticated;

commit;
