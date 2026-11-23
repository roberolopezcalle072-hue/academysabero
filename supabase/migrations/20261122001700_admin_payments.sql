begin;

-- Lista paginada de pagos para el administrador (solo lectura).
-- p_filter: 'paid' (cobrados y reembolsados), 'other' (intentos fallidos o sin terminar), 'all'.
create function public.academy_admin_payments(p_filter text default 'paid', p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  per_page constant integer := 20;
  result jsonb;
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;
  if p_filter not in ('paid', 'other', 'all') or p_page < 1 or p_page > 100000 then
    raise exception 'Invalid filter' using errcode = '22023';
  end if;

  with page as (
    select p.* from public.academy_payments p
    where case p_filter
            when 'paid' then p.status in ('paid', 'refunded')
            when 'other' then p.status not in ('paid', 'refunded')
            else true end
    order by coalesce(p.paid_at, p.created_at) desc, p.id
    offset (p_page - 1) * per_page limit per_page + 1
  )
  select jsonb_build_object(
    'hasNext', (select count(*) from page) > per_page,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id, 'status', x.status, 'amount', x.amount, 'currency', x.currency,
        'course', c.name, 'student', s.full_name, 'email', s.google_email,
        'reason', x.failure_reason, 'date', coalesce(x.paid_at, x.created_at)
      ) order by coalesce(x.paid_at, x.created_at) desc, x.id)
      from (select * from page order by coalesce(paid_at, created_at) desc, id limit per_page) x
      join public.academy_courses c on c.id = x.course_id
      join public.academy_students s on s.user_id = x.student_id), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke execute on function public.academy_admin_payments(text, integer) from public, anon;
grant execute on function public.academy_admin_payments(text, integer) to authenticated;

commit;
