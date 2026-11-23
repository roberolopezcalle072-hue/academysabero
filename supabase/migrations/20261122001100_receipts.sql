begin;

-- Constancia de pago: cada pago confirmado recibe un número correlativo.
create sequence public.academy_receipt_seq;
alter table public.academy_payments add column receipt_number bigint unique;

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
  set status = 'paid', provider = p_provider, external_id = p_external, paid_at = statement_timestamp(),
      receipt_number = nextval('public.academy_receipt_seq')
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

-- Datos de la constancia: solo del propio alumno (o de un administrador) y solo si el pago está confirmado.
create function public.academy_payment_receipt(p_payment uuid)
returns table (
  payment_id uuid, receipt_number bigint, paid_at timestamptz, amount numeric, currency text,
  provider text, external_id text, course_name text, full_name text, email text, phone text, country text
)
language sql stable security definer set search_path = '' as $$
  select p.id, p.receipt_number, p.paid_at, p.amount, p.currency, p.provider, p.external_id,
         c.name, r.full_name, r.email, r.phone, r.country
  from public.academy_payments p
  join public.academy_courses c on c.id = p.course_id
  join public.academy_enrollment_requests r on r.id = p.request_id
  where p.id = p_payment and p.status = 'paid'
    and (p.student_id = (select auth.uid()) or (select academy_private.is_admin()))
    and ((select academy_private.account_email()) is not null);
$$;

create function public.academy_my_payments()
returns table (
  payment_id uuid, receipt_number bigint, status text, amount numeric, currency text,
  course_name text, created_at timestamptz, paid_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select p.id, p.receipt_number, p.status, p.amount, p.currency, c.name, p.created_at, p.paid_at
  from public.academy_payments p
  join public.academy_courses c on c.id = p.course_id
  where p.student_id = (select auth.uid()) and (select academy_private.account_email()) is not null
    and p.status in ('paid', 'refunded')
  order by p.created_at desc limit 50;
$$;

revoke execute on all functions in schema academy_private from public, anon, authenticated;
grant execute on function academy_private.is_admin(), academy_private.is_active_student(),
  academy_private.account_email() to authenticated;
revoke execute on function public.academy_confirm_payment(text, uuid, text, text, numeric, text),
  public.academy_payment_receipt(uuid), public.academy_my_payments() from public, anon, authenticated;
grant execute on function public.academy_confirm_payment(text, uuid, text, text, numeric, text) to anon, authenticated;
grant execute on function public.academy_payment_receipt(uuid), public.academy_my_payments() to authenticated;

commit;
