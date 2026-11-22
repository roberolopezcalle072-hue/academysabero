begin;

-- ============================================================
-- Registro abierto: cualquiera puede crear cuenta (correo y contraseña o Google).
-- El contenido sigue protegido: solo se ve con una matrícula activa.
-- ============================================================

-- Precios del curso (oferta y precio normal).
alter table public.academy_courses
  add column price_regular numeric(10,2) not null default 499 check (price_regular >= 0),
  add column price_offer numeric(10,2) not null default 199 check (price_offer >= 0),
  add column currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$');

-- Correo confirmado de la sesión actual (Google o correo y contraseña).
create function academy_private.account_email()
returns text language sql stable security definer set search_path = '' as $$
  select lower(btrim(u.email))
  from auth.users u
  where u.id = (select auth.uid()) and u.email_confirmed_at is not null
    and nullif(btrim(u.email), '') is not null
    and exists (
      select 1 from auth.sessions s where s.user_id = u.id
        and s.id = nullif(auth.jwt()->>'session_id', '')::uuid
        and (s.not_after is null or s.not_after > now())
    );
$$;

-- Perfil de alumno para cualquier cuenta (la columna google_email guarda el correo de la cuenta).
create function academy_private.create_account_student(target_user uuid)
returns void language sql set search_path = '' as $$
  insert into public.academy_students (user_id, full_name, google_email, created_at)
  select m.user_id,
         coalesce(nullif(btrim(u.raw_user_meta_data->>'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data->>'name'), ''),
                  split_part(lower(btrim(u.email)), '@', 1)),
         lower(btrim(u.email)), m.created_at
  from public.academy_members m
  join auth.users u on u.id = m.user_id
  where m.user_id = target_user and m.role = 'student'
    and nullif(btrim(u.email), '') is not null
  on conflict do nothing;
$$;

create or replace function academy_private.ensure_student_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform academy_private.create_account_student(new.user_id);
  if not exists (select 1 from public.academy_students where user_id = new.user_id) then
    raise exception 'Student membership requires an account with an email'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

-- Un alumno es válido si su cuenta tiene el correo confirmado y no fue revocado por la administración.
create or replace function academy_private.authorized_student()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.academy_members m
    join public.academy_students s using (user_id)
    where m.user_id = (select auth.uid()) and m.role = 'student' and m.active
      and s.google_email = (select academy_private.account_email())
  ) and not exists (
    select 1 from public.academy_authorized_emails a
    where a.email = (select academy_private.account_email()) and not a.active
  );
$$;

create or replace function academy_private.prepare_student()
returns text language plpgsql set search_path = '' as $$
declare
  student_email text := academy_private.account_email();
begin
  if student_email is null then return null; end if;
  perform 1 from public.academy_authorized_emails where email = student_email and not active;
  if found then return null; end if;

  insert into public.academy_members(user_id, role)
  values (auth.uid(), 'student') on conflict (user_id) do nothing;
  perform academy_private.create_account_student(auth.uid());
  if not academy_private.authorized_student() then return null; end if;
  return student_email;
end;
$$;

-- El registro queda abierto; solo se rechazan correos revocados por la administración.
create or replace function public.academy_before_user_created(event jsonb)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when exists (
      select 1 from public.academy_authorized_emails
      where email = lower(btrim(event #>> '{user,email}')) and not active
    )
  then jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Academy access is private'))
  else '{}'::jsonb
  end;
$$;

-- ============================================================
-- Solicitudes de inscripción (la administración las valida)
-- ============================================================
create table public.academy_enrollment_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.academy_students (user_id),
  course_id uuid not null references public.academy_courses (id),
  full_name text not null check (btrim(full_name) <> '' and char_length(full_name) <= 120),
  phone text not null check (char_length(btrim(phone)) between 6 and 30),
  country text not null check (char_length(btrim(country)) between 2 and 60),
  email text not null,
  notes text check (notes is null or char_length(notes) <= 1000),
  price_regular numeric(10,2) not null,
  price_offer numeric(10,2) not null,
  currency text not null,
  terms_version text not null check (char_length(terms_version) between 1 and 20),
  terms_accepted_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  review_note text check (review_note is null or char_length(review_note) <= 500),
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'pending') = (reviewed_at is null))
);
create unique index academy_enrollment_requests_pending_idx
  on public.academy_enrollment_requests (student_id, course_id) where status = 'pending';
