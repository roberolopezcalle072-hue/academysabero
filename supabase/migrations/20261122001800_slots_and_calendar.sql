begin;

-- ============================================================
-- Calendario real (inicio en cualquier día, feriados) y horarios con cupo.
-- REVERSIÓN (solo borra lo de este módulo; vuelve a la versión anterior de las funciones con la migración 1300/1000/1100):
--   drop table public.academy_course_slots, public.academy_schedule_holidays cascade;
--   alter table public.academy_enrollments drop column slot_no; alter table public.academy_payments drop column slot_no;
--   alter table public.academy_enrollment_requests drop column slot_no;
-- ============================================================

-- El curso puede empezar cualquier día laborable (no solo lunes).
alter table public.academy_schedule_settings drop constraint if exists academy_schedule_settings_start_date_check;

create table public.academy_schedule_holidays (
  course_id uuid not null references public.academy_courses (id) on delete cascade,
  day date not null,
  label text not null default 'Feriado' check (btrim(label) <> ''),
  primary key (course_id, day)
);

-- Horarios (turnos) del curso: cupo por turno, enlace de Meet propio y prioridad.
-- tier 1 se ofrece primero; un turno de tier mayor solo aparece cuando los de tier menor están llenos.
create table public.academy_course_slots (
  course_id uuid not null references public.academy_courses (id) on delete cascade,
  slot_no integer not null check (slot_no between 1 and 9),
  label text not null check (btrim(label) <> ''),
  starts time not null,
  ends time not null check (ends > starts),
  meet_url text check (meet_url is null or meet_url ~ '^https://meet\.google\.com/[^[:space:]]+$'),
  capacity integer not null default 10 check (capacity between 1 and 500),
  tier smallint not null default 1 check (tier between 1 and 5),
  active boolean not null default true,
  primary key (course_id, slot_no)
);

alter table public.academy_enrollments add column slot_no integer;
alter table public.academy_payments add column slot_no integer;
alter table public.academy_enrollment_requests add column slot_no integer;

do $$
declare t text;
begin
  foreach t in array array['academy_schedule_holidays', 'academy_course_slots'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Fechas: la clase N es el N-ésimo día de lunes a viernes desde el inicio, sin contar feriados.
-- ---------------------------------------------------------------------------
create or replace function academy_private.class_date(p_class public.academy_class_plan)
returns date language sql stable security definer set search_path = '' as $$
  select x.d::date from (
    select g.d, row_number() over (order by g.d) as rn
    from public.academy_schedule_settings s,
         generate_series(s.start_date::timestamp, (s.start_date + 400)::timestamp, interval '1 day') as g(d)
    where s.course_id = p_class.course_id and s.start_date is not null
      and extract(isodow from g.d) <= 5
      and not exists (select 1 from public.academy_schedule_holidays h where h.course_id = s.course_id and h.day = g.d::date)
  ) x where x.rn = p_class.class_no;
$$;

create or replace function academy_private.class_unlock_at(p_class public.academy_class_plan)
returns timestamptz language sql stable security definer set search_path = '' as $$
  select ((academy_private.class_date(p_class) + s.unlock_time)::timestamp at time zone s.timezone)
  from public.academy_schedule_settings s
  where s.course_id = p_class.course_id and s.start_date is not null;
$$;

revoke execute on function academy_private.class_date(public.academy_class_plan), academy_private.class_unlock_at(public.academy_class_plan)
  from public, anon, authenticated;

-- Cupos ocupados de un turno: matriculados + pagos en curso de los últimos 30 minutos (reserva temporal).
create function academy_private.slot_taken(p_course uuid, p_slot integer, p_except uuid default null)
returns integer language sql stable security definer set search_path = '' as $$
  select (
    (select count(*) from public.academy_enrollments e
      where e.course_id = p_course and e.slot_no = p_slot and e.status in ('active', 'completed'))
    + (select count(*) from public.academy_payments p
        where p.course_id = p_course and p.slot_no = p_slot and p.status in ('pending', 'processing')
          and p.created_at > now() - interval '30 minutes'
          and (p_except is null or p.student_id <> p_except))
  )::integer;
$$;

-- Un turno se ofrece si está activo y no hay otro turno activo de mayor prioridad (tier menor) con cupos libres.
create function academy_private.slot_open(p_course uuid, p_slot integer, p_except uuid default null)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.academy_course_slots s where s.course_id = p_course and s.slot_no = p_slot and s.active)
    and not exists (
      select 1 from public.academy_course_slots a
      join public.academy_course_slots me on me.course_id = a.course_id and me.slot_no = p_slot
      where a.course_id = p_course and a.active and a.tier < me.tier
        and academy_private.slot_taken(p_course, a.slot_no, p_except) < a.capacity);
