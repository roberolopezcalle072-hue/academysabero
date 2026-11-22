begin;

-- Registro de restablecimientos de contraseña hechos por la administración.
create table public.academy_password_resets (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null,
  student_id uuid not null references public.academy_students (user_id),
  created_at timestamptz not null default now()
);
create index academy_password_resets_student_idx on public.academy_password_resets (student_id, created_at desc);
alter table public.academy_password_resets enable row level security;
revoke all on public.academy_password_resets from public, anon, authenticated;
grant select on public.academy_password_resets to authenticated;
create policy admin_read on public.academy_password_resets for select to authenticated
  using ((select academy_private.is_admin()));

-- Solo un administrador (con sesión de Google verificada) puede fijar la contraseña de un alumno.
-- No se aceptan administradores como destino y se cierran todas las sesiones abiertas del alumno.
create function public.academy_admin_set_password(p_student uuid, p_password text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not academy_private.is_admin() then raise insufficient_privilege; end if;
  if p_password is null or char_length(p_password) < 10 or char_length(p_password) > 72 then
    raise exception 'Invalid password' using errcode = '22023';
  end if;
  perform 1 from public.academy_students s
  join public.academy_members m on m.user_id = s.user_id and m.role = 'student'
  where s.user_id = p_student;
  if not found then raise exception 'Student not found' using errcode = '23503'; end if;

  update auth.users
  set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
      updated_at = now()
  where id = p_student;

  delete from auth.sessions where user_id = p_student;
  insert into public.academy_password_resets (admin_id, student_id) values (auth.uid(), p_student);
end;
$$;

revoke execute on function public.academy_admin_set_password(uuid, text) from public, anon, authenticated;
grant execute on function public.academy_admin_set_password(uuid, text) to authenticated;

commit;