create index academy_enrollment_requests_status_idx
  on public.academy_enrollment_requests (status, created_at desc);
alter table public.academy_enrollment_requests enable row level security;
revoke all on public.academy_enrollment_requests from public, anon, authenticated;
grant select on public.academy_enrollment_requests to authenticated;
create policy admin_read on public.academy_enrollment_requests for select to authenticated
  using ((select academy_private.is_admin()));
create policy own_read on public.academy_enrollment_requests for select to authenticated
  using (student_id = (select auth.uid()) and (select academy_private.account_email()) is not null);
create trigger touch_updated_at before update on public.academy_enrollment_requests
  for each row execute function academy_private.touch_updated_at();

-- Catálogo visible para cualquier cuenta con sesión (sin exponer el contenido del curso).
create function public.academy_catalog()
returns table (
  id uuid, name text, description text, image_path text,
  price_regular numeric, price_offer numeric, currency text,
  enrolled boolean, request_status text
)
language sql stable security definer set search_path = '' as $$
  select c.id, c.name, c.description, c.image_path, c.price_regular, c.price_offer, c.currency,
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

create function public.academy_request_enrollment(
  p_course uuid, p_name text, p_phone text, p_country text, p_notes text, p_terms_version text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  student_email text;
  course public.academy_courses;
  request_id uuid;
begin
  student_email := academy_private.prepare_student();
  if student_email is null then raise insufficient_privilege; end if;

  select * into course from public.academy_courses where id = p_course and status = 'published';
  if not found then raise exception 'Course unavailable' using errcode = '23503'; end if;

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
    course.price_regular, course.price_offer, course.currency, p_terms_version, statement_timestamp()
  ) returning id into request_id;
  return request_id;
end;
$$;

create function public.academy_review_enrollment_request(p_id uuid, p_approve boolean, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  request public.academy_enrollment_requests;
begin
  if not academy_private.is_admin() then raise insufficient_privilege; end if;
  select * into request from public.academy_enrollment_requests
  where id = p_id and status = 'pending' for update;
  if not found then raise exception 'Request not found' using errcode = '23503'; end if;

  if p_approve then
    insert into public.academy_enrollments as e (student_id, course_id, status, enrolled_at)
    values (request.student_id, request.course_id, 'active', statement_timestamp())
    on conflict (student_id, course_id) do update
      set status = 'active', enrolled_at = coalesce(e.enrolled_at, excluded.enrolled_at);
  end if;

  update public.academy_enrollment_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      review_note = nullif(left(btrim(coalesce(p_note, '')), 500), ''),
      reviewed_by = auth.uid(), reviewed_at = statement_timestamp()
  where id = p_id;
end;
$$;

-- Permisos
revoke execute on all functions in schema academy_private from public, anon, authenticated;
grant execute on function academy_private.is_admin(), academy_private.is_active_student(),
  academy_private.account_email() to authenticated;
revoke execute on function public.academy_catalog(), public.academy_request_enrollment(uuid, text, text, text, text, text),
  public.academy_review_enrollment_request(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.academy_catalog(), public.academy_request_enrollment(uuid, text, text, text, text, text),
  public.academy_review_enrollment_request(uuid, boolean, text) to authenticated;
revoke execute on function public.academy_before_user_created(jsonb) from public, anon, authenticated;
grant execute on function public.academy_before_user_created(jsonb) to supabase_auth_admin;

-- Curso inicial publicado (editable desde /admin/cursos).
insert into public.academy_courses (name, description, image_path, status, duration_minutes, price_regular, price_offer, currency)
select 'Agente de IA para ventas',
       'Aprende a construir un agente de IA que atiende a tus clientes por WhatsApp, hace seguimiento, agenda y registra todo en tu propio mini CRM. Incluye automatización con Meta y creación de webs conectadas a tu agente.',
       '/images/agente-ia.webp', 'published', 600, 499, 199, 'USD'
where not exists (select 1 from public.academy_courses);

commit;
