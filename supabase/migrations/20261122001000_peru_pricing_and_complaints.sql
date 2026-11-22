begin;

-- ============================================================
-- 1) Precios en soles para Perú (el resto del mundo paga en dólares)
-- ============================================================
alter table public.academy_courses
  add column price_regular_pen numeric(10,2) check (price_regular_pen is null or price_regular_pen >= 0),
  add column price_offer_pen numeric(10,2) check (price_offer_pen is null or price_offer_pen >= 0),
  add constraint academy_courses_pen_pair check ((price_regular_pen is null) = (price_offer_pen is null));

create function academy_private.is_peru(p_country text)
returns boolean language sql immutable set search_path = '' as $$
  select translate(lower(btrim(coalesce(p_country, ''))), 'áéíóú', 'aeiou') in ('peru', 'pe', 'per');
$$;

-- Precio vigente según el país: soles si es Perú y el curso tiene precio en soles; si no, dólares.
create function academy_private.regional_price(p_course public.academy_courses, p_country text)
returns table (regular_price numeric, offer_price numeric, currency_code text)
language sql stable set search_path = '' as $$
  select case when academy_private.is_peru(p_country) and p_course.price_offer_pen is not null
              then p_course.price_regular_pen else p_course.price_regular end,
         case when academy_private.is_peru(p_country) and p_course.price_offer_pen is not null
              then p_course.price_offer_pen else p_course.price_offer end,
         case when academy_private.is_peru(p_country) and p_course.price_offer_pen is not null
              then 'PEN' else p_course.currency end;
$$;

-- Catálogo con ambos precios (la web elige cuál mostrar según el país del formulario).
drop function public.academy_catalog();
create function public.academy_catalog()
returns table (
  id uuid, name text, description text, image_path text,
  price_regular numeric, price_offer numeric, currency text,
  price_regular_pen numeric, price_offer_pen numeric,
  enrolled boolean, request_status text
)
language sql stable security definer set search_path = '' as $$
  select c.id, c.name, c.description, c.image_path, c.price_regular, c.price_offer, c.currency,
    c.price_regular_pen, c.price_offer_pen,
    exists (
      select 1 from public.academy_enrollments e
      where e.student_id = (select auth.uid()) and e.course_id = c.id and e.status in ('active', 'completed')
    ),
    (select r.status from public.academy_enrollment_requests r
      where r.student_id = (select auth.uid()) and r.course_id = c.id
      order by r.created_at desc limit 1)
  from public.academy_courses c
  where c.status = 'published' and (select academy_private.account_email()) is not null
  order by c.created_at;
$$;

-- Precios públicos (para la portada, sin iniciar sesión). No expone nada del contenido.
create function public.academy_public_prices()
returns table (
  name text, price_regular numeric, price_offer numeric, currency text,
  price_regular_pen numeric, price_offer_pen numeric
)
language sql stable security definer set search_path = '' as $$
  select c.name, c.price_regular, c.price_offer, c.currency, c.price_regular_pen, c.price_offer_pen
  from public.academy_courses c where c.status = 'published' order by c.created_at limit 3;
$$;

create or replace function public.academy_request_enrollment(
  p_course uuid, p_name text, p_phone text, p_country text, p_notes text, p_terms_version text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  student_email text;
  course public.academy_courses;
  price record;
  request_id uuid;
begin
  student_email := academy_private.prepare_student();
  if student_email is null then raise insufficient_privilege; end if;

  select * into course from public.academy_courses where id = p_course and status = 'published';
  if not found then raise exception 'Course unavailable' using errcode = '23503'; end if;
  select * into price from academy_private.regional_price(course, p_country);

  if exists (
    select 1 from public.academy_enrollments
    where student_id = auth.uid() and course_id = p_course and status in ('active', 'completed')
  ) then raise exception 'Already enrolled' using errcode = '23505'; end if;

  insert into public.academy_enrollment_requests (
    student_id, course_id, full_name, phone, country, email, notes,
    price_regular, price_offer, currency, terms_version, terms_accepted_at
  ) values (
    auth.uid(), p_course, btrim(p_name), btrim(p_phone), btrim(p_country), student_email,
    nullif(btrim(coalesce(p_notes, '')), ''),
    price.regular_price, price.offer_price, price.currency_code, p_terms_version, statement_timestamp()
  ) returning id into request_id;
  return request_id;
end;
$$;

create or replace function public.academy_start_payment(
  p_course uuid, p_name text, p_phone text, p_country text, p_notes text,
  p_terms_version text, p_provider text
) returns table (payment_id uuid, amount numeric, currency text, course_name text, email text)
language plpgsql security definer set search_path = '' as $$
declare
  student_email text;
  course public.academy_courses;
  price record;
  request_id uuid;
  new_payment uuid;
begin
  student_email := academy_private.prepare_student();
  if student_email is null then raise insufficient_privilege; end if;

  select * into course from public.academy_courses where id = p_course and status = 'published';
  if not found then raise exception 'Course unavailable' using errcode = '23503'; end if;
  select * into price from academy_private.regional_price(course, p_country);

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
      price.regular_price, price.offer_price, price.currency_code, p_terms_version, statement_timestamp()
    ) returning id into request_id;
  else
    update public.academy_enrollment_requests r
    set full_name = btrim(p_name), phone = btrim(p_phone), country = btrim(p_country),
        notes = nullif(btrim(coalesce(p_notes, '')), ''),
        price_regular = price.regular_price, price_offer = price.offer_price, currency = price.currency_code,
        terms_version = p_terms_version, terms_accepted_at = statement_timestamp()
    where r.id = request_id;
  end if;

  update public.academy_payments p
  set status = 'failed', failure_reason = 'Reemplazado por un intento nuevo'
  where p.student_id = auth.uid() and p.course_id = p_course and p.status = 'pending';

  insert into public.academy_payments (student_id, course_id, request_id, provider, amount, currency)
  values (auth.uid(), p_course, request_id, p_provider, price.offer_price, price.currency_code)
  returning id into new_payment;

  return query select new_payment, price.offer_price, price.currency_code, course.name, student_email;
