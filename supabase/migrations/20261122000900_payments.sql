begin;

-- ============================================================
-- Pagos con pasarela (independiente del proveedor: Culqi u otro).
-- La pasarela se verifica en el backend; la base solo confirma el pago
-- cuando el backend presenta el secreto interno de pagos.
-- ============================================================

create table public.academy_payments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.academy_students (user_id),
  course_id uuid not null references public.academy_courses (id),
  request_id uuid references public.academy_enrollment_requests (id),
  provider text not null check (char_length(provider) between 1 and 40),
  external_id text check (external_id is null or char_length(external_id) <= 120),
  amount numeric(10,2) not null check (amount >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed', 'refunded')),
  failure_reason text check (failure_reason is null or char_length(failure_reason) <= 300),
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  updated_at timestamptz not null default now(),
  check ((status = 'paid') = (paid_at is not null) or status = 'refunded')
);
create index academy_payments_student_idx on public.academy_payments (student_id, created_at desc);
create unique index academy_payments_external_idx on public.academy_payments (provider, external_id) where external_id is not null;
alter table public.academy_payments enable row level security;
revoke all on public.academy_payments from public, anon, authenticated;
grant select on public.academy_payments to authenticated;
create policy admin_read on public.academy_payments for select to authenticated
  using ((select academy_private.is_admin()));
create policy own_read on public.academy_payments for select to authenticated
  using (student_id = (select auth.uid()) and (select academy_private.account_email()) is not null);
create trigger touch_updated_at before update on public.academy_payments
  for each row execute function academy_private.touch_updated_at();

-- Secretos internos (solo se guarda el resumen SHA-256). Sin acceso desde la API.
create table public.academy_internal_secrets (
  name text primary key,
  digest text not null check (digest ~ '^[0-9a-f]{64}$')
);
alter table public.academy_internal_secrets enable row level security;
revoke all on public.academy_internal_secrets from public, anon, authenticated;

create function academy_private.check_payments_secret(p_secret text)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_secret is not null and exists (
    select 1 from public.academy_internal_secrets
    where name = 'payments' and digest = encode(sha256(convert_to(p_secret, 'UTF8')), 'hex')
  );
$$;

-- Inicia un pago: guarda los datos y la aceptación de términos y devuelve el monto a cobrar.
create function public.academy_start_payment(
  p_course uuid, p_name text, p_phone text, p_country text, p_notes text,
  p_terms_version text, p_provider text
) returns table (payment_id uuid, amount numeric, currency text, course_name text, email text)
language plpgsql security definer set search_path = '' as $$
declare
  student_email text;
  course public.academy_courses;
  request_id uuid;
  new_payment uuid;
begin
  student_email := academy_private.prepare_student();
  if student_email is null then raise insufficient_privilege; end if;

  select * into course from public.academy_courses where id = p_course and status = 'published';
  if not found then raise exception 'Course unavailable' using errcode = '23503'; end if;

  if exists (
    select 1 from public.academy_enrollments
    where student_id = auth.uid() and course_id = p_course and status in ('active', 'completed')
  ) then raise exception 'Already enrolled' using errcode = '23505'; end if;

  select r.id into request_id from public.academy_enrollment_requests r
  where r.student_id = auth.uid() and r.course_id = p_course and r.status = 'pending';

  if request_id is null then
    insert into public.academy_enrollment_requests (
      student_id, course_id, full_name, phone, country, email, notes,
      price_regular, price_offer, currency, terms_version, terms_accepted_at
    ) values (
      auth.uid(), p_course, btrim(p_name), btrim(p_phone), btrim(p_country), student_email,
      nullif(btrim(coalesce(p_notes, '')), ''),
      course.price_regular, course.price_offer, course.currency, p_terms_version, statement_timestamp()
    ) returning id into request_id;
  else
    update public.academy_enrollment_requests r
    set full_name = btrim(p_name), phone = btrim(p_phone), country = btrim(p_country),
        notes = nullif(btrim(coalesce(p_notes, '')), ''),
        price_regular = course.price_regular, price_offer = course.price_offer, currency = course.currency,
        terms_version = p_terms_version, terms_accepted_at = statement_timestamp()
    where r.id = request_id;
  end if;

  -- Los intentos anteriores sin completar se descartan: solo cuenta el último.
  update public.academy_payments p
  set status = 'failed', failure_reason = 'Reemplazado por un intento nuevo'
  where p.student_id = auth.uid() and p.course_id = p_course and p.status = 'pending';

  insert into public.academy_payments (student_id, course_id, request_id, provider, amount, currency)
  values (auth.uid(), p_course, request_id, p_provider, course.price_offer, course.currency)
  returning id into new_payment;

  return query select new_payment, course.price_offer, course.currency, course.name, student_email;
end;
$$;

-- Datos de un pago pendiente propio, para que el backend lo cobre.
create function public.academy_payment_for_charge(p_payment uuid)
returns table (
  payment_id uuid, amount numeric, currency text, course_name text, email text,
  full_name text, phone text, country text
)
language sql stable security definer set search_path = '' as $$
  select p.id, p.amount, p.currency, c.name, r.email, r.full_name, r.phone, r.country
  from public.academy_payments p
  join public.academy_courses c on c.id = p.course_id
  join public.academy_enrollment_requests r on r.id = p.request_id
  where p.id = p_payment and p.student_id = (select auth.uid()) and p.status = 'pending'
    and (select academy_private.account_email()) is not null;
$$;

-- Confirma el pago y activa la matrícula. Solo el backend (con el secreto interno) puede llamarla.
create function public.academy_confirm_payment(
  p_secret text, p_payment uuid, p_provider text, p_external text, p_amount numeric, p_currency text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  pay public.academy_payments;
begin
  if not academy_private.check_payments_secret(p_secret) then raise insufficient_privilege; end if;

  select * into pay from public.academy_payments where id = p_payment for update;
  if not found then raise exception 'Payment not found' using errcode = '23503'; end if;
  if pay.status = 'paid' then return 'paid'; end if;
  if pay.status <> 'pending' then raise exception 'Payment is not pending' using errcode = '23514'; end if;
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

create function public.academy_fail_payment(p_secret text, p_payment uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not academy_private.check_payments_secret(p_secret) then raise insufficient_privilege; end if;
  update public.academy_payments
  set status = 'failed', failure_reason = left(coalesce(p_reason, 'Pago rechazado'), 300)
  where id = p_payment and status = 'pending';
end;
$$;

-- Permisos
revoke execute on all functions in schema academy_private from public, anon, authenticated;
grant execute on function academy_private.is_admin(), academy_private.is_active_student(),
  academy_private.account_email() to authenticated;
revoke execute on function public.academy_start_payment(uuid, text, text, text, text, text, text),
  public.academy_payment_for_charge(uuid),
  public.academy_confirm_payment(text, uuid, text, text, numeric, text),
  public.academy_fail_payment(text, uuid, text) from public, anon, authenticated;
grant execute on function public.academy_start_payment(uuid, text, text, text, text, text, text),
  public.academy_payment_for_charge(uuid) to authenticated;
grant execute on function public.academy_confirm_payment(text, uuid, text, text, numeric, text),
  public.academy_fail_payment(text, uuid, text) to anon, authenticated;

commit;
