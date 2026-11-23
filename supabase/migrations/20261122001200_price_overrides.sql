begin;

-- ============================================================
-- Precio especial por correo y con vencimiento (para pruebas de pago reales de bajo monto).
-- Solo lo administra quien tiene acceso directo a la base: ningún rol de la API lo ve ni lo edita.
-- ============================================================
create table academy_private.price_overrides (
  email text not null check (email = lower(btrim(email)) and position('@' in email) > 1),
  course_id uuid not null references public.academy_courses (id) on delete cascade,
  amount numeric(10,2) not null check (amount >= 1),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  expires_at timestamptz not null,
  note text,
  created_at timestamptz not null default now(),
  primary key (email, course_id)
);
revoke all on academy_private.price_overrides from public, anon, authenticated;

-- Si la cuenta tiene un precio especial vigente, ese es el que se cobra (en dólares, sin soles).
create or replace function academy_private.regional_price(p_course public.academy_courses, p_country text)
returns table (regular_price numeric, offer_price numeric, currency_code text)
language sql stable set search_path = '' as $$
  select case when academy_private.is_peru(p_country) and p_course.price_offer_pen is not null
              then p_course.price_regular_pen else p_course.price_regular end,
         coalesce(o.amount,
           case when academy_private.is_peru(p_country) and p_course.price_offer_pen is not null
                then p_course.price_offer_pen else p_course.price_offer end),
         coalesce(o.currency,
           case when academy_private.is_peru(p_country) and p_course.price_offer_pen is not null
                then 'PEN' else p_course.currency end)
  from (select 1) base
  left join academy_private.price_overrides o
    on o.course_id = p_course.id and o.expires_at > now()
   and o.email = (select academy_private.account_email());
$$;

-- El catálogo que ve esa cuenta muestra el mismo precio que luego se cobra.
create or replace function public.academy_catalog()
returns table (
  id uuid, name text, description text, image_path text,
  price_regular numeric, price_offer numeric, currency text,
  price_regular_pen numeric, price_offer_pen numeric,
  enrolled boolean, request_status text
)
language sql stable security definer set search_path = '' as $$
  select c.id, c.name, c.description, c.image_path, c.price_regular,
    coalesce(o.amount, c.price_offer), coalesce(o.currency, c.currency),
    case when o.amount is null then c.price_regular_pen end,
    case when o.amount is null then c.price_offer_pen end,
    exists (
      select 1 from public.academy_enrollments e
      where e.student_id = (select auth.uid()) and e.course_id = c.id and e.status in ('active', 'completed')
    ),
    (select r.status from public.academy_enrollment_requests r
      where r.student_id = (select auth.uid()) and r.course_id = c.id
      order by r.created_at desc limit 1)
  from public.academy_courses c
  left join academy_private.price_overrides o
    on o.course_id = c.id and o.expires_at > now()
   and o.email = (select academy_private.account_email())
  where c.status = 'published' and (select academy_private.account_email()) is not null
  order by c.created_at;
$$;

commit;
