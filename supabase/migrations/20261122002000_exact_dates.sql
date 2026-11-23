begin;

-- ============================================================
-- Fechas exactas por clase (las de la malla) y contenido solo con lo entregado.
-- - Cada clase puede tener su fecha propia; si está vacía, se calcula en orden saltando fines de semana y feriados.
-- - Se quitan los días "sin clases" de enero que no estaban en la malla.
-- - Se vacían las descripciones y objetivos de clase que no venían en la malla (quedan para completar desde el panel).
-- ============================================================

alter table public.academy_class_plan add column class_day date;

create or replace function academy_private.class_date(p_class public.academy_class_plan)
returns date language sql stable security definer set search_path = '' as $$
  select coalesce(p_class.class_day, (
    select x.d::date from (
      select g.d, row_number() over (order by g.d) as rn
      from public.academy_schedule_settings s,
           generate_series(s.start_date::timestamp, (s.start_date + 400)::timestamp, interval '1 day') as g(d)
      where s.course_id = p_class.course_id and s.start_date is not null
        and extract(isodow from g.d) <= 5
        and not exists (select 1 from public.academy_schedule_holidays h where h.course_id = s.course_id and h.day = g.d::date)
    ) x where x.rn = p_class.class_no));
$$;

-- La administración puede fijar o borrar la fecha de una clase.
create or replace function public.academy_admin_save_class(p_id uuid, p_data jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  old public.academy_class_plan;
  cur public.academy_class_plan;
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  select * into old from public.academy_class_plan where id = p_id;
  if not found then raise exception 'Class unavailable' using errcode = '23503'; end if;

  update public.academy_class_plan c set
    title = coalesce(nullif(btrim(p_data->>'title'), ''), c.title),
    description = case when p_data ? 'description' then btrim(p_data->>'description') else c.description end,
    objectives = case when p_data ? 'objectives' then btrim(p_data->>'objectives') else c.objectives end,
    content = case when p_data ? 'content' then btrim(p_data->>'content') else c.content end,
    activity = case when p_data ? 'activity' then btrim(p_data->>'activity') else c.activity end,
    outcome = case when p_data ? 'outcome' then btrim(p_data->>'outcome') else c.outcome end,
    meet_url = case when p_data ? 'meet_url' then nullif(btrim(p_data->>'meet_url'), '') else c.meet_url end,
    recording_url = case when p_data ? 'recording_url' then nullif(btrim(p_data->>'recording_url'), '') else c.recording_url end,
    material_url = case when p_data ? 'material_url' then nullif(btrim(p_data->>'material_url'), '') else c.material_url end,
    class_day = case when p_data ? 'class_day' then nullif(btrim(p_data->>'class_day'), '')::date else c.class_day end,
    access = coalesce(nullif(p_data->>'access', ''), c.access),
    held = coalesce(nullif(p_data->>'held', ''), c.held),
    updated_at = now()
  where c.id = p_id returning * into cur;

  if cur.access is distinct from old.access or cur.held is distinct from old.held or cur.class_day is distinct from old.class_day then
    insert into public.academy_schedule_audit (course_id, actor, action, class_no, detail)
    values (cur.course_id, (select auth.uid()), 'class_state', cur.class_no,
            jsonb_build_object('access', jsonb_build_array(old.access, cur.access), 'held', jsonb_build_array(old.held, cur.held),
                               'day', jsonb_build_array(old.class_day, cur.class_day)));
  end if;
end;
$$;

do $$
declare cid uuid; n integer;
begin
  select count(*), min(id::text)::uuid into n, cid
  from public.academy_courses where status = 'published' and lower(name) like '%agente%';
  if n <> 1 then
    raise notice 'Fechas: no se cargaron (cursos coincidentes: %).', n;
    return;
  end if;

  -- Las 20 fechas de la malla, tal cual.
  update public.academy_class_plan c set class_day = v.d
  from (values
    (1, date '2026-12-15'), (2, date '2026-12-16'), (3, date '2026-12-17'), (4, date '2026-12-18'), (5, date '2026-12-21'),
    (6, date '2026-12-22'), (7, date '2026-12-23'), (8, date '2026-12-28'), (9, date '2026-12-29'), (10, date '2026-12-30'),
    (11, date '2027-01-04'), (12, date '2027-01-05'), (13, date '2027-01-06'), (14, date '2027-01-07'), (15, date '2027-01-08'),
    (16, date '2027-01-12'), (17, date '2027-01-13'), (18, date '2027-01-18'), (19, date '2027-01-19'), (20, date '2027-01-20')
  ) as v(n, d) where c.course_id = cid and c.class_no = v.n;

  -- Solo los días que la malla marca: 24 y 31 de diciembre (reservados), 25 de diciembre (Navidad) y 1 de enero (Año Nuevo).
  delete from public.academy_schedule_holidays where course_id = cid and day in (date '2027-01-11', date '2027-01-14', date '2027-01-15');
  update public.academy_schedule_holidays set label = 'Día reservado sin clases'
   where course_id = cid and day in (date '2026-12-24', date '2026-12-31');

  -- Descripciones y objetivos por clase: la malla no los trae, se completan desde el panel.
  update public.academy_class_plan set description = '', objectives = '' where course_id = cid;
end $$;

commit;