$$;

revoke execute on function academy_private.slot_taken(uuid, integer, uuid), academy_private.slot_open(uuid, integer, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Vista pública (sin contenido ni enlaces): fechas, feriados y turnos disponibles.
-- ---------------------------------------------------------------------------
create function public.academy_public_schedule(p_course uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  cid uuid := p_course;
  result jsonb;
begin
  if cid is null then
    select c.id into cid from public.academy_courses c
    where c.status = 'published' and exists (select 1 from public.academy_class_plan k where k.course_id = c.id)
    order by c.created_at limit 1;
  end if;
  if cid is null then return null; end if;

  with k as (
    select p.class_no, academy_private.class_date(p) as day from public.academy_class_plan p where p.course_id = cid
  )
  select jsonb_build_object(
    'course', jsonb_build_object('id', c.id, 'name', c.name),
    'start_date', (select start_date from public.academy_schedule_settings where course_id = cid),
    'end_date', (select max(day) from k),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('class_no', class_no, 'date', day) order by class_no) from k), '[]'::jsonb),
    'holidays', coalesce((select jsonb_agg(jsonb_build_object('day', h.day, 'label', h.label) order by h.day)
                          from public.academy_schedule_holidays h where h.course_id = cid), '[]'::jsonb),
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object(
        'slot_no', s.slot_no, 'label', s.label, 'starts', to_char(s.starts, 'HH24:MI'), 'ends', to_char(s.ends, 'HH24:MI'),
        'capacity', s.capacity, 'remaining', greatest(s.capacity - academy_private.slot_taken(cid, s.slot_no), 0),
        'full', academy_private.slot_taken(cid, s.slot_no) >= s.capacity
      ) order by s.starts)
      from public.academy_course_slots s
      where s.course_id = cid and academy_private.slot_open(cid, s.slot_no)), '[]'::jsonb)
  ) into result
  from public.academy_courses c where c.id = cid;
  return result;
end;
$$;

