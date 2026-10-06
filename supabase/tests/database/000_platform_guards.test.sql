-- Platform-wide guards that must hold for every migration, forever.
begin;
create extension if not exists pgtap with schema extensions;

select plan(3);

select is_empty(
  $$ select c.relname
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relkind in ('r', 'p')
        and not c.relrowsecurity $$,
  'every table in the public schema has row level security enabled'
);

select is_empty(
  $$ select p.proname
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'app')
        and p.prosecdef
        and not exists (
          select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%'
        ) $$,
  'every SECURITY DEFINER function pins its search_path'
);

select is_empty(
  $$ select table_name
       from information_schema.role_table_grants
      where table_schema = 'public'
        and grantee = 'anon'
        and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE') $$,
  'the anonymous role cannot write to any public table'
);

select * from finish();
rollback;