end;
$$;

-- ============================================================
-- 2) Libro de Reclamaciones virtual (Perú)
-- ============================================================
create sequence public.academy_complaint_seq;

create table public.academy_complaints (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  kind text not null check (kind in ('reclamo', 'queja')),
  full_name text not null check (char_length(btrim(full_name)) between 2 and 120),
  doc_type text not null check (doc_type in ('DNI', 'CE', 'PASAPORTE', 'RUC', 'OTRO')),
  doc_number text not null check (char_length(btrim(doc_number)) between 4 and 20),
  address text not null check (char_length(btrim(address)) between 5 and 200),
  phone text not null check (char_length(btrim(phone)) between 6 and 30),
  email text not null check (char_length(email) <= 254 and email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  is_minor boolean not null default false,
  guardian_name text check (guardian_name is null or char_length(btrim(guardian_name)) between 2 and 120),
  service text not null check (char_length(btrim(service)) between 3 and 200),
  amount_claimed text check (amount_claimed is null or char_length(amount_claimed) <= 40),
  detail text not null check (char_length(btrim(detail)) between 10 and 2000),
  request text not null check (char_length(btrim(request)) between 5 and 1000),
  status text not null default 'open' check (status in ('open', 'answered')),
  response text check (response is null or char_length(response) <= 3000),
  answered_at timestamptz,
  created_at timestamptz not null default now(),
  check (not is_minor or guardian_name is not null),
  check ((status = 'answered') = (answered_at is not null))
);
create index academy_complaints_status_idx on public.academy_complaints (status, created_at desc);
create index academy_complaints_email_idx on public.academy_complaints (lower(email), created_at desc);
alter table public.academy_complaints enable row level security;
revoke all on public.academy_complaints from public, anon, authenticated;
grant select on public.academy_complaints to authenticated;
create policy admin_read on public.academy_complaints for select to authenticated
  using ((select academy_private.is_admin()));

-- Cualquier persona puede registrar un reclamo (no exige cuenta). Máximo 5 por correo cada 24 horas.
create function public.academy_submit_complaint(
  p_kind text, p_name text, p_doc_type text, p_doc_number text, p_address text, p_phone text,
  p_email text, p_is_minor boolean, p_guardian text, p_service text, p_amount text,
  p_detail text, p_request text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  new_code text;
begin
  if (select count(*) from public.academy_complaints
      where lower(email) = lower(btrim(p_email)) and created_at > now() - interval '24 hours') >= 5 then
    raise exception 'Too many complaints' using errcode = '54000';
  end if;

  new_code := case when p_kind = 'queja' then 'Q' else 'R' end
    || '-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.academy_complaint_seq')::text, 6, '0');

  insert into public.academy_complaints (
    code, kind, full_name, doc_type, doc_number, address, phone, email, is_minor, guardian_name,
    service, amount_claimed, detail, request
  ) values (
    new_code, p_kind, btrim(p_name), p_doc_type, btrim(p_doc_number), btrim(p_address), btrim(p_phone),
    lower(btrim(p_email)), coalesce(p_is_minor, false), nullif(btrim(coalesce(p_guardian, '')), ''),
    btrim(p_service), nullif(btrim(coalesce(p_amount, '')), ''), btrim(p_detail), btrim(p_request)
  );
  return new_code;
end;
$$;

create function public.academy_answer_complaint(p_id uuid, p_response text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not academy_private.is_admin() then raise insufficient_privilege; end if;
  update public.academy_complaints
  set status = 'answered', response = btrim(p_response), answered_at = statement_timestamp()
  where id = p_id and status = 'open' and char_length(btrim(coalesce(p_response, ''))) between 5 and 3000;
  if not found then raise exception 'Complaint not found' using errcode = '23503'; end if;
end;
$$;

-- Permisos
revoke execute on all functions in schema academy_private from public, anon, authenticated;
grant execute on function academy_private.is_admin(), academy_private.is_active_student(),
  academy_private.account_email() to authenticated;
revoke execute on function public.academy_catalog(), public.academy_public_prices(),
  public.academy_request_enrollment(uuid, text, text, text, text, text),
  public.academy_start_payment(uuid, text, text, text, text, text, text),
  public.academy_submit_complaint(text, text, text, text, text, text, text, boolean, text, text, text, text, text),
  public.academy_answer_complaint(uuid, text) from public, anon, authenticated;
grant execute on function public.academy_catalog(),
  public.academy_request_enrollment(uuid, text, text, text, text, text),
  public.academy_start_payment(uuid, text, text, text, text, text, text),
  public.academy_answer_complaint(uuid, text) to authenticated;
grant execute on function public.academy_public_prices(),
  public.academy_submit_complaint(text, text, text, text, text, text, text, boolean, text, text, text, text, text)
  to anon, authenticated;

commit;