revoke execute on function public.academy_public_schedule(uuid) from public;
grant execute on function public.academy_public_schedule(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Cronograma del alumno / administración (reemplaza la versión anterior; agrega turno, feriados y fechas reales).
-- ---------------------------------------------------------------------------
create or replace function public.academy_schedule(p_course uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  is_adm boolean := coalesce((select academy_private.is_admin()), false);
  cid uuid;
  st public.academy_schedule_settings;
  my_slot public.academy_course_slots;
  result jsonb;
begin
  if uid is null then raise insufficient_privilege; end if;

  if is_adm then
    cid := coalesce(p_course, (select c.course_id from public.academy_class_plan c order by c.created_at limit 1));
  else
    if not (select academy_private.authorized_student()) then raise insufficient_privilege; end if;
    select e.course_id into cid from public.academy_enrollments e
    where e.student_id = uid and e.status in ('active', 'completed')
      and (p_course is null or e.course_id = p_course)
      and exists (select 1 from public.academy_class_plan c where c.course_id = e.course_id)
    order by e.enrolled_at limit 1;
  end if;
  if cid is null then return null; end if;

  select * into st from public.academy_schedule_settings where course_id = cid;
  if not found then st.course_id := cid; st.unlock_time := '08:00'; st.timezone := 'America/Lima'; end if;

  if not is_adm then
    select s.* into my_slot from public.academy_course_slots s
    join public.academy_enrollments e on e.course_id = s.course_id and e.slot_no = s.slot_no
    where e.student_id = uid and e.course_id = cid;
  end if;

  with base as (
    select c.*, academy_private.class_date(c) as class_date, academy_private.class_unlock_at(c) as unlock_at,
           academy_private.class_unlocked(c) as unlocked, academy_private.class_executed(c) as executed
    from public.academy_class_plan c where c.course_id = cid
  ), phased as (
    select b.*, pr.completed_at,
           (select min(x.class_no) from base x where not x.executed) as next_no
    from base b
    left join public.academy_class_progress pr on pr.class_id = b.id and pr.student_id = uid
  ), shaped as (
    select p.week_no, p.class_no, (p.completed_at is not null) as done,
      jsonb_build_object(
        'id', p.id, 'class_no', p.class_no, 'week_no', p.week_no, 'topic_no', p.topic_no,
        'weekday', coalesce(extract(isodow from p.class_date)::int, p.weekday),
        'title', p.title, 'description', p.description, 'duration_minutes', p.duration_minutes,
        'date', p.class_date, 'unlock_at', p.unlock_at, 'unlocked', p.unlocked, 'executed', p.executed,
        'manual', p.access,
        'phase', case when p.executed then 'executed'
                      when p.class_no = p.next_no then
                        case when p.class_date = (now() at time zone st.timezone)::date then 'today' else 'next' end
                      else 'pending' end,
        'completed', p.completed_at is not null, 'completed_at', p.completed_at
      )
      || case when is_adm or p.unlocked then jsonb_build_object(
           'objectives', p.objectives, 'content', p.content, 'activity', p.activity, 'outcome', p.outcome,
           'meet_url', case when is_adm then p.meet_url else coalesce(p.meet_url, my_slot.meet_url) end,
           'recording_url', p.recording_url, 'material_url', p.material_url)
         else '{}'::jsonb end
      || case when is_adm then jsonb_build_object('held', p.held) else '{}'::jsonb end as js
    from phased p
  )
  select jsonb_build_object(
    'course', jsonb_build_object('id', co.id, 'name', co.name),
    'admin', is_adm,
    'settings', jsonb_build_object('start_date', st.start_date, 'unlock_time', to_char(st.unlock_time, 'HH24:MI'),
                                   'timezone', st.timezone),
    'holidays', coalesce((select jsonb_agg(jsonb_build_object('day', h.day, 'label', h.label) order by h.day)
                          from public.academy_schedule_holidays h where h.course_id = cid), '[]'::jsonb),
    'slot', case when my_slot.slot_no is null then null else jsonb_build_object(
      'slot_no', my_slot.slot_no, 'label', my_slot.label,
      'starts', to_char(my_slot.starts, 'HH24:MI'), 'ends', to_char(my_slot.ends, 'HH24:MI'), 'meet_url', my_slot.meet_url) end,
    'slots', case when is_adm then coalesce((
      select jsonb_agg(jsonb_build_object(
        'slot_no', s.slot_no, 'label', s.label, 'starts', to_char(s.starts, 'HH24:MI'), 'ends', to_char(s.ends, 'HH24:MI'),
        'meet_url', s.meet_url, 'capacity', s.capacity, 'tier', s.tier, 'active', s.active,
        'taken', academy_private.slot_taken(cid, s.slot_no)) order by s.starts)
      from public.academy_course_slots s where s.course_id = cid), '[]'::jsonb) else null end,
    'total', (select count(*) from shaped),
    'completed', (select count(*) filter (where done) from shaped),
    'percent', (select case when count(*) = 0 then 0 else round(100.0 * count(*) filter (where done) / count(*)) end from shaped),
    'next', (select s.js from shaped s where (s.js->>'executed')::boolean = false order by s.class_no limit 1),
    'weeks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'week_no', w.week_no, 'title', w.title, 'objective', w.objective,
        'total', (select count(*) from shaped s where s.week_no = w.week_no),
        'completed', (select count(*) filter (where s.done) from shaped s where s.week_no = w.week_no),
        'topics', coalesce((select jsonb_agg(jsonb_build_object('topic_no', t.topic_no, 'title', t.title) order by t.topic_no)
                            from public.academy_schedule_topics t where t.course_id = cid and t.week_no = w.week_no), '[]'::jsonb),
        'classes', coalesce((select jsonb_agg(s.js order by s.class_no) from shaped s where s.week_no = w.week_no), '[]'::jsonb)
      ) order by w.week_no)
      from public.academy_schedule_weeks w where w.course_id = cid), '[]'::jsonb)
  ) into result
  from public.academy_courses co where co.id = cid;
  return result;
end;
$$;

