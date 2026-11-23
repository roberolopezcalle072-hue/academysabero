begin;

-- Resumen del panel de administración: cifras y pagos recientes (solo lectura, solo administradores).
create function public.academy_admin_summary()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not coalesce((select academy_private.is_admin()), false) then raise insufficient_privilege; end if;

  select jsonb_build_object(
    'students', (select count(*) from public.academy_enrollments where status in ('active', 'completed')),
    'pending_requests', (select count(*) from public.academy_enrollment_requests where status = 'pending'),
    'open_inquiries', (select count(*) from public.academy_inquiries where status = 'open'),
    'open_complaints', (select count(*) from public.academy_complaints where status = 'open'),
    'paid_count', (select count(*) from public.academy_payments where status = 'paid'),
    'revenue', coalesce((
      select jsonb_agg(jsonb_build_object('currency', t.currency, 'total', t.total) order by t.currency)
      from (select currency, sum(amount) as total from public.academy_payments where status = 'paid' group by currency) t), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'status', p.status, 'amount', p.amount, 'currency', p.currency,
        'course', c.name, 'student', s.full_name, 'email', s.google_email,
        'date', coalesce(p.paid_at, p.created_at)) order by coalesce(p.paid_at, p.created_at) desc)
      from (select * from public.academy_payments where status in ('paid', 'refunded') order by coalesce(paid_at, created_at) desc limit 8) p
      join public.academy_courses c on c.id = p.course_id
      join public.academy_students s on s.user_id = p.student_id), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke execute on function public.academy_admin_summary() from public, anon;
grant execute on function public.academy_admin_summary() to authenticated;

commit;
