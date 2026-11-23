begin;

-- Consultas de alumnos: lista para el administrador y respuesta desde el sitio.
-- (No cambia las tablas ni lo que ve el alumno: la respuesta aparece en su historial como hasta ahora.)
create function public.academy_admin_inquiries(p_status text default 'open', p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  per_page constant integer := 20;
  result jsonb;
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  if p_status not in ('open', 'answered', 'all') or p_page < 1 or p_page > 100000 then
    raise exception 'Invalid filter' using errcode = '22023';
  end if;

  with page as (
    select i.* from public.academy_inquiries i
    where p_status = 'all' or i.status = p_status
    order by (i.status = 'open') desc, i.created_at desc
    offset (p_page - 1) * per_page limit per_page + 1
  )
  select jsonb_build_object(
    'hasNext', (select count(*) from page) > per_page,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id, 'subject', x.subject, 'body', x.body, 'status', x.status, 'created_at', x.created_at,
        'student_name', s.full_name, 'student_email', s.google_email,
        'replies', coalesce((
          select jsonb_agg(jsonb_build_object('id', r.id, 'body', r.body, 'created_at', r.created_at) order by r.created_at)
          from public.academy_inquiry_replies r where r.inquiry_id = x.id), '[]'::jsonb)
      ) order by (x.status = 'open') desc, x.created_at desc)
      from (select * from page order by (status = 'open') desc, created_at desc limit per_page) x
      join public.academy_students s on s.user_id = x.student_id), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

-- Guarda la respuesta, marca la consulta como respondida y devuelve a quién avisar por correo.
create function public.academy_admin_reply_inquiry(p_id uuid, p_body text)
returns table (student_name text, student_email text, subject text)
language plpgsql security definer set search_path = '' as $$
declare
  admin_id uuid := (select auth.uid());
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  if btrim(coalesce(p_body, '')) = '' or char_length(p_body) > 5000 then
    raise exception 'Invalid reply' using errcode = '23514';
  end if;
  if not exists (select 1 from public.academy_inquiries where id = p_id) then
    raise exception 'Inquiry unavailable' using errcode = '23503';
  end if;

  insert into public.academy_inquiry_replies (inquiry_id, administrator_id, body) values (p_id, admin_id, btrim(p_body));
  update public.academy_inquiries set status = 'answered', updated_at = now() where id = p_id;

  return query
  select s.full_name, s.google_email, i.subject
  from public.academy_inquiries i join public.academy_students s on s.user_id = i.student_id
  where i.id = p_id;
end;
$$;

revoke execute on function public.academy_admin_inquiries(text, integer), public.academy_admin_reply_inquiry(uuid, text)
  from public, anon;
grant execute on function public.academy_admin_inquiries(text, integer), public.academy_admin_reply_inquiry(uuid, text)
  to authenticated;

commit;