-- Administración: la fecha de inicio puede ser cualquier día (ya no solo lunes).
create or replace function public.academy_admin_save_settings(p_course uuid, p_start date, p_time time, p_timezone text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'Zona horaria no válida' using errcode = '23514';
  end if;
  insert into public.academy_schedule_settings (course_id, start_date, unlock_time, timezone)
  values (p_course, p_start, p_time, p_timezone)
  on conflict (course_id) do update
    set start_date = excluded.start_date, unlock_time = excluded.unlock_time,
        timezone = excluded.timezone, updated_at = now();
  insert into public.academy_schedule_audit (course_id, actor, action, detail)
  values (p_course, (select auth.uid()), 'settings',
          jsonb_build_object('start_date', p_start, 'unlock_time', p_time, 'timezone', p_timezone));
end;
$$;

create function public.academy_admin_save_slot(
  p_course uuid, p_slot integer, p_label text, p_starts time, p_ends time, p_meet text,
  p_capacity integer, p_tier integer, p_active boolean
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  insert into public.academy_course_slots (course_id, slot_no, label, starts, ends, meet_url, capacity, tier, active)
  values (p_course, p_slot, btrim(p_label), p_starts, p_ends, nullif(btrim(coalesce(p_meet, '')), ''), p_capacity, p_tier, p_active)
  on conflict (course_id, slot_no) do update
    set label = excluded.label, starts = excluded.starts, ends = excluded.ends, meet_url = excluded.meet_url,
        capacity = excluded.capacity, tier = excluded.tier, active = excluded.active;
  insert into public.academy_schedule_audit (course_id, actor, action, detail)
  values (p_course, (select auth.uid()), 'slot', jsonb_build_object('slot', p_slot, 'capacity', p_capacity, 'tier', p_tier, 'active', p_active));
end;
$$;

create function public.academy_admin_set_holiday(p_course uuid, p_day date, p_label text, p_remove boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  if p_remove then
    delete from public.academy_schedule_holidays where course_id = p_course and day = p_day;
  else
    insert into public.academy_schedule_holidays (course_id, day, label)
    values (p_course, p_day, coalesce(nullif(btrim(p_label), ''), 'Feriado'))
    on conflict (course_id, day) do update set label = excluded.label;
  end if;
  insert into public.academy_schedule_audit (course_id, actor, action, detail)
  values (p_course, (select auth.uid()), 'holiday', jsonb_build_object('day', p_day, 'removed', p_remove));
end;
$$;

revoke execute on function public.academy_admin_save_slot(uuid, integer, text, time, time, text, integer, integer, boolean),
  public.academy_admin_set_holiday(uuid, date, text, boolean) from public, anon;
grant execute on function public.academy_admin_save_slot(uuid, integer, text, time, time, text, integer, integer, boolean),
  public.academy_admin_set_holiday(uuid, date, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Pago: ahora lleva el turno elegido (obligatorio si el curso tiene turnos), con control de cupo.
-- ---------------------------------------------------------------------------
drop function public.academy_start_payment(uuid, text, text, text, text, text, text);

create function public.academy_start_payment(
  p_course uuid, p_name text, p_phone text, p_country text, p_notes text,
  p_terms_version text, p_provider text, p_slot integer default null
) returns table (payment_id uuid, amount numeric, currency text, course_name text, email text)
language plpgsql security definer set search_path = '' as $$
declare
  student_email text;
  course public.academy_courses;
  price record;
  request_id uuid;
  new_payment uuid;
  uid uuid := (select auth.uid());
begin
  student_email := academy_private.prepare_student();
  if student_email is null then raise insufficient_privilege; end if;

  select * into course from public.academy_courses where id = p_course and status = 'published';
  if not found then raise exception 'Course unavailable' using errcode = '23503'; end if;
  select * into price from academy_private.regional_price(course, p_country);

  if exists (
    select 1 from public.academy_enrollments
    where student_id = uid and course_id = p_course and status in ('active', 'completed')
  ) then raise exception 'Already enrolled' using errcode = '23505'; end if;

  -- Turno: obligatorio si el curso tiene turnos activos; debe estar ofrecido y con cupo.
  if exists (select 1 from public.academy_course_slots where course_id = p_course and active) then
    if p_slot is null or not academy_private.slot_open(p_course, p_slot, uid) then
      raise exception 'Slot unavailable' using errcode = '23514';
    end if;
    if academy_private.slot_taken(p_course, p_slot, uid) >=
       (select capacity from public.academy_course_slots where course_id = p_course and slot_no = p_slot) then
      raise exception 'Slot full' using errcode = '54000';
    end if;
  end if;

  select r.id into request_id from public.academy_enrollment_requests r
  where r.student_id = uid and r.course_id = p_course and r.status = 'pending';

  if request_id is null then
    insert into public.academy_enrollment_requests (
      student_id, course_id, full_name, phone, country, email, notes,
      price_regular, price_offer, currency, terms_version, terms_accepted_at, slot_no
    ) values (
      uid, p_course, btrim(p_name), btrim(p_phone), btrim(p_country), student_email,
      nullif(btrim(coalesce(p_notes, '')), ''),
      price.regular_price, price.offer_price, price.currency_code, p_terms_version, statement_timestamp(), p_slot
    ) returning id into request_id;
  else
    update public.academy_enrollment_requests r
    set full_name = btrim(p_name), phone = btrim(p_phone), country = btrim(p_country),
        notes = nullif(btrim(coalesce(p_notes, '')), ''),
        price_regular = price.regular_price, price_offer = price.offer_price, currency = price.currency_code,
        terms_version = p_terms_version, terms_accepted_at = statement_timestamp(), slot_no = p_slot
    where r.id = request_id;
  end if;

  update public.academy_payments p
  set status = 'failed', failure_reason = 'Reemplazado por un intento nuevo'
  where p.student_id = uid and p.course_id = p_course and p.status = 'pending';

  insert into public.academy_payments (student_id, course_id, request_id, provider, amount, currency, slot_no)
  values (uid, p_course, request_id, p_provider, price.offer_price, price.currency_code, p_slot)
  returning id into new_payment;

  return query select new_payment, price.offer_price, price.currency_code, course.name, student_email;
end;
$$;

revoke execute on function public.academy_start_payment(uuid, text, text, text, text, text, text, integer) from public, anon, authenticated;
grant execute on function public.academy_start_payment(uuid, text, text, text, text, text, text, integer) to authenticated;

-- La confirmación del pago guarda el turno en la matrícula.
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

  insert into public.academy_enrollments as e (student_id, course_id, status, enrolled_at, slot_no)
  values (pay.student_id, pay.course_id, 'active', statement_timestamp(), pay.slot_no)
  on conflict (student_id, course_id) do update
    set status = 'active', enrolled_at = coalesce(e.enrolled_at, excluded.enrolled_at),
        slot_no = coalesce(excluded.slot_no, e.slot_no);

  update public.academy_enrollment_requests
  set status = 'approved', review_note = 'Pago confirmado automáticamente', reviewed_at = statement_timestamp()
  where id = pay.request_id and status = 'pending';

  return 'paid';
end;
$$;

-- ---------------------------------------------------------------------------
-- Carga inicial (idempotente): inicio 15 de diciembre de 2026, receso del 24 de diciembre al 1 de enero,
-- tres turnos de 10 cupos (tardes primero; la mañana solo cuando las tardes se llenan).
-- ---------------------------------------------------------------------------
do $$
declare cid uuid; n integer;
begin
  select count(*), min(id::text)::uuid into n, cid
  from public.academy_courses where status = 'published' and lower(name) like '%agente%';
  if n <> 1 then
    raise notice 'Calendario: no se cargó (cursos coincidentes: %).', n;
    return;
  end if;

  insert into public.academy_schedule_settings (course_id, start_date) values (cid, date '2026-12-15')
  on conflict (course_id) do update set start_date = coalesce(public.academy_schedule_settings.start_date, excluded.start_date);

  insert into public.academy_schedule_holidays (course_id, day, label)
  select cid, d::date,
         case when d::date = date '2026-12-24' then 'Nochebuena'
              when d::date = date '2026-12-25' then 'Navidad'
              when d::date = date '2027-01-01' then 'Año Nuevo'
              else 'Receso de fin de año' end
  from generate_series(timestamp '2026-12-24', timestamp '2027-01-01', interval '1 day') g(d)
  on conflict do nothing;

  insert into public.academy_course_slots (course_id, slot_no, label, starts, ends, capacity, tier) values
    (cid, 1, 'Tarde', time '15:00', time '17:00', 10, 1),
    (cid, 2, 'Noche', time '18:00', time '20:00', 10, 1),
    (cid, 3, 'Mañana', time '11:00', time '13:00', 10, 2)
  on conflict do nothing;
end $$;

commit;
