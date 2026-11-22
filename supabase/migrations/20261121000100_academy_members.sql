begin;

create table public.academy_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'student' check (role in ('student', 'admin')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.academy_members enable row level security;
revoke all on public.academy_members from public, anon, authenticated;
grant select on public.academy_members to authenticated;

create policy "Members read their own active membership"
  on public.academy_members
  for select
  to authenticated
  using ((select auth.uid()) = user_id and active);

commit;
