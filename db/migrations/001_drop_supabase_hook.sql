-- El control de correos revocados ahora lo hace el backend al registrarse (ya no existe el "hook" de Supabase Auth).
begin;
drop function if exists public.academy_before_user_created(jsonb);
commit;
